module rrat #(
    parameter DATA_WIDTH = 6,
    parameter NUM_SLOTS = 32,
    parameter NUM_READ_PORTS = 1,
    parameter NUM_WRITE_PORTS = 1
)
(
    input   logic           clk,
    input   logic           rst,
    input   logic           [NUM_WRITE_PORTS-1:0] rrat_we,
    input   logic   [DATA_WIDTH-1:0]  wdata[NUM_WRITE_PORTS],
    input   logic   [($clog2(NUM_SLOTS)-1):0]   waddr[NUM_WRITE_PORTS],
    // not sure if should output whole file or indiv regs. also consider clocking data_out if timing bad
    
    input   logic   [($clog2(NUM_SLOTS)-1):0]   raddr[NUM_READ_PORTS],
    output  logic [DATA_WIDTH-1:0]  rdata[NUM_READ_PORTS],
    output  logic   [DATA_WIDTH-1:0]  rrat_state_out [NUM_SLOTS]
);


    always_comb begin
        for (integer unsigned i = 0; i <  NUM_READ_PORTS; i++) begin
            rdata[i] = rrat_state_out[raddr[i]];
        end
    end
    always_ff @(posedge clk) begin
        if (rst) begin
            for (integer unsigned i = 0; i < NUM_SLOTS; i++) begin
                rrat_state_out[i] <= '0;
            end
        end else begin
            for (integer unsigned i = 0; i < NUM_WRITE_PORTS; i++) begin
                if (rrat_we[i] && (waddr[i] != '0)) begin
                    rrat_state_out[waddr[i]] <= wdata[i];
                end
            end
        end
    end

endmodule : rrat