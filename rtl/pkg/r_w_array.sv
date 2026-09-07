module read_write_valid_array
import rv32i_types::*;
#(
    parameter               S_INDEX     = 4,
    parameter               WIDTH       = 1
)(
    input   logic                   clk0,
    input   logic                   rst0,

    // port 1
    input   logic                   csb0,
    input   logic   [S_INDEX-1:0]   addr0,
    output  logic   [WIDTH-1:0]     dout0,

    // port 2
    input   logic                   csb1,
    input   logic   [S_INDEX-1:0]   addr1,
    input   logic   [WIDTH-1:0]     din1
);

    localparam              NUM_SETS    = 2**S_INDEX;

    logic   [S_INDEX-1:0]   addr0_reg;
    logic   [WIDTH-1:0]     web1_reg;
    logic   [S_INDEX-1:0]   addr1_reg;
    logic   [WIDTH-1:0]     din1_reg;

    logic   [WIDTH-1:0]     internal_array [NUM_SETS];

    always_ff @(posedge clk0) begin
        if (rst0) begin
            addr0_reg <= 'x;
            addr1_reg <= 'x;
            
            din1_reg  <= 'x;
            web1_reg  <= '1;
        end else begin
            if (!csb0) begin
                addr0_reg <= addr0;
            end
            if(!csb1) begin
                web1_reg <= csb1;
                addr1_reg <= addr1;
                din1_reg  <= din1;
            end
        end
    end

    always_ff @(posedge clk0) begin
        if (rst0) begin
            for (integer unsigned i = 0; i < NUM_SETS; i++) begin
                internal_array[i] <= '0;
            end
        end else begin
            if (!web1_reg) begin
                internal_array[addr1_reg] <= din1_reg;
            end
        end
    end

    always_comb begin
        dout0 = internal_array[addr0_reg];
    end


endmodule