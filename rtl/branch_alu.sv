module branch_alu 
import rv32i_types::*;
(
    // control
	input	branch_f3_t	    cmpop,
    input   logic           br_en,
    input   logic           jal_en,
    input   logic           jalr_en,

    // data
    input   logic [31:0]    pc,
    input   logic [31:0]    predicted_pc,
    input   logic [31:0]    imm,
    input   logic [31:0]    rs1_data,
    input   logic [31:0]    rs2_data,

    // outputs
    output  logic           br_mispredict,
    output  logic           br_outcome,
    output  logic [31:0]    actual_next_pc,
    output  logic [31:0]    rd_data
);
    logic        branch_taken;

    
    logic signed   [31:0] as;
    logic signed   [31:0] bs;
    logic unsigned [31:0] au;
    logic unsigned [31:0] bu;

    assign as =   signed'(rs1_data);
    assign bs =   signed'(rs2_data);
    assign au = unsigned'(rs1_data);
    assign bu = unsigned'(rs2_data);

    always_comb begin
		unique case (cmpop)
		    branch_f3_beq:  branch_taken = (au == bu);
		    branch_f3_bne:  branch_taken = (au != bu);
		    branch_f3_blt:  branch_taken = (as <  bs);
		    branch_f3_bge:  branch_taken = (as >=  bs);
		    branch_f3_bltu: branch_taken = (au <  bu);
		    branch_f3_bgeu: branch_taken = (au >=  bu);
		default: branch_taken = 1'bx;
		endcase
    end

    always_comb begin
        // Default values
        actual_next_pc  = '0;
        rd_data         = '0;
        br_mispredict   = '0;
        br_outcome      = '0;

        // 1. Calculate Reality
        if (jal_en) begin
            // Fetch always gets JAL right. Just prep the CDB payload.
            actual_next_pc = pc + imm; 
            rd_data        = pc + 4;
        end 
        else if (jalr_en) begin
            // JALR requires rs1 to calculate the target
            actual_next_pc = (rs1_data + imm) & 32'hFFFFFFFE;
            rd_data        = pc + 4;
        end 
        else if (br_en) begin
            // BR requires the comparator outcome
            actual_next_pc = branch_taken ? (pc + imm) : (pc + 4);
            br_outcome = branch_taken;
        end

        if (actual_next_pc != predicted_pc) begin
            br_mispredict = 1'b1;
        end
    end
endmodule