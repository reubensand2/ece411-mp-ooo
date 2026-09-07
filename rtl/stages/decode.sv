module decode
import rv32i_types::*;
(
	input 	inst_queue_packet_t	inst_queue_packet,
	output 	decode_packet_t   		decode_packet
);

	logic 	[4:0] 	rs1_s;
	logic 	[4:0]	rs2_s;
	logic   [2:0]   funct3;
    logic   [6:0]   funct7;
    logic   [6:0]   opcode;
    logic   [31:0]  i_imm;
    logic   [31:0]  s_imm;
    logic   [31:0]  b_imm;
    logic   [31:0]  u_imm;
    logic   [31:0]  j_imm;
    logic   [4:0]   rd_s;
    logic   [31:0]  inst;

	assign inst = inst_queue_packet.inst;

	assign opcode = inst[6:0];
    assign funct3 = inst[14:12];
    assign funct7 = inst[31:25];

    assign i_imm  = {{21{inst[31]}}, inst[30:20]};
    assign s_imm  = {{21{inst[31]}}, inst[30:25], inst[11:7]};
    assign b_imm  = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
    assign u_imm  = {inst[31:12], 12'h000};
    assign j_imm  = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
    
    assign rs1_s  = inst[19:15];
    assign rs2_s  = inst[24:20];
    assign rd_s   = inst[11:7];

	always_comb begin
		decode_packet = '0;
		decode_packet.rvfi_packet = '0;

		decode_packet.rvfi_packet.valid = inst_queue_packet.valid;
		decode_packet.rvfi_packet.inst 	= inst_queue_packet.inst;
        decode_packet.predicted_pc      = inst_queue_packet.predicted_pc;

        // gshare
        decode_packet.pred_prediction   = inst_queue_packet.pred_prediction;
        decode_packet.pred_pht_index    = inst_queue_packet.pred_pht_index;

        // ras
        decode_packet.ras_top_ptr    = inst_queue_packet.ras_top_ptr;
        
        
        //get order in writeback

		// set rs1_addr, rs2_addr depending on opcode
		// get rs1_rdata, rs2_rdata after issue
		// set rd_addr depending on opcode
		decode_packet.rvfi_packet.pc_rdata = inst_queue_packet.pc;
		decode_packet.rvfi_packet.order = inst_queue_packet.order;
        
		// get rd_wdata, pc_wdata after alu
		// get mem_addr, mem_rmask, mem_wmask, mem_rdata, mem_wdata after LSU
		
		// default control signals
        decode_packet.reg_load      = 1'b0;
        // decode_packet.mem_read      = 1'b0;
        decode_packet.mem_write     = 1'b0;
        decode_packet.aluop         = alu_op_add;
        decode_packet.alu_m1_sel    = rs1_out; // Default to RS1
        decode_packet.alu_m2_sel    = rs2_out; // Default to RS2
        decode_packet.cmpop         = branch_f3_beq;
        decode_packet.ctrl_slt      = 1'b0;
        decode_packet.br_en         = 1'b0;
        decode_packet.jal_en        = 1'b0;
        decode_packet.jalr_en       = 1'b0;

        decode_packet.imm           = '0;

        unique case (opcode)
            
            op_b_lui: begin
                decode_packet.rvfi_packet.rd_addr  = rd_s;
                
                decode_packet.rs_target  = RS_ALU;
                decode_packet.imm        = u_imm;
                decode_packet.alu_m1_sel = zero;
                decode_packet.alu_m2_sel = imm_out;
                decode_packet.reg_load   = 1'b1;
            end

            op_b_auipc: begin
                decode_packet.rvfi_packet.rd_addr     = rd_s;

                decode_packet.rs_target  = RS_ALU;
                decode_packet.imm      = u_imm;
                decode_packet.alu_m1_sel = pc_out; // Use PC
                decode_packet.alu_m2_sel = imm_out; // Use Immediate
                decode_packet.reg_load   = 1'b1;
            end

            op_b_imm: begin
                decode_packet.rvfi_packet.rd_addr     = rd_s;
                decode_packet.rvfi_packet.rs1_addr    = rs1_s;
                
                decode_packet.rs_target  = RS_ALU;
                decode_packet.alu_m2_sel = imm_out; // Immediate
                decode_packet.imm      = i_imm;
                decode_packet.reg_load   = 1'b1;
                
                // --- SLTI Logic ---
                if (funct3 == arith_f3_slt) begin
                    decode_packet.cmpop    = branch_f3_blt;
                    decode_packet.ctrl_slt = 1'b1; // Take result from CMP
                end 
                else if (funct3 == arith_f3_sltu) begin
                    decode_packet.cmpop    = branch_f3_bltu;
                    decode_packet.ctrl_slt = 1'b1; // Take result from CMP
                end 
                else begin
                    // Standard ALU Op
                    if (funct3 == arith_f3_sr && funct7[5])
                        decode_packet.aluop = alu_op_sra;
                    else
                        decode_packet.aluop = alu_ops'(funct3);
                end
            end

            op_b_reg: begin
                decode_packet.rvfi_packet.rs1_addr    = rs1_s;
                decode_packet.rvfi_packet.rs2_addr    = rs2_s;
                decode_packet.rvfi_packet.rd_addr     = rd_s;

                decode_packet.reg_load   = 1'b1;
                
                // --- Multiply & Divide (M-Extension) ---
                if (funct7[0]) begin
                    // Assuming you have a local variable mul_op for the case switch
                    mul_funct3_t mul_op;
                    mul_op = mul_funct3_t'(funct3); 
                    
                    // funct3[2] == 0 means MUL, funct3[2] == 1 means DIV/REM
                    decode_packet.rs_target = funct3[2] ? RS_DIV : RS_MUL;

                    case (mul_op)
                        // --- MULTIPLY CASES ---
                        mul: begin 
                            decode_packet.rs1_is_signed = '0;   // don't need to be signed
                            decode_packet.rs2_is_signed = '0;   // don't need to be signed
                            decode_packet.mul_high_bits = '0;
                            decode_packet.div_get_rem   = '0; // Default
                        end
                        mulh: begin
                            decode_packet.rs1_is_signed = '1; 
                            decode_packet.rs2_is_signed = '1;
                            decode_packet.mul_high_bits = '1;
                            decode_packet.div_get_rem   = '0;
                        end
                        mulhsu: begin 
                            decode_packet.rs1_is_signed = '1; 
                            decode_packet.rs2_is_signed = '0; 
                            decode_packet.mul_high_bits = '1;
                            decode_packet.div_get_rem   = '0;
                        end
                        mulhu: begin 
                            decode_packet.rs1_is_signed = '0; 
                            decode_packet.rs2_is_signed = '0; 
                            decode_packet.mul_high_bits = '1;
                            decode_packet.div_get_rem   = '0;
                        end
                        
                        // --- DIVIDE / REMAINDER CASES ---
                        div: begin
                            decode_packet.rs1_is_signed = '1; 
                            decode_packet.rs2_is_signed = '1; 
                            decode_packet.mul_high_bits = '0; 
                            decode_packet.div_get_rem   = '0; // Want Quotient
                        end
                        divu: begin
                            decode_packet.rs1_is_signed = '0; 
                            decode_packet.rs2_is_signed = '0; 
                            decode_packet.mul_high_bits = '0; 
                            decode_packet.div_get_rem   = '0; // Want Quotient
                        end
                        rem: begin
                            decode_packet.rs1_is_signed = '1; 
                            decode_packet.rs2_is_signed = '1; 
                            decode_packet.mul_high_bits = '0; 
                            decode_packet.div_get_rem   = '1; // Want Remainder
                        end
                        remu: begin
                            decode_packet.rs1_is_signed = '0; 
                            decode_packet.rs2_is_signed = '0; 
                            decode_packet.mul_high_bits = '0; 
                            decode_packet.div_get_rem   = '1; // Want Remainder
                        end
                        
                        default: begin 
                            decode_packet.rs1_is_signed = '0; 
                            decode_packet.rs2_is_signed = '0; 
                            decode_packet.mul_high_bits = '0;
                            decode_packet.div_get_rem   = '0;
                        end
                    endcase
                end
                // --- SLT Logic ---
                else if (funct3 == arith_f3_slt) begin
                    decode_packet.cmpop    = branch_f3_blt;
                    decode_packet.ctrl_slt = 1'b1;
                    decode_packet.rs_target = RS_ALU;
                end 
                else if (funct3 == arith_f3_sltu) begin
                    decode_packet.cmpop    = branch_f3_bltu;
                    decode_packet.ctrl_slt = 1'b1;
                    decode_packet.rs_target = RS_ALU;
                end 
                else begin
                    // Standard ALU Op
                    decode_packet.rs_target = RS_ALU;
                    if (funct3 == arith_f3_sr && funct7[5])
                        decode_packet.aluop = alu_op_sra;
                    else if (funct3 == arith_f3_add && funct7[5])
                        decode_packet.aluop = alu_op_sub;
                    else
                        decode_packet.aluop = alu_ops'(funct3);
                end
            end

            op_b_load: begin
                decode_packet.rvfi_packet.rs1_addr        = rs1_s;
                decode_packet.rvfi_packet.rd_addr         = rd_s;

                decode_packet.rs_target    = RS_LD;
                decode_packet.alu_m2_sel   = imm_out; // I-Imm
                decode_packet.imm          = i_imm;
                decode_packet.funct3       = funct3;
                // decode_packet.mem_read     = 1'b1; // It's a load!
                decode_packet.reg_load     = 1'b1; // Will write back later
            end

            op_b_store: begin
                decode_packet.rvfi_packet.rs1_addr        = rs1_s;
                decode_packet.rvfi_packet.rs2_addr        = rs2_s;
                
                decode_packet.rs_target    = RS_SQ; // TODO:CHANGE
                decode_packet.alu_m2_sel   = imm_out;
                decode_packet.imm          = s_imm;
                decode_packet.funct3       = funct3;
                decode_packet.mem_write    = 1'b1; // It's a store!
            end
            
            op_b_br: begin
                decode_packet.rvfi_packet.rs1_addr        = rs1_s;
                decode_packet.rvfi_packet.rs2_addr        = rs2_s;
                
                decode_packet.rs_target    = RS_BR;
                decode_packet.imm          = b_imm;
                decode_packet.alu_m1_sel   = pc_out;
                decode_packet.alu_m2_sel   = imm_out;
                decode_packet.cmpop        = branch_f3_t'(funct3);
                decode_packet.br_en        = 1'b1;
            end

            op_b_jal: begin
                decode_packet.rvfi_packet.rd_addr         = rd_s;
                
                decode_packet.rs_target    = RS_BR;
                decode_packet.imm          = j_imm;
                decode_packet.alu_m1_sel   = pc_out;
                decode_packet.alu_m2_sel   = imm_out;
                decode_packet.reg_load     = 1'b1;
                decode_packet.jal_en        = 1'b1;
            end

            op_b_jalr: begin
                decode_packet.rvfi_packet.rs1_addr        = rs1_s;
                decode_packet.rvfi_packet.rd_addr         = rd_s;

                decode_packet.rs_target    = RS_BR;
                decode_packet.imm          = i_imm;
                decode_packet.alu_m1_sel   = rs1_out;
                decode_packet.alu_m2_sel   = imm_out;
                decode_packet.reg_load     = 1'b1;
                decode_packet.jalr_en        = 1'b1;
            end

            default: ;
        endcase

        // rs1 is used by almost everything except U-types and JAL
        // In your logic, it's used if it goes to the ALU or the Comparator
        decode_packet.rs1_used = (decode_packet.alu_m1_sel == rs1_out) || decode_packet.br_en;
        
        // rs2 is used if:
        // 1. It goes to the ALU (R-type)
        // 2. It's a Branch comparison (B-type)
        // 3. It's the data being stored to memory (S-type)
        decode_packet.rs2_used = (decode_packet.alu_m2_sel == rs2_out) || decode_packet.br_en || decode_packet.mem_write;

	end
endmodule