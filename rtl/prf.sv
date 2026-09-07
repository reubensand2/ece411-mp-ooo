module prf 
import rv32i_types::*;
#(
    parameter DATA_WIDTH = 32,
    parameter NUM_SLOTS = 64,
    parameter NUM_READ_PORTS = 1,
    parameter NUM_WRITE_PORTS = 1
)
(
    input   logic           clk,
    input   logic           rst,
    input   logic           [NUM_WRITE_PORTS-1:0] prf_we,
    input   logic   [DATA_WIDTH-1:0]  wdata[NUM_WRITE_PORTS], 
    input   logic   [PRF_IDX_WIDTH-1:0]   waddr[NUM_WRITE_PORTS],

    // not sure if should output whole file. also consider clocking data_out if timing bad
    // output  logic   [DATA_WIDTH-1:0]  data[NUM_SLOTS]

    input   logic   [PRF_IDX_WIDTH-1:0]   raddr[NUM_READ_PORTS],
    output logic [DATA_WIDTH-1:0]  rdata[NUM_READ_PORTS]
);

    logic   [DATA_WIDTH-1:0]  data [NUM_SLOTS];

    always_comb begin
        for (integer unsigned i = 0; i <  NUM_READ_PORTS; i++) begin
            rdata[i] = data[raddr[i]];
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (integer unsigned i = 0; i < NUM_SLOTS; i++) begin
                data[i] <= '0;
            end
        end else begin
            for (integer unsigned i = 0; i < NUM_WRITE_PORTS; i++) begin
                if (prf_we[i] && (waddr[i] != 0)) begin
                    data[waddr[i]] <= wdata[i];
                end
            end
        end
    end

endmodule : prf