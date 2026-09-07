module rat 
import rv32i_types::*;
#(
    parameter DATA_WIDTH = 6,
    parameter NUM_SLOTS = 32,
    parameter NUM_READ_PORTS = 2,
    parameter NUM_WRITE_PORTS = 1
)
(
    input   logic           clk,
    input   logic           rst,

    // dispatch invalidates new destination register
    input   logic          [NUM_WRITE_PORTS-1:0] rat_we,
    input   logic   [DATA_WIDTH-1:0]  wdata[NUM_WRITE_PORTS],
    input   logic   [($clog2(NUM_SLOTS)-1):0]   waddr[NUM_WRITE_PORTS],
    
    // cdb validates completed instruction's destination register
    input   cdb_packet_t cdb_packet,

    // dispatch reads the rat for rs1/rs2, and whether they're ready or not
    input   logic   [($clog2(NUM_SLOTS)-1):0]   raddr[NUM_READ_PORTS],
    output  logic [DATA_WIDTH-1:0]  rdata[NUM_READ_PORTS],
    output  logic           valid_out[NUM_READ_PORTS],

    input   logic           flush,
    input   logic [DATA_WIDTH-1:0]  rrat_state_in [NUM_SLOTS],
    input   logic                           commit_we,
    input   logic [($clog2(NUM_SLOTS)-1):0] commit_waddr,
    input   logic [DATA_WIDTH-1:0]          commit_wdata,

    // Add to port list:
    input  logic                             commit_we_1,
    input  logic [($clog2(NUM_SLOTS)-1):0]  commit_waddr_1,
    input  logic [DATA_WIDTH-1:0]           commit_wdata_1

);

    logic   [DATA_WIDTH-1:0]  data [NUM_SLOTS];
    logic   valid [NUM_SLOTS];


    always_comb begin
        for (integer unsigned i = 0; i <  NUM_READ_PORTS; i++) begin
            rdata[i] = (raddr[i] != '0) ? data[raddr[i]] : '0;
            valid_out[i] = valid[raddr[i]];
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            // all registers are valid on reset (not waiting for an instruction)
            for (integer unsigned i = 0; i < NUM_SLOTS; i++) begin
                data[i] <= '0;
                valid[i] <= '1;
            end
        end else if (flush) begin
            // copy entire RRAT to RAT
            data    <= rrat_state_in;

            // override is instruction is committing while flushing (jumps)
            if (commit_we && commit_waddr != '0)
                data[commit_waddr] <= commit_wdata;
            if (commit_we_1 && commit_waddr_1 != '0)
                data[commit_waddr_1] <= commit_wdata_1;
            
            // mark all register as valid
            for (integer unsigned i = 0; i < NUM_SLOTS; i++)
                valid[i] <= '1;
        end
        else begin
            // CDB packet validates completed instructions destination registers
            if ((cdb_packet.alu_en) && (data[cdb_packet.alu_rd_addr] == cdb_packet.alu_rd_paddr)) begin
                valid[cdb_packet.alu_rd_addr] <= '1;
            end

            if ((cdb_packet.mul_en) && (data[cdb_packet.mul_rd_addr] == cdb_packet.mul_rd_paddr)) begin
                valid[cdb_packet.mul_rd_addr] <= '1;
            end

            if ((cdb_packet.div_en) && (data[cdb_packet.div_rd_addr] == cdb_packet.div_rd_paddr)) begin
                valid[cdb_packet.div_rd_addr] <= '1;
            end
            
            if ((cdb_packet.branch_en) && (data[cdb_packet.branch_rd_addr] == cdb_packet.branch_rd_paddr)) begin
                valid[cdb_packet.branch_rd_addr] <= '1;
            end
            
            if ((cdb_packet.mem_en) && (data[cdb_packet.mem_rd_addr] == cdb_packet.mem_rd_paddr)) begin
                valid[cdb_packet.mem_rd_addr] <= '1;
            end

            // Dispatch override
            // Because this comes AFTER the CDB logic in the procedural block, 
            // if a dispatch and a CDB hit the same architectural register, 
            // dispatch assignment wins
            for (integer unsigned i = 0; i < NUM_WRITE_PORTS; i++) begin
                if (rat_we[i] && (waddr[i] != '0)) begin
                    data[waddr[i]] <= wdata[i];
                    valid[waddr[i]] <= '0;
                end
            end
        end
    end

endmodule