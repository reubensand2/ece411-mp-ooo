module alu
import rv32i_types::*;
(
    // control
    input	alu_ops         aluop,
	input	alu_m1_sel_t    alu_m1_sel,
	input	alu_m2_sel_t    alu_m2_sel,
	input	branch_f3_t	    cmpop,
	input	logic           ctrl_slt,   // 1 = CMP output, 0 = ALU output ,

    // data
    input   logic [31:0]    pc,
    input   logic [31:0]    rs1_data,
    input   logic [31:0]    rs2_data,
    input   logic [31:0]    imm,
    output  logic [31:0]    rd_data
);

    logic [31:0] a, b, f;
    logic cmpout;

    
    logic signed   [31:0] as;
    logic signed   [31:0] bs;
    logic unsigned [31:0] au;
    logic unsigned [31:0] bu;

    assign as =   signed'(a);
    assign bs =   signed'(b);
    assign au = unsigned'(a);
    assign bu = unsigned'(b);

    always_comb begin
        unique case (alu_m1_sel)
            rs1_out: a = rs1_data;
            pc_out : a = pc;
            zero   : a = '0;
            default: a = '0;
        endcase

        unique case (alu_m2_sel)
            rs2_out: b = rs2_data;
            imm_out: b = imm;
            default: b = '0;
        endcase
        unique case (aluop)
            alu_op_add: f = au +   bu;
            alu_op_sll: f = au <<  bu[4:0];
            alu_op_sra: f = unsigned'(as >>> bu[4:0]);
            alu_op_sub: f = au -   bu;
            alu_op_xor: f = au ^   bu;
            alu_op_srl: f = au >>  bu[4:0];
            alu_op_or : f = au |   bu;
            alu_op_and: f = au &   bu;
            default   : f = 'x;
        endcase
    end

    always_comb begin
		unique case (cmpop)
		    branch_f3_beq:  cmpout = (au == bu);
		    branch_f3_bne:  cmpout = (au != bu);
		    branch_f3_blt:  cmpout = (as <  bs);
		    branch_f3_bge:  cmpout = (as >=  bs);
		    branch_f3_bltu: cmpout = (au <  bu);
		    branch_f3_bgeu: cmpout = (au >=  bu);
		default: cmpout = 1'bx;
		endcase
    end

    assign rd_data = ctrl_slt ? {31'd0, cmpout} : f;

endmodule