module mem_alu 
import rv32i_types::*;
(
    input logic mem_write,
    // input logic accept_new,
    input logic [31:0] rs1_data,
    input logic [31:0] rs2_data,
    input load_f3_t ld_type,
    input store_f3_t st_type,
    input logic [31:0] imm,
    // processing mem_rdata 
    input logic dmem_resp,
    input logic [31:0] dmem_rdata,
    input load_f3_t mem_saved_ld_type,
    input logic [1:0] offset,

    output logic [31:0] dmem_addr,
    output logic [3:0]  dmem_rmask,
    output logic [3:0]  dmem_wmask,
    output logic [31:0] dmem_wdata,
    output logic [31:0] mem_rd_data
);

always_comb begin
    dmem_addr   = imm + rs1_data;
    dmem_rmask  = '0;
    dmem_wmask  = '0;
    dmem_wdata  = '0;
    mem_rd_data = '0;

    // Always compute masks/wdata — gating is now handled in execute
    if (mem_write) begin
        unique case (st_type)
            store_f3_sb: dmem_wmask = 4'b0001 << dmem_addr[1:0];
            store_f3_sh: dmem_wmask = 4'b0011 << dmem_addr[1:0];
            store_f3_sw: dmem_wmask = 4'b1111;
            default    : dmem_wmask = '0;
        endcase
        unique case (st_type)
            store_f3_sb: dmem_wdata[8 *dmem_addr[1:0] +: 8 ] = rs2_data[7 :0];
            store_f3_sh: dmem_wdata[16*dmem_addr[1]   +: 16] = rs2_data[15:0];
            store_f3_sw: dmem_wdata                           = rs2_data;
            default    : dmem_wdata = '0;
        endcase
    end else begin
        unique case (ld_type)
            load_f3_lb, load_f3_lbu: dmem_rmask = 4'b0001 << dmem_addr[1:0];
            load_f3_lh, load_f3_lhu: dmem_rmask = 4'b0011 << dmem_addr[1:0];
            load_f3_lw              : dmem_rmask = 4'b1111;
            default                 : dmem_rmask = '0;
        endcase
    end

    // Read data decode — only valid when dmem_resp is high
    if (dmem_resp) begin
        unique case (mem_saved_ld_type)
            load_f3_lb : mem_rd_data = {{24{dmem_rdata[7 +8 *offset[1:0]]}}, dmem_rdata[8 *offset[1:0] +: 8 ]};
            load_f3_lbu: mem_rd_data = {{24{1'b0}},                           dmem_rdata[8 *offset[1:0] +: 8 ]};
            load_f3_lh : mem_rd_data = {{16{dmem_rdata[15+16*offset[1]  ]}}, dmem_rdata[16*offset[1]   +: 16]};
            load_f3_lhu: mem_rd_data = {{16{1'b0}},                           dmem_rdata[16*offset[1]   +: 16]};
            load_f3_lw : mem_rd_data = dmem_rdata;
            default    : mem_rd_data = '0;
        endcase
    end
end

endmodule