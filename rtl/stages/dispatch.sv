module dispatch 
import rv32i_types::*;
(
    input 	decode_packet_t   		decode_packet_in,

    input   logic                   alu_rs_full,
    input   logic                   mul_rs_full,
    input   logic                   div_rs_full,
    input   logic                   branch_rs_full,
    input   logic                   ld_rs_full,
    input   logic                   sq_full,
    input   logic                   sb_full,

    input   logic                   rob_full,
    input   logic [ROB_IDX_WIDTH-1:0]  rob_idx,

    input   logic              rat_rs1_valid,
    input   logic              rat_rs2_valid,
    input   logic   [5:0]      rat_rs1_paddr,
    input   logic   [5:0]      rat_rs2_paddr,

    input cdb_packet_t cdb_packet_wb,

    output  logic               rat_we,
    output	logic   [4:0]      rat_rd_addr_for_invalidating_rat,
    output	logic   [PRF_IDX_WIDTH-1:0]      rat_phys_reg_set,
    
    
    input   logic [PRF_IDX_WIDTH-1:0]  fl_phys_addr,
    input   logic                   fl_empty,
    output  logic                   fl_req,


    output dispatch_packet_t dispatch_packet,
    output  logic stall_decode
);

    logic target_rs_full;
    logic rs1_ready_temp;
    logic rs2_ready_temp;

    always_comb begin
        dispatch_packet = '0;
        target_rs_full = '0;
        rat_rd_addr_for_invalidating_rat = '0;
        rat_phys_reg_set = '0;
        rat_we = '0;
        fl_req = '0;
        stall_decode = '0;
        rs1_ready_temp = '0;
        rs2_ready_temp = '0;

        // 1. Determine if the specifically requested RS is full
        unique case (decode_packet_in.rs_target)
            RS_ALU: target_rs_full = alu_rs_full;
            RS_MUL: target_rs_full = mul_rs_full;
            RS_DIV: target_rs_full = div_rs_full;
            RS_LD: target_rs_full = ld_rs_full;
            RS_SQ: target_rs_full = sq_full || sb_full;
            RS_BR:  target_rs_full = branch_rs_full;
            default: target_rs_full = 1'b0;
        endcase

        // 2. Check all structural hazards at once
        if (decode_packet_in.rvfi_packet.valid && (target_rs_full || rob_full || (decode_packet_in.reg_load && (decode_packet_in.rvfi_packet.rd_addr != 5'b00000) && fl_empty))) begin
            // We lack the resources to dispatch this cycle.
            stall_decode = 1'b1;
        end else begin
            // commmon dispatch logic

            // destination register
            if (decode_packet_in.reg_load && (decode_packet_in.rvfi_packet.rd_addr != '0)) begin 
                // we are goign to invalidate rat and assign the new physical register
                rat_we = '1;
                // tell free list we're taking a register it's pointing to
                fl_req = '1;
                // 1. invalid RAT 2. assign new physical reg to RAT
                rat_rd_addr_for_invalidating_rat = decode_packet_in.rvfi_packet.rd_addr;
                rat_phys_reg_set =  fl_phys_addr;

            end

            // rs1 
            if (decode_packet_in.rs1_used) begin
                // send rs1 architectural reg to the RAT
                dispatch_packet.rat_rs1_addr = decode_packet_in.rvfi_packet.rs1_addr;
                rs1_ready_temp = rat_rs1_valid;

                // CDB snoop at dispatch
                if ((cdb_packet_wb.alu_en && cdb_packet_wb.alu_rd_paddr == rat_rs1_paddr) ||
                    (cdb_packet_wb.mul_en && cdb_packet_wb.mul_rd_paddr == rat_rs1_paddr) ||
                    (cdb_packet_wb.div_en && cdb_packet_wb.div_rd_paddr == rat_rs1_paddr) ||
                    (cdb_packet_wb.mem_en && cdb_packet_wb.mem_rd_paddr == rat_rs1_paddr) ||
                    (cdb_packet_wb.branch_en && cdb_packet_wb.branch_rd_paddr == rat_rs1_paddr)
                    )
                begin
                    rs1_ready_temp = 1'b1;
                end
            end

            // rs2
            if (decode_packet_in.rs2_used) begin
                dispatch_packet.rat_rs2_addr = decode_packet_in.rvfi_packet.rs2_addr;
                rs2_ready_temp = rat_rs2_valid;

                // CDB snoop at dispatch
                if ((cdb_packet_wb.alu_en && cdb_packet_wb.alu_rd_paddr == rat_rs2_paddr) ||
                    (cdb_packet_wb.mul_en && cdb_packet_wb.mul_rd_paddr == rat_rs2_paddr) ||
                    (cdb_packet_wb.div_en && cdb_packet_wb.div_rd_paddr == rat_rs2_paddr) ||
                    (cdb_packet_wb.mem_en && cdb_packet_wb.mem_rd_paddr == rat_rs2_paddr) ||
                    (cdb_packet_wb.branch_en && cdb_packet_wb.branch_rd_paddr == rat_rs2_paddr)
                    )
                begin
                    rs2_ready_temp = 1'b1;
                end
            end

            // rob
            dispatch_packet.rob_packet.ready = '0; // since instruction hasn't finished
            dispatch_packet.rob_packet.rd_paddr =  rat_phys_reg_set;
            dispatch_packet.rob_packet.reg_load = decode_packet_in.reg_load;        // to know if rrat needs to kick to free list
            dispatch_packet.rob_packet.rvfi_packet = decode_packet_in.rvfi_packet;
            dispatch_packet.rob_packet.is_conditional = decode_packet_in.br_en;
            dispatch_packet.rob_packet.is_non_return_jalr = decode_packet_in.jalr_en && !(decode_packet_in.rvfi_packet.inst[11:7] == 5'd0 && decode_packet_in.rvfi_packet.inst[19:15] == 5'd1);
            dispatch_packet.rob_packet.rob_old_prediction = decode_packet_in.pred_prediction;
            dispatch_packet.rob_packet.rob_pht_index = decode_packet_in.pred_pht_index;
            dispatch_packet.rob_packet.ras_top_ptr = decode_packet_in.ras_top_ptr;
            dispatch_packet.rob_packet.mem_write = decode_packet_in.mem_write; // will need this for checking rob head


            unique case (decode_packet_in.rs_target)
                RS_ALU : begin
                    dispatch_packet.alu_add_entry_en = '1;

                    // common RS metadata
                    dispatch_packet.alu_rs_packet.valid = '1;
                    dispatch_packet.alu_rs_packet.rob_idx = rob_idx;
                    dispatch_packet.alu_rs_packet.rd_paddr = rat_phys_reg_set;
                    dispatch_packet.alu_rs_packet.rs1_en = decode_packet_in.rs1_used;
                    dispatch_packet.alu_rs_packet.rs1_paddr = rat_rs1_paddr;
                    dispatch_packet.alu_rs_packet.rs1_ready = rs1_ready_temp;
                    dispatch_packet.alu_rs_packet.rs2_en = decode_packet_in.rs2_used;
                    dispatch_packet.alu_rs_packet.rs2_paddr = rat_rs2_paddr;
                    dispatch_packet.alu_rs_packet.rs2_ready = rs2_ready_temp;

                    // alu specific
                    dispatch_packet.alu_rs_packet.alu_imm = decode_packet_in.imm;
                    dispatch_packet.alu_rs_packet.aluop = decode_packet_in.aluop;
                    dispatch_packet.alu_rs_packet.alu_m1_sel = decode_packet_in.alu_m1_sel;
                    dispatch_packet.alu_rs_packet.alu_m2_sel = decode_packet_in.alu_m2_sel;
                    dispatch_packet.alu_rs_packet.cmpop = decode_packet_in.cmpop;
                    dispatch_packet.alu_rs_packet.ctrl_slt = decode_packet_in.ctrl_slt;

                    // rvfi
                    dispatch_packet.alu_rs_packet.rvfi_packet = decode_packet_in.rvfi_packet;
                end
                RS_MUL : begin
                    dispatch_packet.mul_add_entry_en = '1;

                    // common RS metadata
                    dispatch_packet.mul_rs_packet.valid = '1;
                    dispatch_packet.mul_rs_packet.rob_idx = rob_idx;
                    dispatch_packet.mul_rs_packet.rd_paddr = rat_phys_reg_set;
                    dispatch_packet.mul_rs_packet.rs1_paddr = rat_rs1_paddr;
                    dispatch_packet.mul_rs_packet.rs1_ready = rs1_ready_temp;
                    dispatch_packet.mul_rs_packet.rs2_paddr = rat_rs2_paddr;
                    dispatch_packet.mul_rs_packet.rs2_ready = rs2_ready_temp;

                    // mul specific
                    dispatch_packet.mul_rs_packet.rs1_is_signed = decode_packet_in.rs1_is_signed;
                    dispatch_packet.mul_rs_packet.rs2_is_signed = decode_packet_in.rs2_is_signed;
                    dispatch_packet.mul_rs_packet.mul_high_bits = decode_packet_in.mul_high_bits;

                    // rvfi
                    dispatch_packet.mul_rs_packet.rvfi_packet = decode_packet_in.rvfi_packet;
                end

                RS_DIV : begin
                    dispatch_packet.div_add_entry_en = '1;

                    // common RS metadata
                    dispatch_packet.div_rs_packet.valid = '1;
                    dispatch_packet.div_rs_packet.rob_idx = rob_idx;
                    dispatch_packet.div_rs_packet.rd_paddr = rat_phys_reg_set;
                    dispatch_packet.div_rs_packet.rs1_paddr = rat_rs1_paddr;
                    dispatch_packet.div_rs_packet.rs1_ready = rs1_ready_temp;
                    dispatch_packet.div_rs_packet.rs2_paddr = rat_rs2_paddr;
                    dispatch_packet.div_rs_packet.rs2_ready = rs2_ready_temp;

                    // mul specific
                    dispatch_packet.div_rs_packet.rs1_is_signed = decode_packet_in.rs1_is_signed;
                    dispatch_packet.div_rs_packet.rs2_is_signed = decode_packet_in.rs2_is_signed;
                    dispatch_packet.div_rs_packet.div_get_rem = decode_packet_in.div_get_rem;

                    // rvfi
                    dispatch_packet.div_rs_packet.rvfi_packet = decode_packet_in.rvfi_packet;
                end

                RS_LD : begin
                    dispatch_packet.ld_add_entry_en = '1;

                    // common RS metadata
                    dispatch_packet.ld_rs_packet.valid = '1;
                    dispatch_packet.ld_rs_packet.rob_idx = rob_idx;
                    dispatch_packet.ld_rs_packet.rd_paddr = rat_phys_reg_set;
                    dispatch_packet.ld_rs_packet.rs1_paddr = rat_rs1_paddr;
                    dispatch_packet.ld_rs_packet.rs1_ready = rs1_ready_temp;
                    // dispatch_packet.ld_rs_packet.rs2_en = decode_packet_in.rs2_used;
                    // dispatch_packet.ld_~rs_packet.rs2_paddr = rat_rs2_paddr;
                    // dispatch_packet.ld_rs_packet.rs2_ready = rs2_ready_temp;

                    // load/store specifc
                    dispatch_packet.ld_rs_packet.ld_type = load_f3_t'(decode_packet_in.funct3);
                    dispatch_packet.ld_rs_packet.imm = decode_packet_in.imm;

                    // rvfi
                    dispatch_packet.ld_rs_packet.rvfi_packet = decode_packet_in.rvfi_packet;
                end
                RS_SQ : begin
                    dispatch_packet.store_add_entry_en = '1;

                    // common RS metadata
                    dispatch_packet.sq_packet.valid = '1;
                    dispatch_packet.sq_packet.rob_idx = rob_idx;
                    // dispatch_packet.sq_packet.rs1_en = decode_packet_in.rs1_used;
                    dispatch_packet.sq_packet.rs1_paddr = rat_rs1_paddr;
                    dispatch_packet.sq_packet.rs1_ready = rs1_ready_temp;
                    // dispatch_packet.sq_packet.rs2_en = decode_packet_in.rs2_used;
                    dispatch_packet.sq_packet.rs2_paddr = rat_rs2_paddr;
                    dispatch_packet.sq_packet.rs2_ready = rs2_ready_temp;

                    // load/store specifc
                    dispatch_packet.sq_packet.st_type = store_f3_t'(decode_packet_in.funct3);
                    dispatch_packet.sq_packet.imm = decode_packet_in.imm;

                    // rvfi
                    dispatch_packet.sq_packet.rvfi_packet = decode_packet_in.rvfi_packet;
                end
                RS_BR : begin
                    dispatch_packet.branch_add_entry_en = '1;

                    // common RS metadata
                    dispatch_packet.branch_rs_packet.valid = '1;
                    dispatch_packet.branch_rs_packet.rob_idx = rob_idx;
                    dispatch_packet.branch_rs_packet.rd_paddr = rat_phys_reg_set;
                    dispatch_packet.branch_rs_packet.rs1_en = decode_packet_in.rs1_used;
                    dispatch_packet.branch_rs_packet.rs1_paddr = rat_rs1_paddr;
                    dispatch_packet.branch_rs_packet.rs1_ready = rs1_ready_temp;
                    dispatch_packet.branch_rs_packet.rs2_en = decode_packet_in.rs2_used;
                    dispatch_packet.branch_rs_packet.rs2_paddr = rat_rs2_paddr;
                    dispatch_packet.branch_rs_packet.rs2_ready = rs2_ready_temp;

                    // branch specifc
                    dispatch_packet.branch_rs_packet.predicted_pc = decode_packet_in.predicted_pc;
                    dispatch_packet.branch_rs_packet.br_en = decode_packet_in.br_en;
                    dispatch_packet.branch_rs_packet.jal_en = decode_packet_in.jal_en;
                    dispatch_packet.branch_rs_packet.jalr_en = decode_packet_in.jalr_en;
                    dispatch_packet.branch_rs_packet.cmpop = decode_packet_in.cmpop;
                    dispatch_packet.branch_rs_packet.br_imm = decode_packet_in.imm;

                    // rvfi
                    dispatch_packet.branch_rs_packet.rvfi_packet = decode_packet_in.rvfi_packet;
                end
                default : ; 
            endcase
        end
    end    
endmodule