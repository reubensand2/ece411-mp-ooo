module execute
import rv32i_types::*;
(
    input   logic   clk,
    input   logic   rst,
    input   logic   flush_pipeline,
    input   logic   [23:0] flush_order,

    input   issue_packet_t          issue_packet,
    output  cdb_packet_t            execute_cdb_out,

    // ROB head order — needed so the SB knows when its head store has retired
    input   logic [23:0]            rob_head_order,

    output  logic [31:0] dmem_addr_4_bytes_aligned,
    output  logic [3:0]  dmem_rmask,
    output  logic [3:0]  dmem_wmask,
    input   logic        dmem_resp,
    input   logic [31:0] dmem_rdata,
    output  logic [31:0] dmem_wdata,
    input   logic        raw_hazard,
    output  logic        sb_full,
    output logic sb_empty,
    output sb_entry_t sb_head_entry,
    output logic store_ready,
    output logic load_ready,
    output logic sb_enq_req,
    output logic [23:0] sb_enq_order
);

    // =========================================================================
    // ALU
    // =========================================================================
    logic [31:0] alu_rd_data;

    alu alu_inst(
        .aluop(issue_packet.aluop),
        .pc(issue_packet.alu_rvfi_packet.pc_rdata),
        .alu_m1_sel(issue_packet.alu_m1_sel),
        .alu_m2_sel(issue_packet.alu_m2_sel),
        .cmpop(issue_packet.cmpop),
        .ctrl_slt(issue_packet.ctrl_slt),
        .rs1_data(issue_packet.alu_rs1_data),
        .rs2_data(issue_packet.alu_rs2_data),
        .imm(issue_packet.alu_imm),
        .rd_data(alu_rd_data)
    );

    // =========================================================================
    // MULTIPLIER
    // =========================================================================
    logic        mul_busy, mul_ready_raw, actual_mul_ready, mul_res_neg;
    logic [63:0] mul_raw_product, mul_final_product;
    logic [31:0] mul_abs_a, mul_abs_b;
    logic        start_mul;

    logic [ROB_IDX_WIDTH-1:0] mul_saved_rob_idx;
    logic [PRF_IDX_WIDTH-1:0] mul_saved_rd_paddr;
    logic mul_saved_high_bits;
    rvfi_packet_t mul_saved_rvfi;

    logic mul_sign_a, mul_sign_b;
    assign mul_sign_a = issue_packet.mul_rs1_is_signed && issue_packet.mul_rs1_data[31];
    assign mul_sign_b = issue_packet.mul_rs2_is_signed && issue_packet.mul_rs2_data[31];

    assign mul_abs_a  = mul_sign_a ? (~issue_packet.mul_rs1_data + 1'b1) : issue_packet.mul_rs1_data;
    assign mul_abs_b  = mul_sign_b ? (~issue_packet.mul_rs2_data + 1'b1) : issue_packet.mul_rs2_data;
    assign start_mul  = issue_packet.mul_issue && !mul_busy;
    assign actual_mul_ready = mul_busy ? mul_ready_raw : 1'b0;

    always_ff @(posedge clk) begin
        if (rst || flush_pipeline) begin
            mul_busy           <= '0;
            mul_res_neg        <= '0;
            mul_saved_rob_idx  <= '0;
            mul_saved_rd_paddr <= '0;
            mul_saved_rvfi     <= '0;
            mul_saved_high_bits<= '0;
        end else if (start_mul) begin
            mul_busy            <= 1'b1;
            mul_res_neg         <= mul_sign_a ^ mul_sign_b;
            mul_saved_rob_idx   <= issue_packet.mul_rob_idx;
            mul_saved_rd_paddr  <= issue_packet.mul_rd_paddr;
            mul_saved_rvfi      <= issue_packet.mul_rvfi_packet;
            mul_saved_high_bits <= issue_packet.mul_high_bits;
        end else if (actual_mul_ready) begin
            mul_busy <= 1'b0;
        end
    end

    DW_mult_seq #(
        .a_width(32), .b_width(32), .tc_mode(0),
        .num_cyc(3),  .rst_mode(0), .input_mode(1),
        .output_mode(0), .early_start(0)
    ) multiplier (
        .clk(clk), .rst_n(!(rst || flush_pipeline)),
        .hold('0),  .start(start_mul),
        .a(mul_abs_a), .b(mul_abs_b),
        .complete(mul_ready_raw), .product(mul_raw_product)
    );

    assign mul_final_product = mul_res_neg ? (~mul_raw_product + 1'b1) : mul_raw_product;

    // =========================================================================
    // DIVIDER
    // =========================================================================
    logic        div_busy, div_ready_raw, actual_div_ready, res_q_neg, res_r_neg, ip_div_0;
    logic [31:0] div_abs_a, div_abs_b, a_save, b_save, raw_q, raw_r;
    logic [31:0] div_quotient, div_remainder, div_final_product;
    logic        div_get_rem_save;
    logic        start_div;

    logic [ROB_IDX_WIDTH-1:0] div_saved_rob_idx;
    logic [PRF_IDX_WIDTH-1:0] div_saved_rd_paddr;
    rvfi_packet_t div_saved_rvfi;

    logic div_sign_a, div_sign_b;
    assign div_sign_a = issue_packet.div_rs1_is_signed && issue_packet.div_rs1_data[31];
    assign div_sign_b = issue_packet.div_rs2_is_signed && issue_packet.div_rs2_data[31];

    assign div_abs_a      = div_sign_a ? (~issue_packet.div_rs1_data + 32'h1) : issue_packet.div_rs1_data;
    assign div_abs_b      = div_sign_b ? (~issue_packet.div_rs2_data + 32'h1) : issue_packet.div_rs2_data;
    assign start_div      = issue_packet.div_issue && !div_busy;
    assign actual_div_ready = div_busy ? div_ready_raw : 1'b0;

    always_ff @(posedge clk) begin
        if (rst || flush_pipeline) begin
            div_busy           <= 1'b0;
            res_q_neg          <= '0;
            res_r_neg          <= '0;
            a_save             <= '0;
            b_save             <= '0;
            div_get_rem_save   <= '0;
            div_saved_rob_idx  <= '0;
            div_saved_rd_paddr <= '0;
            div_saved_rvfi     <= '0;
        end else if (start_div) begin
            div_busy           <= 1'b1;
            res_q_neg          <= div_sign_a ^ div_sign_b;
            res_r_neg          <= div_sign_a;
            a_save             <= issue_packet.div_rs1_data;
            b_save             <= issue_packet.div_rs2_data;
            div_get_rem_save   <= issue_packet.div_get_rem;
            div_saved_rob_idx  <= issue_packet.div_rob_idx;
            div_saved_rd_paddr <= issue_packet.div_rd_paddr;
            div_saved_rvfi     <= issue_packet.div_rvfi_packet;
        end else if (actual_div_ready) begin
            div_busy <= 1'b0;
        end
    end

    DW_div_seq #(
        .a_width(32), .b_width(32), .tc_mode(0),
        .num_cyc(16), .rst_mode(0), .input_mode(1),
        .output_mode(0), .early_start(0)
    ) divider (
        .clk(clk), .rst_n(!(rst || flush_pipeline)),
        .hold('0),  .start(start_div),
        .a(div_abs_a), .b(div_abs_b),
        .complete(div_ready_raw), .divide_by_0(ip_div_0),
        .quotient(raw_q), .remainder(raw_r)
    );

    assign div_quotient    = (b_save == 0) ? '1 : (res_q_neg ? (~raw_q + 32'h1) : raw_q);
    assign div_remainder   = (b_save == 0) ? a_save : (res_r_neg ? (~raw_r + 32'h1) : raw_r);
    assign div_final_product = div_get_rem_save ? div_remainder : div_quotient;

    // =========================================================================
    // BRANCH
    // =========================================================================
    logic br_mispredict, br_outcome;
    logic [31:0] br_rd_data, br_actual_next_pc;

    branch_alu br_alu (
        .cmpop(issue_packet.branch_cmpop),
        .br_en(issue_packet.branch_br_en),
        .jal_en(issue_packet.branch_jal_en),
        .jalr_en(issue_packet.branch_jalr_en),
        .pc(issue_packet.branch_rvfi_packet.pc_rdata),
        .predicted_pc(issue_packet.branch_predicted_pc),
        .imm(issue_packet.branch_imm),
        .rs1_data(issue_packet.branch_rs1_data),
        .rs2_data(issue_packet.branch_rs2_data),
        .br_mispredict(br_mispredict),
        .br_outcome(br_outcome),
        .actual_next_pc(br_actual_next_pc),
        .rd_data(br_rd_data)
    );

    // =========================================================================
    // LOAD & STORE — post-commit store buffer, NO FORWARDING
    // =========================================================================
    //
    // Dataflow:
    //   - issue brings in a single mem op per cycle (load OR store)
    //   - STORES: enqueue into SB at issue. CDB broadcasts mem_en=1 the same
    //     cycle (architectural retirement). Cache traffic happens later when
    //     the SB head drains.
    //   - LOADS: ALWAYS go to the cache. No SB lookup, no forwarding.
    //   - SB drain: when SB head has retired from ROB and the cache is free,
    //     SB head goes to cache. dmem_resp for the drain does NOT broadcast
    //     on CDB (store already retired at enqueue).
    // =========================================================================

    // --- Inflight (currently outstanding to cache) ---
    logic                     mem_busy;
    logic                     flush_pending;
    logic [31:0]              saved_dmem_addr;
    logic [3:0]               saved_dmem_rmask, saved_dmem_wmask;
    logic [31:0]              saved_dmem_wdata;
    logic [ROB_IDX_WIDTH-1:0] mem_saved_rob_idx;
    logic [PRF_IDX_WIDTH-1:0] mem_saved_rd_paddr;
    rvfi_packet_t             mem_saved_rvfi;
    load_f3_t                 mem_saved_ld_type;
    logic                     inflight_is_store;

    // --- Pending (load waiting for cache to free up) ---
    logic                     pending_valid;
    logic [31:0]              pending_addr;
    logic [3:0]               pending_rmask;
    logic [ROB_IDX_WIDTH-1:0] pending_rob_idx;
    logic [PRF_IDX_WIDTH-1:0] pending_rd_paddr;
    rvfi_packet_t             pending_rvfi;
    load_f3_t                 pending_ld_type;

    // --- mem_alu combinational outputs ---
    logic [31:0] dmem_addr_comb;
    logic [3:0]  dmem_rmask_comb, dmem_wmask_comb;
    logic [31:0] dmem_wdata_comb;
    logic [31:0] mem_rd_data;

    
    mem_alu m_alu (
        .mem_write        (issue_packet.mem_write),
        .rs1_data         (issue_packet.mem_rs1_data),
        .rs2_data         (issue_packet.mem_rs2_data),
        .ld_type          (issue_packet.ld_type),
        .mem_saved_ld_type(mem_saved_ld_type),
        .st_type          (issue_packet.st_type),
        .imm              (issue_packet.mem_imm),
        .dmem_resp        (dmem_resp),
        .dmem_rdata       (dmem_rdata),
        .offset           (saved_dmem_addr[1:0]),
        .dmem_addr        (dmem_addr_comb),
        .dmem_rmask       (dmem_rmask_comb),
        .dmem_wmask       (dmem_wmask_comb),
        .dmem_wdata       (dmem_wdata_comb),
        .mem_rd_data      (mem_rd_data)
    );

    logic discard_resp;
    assign discard_resp = flush_pending || flush_pipeline;

     // resend_after_raw: cache dropped our request due to RAW hazard
    logic raw_hazard_r;
    always_ff @(posedge clk) begin
        if (rst || flush_pipeline) raw_hazard_r <= '0;
        else                       raw_hazard_r <= raw_hazard;
    end

    logic resend_after_raw;
    assign resend_after_raw = raw_hazard_r && mem_busy && !flush_pipeline;

    // =========================================================================
    // STORE BUFFER (post-commit, no CAM/forwarding)
    // =========================================================================
    sb_entry_t sb_slot;
    // sb_entry_t sb_head_entry;
    // logic      sb_empty;

    logic sb_full_next;
    logic [$clog2(STORE_BUF_SIZE):0] sb_curr_size;
    // Enqueue: store issuing this cycle goes into SB.
    // logic sb_enq_req;
    assign sb_enq_req = issue_packet.mem_issue && issue_packet.mem_write
                     && !flush_pipeline && !sb_full;
    assign sb_enq_order      = issue_packet.mem_rvfi_packet.order[23:0];

    assign sb_full_next = sb_full || (sb_enq_req && ($clog2(STORE_BUF_SIZE)+1)'(sb_curr_size + 1) == ($clog2(STORE_BUF_SIZE)+1)'(STORE_BUF_SIZE));
    // SB head drains to cache when retired and cache is free.
    logic sb_head_retired;
    assign sb_head_retired = sb_head_entry.valid
                          && (rob_head_order[23:0] > sb_head_entry.rvfi_packet.order[23:0]);

    logic load_to_cache_req;
    assign load_to_cache_req = issue_packet.mem_issue && !issue_packet.mem_write
                            && !flush_pipeline;

    logic sb_drain_to_cache;
    assign sb_drain_to_cache = sb_head_retired
                            && !(execute_cdb_out.mem_busy) && !(execute_cdb_out.mem_pending)
                            && !load_to_cache_req
                            && !discard_resp;

    logic sb_deq_req;
    assign sb_deq_req = sb_drain_to_cache;

    // logic store_ready;
    // logic cache_load_completing;
    // assign cache_load_completing = mem_busy && dmem_resp && !discard_resp && !inflight_is_store;

    // Replace store_ready and load_ready with:
    // assign store_ready = !sb_full_next && !cache_load_completing;
    assign store_ready = !sb_full_next && !(execute_cdb_out.mem_busy) && !(execute_cdb_out.mem_pending);
    // assign load_ready = !(execute_cdb_out.mem_busy) && !(execute_cdb_out.mem_pending) && !raw_hazard;
    assign load_ready = (!mem_busy || dmem_resp) && !pending_valid;
    store_buf #(
        .STORE_BUF_SIZE(STORE_BUF_SIZE),
        .NUM_UPDATE_PORTS(0)
    ) dummy_store_buf (
        .clk(clk),
        .rst(rst),

        .enq_req(sb_enq_req),
        .enq_data(sb_slot),

        .flush_en   (flush_pipeline),
        .flush_order(flush_order),

        .deq_req        (sb_deq_req),
        .deq_data       (sb_head_entry),

        .full           (sb_full),
        .empty          (sb_empty),
        .curr_size(sb_curr_size)
    );

    // =========================================================================
    // Cache request scheduling
    // =========================================================================
    logic send_load_direct;
    assign send_load_direct = load_to_cache_req
                           && (!mem_busy || dmem_resp)
                           && !pending_valid;

    logic accept_load_new;
    assign accept_load_new = load_to_cache_req
                          && mem_busy && !dmem_resp
                          && !pending_valid;

    logic fire_to_cache;
    assign fire_to_cache = pending_valid && dmem_resp
                        && !flush_pending && !flush_pipeline;


    // =========================================================================
    // Inflight / pending state update
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            mem_busy           <= '0;
            flush_pending      <= '0;
            pending_valid      <= '0;
            pending_addr       <= '0;
            pending_rmask      <= '0;
            pending_rob_idx    <= '0;
            pending_rd_paddr   <= '0;
            pending_rvfi       <= '0;
            pending_ld_type    <= load_f3_t'('0);
            saved_dmem_addr    <= '0;
            saved_dmem_rmask   <= '0;
            saved_dmem_wmask   <= '0;
            saved_dmem_wdata   <= '0;
            mem_saved_rob_idx  <= '0;
            mem_saved_rd_paddr <= '0;
            mem_saved_ld_type  <= load_f3_t'('0);
            mem_saved_rvfi     <= '0;
            inflight_is_store  <= '0;
        end
        else if (flush_pipeline) begin
            pending_valid <= '0;
            if (dmem_resp) begin
                mem_busy      <= '0;
                flush_pending <= '0;
            end else if (mem_busy) begin
                flush_pending <= '1;
            end
        end
        else begin
            // ----- Inflight slot updates -----
            if (send_load_direct) begin
                mem_busy           <= 1'b1;
                flush_pending      <= '0;
                inflight_is_store  <= 1'b0;
                saved_dmem_addr    <= dmem_addr_comb;
                saved_dmem_rmask   <= dmem_rmask_comb;
                saved_dmem_wmask   <= '0;
                saved_dmem_wdata   <= '0;
                mem_saved_rob_idx  <= issue_packet.mem_rob_idx;
                mem_saved_rd_paddr <= issue_packet.mem_rd_paddr;
                mem_saved_ld_type  <= issue_packet.ld_type;
                mem_saved_rvfi     <= issue_packet.mem_rvfi_packet;
            end
            else if (sb_drain_to_cache) begin
                mem_busy           <= 1'b1;
                flush_pending      <= '0;
                inflight_is_store  <= 1'b1;
                saved_dmem_addr    <= sb_head_entry.dmem_addr;
                saved_dmem_rmask   <= '0;
                saved_dmem_wmask   <= sb_head_entry.dmem_wmask;
                saved_dmem_wdata   <= sb_head_entry.dmem_wdata;
                mem_saved_rob_idx  <= sb_head_entry.rob_idx;
                mem_saved_rd_paddr <= '0;
                mem_saved_ld_type  <= load_f3_t'('0);
                mem_saved_rvfi     <= sb_head_entry.rvfi_packet;
            end
            else if (fire_to_cache) begin
                mem_busy           <= 1'b1;
                flush_pending      <= '0;
                inflight_is_store  <= 1'b0;
                saved_dmem_addr    <= pending_addr;
                saved_dmem_rmask   <= pending_rmask;
                saved_dmem_wmask   <= '0;
                saved_dmem_wdata   <= '0;
                mem_saved_rob_idx  <= pending_rob_idx;
                mem_saved_rd_paddr <= pending_rd_paddr;
                mem_saved_ld_type  <= pending_ld_type;
                mem_saved_rvfi     <= pending_rvfi;
            end
            else if (dmem_resp) begin
                mem_busy      <= '0;
                flush_pending <= '0;
            end

            // ----- Pending slot updates -----
            if (accept_load_new) begin
                pending_valid     <= '1;
                pending_addr      <= dmem_addr_comb;
                pending_rmask     <= dmem_rmask_comb;
                pending_rob_idx   <= issue_packet.mem_rob_idx;
                pending_rd_paddr  <= issue_packet.mem_rd_paddr;
                pending_ld_type   <= issue_packet.ld_type;
                pending_rvfi      <= issue_packet.mem_rvfi_packet;
            end
            else if (fire_to_cache) begin
                pending_valid <= '0;
            end

            // RAW hazard latch — only meaningful for loads
            if (raw_hazard && !flush_pipeline && load_to_cache_req) begin
                saved_dmem_addr    <= dmem_addr_comb;
                saved_dmem_rmask   <= dmem_rmask_comb;
                saved_dmem_wmask   <= '0;
                saved_dmem_wdata   <= '0;
                mem_saved_rob_idx  <= issue_packet.mem_rob_idx;
                mem_saved_rd_paddr <= issue_packet.mem_rd_paddr;
                mem_saved_ld_type  <= issue_packet.ld_type;
                mem_saved_rvfi     <= issue_packet.mem_rvfi_packet;
                inflight_is_store  <= 1'b0;
                mem_busy           <= 1'b1;
            end
        end
    end

    // =========================================================================
    // Build SB enqueue payload
    // =========================================================================
    always_comb begin
        sb_slot             = '0;
        sb_slot.valid       = 1'b1;
        sb_slot.rob_idx     = issue_packet.mem_rob_idx;
        sb_slot.dmem_addr   = dmem_addr_comb & 32'hFFFF_FFFC;
        sb_slot.dmem_wmask  = dmem_wmask_comb;
        sb_slot.dmem_wdata  = dmem_wdata_comb;
        sb_slot.rvfi_packet = issue_packet.mem_rvfi_packet;
    end

    // =========================================================================
    // Build CDB output
    //
    // Two mem completion paths:
    //   (1) Cache response for a LOAD  → mem_en=1 with load's saved info
    //   (2) Store enqueue into SB      → mem_en=1 with store's issue info
    //
    // Cache response for a STORE-DRAIN: NO CDB broadcast (store already
    // retired at enqueue; the cache write is just a side effect).
    //
    // These two paths are mutually exclusive in practice: a store can only
    // be issuing when issue.sv allows it (mem_ready high), and mem_ready is
    // gated by !mem_busy. dmem_resp implies mem_busy was 1 going into this
    // cycle, which means issue.sv saw mem_ready=0 last cycle and didn't
    // issue anything that arrives at execute this cycle. Defensive ordering
    // below: cache response wins.
    // =========================================================================
    always_comb begin
        execute_cdb_out = '0;

        // --- ALU ---
        execute_cdb_out.alu_en          = issue_packet.alu_issue;
        execute_cdb_out.alu_rob_idx     = issue_packet.alu_rob_idx;
        execute_cdb_out.alu_rd_addr     = issue_packet.alu_rvfi_packet.rd_addr;
        execute_cdb_out.alu_rd_paddr    = issue_packet.alu_rd_paddr;
        execute_cdb_out.alu_result      = alu_rd_data;
        execute_cdb_out.alu_rvfi_packet = issue_packet.alu_rvfi_packet;
        execute_cdb_out.alu_rvfi_packet.rd_wdata = alu_rd_data;
        execute_cdb_out.alu_rvfi_packet.pc_wdata = issue_packet.alu_rvfi_packet.pc_rdata + 4;

        // --- MUL ---
        execute_cdb_out.mul_en          = actual_mul_ready;
        execute_cdb_out.mul_busy        = start_mul ? 1'b1 : mul_busy;
        execute_cdb_out.mul_rob_idx     = mul_saved_rob_idx;
        execute_cdb_out.mul_rd_paddr    = mul_saved_rd_paddr;
        execute_cdb_out.mul_rd_addr     = mul_saved_rvfi.rd_addr;
        execute_cdb_out.mul_result      = mul_saved_high_bits ? mul_final_product[63:32] : mul_final_product[31:0];
        execute_cdb_out.mul_rvfi_packet = mul_saved_rvfi;
        execute_cdb_out.mul_rvfi_packet.rd_wdata = mul_saved_high_bits ? mul_final_product[63:32] : mul_final_product[31:0];
        execute_cdb_out.mul_rvfi_packet.pc_wdata = mul_saved_rvfi.pc_rdata + 4;

        // --- DIV ---
        execute_cdb_out.div_en          = actual_div_ready;
        execute_cdb_out.div_busy        = start_div ? 1'b1 : div_busy;
        execute_cdb_out.div_rob_idx     = div_saved_rob_idx;
        execute_cdb_out.div_rd_addr     = div_saved_rvfi.rd_addr;
        execute_cdb_out.div_rd_paddr    = div_saved_rd_paddr;
        execute_cdb_out.div_result      = div_final_product;
        execute_cdb_out.div_rvfi_packet = div_saved_rvfi;
        execute_cdb_out.div_rvfi_packet.rd_wdata = div_final_product;
        execute_cdb_out.div_rvfi_packet.pc_wdata = div_saved_rvfi.pc_rdata + 4;

        // --- BRANCH ---
        execute_cdb_out.branch_en               = issue_packet.branch_issue;
        execute_cdb_out.branch_rob_idx          = issue_packet.branch_rob_idx;
        execute_cdb_out.branch_rd_addr          = issue_packet.branch_rvfi_packet.rd_addr;
        execute_cdb_out.branch_rd_paddr         = issue_packet.branch_rd_paddr;
        execute_cdb_out.branch_result           = br_rd_data;
        execute_cdb_out.branch_mispredict       = br_mispredict;
        execute_cdb_out.branch_outcome          = br_outcome;
        execute_cdb_out.branch_rvfi_packet      = issue_packet.branch_rvfi_packet;
        execute_cdb_out.branch_rvfi_packet.rd_wdata = br_rd_data;
        execute_cdb_out.branch_rvfi_packet.pc_wdata = br_actual_next_pc;

        if (dmem_resp && !discard_resp && !inflight_is_store) begin
            // (1) Cache response for a LOAD
            execute_cdb_out.mem_en        = 1'b1;
            execute_cdb_out.mem_pending   = accept_load_new ? 1'b1
                                          : fire_to_cache  ? 1'b0
                                          : pending_valid;
            execute_cdb_out.mem_busy      = mem_busy && !dmem_resp;
            execute_cdb_out.mem_rob_idx   = mem_saved_rob_idx;
            execute_cdb_out.mem_rd_addr   = mem_saved_rvfi.rd_addr;
            execute_cdb_out.mem_rd_paddr  = mem_saved_rd_paddr;
            execute_cdb_out.mem_result    = mem_rd_data;
            execute_cdb_out.mem_rvfi_packet           = mem_saved_rvfi;
            execute_cdb_out.mem_rvfi_packet.rd_wdata  = mem_rd_data;
            execute_cdb_out.mem_rvfi_packet.mem_addr  = saved_dmem_addr;
            execute_cdb_out.mem_rvfi_packet.mem_rmask = saved_dmem_rmask;
            execute_cdb_out.mem_rvfi_packet.mem_rdata = dmem_rdata;
            execute_cdb_out.mem_rvfi_packet.mem_wmask = '0;
            execute_cdb_out.mem_rvfi_packet.mem_wdata = '0;
            execute_cdb_out.mem_rvfi_packet.pc_wdata  = mem_saved_rvfi.pc_rdata + 4;
            
            if (sb_enq_req) begin
                // (2) Store enqueue — completes architecturally as it lands in SB
                execute_cdb_out.store_en        = 1'b1;
                execute_cdb_out.store_rob_idx   = issue_packet.mem_rob_idx;
                execute_cdb_out.store_rvfi_packet           = issue_packet.mem_rvfi_packet;
                execute_cdb_out.store_rvfi_packet.rd_wdata  = '0;
                execute_cdb_out.store_rvfi_packet.mem_addr  = dmem_addr_comb & 32'hFFFF_FFFC;
                execute_cdb_out.store_rvfi_packet.mem_rmask = '0;
                execute_cdb_out.store_rvfi_packet.mem_rdata = '0;
                execute_cdb_out.store_rvfi_packet.mem_wmask = dmem_wmask_comb;
                execute_cdb_out.store_rvfi_packet.mem_wdata = dmem_wdata_comb;
                execute_cdb_out.store_rvfi_packet.pc_wdata  = issue_packet.mem_rvfi_packet.pc_rdata + 4;
            end
        end
        else if (sb_enq_req) begin
            // (2) Store enqueue — completes architecturally as it lands in SB
            // execute_cdb_out.mem_en        = 1'b1;
            execute_cdb_out.store_en        = 1'b1;
            execute_cdb_out.mem_pending   = pending_valid;
            execute_cdb_out.mem_busy      = mem_busy && !dmem_resp;
            execute_cdb_out.store_rob_idx   = issue_packet.mem_rob_idx;
            execute_cdb_out.mem_rd_addr   = '0;
            execute_cdb_out.mem_rd_paddr  = '0;
            execute_cdb_out.mem_result    = '0;
            execute_cdb_out.store_rvfi_packet           = issue_packet.mem_rvfi_packet;
            execute_cdb_out.store_rvfi_packet.rd_wdata  = '0;
            execute_cdb_out.store_rvfi_packet.mem_addr  = dmem_addr_comb & 32'hFFFF_FFFC;
            execute_cdb_out.store_rvfi_packet.mem_rmask = '0;
            execute_cdb_out.store_rvfi_packet.mem_rdata = '0;
            execute_cdb_out.store_rvfi_packet.mem_wmask = dmem_wmask_comb;
            execute_cdb_out.store_rvfi_packet.mem_wdata = dmem_wdata_comb;
            execute_cdb_out.store_rvfi_packet.pc_wdata  = issue_packet.mem_rvfi_packet.pc_rdata + 4;
        end
        else begin
            // No mem completion this cycle (idle, or store-drain cache response)
            execute_cdb_out.mem_en        = 1'b0;
            execute_cdb_out.mem_pending   = pending_valid;
            execute_cdb_out.mem_busy      = mem_busy && !dmem_resp;
            execute_cdb_out.mem_rob_idx   = '0;
            execute_cdb_out.mem_rd_addr   = '0;
            execute_cdb_out.mem_rd_paddr  = '0;
            execute_cdb_out.mem_result    = '0;
            execute_cdb_out.mem_rvfi_packet           = '0;
        end

        // =====================================================================
        // Drive cache request signals
        // Priority:
        //   resend_after_raw > sb_drain_to_cache > send_load_direct > fire_to_cache > idle
        // =====================================================================
        if (resend_after_raw) begin
            dmem_rmask                = saved_dmem_rmask;
            dmem_wmask                = saved_dmem_wmask;
            dmem_wdata                = saved_dmem_wdata;
            dmem_addr_4_bytes_aligned = saved_dmem_addr & 32'hFFFF_FFFC;
        end
        else if (sb_drain_to_cache) begin
            dmem_rmask                = '0;
            dmem_wmask                = sb_head_entry.dmem_wmask;
            dmem_wdata                = sb_head_entry.dmem_wdata;
            dmem_addr_4_bytes_aligned = sb_head_entry.dmem_addr;
        end
        else if (send_load_direct) begin
            dmem_rmask                = dmem_rmask_comb;
            dmem_wmask                = '0;
            dmem_wdata                = '0;
            dmem_addr_4_bytes_aligned = dmem_addr_comb & 32'hFFFF_FFFC;
        end
        else if (fire_to_cache) begin
            dmem_rmask                = pending_rmask;
            dmem_wmask                = '0;
            dmem_wdata                = '0;
            dmem_addr_4_bytes_aligned = pending_addr & 32'hFFFF_FFFC;
        end
        else begin
            dmem_rmask                = '0;
            dmem_wmask                = '0;
            dmem_wdata                = '0;
            dmem_addr_4_bytes_aligned = '0;
        end
    end
    // Memory access debug monitor
    // Set WATCH_ADDR to the address you want to observe.
    // =====================================================================

    // localparam logic [31:0] WATCH_ADDR = 32'haaab_10b8; // <-- change this

    // always_ff @(posedge clk) begin
    //     if (!rst) begin

    //         // Watch for loads completing
    //         if (execute_cdb_out.mem_en
    //             && (saved_dmem_addr & 32'hFFFF_FFFC) == (WATCH_ADDR & 32'hFFFF_FFFC)) begin
    //             $display(" READ  | addr=0x%08h | data=0x%08h | rmask=4'b%04b | rob=%0d | order=%0d | pc=0x%08h | inst=0x%08h",
    //                 saved_dmem_addr,
    //                 execute_cdb_out.mem_result,
    //                 saved_dmem_rmask,
    //                 execute_cdb_out.mem_rob_idx,
    //                 execute_cdb_out.mem_rvfi_packet.order,
    //                 execute_cdb_out.mem_rvfi_packet.pc_rdata,
    //                 execute_cdb_out.mem_rvfi_packet.inst);
    //         end

    //         // Watch for stores enqueuing into SB
    //         if (sb_enq_req
    //             && (sb_slot.dmem_addr & 32'hFFFF_FFFC) == (WATCH_ADDR & 32'hFFFF_FFFC)) begin
    //             $display("| WRITE | addr=0x%08h | data=0x%08h | wmask=4'b%04b | rob=%0d | order=%0d | pc=0x%08h | inst=0x%08h",
    //                 sb_slot.dmem_addr,
    //                 sb_slot.dmem_wdata,
    //                 sb_slot.dmem_wmask,
    //                 sb_slot.rob_idx,
    //                 sb_slot.rvfi_packet.order,
    //                 sb_slot.rvfi_packet.pc_rdata,
    //                 sb_slot.rvfi_packet.inst);
    //         end

    //         // Watch for SB draining to cache at that address
    //         if (sb_drain_to_cache
    //             && (sb_head_entry.dmem_addr & 32'hFFFF_FFFC) == (WATCH_ADDR & 32'hFFFF_FFFC)) begin
    //             $display("| DRAIN | addr=0x%08h | data=0x%08h | wmask=4'b%04b | order=%0d | pc=0x%08h | inst=0x%08h",
    //                 sb_head_entry.dmem_addr,
    //                 sb_head_entry.dmem_wdata,
    //                 sb_head_entry.dmem_wmask,
    //                 sb_head_entry.rvfi_packet.order,
    //                 sb_head_entry.rvfi_packet.pc_rdata,
    //                 sb_head_entry.rvfi_packet.inst);
    //         end

    //     end
    // end

endmodule
