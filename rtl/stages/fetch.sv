module fetch
import rv32i_types::*;
(
    input  logic        clk,
    input  logic        rst,
    input  logic        imem_resp,
    input  logic [255:0] hit_cache_line,
    input  logic [31:0]  hit_cache_line_addr,

    input  logic        br_mispredict,
    input  logic [31:0] branch_pc,
    input  logic [23:0] branch_order,

    // update gshare
    input  logic        update_predictor,
    input  logic        commit_br_outcome,
    input  logic [1:0]  commit_rob_old_prediction,
    input  logic [$clog2(PHT_SIZE)-1:0] commit_rob_pht_index,

    // revert RAS
    input logic [RAS_P_WIDTH-1:0]   rob_saved_ras_ptr,

    // update btb
    input  logic        update_btb,
    input  logic [31:0] btb_pc_writing,
    // use branch_pc for 

    input  logic        stall_decode,

    output logic [31:0] imem_addr,
    output logic [3:0]  imem_rmask,

    output inst_queue_packet_t  inst_queue_packet
);

    inst_queue_packet_t enq_packet;
    inst_queue_packet_t deq_packet;
    logic [31:0]        pc, pc_next, flush_target;
    logic [23:0]        order, order_next;
    logic               flush_pending, flush_pending_next;
    logic               enq_allowed, deq_allowed, full, empty;
    logic [31:0]        current_inst;
    logic               deq_req;

    // gshare
    logic [1:0] gshare_prediction;
    logic [$clog2(PHT_SIZE)-1:0] gshare_pht_index;
    logic predict_taken;

    // ras
    logic ras_push, ras_pop;
    logic [31:0] ras_din, ras_dout;
    logic [RAS_P_WIDTH-1:0] ras_ptr;

    // jalr btb
    logic [29:0]    btb_addr_prediction;
    logic           btb_valid;


    // --- Pre-Decode Branch Targets ---
    logic [31:0] jal_imm;
    logic [31:0] br_imm;

    assign jal_imm = { {12{current_inst[31]}}, current_inst[19:12], current_inst[20], current_inst[30:21], 1'b0 };
    assign br_imm  = { {20{current_inst[31]}}, current_inst[7], current_inst[30:25], current_inst[11:8], 1'b0 };
    
    // Check if gshare says "Taken" (MSB is 1 means Taken in standard 2-bit counter)
    assign predict_taken = gshare_prediction[1];


    // --- linebuffer interface ---
    logic [255:0]   line0, line1;
    logic [31:0]    addr0, addr1;
    logic           valid0, valid1;

    logic           pf_req;
    logic [31:0]    pf_addr;
    logic           pf_issued;
    logic           resp_is_prefetch;

    // which slot (if any) currently holds the line for this PC
    logic           lb_hit;
    logic           hit_slot;   // 0 => slot0, 1 => slot1
    logic [255:0]   hit_line;

    // --- demand miss / arbitration bookkeeping ---
    logic           demand_miss_inflight, demand_miss_inflight_next;
    logic           inflight_is_prefetch, inflight_is_prefetch_next;
    logic           issue_demand, issue_prefetch;
    logic           flush_prefetch, flush_prefetch_pending, flush_prefetch_pending_next;
    // --- linebuffer lookup ---
    assign lb_hit   = (valid0 && (pc[31:5] == addr0[31:5])) || (valid1 && (pc[31:5] == addr1[31:5]));
    assign hit_slot = (valid1 && (pc[31:5] == addr1[31:5]));
    assign hit_line = hit_slot ? line1 : line0;

    assign current_inst = lb_hit ? hit_line[32*pc[4:2] +: 32] : hit_cache_line[32*pc[4:2] +: 32];
    assign resp_is_prefetch = inflight_is_prefetch;

    // ---------------- RAS DEBUG COUNTERS ----------------
    logic [63:0] ras_push_cnt, ras_pop_cnt;
    logic [63:0] ras_underflow_cnt;

    logic [63:0] ras_push_wrong_path_cnt, ras_pop_wrong_path_cnt;
    logic [63:0] ras_push_and_pop_same_cycle_cnt;


    logic [63:0] btb_queries_cnt, btb_hits_cnt, btb_misses_cnt;
    logic [63:0] btb_updates_cnt;

    // Helper signal for BTB counters to keep always_ff clean
    logic is_btb_eligible;
    assign is_btb_eligible = (current_inst[6:0] == op_b_jalr) && 
                             !(current_inst[11:7] == 5'd0 && current_inst[19:15] == 5'd1);

    linebuffer fetch_lb (
        .clk                 (clk),
        .rst                 (rst),
        .hit_icache_line     (hit_cache_line),
        .hit_cache_line_addr (hit_cache_line_addr),
        .imem_resp           (imem_resp),
        .pc                  (pc),
        .demand_miss_inflight(demand_miss_inflight),
        .pf_req              (pf_req),
        .pf_addr             (pf_addr),
        .pf_issued           (pf_issued),
        .resp_is_prefetch    (resp_is_prefetch),
        .line0(line0), .line1(line1),
        .addr0(addr0), .addr1(addr1),
        .valid0(valid0), .valid1(valid1)
    );

    always_comb begin
        // defaults
        pc_next                   = pc;
        order_next                = order;
        flush_pending_next        = flush_pending;
        imem_rmask                = '0;
        imem_addr                 = pc;
        enq_packet                = '0;
        enq_packet.valid          = '0;

        issue_demand              = 1'b0;
        issue_prefetch            = 1'b0;
        demand_miss_inflight_next = demand_miss_inflight;
        inflight_is_prefetch_next = inflight_is_prefetch;
        flush_prefetch = '0;
        flush_prefetch_pending_next = flush_prefetch_pending;

        ras_din = '0;
        ras_push = '0;
        ras_pop = '0;

        // handle a pending flush (waiting for stale imem_resp)
        if (flush_pending) begin
            if (imem_resp) begin
                pc_next            = flush_target;
                flush_pending_next = 1'b0;
                // in-flight request (whatever it was) just resolved
                demand_miss_inflight_next = 1'b0;
                inflight_is_prefetch_next = 1'b0;
            end else begin
                // hold, keep demand address driven
                issue_demand       = 1'b1;
                imem_addr          = pc;
                flush_pending_next = 1'b1;
            end
        end

        // new flush this cycle
        else if (br_mispredict) begin
            if (!inflight_is_prefetch && (imem_resp || lb_hit)) begin
                pc_next            = branch_pc;
                order_next         = branch_order + 1'd1;
                flush_pending_next = 1'b0;
                flush_prefetch_pending_next = 1'b0;
                if (imem_resp) begin
                    demand_miss_inflight_next = 1'b0;
                    inflight_is_prefetch_next = 1'b0;
                end
            end else begin
                flush_pending_next = 1'b1;
                flush_prefetch_pending_next = 1'b0;
                issue_demand       = 1'b1;
                imem_addr          = pc;   // stale, will be redirected to flush_target next cycle
                order_next         = branch_order + 1'd1;
            end
        end

        else if (flush_prefetch_pending) begin
            if (imem_resp) begin
                pc_next            = flush_target;
                flush_prefetch_pending_next = 1'b0;
                // in-flight request (whatever it was) just resolved
                demand_miss_inflight_next = 1'b0;
                inflight_is_prefetch_next = 1'b0;
            end else begin
                // hold, keep demand address driven
                issue_demand       = 1'b1;
                imem_addr          = pc;
                flush_prefetch_pending_next = 1'b1;
            end
        end

        // iqueue full, stall
        else if (!enq_allowed) begin
            pc_next    = pc;
            order_next = order;
            // still allow prefetch to make progress — port is idle
            if (pf_req && !demand_miss_inflight) begin
                issue_prefetch = 1'b1;
                imem_addr      = pf_addr;
            end
        end

        // linebuffer hit — no demand fetch needed, try prefetch
        else if (lb_hit) begin
            enq_packet.valid            = 1'b1;
            enq_packet.pc               = pc;
            enq_packet.inst             = current_inst;
            enq_packet.order            = order;
            enq_packet.pred_prediction  = gshare_prediction;
            enq_packet.pred_pht_index   = gshare_pht_index;
            enq_packet.ras_top_ptr      = ras_ptr;

            if (current_inst[6:0] == op_b_jal) begin
                pc_next = pc + jal_imm;

                // function call
                if (current_inst[11:7] == 5'd1) begin   // no jal calls so might be useless
                    ras_push    = '1;
                    ras_din     = pc + 4;
                end
                // flush prefetch on redirect
                if (inflight_is_prefetch || pf_req) begin
                    flush_prefetch = 1'b1;
                    flush_prefetch_pending_next = 1'b1;
                    issue_demand       = 1'b1;
                    imem_addr          = pc;   // stale, will be redirected to flush_target next cycle
                end
            end
            else if (current_inst[6:0] == op_b_br && predict_taken) begin
                pc_next = pc + br_imm;

                // flush prefetch on redirect
                if (inflight_is_prefetch || pf_req) begin
                    flush_prefetch = 1'b1;
                    flush_prefetch_pending_next = 1'b1;
                    issue_demand = 1'b1;
                    imem_addr    = pc; 
                end
            end
            else if (current_inst[6:0] == op_b_jalr) begin
                // function return (rd: x0, rs1: x1)
                if (current_inst[11:7] == 5'd0 && current_inst[19:15] == 5'd1) begin    // check if not checking rs1 == x1 matters
                    ras_pop = '1;
                    pc_next = ras_dout;
                end else begin
                    // check for function call (rd: x1, rs1: x1)
                    if (current_inst[11:7] == 5'd1 && current_inst[19:15] == 5'd1) begin    // check if 
                        ras_push    = '1;
                        ras_din     = pc + 4;
                    end

                    // use btb if possible
                    if (btb_valid)
                        pc_next = {btb_addr_prediction, 2'b00};
                end
                // flush prefetch on redirect
                if (inflight_is_prefetch || pf_req) begin
                    flush_prefetch = 1'b1;
                    flush_prefetch_pending_next = 1'b1;
                    issue_demand       = 1'b1;
                    imem_addr          = pc;   // stale, will be redirected to flush_target next cycle
                end
            end
            else    // not a br or jal
                pc_next = pc + 4;

            enq_packet.predicted_pc = pc_next;
            order_next              = order + 1'b1;

            // port is idle this cycle, issue prefetch if requested
            if (pf_req && !demand_miss_inflight) begin
                issue_prefetch = 1'b1;
                imem_addr      = pf_addr;
            end
        end

        // demand miss — cache has not responded
        else if (!imem_resp) begin
            issue_demand = 1'b1;
            imem_addr    = pc;
            pc_next      = pc;
            if (!demand_miss_inflight) demand_miss_inflight_next = 1'b1;
        end

        // demand miss — cache responded this cycle
        else begin
            // FIX: Only enqueue instruction if this response was for a demand fetch,
            // not a prefetch. A prefetch response returns hit_cache_line for pf_addr,
            // not pc — indexing it with pc[4:2] yields the wrong instruction word.
            if (!resp_is_prefetch) begin
                enq_packet.valid            = 1'b1;
                enq_packet.pc               = pc;
                enq_packet.inst             = current_inst;
                enq_packet.order            = order;
                enq_packet.pred_prediction  = gshare_prediction;
                enq_packet.pred_pht_index   = gshare_pht_index;
                enq_packet.ras_top_ptr      = ras_ptr;

                if (current_inst[6:0] == op_b_jal) begin
                    pc_next = pc + jal_imm;

                    // function call
                    if (current_inst[11:7] == 5'd1) begin
                        ras_push    = '1;
                        ras_din     = pc + 4;
                    end

                    // flush prefetch on redirect
                    if (inflight_is_prefetch || pf_req) begin
                        flush_prefetch = 1'b1;
                        flush_prefetch_pending_next = 1'b1;
                        issue_demand       = 1'b1;
                        imem_addr          = pc;   // stale, will be redirected to flush_target next cycle
                    end
                end
                else if (current_inst[6:0] == op_b_br && predict_taken) begin
                    pc_next = pc + br_imm;

                    // flush prefetch on redirect
                    if (inflight_is_prefetch || pf_req) begin
                        flush_prefetch = 1'b1;
                        flush_prefetch_pending_next = 1'b1;
                        issue_demand = 1'b1;
                        imem_addr    = pc; 
                    end
                end
                else if (current_inst[6:0] == op_b_jalr) begin
                    // function return (rd: x0, rs1: x1)
                    if (current_inst[11:7] == 5'd0 && current_inst[19:15] == 5'd1) begin
                        ras_pop = '1;
                        pc_next = ras_dout;
                    end else begin
                        // check for function call (rd: x1, rs1: x1)
                        if (current_inst[11:7] == 5'd1 && current_inst[19:15] == 5'd1) begin
                            ras_push    = '1;
                            ras_din     = pc + 4;
                        end

                        // use btb if possible
                        if (btb_valid)
                            pc_next = {btb_addr_prediction, 2'b00};
                    end
                    
                    // flush prefetch on redirect
                    if (inflight_is_prefetch || pf_req) begin
                        flush_prefetch = 1'b1;
                        flush_prefetch_pending_next = 1'b1;
                        issue_demand       = 1'b1;
                        imem_addr          = pc;   // stale, will be redirected to flush_target next cycle
                    end
                end
                else    // not a br or jal
                    pc_next = pc + 4;

                enq_packet.predicted_pc = pc_next;
                order_next              = order + 1'b1;
            end
            // else: prefetch response — line has been stored in linebuffer by fetch_lb.
            // Do not enqueue; pc stays, next cycle will lb_hit and enqueue correctly.

            // port freed up regardless of whether it was demand or prefetch
            demand_miss_inflight_next = 1'b0;
            inflight_is_prefetch_next = 1'b0;
        end

        // drive rmask based on what we decided to issue
        imem_rmask = (issue_demand || issue_prefetch) ? 4'b1111 : 4'b0000;
    end

    // prefetch grant: we issued it this cycle
    assign pf_issued = issue_prefetch;

    always_ff @(posedge clk) begin
        if (rst) begin
            pc                   <= 32'haaaaa000;
            order                <= '0;
            flush_pending        <= '0;
            flush_target         <= '0;
            demand_miss_inflight <= '0;
            inflight_is_prefetch <= '0;
            flush_prefetch_pending <= '0;
        end else begin
            pc            <= pc_next;
            order         <= order_next;
            flush_pending <= flush_pending_next;
            flush_prefetch_pending <= flush_prefetch_pending_next;

            demand_miss_inflight <= demand_miss_inflight_next;
            // once we grant a prefetch, remember it was a prefetch until the response returns
            if (issue_prefetch)
                inflight_is_prefetch <= 1'b1;
            else if (imem_resp)
                inflight_is_prefetch <= 1'b0;
            else
                inflight_is_prefetch <= inflight_is_prefetch_next;

            if (br_mispredict) begin
                flush_target <= branch_pc;
            end
            else if (flush_prefetch) begin
                flush_target <= pc_next;
            end
        end
    end

    always_ff @(posedge clk) begin 
        // ---------------- DEBUG COUNTERS ----------------
        if (rst) begin
            ras_push_cnt                    <= '0;
            ras_pop_cnt                     <= '0;
            ras_underflow_cnt               <= '0;
            ras_push_wrong_path_cnt         <= '0;
            ras_pop_wrong_path_cnt          <= '0;
            ras_push_and_pop_same_cycle_cnt <= '0;

            btb_queries_cnt                 <= '0;
            btb_hits_cnt                    <= '0;
            btb_misses_cnt                  <= '0;
            btb_updates_cnt                 <= '0;
        end else begin 
            // BTB Updates (independent of fetch validity)
            if (update_btb) begin
                btb_updates_cnt <= btb_updates_cnt + 1;
            end

            if (enq_packet.valid) begin
                if (ras_push)
                    ras_push_cnt <= ras_push_cnt + 1;

                if (ras_pop)
                    ras_pop_cnt <= ras_pop_cnt + 1;

                // underflow detection
                if (ras_pop && (ras_ptr == 0))
                    ras_underflow_cnt <= ras_underflow_cnt + 1;

                // wrong-path updates (very important)
                if (br_mispredict && ras_push)
                    ras_push_wrong_path_cnt <= ras_push_wrong_path_cnt + 1;

                if (br_mispredict && ras_pop)
                    ras_pop_wrong_path_cnt <= ras_pop_wrong_path_cnt + 1;

                // simultaneous push/pop (this catches your earlier bug)
                if (ras_push && ras_pop)
                    ras_push_and_pop_same_cycle_cnt <= ras_push_and_pop_same_cycle_cnt + 1;

                // BTB Counters
                if (is_btb_eligible) begin
                    btb_queries_cnt <= btb_queries_cnt + 1;
                    if (btb_valid)
                        btb_hits_cnt <= btb_hits_cnt + 1;
                    else
                        btb_misses_cnt <= btb_misses_cnt + 1;
                end
            end
        end
    end

    // final begin
    //     $display("\nRAS Debug (Fetch Stage)");
    //     $display("---------------------------------------------");
    //     $display("RAS pushes                 : %0d", ras_push_cnt);
    //     $display("RAS pops                   : %0d", ras_pop_cnt);
    //     $display("RAS underflows             : %0d", ras_underflow_cnt);
    //     $display("Push on wrong path         : %0d", ras_push_wrong_path_cnt);
    //     $display("Pop on wrong path          : %0d", ras_pop_wrong_path_cnt);
    //     $display("Push+Pop same cycle        : %0d", ras_push_and_pop_same_cycle_cnt);

    //     $display("\nBTB Debug (Fetch Stage)");
    //     $display("---------------------------------------------");
    //     $display("BTB Queries                : %0d", btb_queries_cnt);
    //     $display("BTB Hits (Valid Preds)     : %0d", btb_hits_cnt);
    //     $display("BTB Misses (Invalid Preds) : %0d", btb_misses_cnt);
    //     $display("BTB Updates (from Commit)  : %0d", btb_updates_cnt);
    // end

    assign deq_req = !empty && !stall_decode;
    assign inst_queue_packet = deq_req ? deq_packet : '0;

    sv_queue #(
        .DATA_WIDTH($bits(inst_queue_packet_t)),
        .NUM_SLOTS(32)
    ) iqueue (
        .clk(clk),
        .rst(rst || br_mispredict),
        .enq_req(enq_packet.valid),
        .enq_allowed(enq_allowed),
        .enq_data(enq_packet),
        .deq_req(deq_req),
        .deq_allowed(deq_allowed),
        .deq_data(deq_packet),
        .full(full),
        .empty(empty)
    );

    // --- Gshare Predictor ---
    gshare bpd (
        .clk                (clk),
        .rst                (rst),
        
        // Predict port (Driven by fetch's next PC)
        .pc_next            (pc_next),
        .new_prediction     (gshare_prediction),
        .new_pht_index      (gshare_pht_index),
        
        // Update port (Driven by Commit)
        .update_predictor   (update_predictor),
        .br_outcome         (commit_br_outcome),
        .rob_old_prediction (commit_rob_old_prediction),
        .rob_pht_index      (commit_rob_pht_index)
    );

    ras my_ras (
        .clk(clk),
        .rst(rst),
        .push(ras_push), 
        .pop(ras_pop),
        .din(ras_din),
        .dout(ras_dout),
        
        // Recovery signals from ROB
        .restore_en(br_mispredict),
        .restore_ptr(rob_saved_ras_ptr),
        
        .ptr_to_rob(ras_ptr)
    );

    btb jalr_btb (
        .clk(clk),
        .rst(rst),
        
        // fetch
        .pc_read(pc_next[31:2]),
        .addr_prediction(btb_addr_prediction),
        .btb_valid(btb_valid),

        // commit
        .pc_writing(btb_pc_writing[31:2]),
        .addr_writing(branch_pc[31:2]),
        .update_btb(update_btb)
    );

endmodule