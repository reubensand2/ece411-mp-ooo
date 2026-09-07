module cpu
import rv32i_types::*;
(
    input   logic               clk,
    input   logic               rst,

    output  logic   [31:0]      dram_addr,
    output  logic               dram_read,
    output  logic               dram_write,
    output  logic   [63:0]      dram_wdata,
    input   logic               dram_ready,

    input   logic   [31:0]      dram_raddr,
    input   logic   [63:0]      dram_rdata,
    input   logic               dram_rvalid
);   
    // cache and dram signals
    logic   [31:0]  imem_addr, imem_rdata;
    logic   [3:0]   imem_rmask, imem_wmask;
    logic           imem_resp;
    logic   [31:0]  dmem_addr, dmem_rdata, dmem_wdata;
    logic   [3:0]   dmem_rmask, dmem_wmask;
    logic           dmem_resp;
    logic   [255:0] hit_icache_line;
    logic   [31:0]  hit_icache_line_addr;
    logic   [31:0]  icache_addr, dcache_addr;
    logic           icache_read, dcache_read;
    logic           icache_write, dcache_write;
    logic   [255:0] icache_rdata, dcache_rdata;
    logic   [255:0] icache_wdata, dcache_wdata;
    logic           icache_resp, dcache_resp;
    
    // fetch outputs
    inst_queue_packet_t inst_queue_packet;

    // decode outputs
    decode_packet_t  decode_packet, decode_packet_next;

    // dispatch outputs
    logic           rat_we;
    logic   [4:0]   rat_rd_addr_for_invalidating_rat;
    logic   [PRF_IDX_WIDTH-1:0] rat_phys_reg_set;
    logic           get_phys_reg_from_fl;
    dispatch_packet_t dispatch_packet;
    logic           stall_decode;

    // issue outputs
    issue_packet_t issue_packet, issue_packet_next;
    rs_clear_t  rs_clear;
    logic [(PRF_IDX_WIDTH-1):0] alu_rs1_raddr, alu_rs2_raddr, mul_rs1_raddr, mul_rs2_raddr, div_rs1_raddr, div_rs2_raddr;

    // execute outputs
    cdb_packet_t    cdb_packet_ex;

    // writeback registered and combined signals
    cdb_packet_t    cdb_packet_wb;
    logic   [(RS_NUM_WAKEUP_PORTS-1):0]   cdb_rs_wakeup_bus;
    logic   [(ROB_NUM_WRITE_PORTS-1):0]   cdb_rob_wakeup_bus;

    assign cdb_rs_wakeup_bus = {cdb_packet_wb.mem_en, cdb_packet_wb.branch_en, cdb_packet_wb.div_en, cdb_packet_wb.mul_en, cdb_packet_wb.alu_en};
    assign cdb_rob_wakeup_bus = {cdb_packet_wb.store_en, cdb_packet_wb.mem_en, cdb_packet_wb.branch_en, cdb_packet_wb.div_en, cdb_packet_wb.mul_en, cdb_packet_wb.alu_en};
    

    // reservation stations
    logic           alu_rs_full;
    alu_res_station_entry_t alu_res_station[ALU_RES_STATION_SIZE];
    logic           mul_rs_full;
    mul_res_station_entry_t mul_res_station[MUL_RES_STATION_SIZE];
    logic           div_rs_full; 
    div_res_station_entry_t div_res_station[DIV_RES_STATION_SIZE];
    logic           branch_rs_full;
    branch_res_station_entry_t branch_res_station[BR_RES_STATION_SIZE];
    logic           ld_rs_full;
    ld_res_station_entry_t ld_res_station[LD_RES_STATION_SIZE];
    logic [PRF_IDX_WIDTH-1:0] rs_ready_addr_bus [RS_NUM_WAKEUP_PORTS];

    assign rs_ready_addr_bus[0] = cdb_packet_wb.alu_rd_paddr;
    assign rs_ready_addr_bus[1] = cdb_packet_wb.mul_rd_paddr;
    assign rs_ready_addr_bus[2] = cdb_packet_wb.div_rd_paddr;
    assign rs_ready_addr_bus[3] = cdb_packet_wb.branch_rd_paddr;
    assign rs_ready_addr_bus[4] = cdb_packet_wb.mem_rd_paddr;

    // ROB outputs
    logic [ROB_IDX_WIDTH-1:0] rob_idx;
    rob_entry_t     head_of_rob;
    rob_entry_t     head_of_rob_1;
    logic           rob_full;
    logic           rob_empty;
    logic           rob_empty_1;

    // commit signals
    logic           commit;
    logic           commit_two;
    logic           commit_reg_write;
    logic           commit_reg_write_1;
    logic           waw;

    logic [ROB_IDX_WIDTH-1:0]   rob_idx_bus [ROB_NUM_WRITE_PORTS];
    rvfi_packet_t               rvfi_packet_bus [ROB_NUM_WRITE_PORTS];
    logic                       branch_mispredict_bus[ROB_NUM_WRITE_PORTS];
    logic                       branch_outcome_bus[ROB_NUM_WRITE_PORTS];

    assign rob_idx_bus[0] = cdb_packet_wb.alu_rob_idx;
    assign rob_idx_bus[1] = cdb_packet_wb.mul_rob_idx;
    assign rob_idx_bus[2] = cdb_packet_wb.div_rob_idx;
    assign rob_idx_bus[3] = cdb_packet_wb.branch_rob_idx;
    assign rob_idx_bus[4] = cdb_packet_wb.mem_rob_idx;
    assign rob_idx_bus[5] = cdb_packet_wb.store_rob_idx;

    assign rvfi_packet_bus[0] = cdb_packet_wb.alu_rvfi_packet;
    assign rvfi_packet_bus[1] = cdb_packet_wb.mul_rvfi_packet;
    assign rvfi_packet_bus[2] = cdb_packet_wb.div_rvfi_packet;
    assign rvfi_packet_bus[3] = cdb_packet_wb.branch_rvfi_packet;
    assign rvfi_packet_bus[4] = cdb_packet_wb.mem_rvfi_packet;
    assign rvfi_packet_bus[5] = cdb_packet_wb.store_rvfi_packet;
    assign branch_mispredict_bus[0] = '0;
    assign branch_mispredict_bus[1] = '0;
    assign branch_mispredict_bus[2] = '0;
    assign branch_mispredict_bus[3] = cdb_packet_wb.branch_mispredict;
    assign branch_mispredict_bus[4] = '0;
    assign branch_mispredict_bus[5] = '0;
    assign branch_outcome_bus[0] = '0;
    assign branch_outcome_bus[1] = '0;
    assign branch_outcome_bus[2] = '0;
    assign branch_outcome_bus[3] = cdb_packet_wb.branch_outcome;
    assign branch_outcome_bus[4] = '0;
    assign branch_outcome_bus[5] = '0;
    
    // free list outputs
    logic [PRF_IDX_WIDTH-1:0]   phys_reg_from_fl;
    logic                       free_list_empty;
    logic [PRF_SIZE-1:0]        recovery_mask;


    // RAT outputs
    logic   [($clog2(RAT_NUM_SLOTS)-1):0]   rat_waddr_bus [RAT_NUM_WRITE_PORTS];
    logic   [PRF_IDX_WIDTH-1:0]             rat_wdata_bus [RAT_NUM_WRITE_PORTS];
    logic   [($clog2(RAT_NUM_SLOTS)-1):0]   rat_raddr_bus [RAT_NUM_READ_PORTS];
    logic   [PRF_IDX_WIDTH-1:0]             rat_rdata_bus [RAT_NUM_READ_PORTS];
    logic                                   rat_valid_bus [RAT_NUM_READ_PORTS];

    assign rat_waddr_bus[0] = rat_rd_addr_for_invalidating_rat;
    assign rat_wdata_bus[0] = rat_phys_reg_set;
    assign rat_raddr_bus[0] = dispatch_packet.rat_rs1_addr;
    assign rat_raddr_bus[1] = dispatch_packet.rat_rs2_addr;

    // PRF input/outputs
    logic [31:0]                prf_rdata[PRF_NUM_READ_PORTS];
    logic [(PRF_IDX_WIDTH-1):0] prf_raddr_bus [PRF_NUM_READ_PORTS];
    logic [PRF_NUM_WRITE_PORTS-1:0] prf_we_bus;
    logic [PRF_IDX_WIDTH-1:0] prf_waddr_bus [PRF_NUM_WRITE_PORTS];
    logic [31:0]                prf_wdata_bus [PRF_NUM_WRITE_PORTS];

    logic raw_hazard; 
    // logic [(PRF_IDX_WIDTH-1):0] mem_rs1_raddr;
    logic [(PRF_IDX_WIDTH-1):0] mem_rs1_raddr;
    logic [(PRF_IDX_WIDTH-1):0] mem_rs2_raddr;
    logic [(PRF_IDX_WIDTH-1):0] branch_rs1_raddr;
    logic [(PRF_IDX_WIDTH-1):0] branch_rs2_raddr;

    assign prf_raddr_bus[0] = alu_rs1_raddr;
    assign prf_raddr_bus[1] = alu_rs2_raddr;
    assign prf_raddr_bus[2] = mul_rs1_raddr;
    assign prf_raddr_bus[3] = mul_rs2_raddr;
    assign prf_raddr_bus[4] = div_rs1_raddr;
    assign prf_raddr_bus[5] = div_rs2_raddr;

    assign prf_raddr_bus[6] = branch_rs1_raddr;
    assign prf_raddr_bus[7] = branch_rs2_raddr;
    assign prf_raddr_bus[8] = mem_rs1_raddr;
    assign prf_raddr_bus[9] = mem_rs2_raddr;
    // assign prf_raddr_bus[10] = str_rs2_raddr;

    // reuben do we need wdata bus for branch?
    assign prf_wdata_bus[0] = cdb_packet_wb.alu_result;
    assign prf_wdata_bus[1] = cdb_packet_wb.mul_result;
    assign prf_wdata_bus[2] = cdb_packet_wb.div_result;
    assign prf_wdata_bus[3] = cdb_packet_wb.mem_result;
    assign prf_wdata_bus[4] = cdb_packet_wb.branch_result;

    assign prf_we_bus[0] = cdb_packet_wb.alu_en;
    assign prf_we_bus[1] = cdb_packet_wb.mul_en;
    assign prf_we_bus[2] = cdb_packet_wb.div_en;
    assign prf_we_bus[3] = cdb_packet_wb.mem_en;
    assign prf_we_bus[4] = cdb_packet_wb.branch_en;

    assign prf_waddr_bus[0] = cdb_packet_wb.alu_rd_paddr;
    assign prf_waddr_bus[1] = cdb_packet_wb.mul_rd_paddr;
    assign prf_waddr_bus[2] = cdb_packet_wb.div_rd_paddr;
    assign prf_waddr_bus[3] = cdb_packet_wb.mem_rd_paddr;
    assign prf_waddr_bus[4] = cdb_packet_wb.branch_rd_paddr;
    
    // RRAT outptus
    logic [PRF_IDX_WIDTH-1:0]               rrat_wdata_bus [RRAT_NUM_WRITE_PORTS];
    logic [($clog2(RRAT_NUM_SLOTS)-1):0]    rrat_raddr_bus [RRAT_NUM_READ_PORTS];
    logic [($clog2(RRAT_NUM_SLOTS)-1):0]    rrat_waddr_bus [RRAT_NUM_WRITE_PORTS];
    logic [PRF_IDX_WIDTH-1:0]               rrat_rdata_bus [RRAT_NUM_READ_PORTS];
    logic [PRF_IDX_WIDTH-1:0]               rrat_state_bus [RRAT_NUM_SLOTS];
    logic [RRAT_NUM_WRITE_PORTS-1:0] rrat_we; 
    
    assign rrat_wdata_bus[0] = head_of_rob.rd_paddr;
    assign rrat_raddr_bus[0] = head_of_rob.rvfi_packet.rd_addr;
    assign rrat_waddr_bus[0] = head_of_rob.rvfi_packet.rd_addr;

    assign rrat_wdata_bus[1] = head_of_rob_1.rd_paddr;
    assign rrat_raddr_bus[1] = head_of_rob_1.rvfi_packet.rd_addr;
    assign rrat_waddr_bus[1] = head_of_rob_1.rvfi_packet.rd_addr;

    // store_Q outputs
    logic           sq_full;
    logic           sq_empty;
    sq_entry_t sq_head_entry;

    logic sb_full;
    logic sb_empty;
    sb_entry_t sb_head_entry;
    logic sb_enq_req;
    logic [23:0] sb_enq_order;

    logic store_ready;
    logic load_ready;
    logic sq_deq_req;
    
    logic           flush_pipeline;

    assign rrat_we[0] = commit_reg_write;
    assign rrat_we[1] = commit_reg_write_1;

    // pipeline registers
    always_ff @(posedge clk) begin
        if (rst || flush_pipeline) begin
            decode_packet <= '0;
            cdb_packet_wb <= '0;
            issue_packet <= '0;
        end else begin
            if(!stall_decode)
                decode_packet <= decode_packet_next;
            
            issue_packet <= issue_packet_next;
            cdb_packet_wb <= cdb_packet_ex;
        end
    end

    cacheline_adapter adapter (
        .clk(clk),
        .rst(rst),

        .dram_addr(dram_addr), 
        .dram_read(dram_read),
        .dram_write(dram_write),
        .dram_wdata(dram_wdata),
        .dram_ready(dram_ready),

        .dram_raddr(dram_raddr),
        .dram_rdata(dram_rdata), 
        .dram_rvalid(dram_rvalid),

        .icache_addr(icache_addr),
        .icache_read(icache_read),
        .icache_rdata(icache_rdata),
        .icache_resp(icache_resp),

        .dcache_addr(dcache_addr),
        .dcache_read(dcache_read),
        .dcache_write(dcache_write),
        .dcache_rdata(dcache_rdata),
        .dcache_wdata(dcache_wdata),
        .dcache_resp(dcache_resp)
    );

    // icache instr_cache (
    //     .clk(clk),
    //     .rst(rst),

    //     // cpu side signals, ufp -> upward facing port
    //     .ufp_addr(imem_addr),
    //     .ufp_rmask(imem_rmask),
    //     // .ufp_rdata(imem_rdata),
    //     .ufp_resp(imem_resp),

    //     // memory side signals, dfp -> downward facing port
    //     .dfp_addr(icache_addr),
    //     .dfp_read(icache_read),
    //     .dfp_rdata(icache_rdata),
    //     .dfp_resp(icache_resp),

    //     .hit_cache_line(hit_icache_line),
    //     .hit_cache_line_addr(hit_icache_line_addr)
    // );

    icache_pp instr_cache_pp (
        .clk(clk),
        .rst(rst),

        // cpu side signals, ufp -> upward facing port
        .ufp_addr(imem_addr),
        .ufp_rmask(imem_rmask),
        .ufp_resp(imem_resp),

        // memory side signals, dfp -> downward facing port
        .dfp_addr(icache_addr),
        .dfp_read(icache_read),
        .dfp_rdata(icache_rdata),
        .dfp_resp(icache_resp),

        .hit_cache_line(hit_icache_line),
        .hit_cache_line_addr(hit_icache_line_addr)
    );

    dcache_pp data_cache (
        .clk(clk),
        .rst(rst),

        // cpu side signals, ufp -> upward facing port
        .ufp_addr(dmem_addr),
        .ufp_rmask(dmem_rmask),
        .ufp_wmask(dmem_wmask),
        .ufp_rdata(dmem_rdata),
        .ufp_wdata(dmem_wdata),
        .ufp_resp(dmem_resp),
        .ufp_raw_hazard(raw_hazard),

        // memory side signals, dfp -> downward facing port
        .dfp_addr(dcache_addr),
        .dfp_read(dcache_read),
        .dfp_write(dcache_write),
        .dfp_rdata(dcache_rdata),
        .dfp_wdata(dcache_wdata),
        .dfp_resp(dcache_resp)

        // .hit_cache_line(hit_dcache_line),
        // .hit_cache_line_addr(hit_dcache_line_addr)
    );
    
    fetch dummy_fetch (
        .clk(clk),
        .rst(rst),
        .imem_resp(imem_resp),
        
        .hit_cache_line(hit_icache_line),
        .hit_cache_line_addr(hit_icache_line_addr),

        // branch mispredict
        .br_mispredict(flush_pipeline),
        .branch_pc(head_of_rob.rvfi_packet.pc_wdata),
        .branch_order(head_of_rob.rvfi_packet.order),
        
        // ghsare update
        .update_predictor(commit && head_of_rob.is_conditional),        // test whether update on conditional or all is better
        .commit_br_outcome(head_of_rob.branch_outcome),
        .commit_rob_old_prediction(head_of_rob.rob_old_prediction),
        .commit_rob_pht_index(head_of_rob.rob_pht_index),

        // ras update
        .rob_saved_ras_ptr(head_of_rob.ras_top_ptr),

        // btb update
        .update_btb(commit && head_of_rob.is_non_return_jalr),
        .btb_pc_writing(head_of_rob.rvfi_packet.pc_rdata),

        .stall_decode(stall_decode),
        .imem_addr(imem_addr),
        .imem_rmask(imem_rmask),
        .inst_queue_packet(inst_queue_packet)
    );

    decode dummy_decode (
        .inst_queue_packet(inst_queue_packet),
        .decode_packet(decode_packet_next)
    );

    dispatch dummy_dispatch (
        .decode_packet_in(decode_packet),
        .alu_rs_full(alu_rs_full),
        .mul_rs_full(mul_rs_full),
        .div_rs_full(div_rs_full),
        .ld_rs_full(ld_rs_full),
        .sq_full(sq_full),
        .sb_full(sb_full),
        .branch_rs_full(branch_rs_full),

        .rob_full(rob_full),
        .rob_idx(rob_idx),
        .rat_rs1_valid(rat_valid_bus[0]),           // -> dispatch.sv 
        .rat_rs2_valid(rat_valid_bus[1]),           // -> dispatch.sv
        .rat_rs1_paddr(rat_rdata_bus[0]), // -> dispatch.sv 
        .rat_rs2_paddr(rat_rdata_bus[1]), // -> dispatch.sv 
        .rat_rd_addr_for_invalidating_rat(rat_rd_addr_for_invalidating_rat),
        .rat_phys_reg_set(rat_phys_reg_set),
        .rat_we(rat_we),

        .cdb_packet_wb(cdb_packet_wb),
        .fl_phys_addr(phys_reg_from_fl),
        .fl_empty(free_list_empty),
        .fl_req(get_phys_reg_from_fl),

        .dispatch_packet(dispatch_packet),
        .stall_decode(stall_decode)
    );

    issue dummy_issue (
        .prf_data(prf_rdata[0:9]),

        .alu_res_station(alu_res_station),
        .mul_res_station(mul_res_station),
        .div_res_station(div_res_station),
        .branch_res_station(branch_res_station),
        .ld_res_station(ld_res_station),

        .sq_head_entry(sq_head_entry),
        .sq_empty(sq_empty),
        .sb_head_entry(sb_head_entry),
        .sb_empty(sb_empty),
        .sb_enq_req(sb_enq_req),
        .sb_enq_order(sb_enq_order),
        //.rob_head_mem_write(head_of_rob.mem_write),
        // .rob_head_order(head_of_rob.rvfi_packet.order),

        .alu_ready('1),
        .mul_ready(!cdb_packet_ex.mul_busy), // use most updated signal from execute
        .div_ready(!cdb_packet_ex.div_busy),
        .br_ready('1),
        .store_ready(store_ready),
        .load_ready(load_ready),
        // .mem_ready(!cdb_packet_ex.mem_busy),
        
        .issue_packet(issue_packet_next),
        .rs_clear(rs_clear),
        .sq_deq_req(sq_deq_req),
        .alu_rs1_raddr(alu_rs1_raddr),
        .alu_rs2_raddr(alu_rs2_raddr),
        .mul_rs1_raddr(mul_rs1_raddr),
        .mul_rs2_raddr(mul_rs2_raddr),
        .div_rs1_raddr(div_rs1_raddr),
        .div_rs2_raddr(div_rs2_raddr),
        .branch_rs1_raddr(branch_rs1_raddr),
        .branch_rs2_raddr(branch_rs2_raddr),
        .mem_rs1_raddr(mem_rs1_raddr),
        .mem_rs2_raddr(mem_rs2_raddr)
    );

    reservation_station #(
        .RES_STATION_ENTRY_T(alu_res_station_entry_t),
        .NUM_SLOTS(ALU_RES_STATION_SIZE),
        .PRF_IDX_WIDTH(PRF_IDX_WIDTH),
        .NUM_WAKEUP_PORTS(RS_NUM_WAKEUP_PORTS)
    ) dummy_rs_alu (
        .clk(clk),
        .rst(rst),
        .add_entry_en(dispatch_packet.alu_add_entry_en),
        .wdata(dispatch_packet.alu_rs_packet),

        // All 3 CDB broadcasts, registered for clean timing
        .rs_wakeup(cdb_rs_wakeup_bus),
        .rs_ready_addr(rs_ready_addr_bus),

        .clear_entry_en(rs_clear.alu_res_station_clear_en),
        .clear_entry_idx(rs_clear.alu_res_station_clear_idx),
        .flush_pipeline(flush_pipeline),
        .full(alu_rs_full),
        .data(alu_res_station) 
    );

    reservation_station #(
        .RES_STATION_ENTRY_T(mul_res_station_entry_t),
        .NUM_SLOTS(MUL_RES_STATION_SIZE),
        .PRF_IDX_WIDTH(PRF_IDX_WIDTH),
        .NUM_WAKEUP_PORTS(RS_NUM_WAKEUP_PORTS)
    ) dummy_rs_mul (
        .clk(clk),
        .rst(rst),
        .add_entry_en(dispatch_packet.mul_add_entry_en),
        .wdata(dispatch_packet.mul_rs_packet),

        .rs_wakeup(cdb_rs_wakeup_bus),
        .rs_ready_addr(rs_ready_addr_bus),

        .clear_entry_en(rs_clear.mul_res_station_clear_en),
        .clear_entry_idx(rs_clear.mul_res_station_clear_idx),
        .flush_pipeline(flush_pipeline),
        .full(mul_rs_full),
        .data(mul_res_station) 
    );

    reservation_station #(
        .RES_STATION_ENTRY_T(div_res_station_entry_t),
        .NUM_SLOTS(DIV_RES_STATION_SIZE),
        .PRF_IDX_WIDTH(PRF_IDX_WIDTH),
        .NUM_WAKEUP_PORTS(RS_NUM_WAKEUP_PORTS)
    ) dummy_rs_div (
        .clk(clk),
        .rst(rst),
        .add_entry_en(dispatch_packet.div_add_entry_en),
        .wdata(dispatch_packet.div_rs_packet),

        .rs_wakeup(cdb_rs_wakeup_bus),
        .rs_ready_addr(rs_ready_addr_bus),

        .clear_entry_en(rs_clear.div_res_station_clear_en),
        .clear_entry_idx(rs_clear.div_res_station_clear_idx),
        .flush_pipeline(flush_pipeline),
        .full(div_rs_full),
        .data(div_res_station) 
    );

    reservation_station #(
        .RES_STATION_ENTRY_T(branch_res_station_entry_t),
        .NUM_SLOTS(BR_RES_STATION_SIZE),
        .PRF_IDX_WIDTH(PRF_IDX_WIDTH),
        .NUM_WAKEUP_PORTS(RS_NUM_WAKEUP_PORTS)
    ) dummy_rs_branch (
        .clk(clk),
        .rst(rst),
        .add_entry_en(dispatch_packet.branch_add_entry_en),
        .wdata(dispatch_packet.branch_rs_packet),

        .rs_wakeup(cdb_rs_wakeup_bus),
        .rs_ready_addr(rs_ready_addr_bus),

        .clear_entry_en(rs_clear.branch_res_station_clear_en),
        .clear_entry_idx(rs_clear.branch_res_station_clear_idx),
        .flush_pipeline(flush_pipeline),
        .full(branch_rs_full),
        .data(branch_res_station) 
    );

    reservation_station #(
        .RES_STATION_ENTRY_T(ld_res_station_entry_t),
        .NUM_SLOTS(LD_RES_STATION_SIZE),
        .PRF_IDX_WIDTH(PRF_IDX_WIDTH),
        .NUM_WAKEUP_PORTS(RS_NUM_WAKEUP_PORTS)
    ) dummy_rs_ld (
        .clk(clk),
        .rst(rst),
        .add_entry_en(dispatch_packet.ld_add_entry_en),
        .wdata(dispatch_packet.ld_rs_packet),

        .rs_wakeup(cdb_rs_wakeup_bus),
        .rs_ready_addr(rs_ready_addr_bus),

        .clear_entry_en(rs_clear.ld_res_station_clear_en),
        .clear_entry_idx(rs_clear.ld_res_station_clear_idx),
        .flush_pipeline(flush_pipeline),
        .full(ld_rs_full),
        .data(ld_res_station) 
    );

    execute dummy_execute (
        .clk(clk),
        .rst(rst),
        .flush_pipeline(flush_pipeline),
        .flush_order(head_of_rob.rvfi_packet.order),
        .issue_packet(issue_packet),
        .execute_cdb_out(cdb_packet_ex),       
        .rob_head_order(head_of_rob.rvfi_packet.order),
        .dmem_addr_4_bytes_aligned(dmem_addr), // mem needs aligned addr
        .dmem_rmask(dmem_rmask),
        .dmem_wmask(dmem_wmask),
        .dmem_resp(dmem_resp),
        .dmem_rdata(dmem_rdata),
        .dmem_wdata(dmem_wdata),
        .raw_hazard(raw_hazard),
        .sb_full(sb_full),
        .sb_empty(sb_empty),
        .sb_head_entry(sb_head_entry),
        .store_ready(store_ready),
        .load_ready(load_ready),
        .sb_enq_req(sb_enq_req),
        .sb_enq_order(sb_enq_order)
    );


    // STORE QUEUE
    store_queue #(
        .SQ_SIZE(STORE_QUEUE_SIZE),
        .NUM_UPDATE_PORTS(RS_NUM_WAKEUP_PORTS) // CDB
    ) dummy_store_queue(
        .clk(clk),
        .rst(rst || flush_pipeline),
        .enq_req(!stall_decode && decode_packet.rvfi_packet.valid && dispatch_packet.store_add_entry_en), 
        .enq_data(dispatch_packet.sq_packet),
        .deq_req(sq_deq_req), 
        .deq_data(sq_head_entry),
        .rs_wakeup(cdb_rs_wakeup_bus),
        .rs_ready_addr(rs_ready_addr_bus),
        .full(sq_full),
        .empty(sq_empty)
        // .curr_size()
    );
    /* ___ENDDDDD_____________ LOAD AND STORES   ______________ENDDDDDD___*/


    rob #(
        .ROB_SIZE(ROB_SIZE),
        .NUM_UPDATE_PORTS(ROB_NUM_WRITE_PORTS)
    ) dummy_rob(
        .clk(clk),
        .rst(rst || flush_pipeline),
        .enq_req(!stall_decode && decode_packet.rvfi_packet.valid),
        .enq_data(dispatch_packet.rob_packet),
        .rob_enq_idx(rob_idx),
        .deq_req(commit),  // we dequeue from the ROB we want to commit instruction
        .deq_data(head_of_rob), // always pointing to the head of the ROB
        .rob_update_wen(cdb_rob_wakeup_bus),
        .rob_update_idx(rob_idx_bus),
        .cdb_rvfi_packet(rvfi_packet_bus),
        .cdb_branch_mispredict(branch_mispredict_bus),
        .cdb_branch_outcome(branch_outcome_bus),
        .full(rob_full),
        .empty(rob_empty),
        .deq_two(commit_two),          // NEW
        .deq_data_1(head_of_rob_1),    // NEW
        .empty_1(rob_empty_1)          // NEW
    );

    free_list #(
        .NUM_PHYS_REGS(PRF_SIZE)
    ) dummy_free_list (
        .clk(clk),
        .rst(rst),
        .allocate_req(get_phys_reg_from_fl), // <- from dispatch.sv request
        .allocate_id(phys_reg_from_fl),  // -> physical register to dispatch.sv
        .empty(free_list_empty),
        .rrat_insert_req(commit_reg_write), 
        .rrat_insert_paddr(rrat_rdata_bus[0]),
        .restore_req(flush_pipeline),
        .restore_bitmask(recovery_mask),
        .rrat_insert_req_1(commit_reg_write_1),      // NEW
        .rrat_insert_paddr_1(rrat_rdata_bus[1]),     // NEW
        .waw_free_req(waw),                          // NEW
        .waw_free_paddr(head_of_rob.rd_paddr)        // NEW
    );

    rat #(
        .DATA_WIDTH(PRF_IDX_WIDTH),
        .NUM_SLOTS(RAT_NUM_SLOTS),
        .NUM_READ_PORTS(RAT_NUM_READ_PORTS),
        .NUM_WRITE_PORTS(RAT_NUM_WRITE_PORTS)
    ) dummy_rat (
    	.clk(clk),
        .rst(rst),
        .rat_we(rat_we), 
        .wdata(rat_wdata_bus),
        .waddr(rat_waddr_bus),
        .cdb_packet(cdb_packet_wb),
        .raddr(rat_raddr_bus),
        .rdata(rat_rdata_bus),
        .valid_out(rat_valid_bus),
        .flush(flush_pipeline),
        .rrat_state_in(rrat_state_bus),
        .commit_we(commit_reg_write),
        .commit_waddr(rrat_waddr_bus[0]),
        .commit_wdata(rrat_wdata_bus[0]),
        .commit_we_1(commit_reg_write_1),            // NEW
        .commit_waddr_1(rrat_waddr_bus[1]),          // NEW
        .commit_wdata_1(rrat_wdata_bus[1])           // NEW
	);

    prf #(
        .DATA_WIDTH(32),
        .NUM_SLOTS(PRF_SIZE),
        .NUM_READ_PORTS(PRF_NUM_READ_PORTS),
        .NUM_WRITE_PORTS(PRF_NUM_WRITE_PORTS)
    ) dummy_prf (
        .clk(clk),
        .rst(rst),
        .prf_we(prf_we_bus),
        .wdata(prf_wdata_bus),
        .waddr(prf_waddr_bus/*rs_ready_addr_bus*/),
        .raddr(prf_raddr_bus),
        .rdata(prf_rdata)
    );

    rrat #(
        .DATA_WIDTH(PRF_IDX_WIDTH),
        .NUM_SLOTS(RRAT_NUM_SLOTS),
        .NUM_READ_PORTS(RRAT_NUM_READ_PORTS),
        .NUM_WRITE_PORTS(RRAT_NUM_WRITE_PORTS) /*when committing, we also want to update the RRAT*/
    ) dummy_rrat (
        .clk(clk),
        .rst(rst),
        .rrat_we(rrat_we), /* write to RAT when commiting instruction */
        .wdata(rrat_wdata_bus),   /* rd_s's phys_addr from ROB */
        .waddr(rrat_waddr_bus), /* rd_s's RISV address from ROB */
        .raddr(rrat_raddr_bus), /* rd_s's RISV address from ROB */
        .rdata(rrat_rdata_bus), /* old physical address goes to the free list */
        .rrat_state_out(rrat_state_bus)

    );

    // restoring free list logic
    always_comb begin
        recovery_mask    = '0;
        recovery_mask[0] = '1;

        for (integer unsigned i = 1; i < RRAT_NUM_SLOTS; i++) begin
            if (commit_reg_write && ($clog2(RRAT_NUM_SLOTS)'(i) == rrat_waddr_bus[0]))
                recovery_mask[rrat_wdata_bus[0]] = '1;
            else if (commit_reg_write_1 && ($clog2(RRAT_NUM_SLOTS)'(i) == rrat_waddr_bus[1]))
                recovery_mask[rrat_wdata_bus[1]] = '1;
            else
                recovery_mask[rrat_state_bus[i]] = '1;
        end
    end

    /* _________ COMMIT FROM ROB ___________*/
    always_comb begin
        commit           = '0;
        commit_two       = '0;
        commit_reg_write = '0;
        commit_reg_write_1 = '0;
        flush_pipeline   = '0;
        waw              = '0;

        if (!rob_empty && head_of_rob.ready) begin
            commit = '1;

            if (head_of_rob.rvfi_packet.inst[6] && head_of_rob.branch_mispredict)
                flush_pipeline = '1;

            // Dual commit: slot 0 must not be store or control inst,
            // slot 1 must exist, be ready, not store, not control
            if (!flush_pipeline
            && !head_of_rob.mem_write
            && !head_of_rob.rvfi_packet.inst[6]
            && !rob_empty_1
            && head_of_rob_1.ready
            && !head_of_rob_1.mem_write
            && !head_of_rob_1.rvfi_packet.inst[6]) begin
                commit_two = '1;
            end
        end

        // WAW: both write same non-x0 architectural register
        waw = commit_two
        && head_of_rob.reg_load
        && head_of_rob_1.reg_load
        && (head_of_rob.rvfi_packet.rd_addr == head_of_rob_1.rvfi_packet.rd_addr)
        && (head_of_rob.rvfi_packet.rd_addr != '0);

            // slot 0 RRAT write suppressed on WAW — slot 1 wins
            commit_reg_write   = commit
                            && head_of_rob.reg_load
                            && (rrat_waddr_bus[0] != '0)
                            && !waw;

            commit_reg_write_1 = commit_two
                            && head_of_rob_1.reg_load
                            && (rrat_waddr_bus[1] != '0);
    end

    // Separate Counters for detailed analysis
    logic [63:0] jal_cnt, jalr_cnt, cond_br_cnt;
    logic [63:0] jal_mis_cnt, jalr_mis_cnt, cond_br_mis_cnt;

        // RAS counters
    logic [63:0] jal_call_cnt, jal_call_mis_cnt;
    logic [63:0] jalr_call_cnt, jalr_call_mis_cnt;
    logic [63:0] jalr_ret_cnt,  jalr_ret_mis_cnt;


    always_ff @(posedge clk) begin
        if (rst) begin
            jal_cnt         <= '0;
            jalr_cnt        <= '0;
            cond_br_cnt     <= '0;

            jal_mis_cnt     <= '0;
            jalr_mis_cnt    <= '0;
            cond_br_mis_cnt <= '0;

            jal_call_cnt    <= '0;
            jal_call_mis_cnt<= '0;

            jalr_call_cnt   <= '0;
            jalr_call_mis_cnt <= '0;

            jalr_ret_cnt    <= '0;
            jalr_ret_mis_cnt<= '0;

        end else if (commit && head_of_rob.rvfi_packet.inst[6]) begin
            logic [31:0] inst;
            logic [4:0] rd, rs1;

            inst = head_of_rob.rvfi_packet.inst;
            rd   = inst[11:7];
            rs1  = inst[19:15];

            case (inst[6:0])

                // ---------------- JAL ----------------
                op_b_jal: begin
                    jal_cnt <= jal_cnt + 1'b1;

                    if (head_of_rob.branch_mispredict)
                        jal_mis_cnt <= jal_mis_cnt + 1'b1;

                    // call = jal x1
                    if (rd == 5'd1) begin
                        jal_call_cnt <= jal_call_cnt + 1'b1;

                        if (head_of_rob.branch_mispredict)
                            jal_call_mis_cnt <= jal_call_mis_cnt + 1'b1;
                    end
                end

                // ---------------- JALR ----------------
                op_b_jalr: begin
                    jalr_cnt <= jalr_cnt + 1;

                    if (head_of_rob.branch_mispredict)
                        jalr_mis_cnt <= jalr_mis_cnt + 1'b1;

                    // CALL = jalr x1, x1
                    if ((rd == 5'd1) && (rs1 == 5'd1)) begin
                        jalr_call_cnt <= jalr_call_cnt + 1'b1;

                        if (head_of_rob.branch_mispredict)
                            jalr_call_mis_cnt <= jalr_call_mis_cnt + 1'b1;
                    end

                    // RETURN = jalr x0, x1
                    else if ((rd == 5'd0) && (rs1 == 5'd1)) begin
                        jalr_ret_cnt <= jalr_ret_cnt + 1'b1;

                        if (head_of_rob.branch_mispredict)
                            jalr_ret_mis_cnt <= jalr_ret_mis_cnt + 1'b1;
                    end
                end

                // ---------------- BRANCH ----------------
                op_b_br: begin
                    cond_br_cnt <= cond_br_cnt + 1'b1;

                    if (head_of_rob.branch_mispredict)
                        cond_br_mis_cnt <= cond_br_mis_cnt + 1'b1;
                end

            endcase
        end
    end

    // // ======================================================
    // // INSTRUCTION COMPOSITION
    // // ======================================================
    // integer arith_count;
    // integer ls_count;
    // integer br_jal_count;
    // integer mul_count;
    // integer div_count;

    // integer lui_count;
    // integer auipc_count;
    // integer imm_count;
    // integer reg_count;
    // integer jal_count;
    // integer jalr_count;
    // integer br_count;
    // integer load_count;
    // integer store_count;

    // always @(posedge clk) begin
    //     if (rst) begin
    //         arith_count <= 0;
    //         ls_count <= 0;
    //         br_jal_count <= 0;
    //         mul_count <= 0;
    //         div_count <= 0;

    //         lui_count <= 0;
    //         auipc_count <= 0;
    //         imm_count <= 0;
    //         reg_count <= 0;
    //         jal_count <= 0;
    //         jalr_count <= 0;
    //         br_count <= 0;
    //         load_count <= 0;
    //         store_count <= 0;
    //     end else if (commit) begin
    //         unique case (head_of_rob.rvfi_packet.inst[6:0]) 
    //             op_b_lui: begin
    //                 lui_count   <= lui_count + 1;
    //                 arith_count <= arith_count + 1;
    //             end
    //             op_b_auipc: begin
    //                 auipc_count <= auipc_count + 1;
    //                 arith_count <= arith_count + 1;
    //             end
    //             op_b_imm: begin
    //                 imm_count   <= imm_count + 1;
    //                 arith_count <= arith_count + 1;
    //             end
    //             op_b_reg: begin
    //                 if (head_of_rob.rvfi_packet.inst[25]) begin
    //                     if (head_of_rob.rvfi_packet.inst[14])
    //                         div_count <= div_count + 1;
    //                     else
    //                         mul_count <= mul_count + 1;
    //                 end else begin
    //                     reg_count   <= reg_count + 1;
    //                     arith_count <= arith_count + 1;
    //                 end   
    //             end

    //             op_b_jal: begin
    //                 jal_count    <= jal_count + 1;
    //                 br_jal_count <= br_jal_count + 1;
    //             end
    //             op_b_jalr: begin
    //                 jalr_count   <= jalr_count + 1;
    //                 br_jal_count <= br_jal_count + 1;
    //             end
    //             op_b_br: begin
    //                 br_count     <= br_count + 1;
    //                 br_jal_count <= br_jal_count + 1;
    //             end

    //             op_b_load: begin
    //                 load_count <= load_count + 1;
    //                 ls_count   <= ls_count + 1;
    //             end
    //             op_b_store: begin
    //                 store_count <= store_count + 1;
    //                 ls_count    <= ls_count + 1;
    //             end
    //         endcase
    //     end
    // end


    // ======================================================
    // STALL COUNTERS
    // ======================================================
//     integer decode_stall_count;
//     integer alu_rs_full_count;
//     integer mul_rs_full_count;
//     integer div_rs_full_count;
//     integer load_rs_full_count;
//     integer br_rs_full_count;
//     integer rob_full_count;
//     integer store_queue_full_count;

//     always @(posedge clk) begin
//         if (rst) begin
//             decode_stall_count      <= 0;
//             alu_rs_full_count       <= 0;
//             mul_rs_full_count       <= 0;
//             div_rs_full_count       <= 0;
//             load_rs_full_count      <= 0;
//             br_rs_full_count        <= 0;
//             rob_full_count          <= 0;
//             store_queue_full_count  <= 0;
//         end else begin
//             if (stall_decode)   decode_stall_count     <= decode_stall_count + 1;
//             if (alu_rs_full)    alu_rs_full_count      <= alu_rs_full_count + 1;
//             if (mul_rs_full)    mul_rs_full_count      <= mul_rs_full_count + 1;
//             if (div_rs_full)    div_rs_full_count      <= div_rs_full_count + 1;
//             if (branch_rs_full) br_rs_full_count       <= br_rs_full_count + 1;
//             if (ld_rs_full)     load_rs_full_count     <= load_rs_full_count + 1;
//             if (sq_full)        store_queue_full_count <= store_queue_full_count + 1;
//             if (rob_full)       rob_full_count         <= rob_full_count + 1;
//         end
//     end

//     // ======================================================
//     // STARVATION STATS
//     // ======================================================
//     integer instr_queue_empty_count;

//     always @(posedge clk) begin
//         if (rst) begin
//             instr_queue_empty_count <= 0;
//         end else begin
//             if (dummy_fetch.empty)
//                 instr_queue_empty_count <= instr_queue_empty_count + 1;
//         end
//     end

//     final begin
//         $display("Stall Statistics\n");
//         $display("Decode stall count:           %d", decode_stall_count);
//         $display("ALU RS full count:            %d", alu_rs_full_count);
//         $display("Multiplier RS full count:     %d", mul_rs_full_count);
//         $display("Divider RS full count:        %d", div_rs_full_count);
//         $display("Branch RS full count:         %d", br_rs_full_count);
//         $display("Load RS full count:           %d", load_rs_full_count);
//         $display("Store queue full count:       %d", store_queue_full_count);
//         $display("ROB full count:               %d", rob_full_count);
// $display("Branch Statistics\n");
// $display("Type        |  Total Count  |  Mispredicts  |  Correct/Total");
// $display("-----------------------------------------------------------------------");

// $display("JAL         |  %12d |  %12d |  %12d / %0d",
//     jal_cnt,
//     jal_mis_cnt,
//     (jal_cnt - jal_mis_cnt),
//     jal_cnt
// );

// $display("JALR        |  %12d |  %12d |  %12d / %0d",
//     jalr_cnt,
//     jalr_mis_cnt,
//     (jalr_cnt - jalr_mis_cnt),
//     jalr_cnt
// );

// $display("Cond Branch |  %12d |  %12d |  %12d / %0d",
//     cond_br_cnt,
//     cond_br_mis_cnt,
//     (cond_br_cnt - cond_br_mis_cnt),
//     cond_br_cnt
// );
    
//     $display("\nFunction Call / Return Breakdown");
//     $display("Type              |  Total Count  |  Mispredicts  |  Correct/Total");
//     $display("----------------------------------------------------------------------------");

//     $display("JAL Calls         |  %12d |  %12d |  %12d / %0d",
//         jal_call_cnt,
//         jal_call_mis_cnt,
//         (jal_call_cnt - jal_call_mis_cnt),
//         jal_call_cnt
//     );

//     $display("JALR Calls        |  %12d |  %12d |  %12d / %0d",
//         jalr_call_cnt,
//         jalr_call_mis_cnt,
//         (jalr_call_cnt - jalr_call_mis_cnt),
//         jalr_call_cnt
//     );

//     $display("JALR Returns      |  %12d |  %12d |  %12d / %0d",
//         jalr_ret_cnt,
//         jalr_ret_mis_cnt,
//         (jalr_ret_cnt - jalr_ret_mis_cnt),
//         jalr_ret_cnt
//     );
//         $display("Starvation Statistics\n");
//         $display("Instruction Queue Empty Count:%d", instr_queue_empty_count);
//     end

    logic           monitor_valid;
    logic   [63:0]  monitor_order;
    logic   [31:0]  monitor_inst;
    logic   [4:0]   monitor_rs1_addr;
    logic   [4:0]   monitor_rs2_addr;
    logic   [31:0]  monitor_rs1_rdata;
    logic   [31:0]  monitor_rs2_rdata;
    logic   [4:0]   monitor_rd_addr;
    logic   [31:0]  monitor_rd_wdata;
    logic   [31:0]  monitor_pc_rdata;
    logic   [31:0]  monitor_pc_wdata;
    logic   [31:0]  monitor_mem_addr;
    logic   [3:0]   monitor_mem_rmask;
    logic   [3:0]   monitor_mem_wmask;
    logic   [31:0]  monitor_mem_rdata;
    logic   [31:0]  monitor_mem_wdata;

    assign monitor_valid = commit;
    assign monitor_order = head_of_rob.rvfi_packet.order;
    assign monitor_inst = head_of_rob.rvfi_packet.inst;
    assign monitor_rs1_addr = head_of_rob.rvfi_packet.rs1_addr;
    assign monitor_rs2_addr = head_of_rob.rvfi_packet.rs2_addr;
    assign monitor_rs1_rdata = head_of_rob.rvfi_packet.rs1_rdata;
    assign monitor_rs2_rdata = head_of_rob.rvfi_packet.rs2_rdata;
    assign monitor_rd_addr = head_of_rob.rvfi_packet.rd_addr;
    assign monitor_rd_wdata = head_of_rob.rvfi_packet.rd_wdata;
    assign monitor_pc_rdata = head_of_rob.rvfi_packet.pc_rdata;
    assign monitor_pc_wdata = head_of_rob.rvfi_packet.pc_wdata;
    assign monitor_mem_addr = head_of_rob.rvfi_packet.mem_addr;
    assign monitor_mem_rmask = head_of_rob.rvfi_packet.mem_rmask;
    assign monitor_mem_wmask = head_of_rob.rvfi_packet.mem_wmask;
    assign monitor_mem_rdata = head_of_rob.rvfi_packet.mem_rdata;
    assign monitor_mem_wdata = head_of_rob.rvfi_packet.mem_wdata;

    logic           monitor_valid_2;
    logic   [63:0]  monitor_order_2;
    logic   [31:0]  monitor_inst_2;
    logic   [4:0]   monitor_rs1_addr_2;
    logic   [4:0]   monitor_rs2_addr_2;
    logic   [31:0]  monitor_rs1_rdata_2;
    logic   [31:0]  monitor_rs2_rdata_2;
    logic   [4:0]   monitor_rd_addr_2;
    logic   [31:0]  monitor_rd_wdata_2;
    logic   [31:0]  monitor_pc_rdata_2;
    logic   [31:0]  monitor_pc_wdata_2;
    logic   [31:0]  monitor_mem_addr_2;
    logic   [3:0]   monitor_mem_rmask_2;
    logic   [3:0]   monitor_mem_wmask_2;
    logic   [31:0]  monitor_mem_rdata_2;
    logic   [31:0]  monitor_mem_wdata_2;

    assign monitor_valid_2     = commit_two;
    assign monitor_order_2     = {40'b0, head_of_rob_1.rvfi_packet.order};
    assign monitor_inst_2      = head_of_rob_1.rvfi_packet.inst;
    assign monitor_rs1_addr_2  = head_of_rob_1.rvfi_packet.rs1_addr;
    assign monitor_rs2_addr_2  = head_of_rob_1.rvfi_packet.rs2_addr;
    assign monitor_rs1_rdata_2 = head_of_rob_1.rvfi_packet.rs1_rdata;
    assign monitor_rs2_rdata_2 = head_of_rob_1.rvfi_packet.rs2_rdata;
    assign monitor_rd_addr_2   = head_of_rob_1.rvfi_packet.rd_addr;
    assign monitor_rd_wdata_2  = head_of_rob_1.rvfi_packet.rd_wdata;
    assign monitor_pc_rdata_2  = head_of_rob_1.rvfi_packet.pc_rdata;
    assign monitor_pc_wdata_2  = head_of_rob_1.rvfi_packet.pc_wdata;
    assign monitor_mem_addr_2  = head_of_rob_1.rvfi_packet.mem_addr;
    assign monitor_mem_rmask_2 = head_of_rob_1.rvfi_packet.mem_rmask;
    assign monitor_mem_wmask_2 = head_of_rob_1.rvfi_packet.mem_wmask;
    assign monitor_mem_rdata_2 = head_of_rob_1.rvfi_packet.mem_rdata;
    assign monitor_mem_wdata_2 = head_of_rob_1.rvfi_packet.mem_wdata;

endmodule