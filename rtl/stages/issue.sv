module issue 
import rv32i_types::*;
(
    input [31:0]  prf_data[PRF_NUM_READ_PORTS],

    input alu_res_station_entry_t alu_res_station[ALU_RES_STATION_SIZE],
    input mul_res_station_entry_t mul_res_station[MUL_RES_STATION_SIZE],
    input div_res_station_entry_t div_res_station[DIV_RES_STATION_SIZE],
    input branch_res_station_entry_t branch_res_station[BR_RES_STATION_SIZE],
    input ld_res_station_entry_t ld_res_station[LD_RES_STATION_SIZE],

    input sq_entry_t sq_head_entry,
    input logic sq_empty,
    input sb_entry_t sb_head_entry,
    input logic sb_empty,
    input logic sb_enq_req,
    input logic [23:0] sb_enq_order,
    //input logic      rob_head_mem_write,
    // input logic [63:0] rob_head_order,

    input logic alu_ready, // this will come from broadcast??
    input logic mul_ready,
    input logic div_ready,
    input logic br_ready,
    input logic store_ready,
    input logic load_ready,
    // input logic mem_ready,
    output issue_packet_t      issue_packet,
    output rs_clear_t          rs_clear,
    output logic sq_deq_req,

    output	logic [(PRF_IDX_WIDTH-1):0] alu_rs1_raddr,
	output	logic [(PRF_IDX_WIDTH-1):0] alu_rs2_raddr,
	output	logic [(PRF_IDX_WIDTH-1):0] mul_rs1_raddr,
	output	logic [(PRF_IDX_WIDTH-1):0] mul_rs2_raddr,
	output	logic [(PRF_IDX_WIDTH-1):0] div_rs1_raddr,
	output	logic [(PRF_IDX_WIDTH-1):0] div_rs2_raddr,
	output	logic [(PRF_IDX_WIDTH-1):0] branch_rs1_raddr,
	output	logic [(PRF_IDX_WIDTH-1):0] branch_rs2_raddr,
	output	logic [(PRF_IDX_WIDTH-1):0] mem_rs1_raddr,
	output	logic [(PRF_IDX_WIDTH-1):0] mem_rs2_raddr
);

    always_comb begin
        issue_packet = '0;
        rs_clear = '0;
        alu_rs1_raddr = '0;
        alu_rs2_raddr = '0;
        mul_rs1_raddr = '0;
        mul_rs2_raddr = '0;
        div_rs1_raddr = '0;
        div_rs2_raddr = '0;
        branch_rs1_raddr = '0;
        branch_rs2_raddr = '0;
        mem_rs1_raddr = '0;
        mem_rs2_raddr = '0;
        sq_deq_req = '0;

        // ---------------------------------------------------------
        // 1. ALU Issue Priority Encoder
        // ---------------------------------------------------------
        for (integer unsigned i = 0; i< ALU_RES_STATION_SIZE; i++) begin
            if (alu_ready && alu_res_station[i].valid) begin //sometimes only rs1 is used
                if (((alu_res_station[i].rs1_en && alu_res_station[i].rs1_ready) || !alu_res_station[i].rs1_en) &&
                ((alu_res_station[i].rs2_en && alu_res_station[i].rs2_ready) || !alu_res_station[i].rs2_en)) begin
                    // issue inst into funct unit
                    issue_packet.alu_issue = '1;

                    alu_rs1_raddr = alu_res_station[i].rs1_paddr;
                    alu_rs2_raddr = alu_res_station[i].rs2_paddr;

                    // pass to execute
                    issue_packet.alu_rs1_data = prf_data[0];
                    issue_packet.alu_rs2_data = prf_data[1];
                    issue_packet.alu_rob_idx = alu_res_station[i].rob_idx;
                    issue_packet.alu_rd_paddr = alu_res_station[i].rd_paddr;

                                        
                    issue_packet.alu_imm = alu_res_station[i].alu_imm;
                    issue_packet.aluop = alu_res_station[i].aluop;
                    issue_packet.cmpop = alu_res_station[i].cmpop;
                    issue_packet.ctrl_slt = alu_res_station[i].ctrl_slt;
                    issue_packet.alu_rvfi_packet = alu_res_station[i].rvfi_packet;
                    issue_packet.alu_m1_sel = alu_res_station[i].alu_m1_sel;
                    issue_packet.alu_m2_sel = alu_res_station[i].alu_m2_sel;

                    // update rvfi packet after reading register file
                    issue_packet.alu_rvfi_packet.rs1_rdata    = prf_data[0];
                    issue_packet.alu_rvfi_packet.rs2_rdata    = prf_data[1];

                    // clear res_station entry
                    rs_clear.alu_res_station_clear_en = '1;
                    rs_clear.alu_res_station_clear_idx = $clog2(ALU_RES_STATION_SIZE)'(i);
                    break;
                end
            end
        end

        // ---------------------------------------------------------
        // 2. MUL Issue Priority Encoder
        // ---------------------------------------------------------
        for (integer unsigned i = 0; i< MUL_RES_STATION_SIZE; i++) begin
            if (mul_ready && mul_res_station[i].valid) begin // rs1 and rs2 are both used
                if (mul_res_station[i].rs1_ready && mul_res_station[i].rs2_ready) begin
                    // issue inst into funct unit
                    issue_packet.mul_issue = '1;

                    mul_rs1_raddr = mul_res_station[i].rs1_paddr;
                    mul_rs2_raddr = mul_res_station[i].rs2_paddr;

                    // pass to execute 
                    issue_packet.mul_rs1_data = prf_data[2];
                    issue_packet.mul_rs2_data = prf_data[3];
                    issue_packet.mul_rob_idx = mul_res_station[i].rob_idx;
                    issue_packet.mul_rd_paddr = mul_res_station[i].rd_paddr;


                    issue_packet.mul_rs1_is_signed = mul_res_station[i].rs1_is_signed;
                    issue_packet.mul_rs2_is_signed = mul_res_station[i].rs2_is_signed;
                    issue_packet.mul_high_bits = mul_res_station[i].mul_high_bits;
                    issue_packet.mul_rvfi_packet = mul_res_station[i].rvfi_packet;
                    
                    // update rvfi packet after reading register file
                    issue_packet.mul_rvfi_packet.rs1_rdata    = prf_data[2];
                    issue_packet.mul_rvfi_packet.rs2_rdata    = prf_data[3];
                    // clear res_station entry
                    rs_clear.mul_res_station_clear_en = '1;
                    rs_clear.mul_res_station_clear_idx = $clog2(MUL_RES_STATION_SIZE)'(i);
                    break;
                end
            end
        end

        // ---------------------------------------------------------
        // 3. DIV Issue Priority Encoder
        // ---------------------------------------------------------
        for (integer unsigned i = 0; i< DIV_RES_STATION_SIZE; i++) begin
            if (div_ready && div_res_station[i].valid) begin // rs1 and rs2 are both used
                if (div_res_station[i].rs1_ready && div_res_station[i].rs2_ready) begin
                    // issue inst into funct unit
                    issue_packet.div_issue = '1;

                    div_rs1_raddr = div_res_station[i].rs1_paddr;
                    div_rs2_raddr = div_res_station[i].rs2_paddr;

                    // pass to execute 
                    issue_packet.div_rs1_data = prf_data[4];
                    issue_packet.div_rs2_data = prf_data[5];
                    issue_packet.div_rob_idx = div_res_station[i].rob_idx;
                    issue_packet.div_rd_paddr = div_res_station[i].rd_paddr;

                    issue_packet.div_rs1_is_signed = div_res_station[i].rs1_is_signed;
                    issue_packet.div_rs2_is_signed = div_res_station[i].rs2_is_signed;
                    issue_packet.div_get_rem = div_res_station[i].div_get_rem;
                    issue_packet.div_rvfi_packet = div_res_station[i].rvfi_packet;

                    // update rvfi packet after reading register file
                    issue_packet.div_rvfi_packet.rs1_rdata    = prf_data[4];
                    issue_packet.div_rvfi_packet.rs2_rdata    = prf_data[5];
                    // clear res_station entry
                    rs_clear.div_res_station_clear_en = '1;
                    rs_clear.div_res_station_clear_idx = $clog2(DIV_RES_STATION_SIZE)'(i);
                    break;
                end
            end
        end


        // ---------------------------------------------------------
        // 4. BR Issue Priority Encoder
        // ---------------------------------------------------------
        for (integer unsigned i = 0; i< BR_RES_STATION_SIZE; i++) begin
            if (br_ready && branch_res_station[i].valid) begin // rs1 and rs2 are both used
                if (((branch_res_station[i].rs1_en && branch_res_station[i].rs1_ready) || !branch_res_station[i].rs1_en) &&
                    ((branch_res_station[i].rs2_en && branch_res_station[i].rs2_ready) || !branch_res_station[i].rs2_en)) begin
                    // issue inst into funct unit
                    issue_packet.branch_issue = '1;

                    branch_rs1_raddr = branch_res_station[i].rs1_paddr;
                    branch_rs2_raddr = branch_res_station[i].rs2_paddr;

                    // pass to execute 
                    issue_packet.branch_rs1_data    = prf_data[6];
                    issue_packet.branch_rs2_data    = prf_data[7];
                    issue_packet.branch_rob_idx     = branch_res_station[i].rob_idx;
                    issue_packet.branch_rd_paddr    = branch_res_station[i].rd_paddr;

                    issue_packet.branch_predicted_pc    = branch_res_station[i].predicted_pc;
                    issue_packet.branch_imm             = branch_res_station[i].br_imm;
                    issue_packet.branch_cmpop           = branch_res_station[i].cmpop;
                    issue_packet.branch_br_en           = branch_res_station[i].br_en;
                    issue_packet.branch_jal_en          = branch_res_station[i].jal_en;
                    issue_packet.branch_jalr_en         = branch_res_station[i].jalr_en;
                    issue_packet.branch_rvfi_packet     = branch_res_station[i].rvfi_packet;

                    // update rvfi packet after reading register file
                    issue_packet.branch_rvfi_packet.rs1_rdata    = prf_data[6];
                    issue_packet.branch_rvfi_packet.rs2_rdata    = prf_data[7];
                    // clear res_station entry
                    rs_clear.branch_res_station_clear_en = '1;
                    rs_clear.branch_res_station_clear_idx = $clog2(BR_RES_STATION_SIZE)'(i);
                    break;
                end
            end
        end

        // ---------------------------------------------------------
        // 5. Store Issue
        // ---------------------------------------------------------
        if (store_ready && sq_head_entry.valid && sq_head_entry.rs1_ready && sq_head_entry.rs2_ready) begin // if head of rob is a store
            // issue inst into funct unit
            issue_packet.mem_issue = '1;
            sq_deq_req = '1; // dequeue from store queue
            mem_rs1_raddr = sq_head_entry.rs1_paddr;
            mem_rs2_raddr = sq_head_entry.rs2_paddr;

            // pass to execute
            issue_packet.mem_rs1_data = prf_data[8];
            issue_packet.mem_rs2_data = prf_data[9];
            issue_packet.mem_rob_idx = sq_head_entry.rob_idx;
            issue_packet.mem_write = '1;
            issue_packet.st_type = sq_head_entry.st_type;
            issue_packet.mem_imm = sq_head_entry.imm;
            
            // update rvfi packet after reading register file
            issue_packet.mem_rvfi_packet = sq_head_entry.rvfi_packet;
            issue_packet.mem_rvfi_packet.rs1_rdata    = prf_data[8];
            issue_packet.mem_rvfi_packet.rs2_rdata    = prf_data[9];
        end
        else begin
            // ---------------------------------------------------------
            // 6. LD Issue Priority Encoder
            // ---------------------------------------------------------
            for (integer unsigned i = 0; i< LD_RES_STATION_SIZE; i++) begin
                // age-ordering 
                if ((sq_empty || (!sq_empty && sq_head_entry.rvfi_packet.order[23:0] > ld_res_station[i].rvfi_packet.order[23:0])) && 
                (!sb_enq_req || (sb_enq_order > ld_res_station[i].rvfi_packet.order[23:0])) && 
                (sb_empty || (!sb_empty && sb_head_entry.rvfi_packet.order[23:0] > ld_res_station[i].rvfi_packet.order[23:0])) &&  load_ready && ld_res_station[i].valid) begin // only rs1 are both used
                    if ((ld_res_station[i].rs1_ready) /*||  ld_res_station[i].rs1_en*/) begin
                        // issue inst into funct unit
                        issue_packet.mem_issue = '1;

                        mem_rs1_raddr = ld_res_station[i].rs1_paddr;

                        // pass to execute 
                        issue_packet.mem_rs1_data    = prf_data[8];
                        issue_packet.mem_rob_idx     = ld_res_station[i].rob_idx;
                        issue_packet.mem_rd_paddr    = ld_res_station[i].rd_paddr;
                        issue_packet.ld_type = ld_res_station[i].ld_type;
                        issue_packet.mem_imm = ld_res_station[i].imm;

                        issue_packet.mem_rvfi_packet     = ld_res_station[i].rvfi_packet;

                        // update rvfi packet after reading register file
                        issue_packet.mem_rvfi_packet.rs1_rdata    = prf_data[8];
                        // clear res_station entry
                        rs_clear.ld_res_station_clear_en = '1;
                        rs_clear.ld_res_station_clear_idx = $clog2(LD_RES_STATION_SIZE)'(i);
                        break;
                    end
                end
            end
        end
        // =====================================================================
    end
endmodule