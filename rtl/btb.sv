module btb 
import rv32i_types::*;
(
    input  logic        clk,
    input  logic        rst,

    // fetch reads BTB
    input  logic [29:0] pc_read,
    output logic [29:0] addr_prediction,
    output logic        btb_valid,

    // commit writes to BTB
    input  logic [29:0] pc_writing,
    input  logic [29:0] addr_writing,
    input  logic        update_btb
);

    logic [JALR_BTB_INDEX-1:0] read_index, write_index;

    assign read_index = pc_read[JALR_BTB_INDEX-1:0];
    assign write_index = pc_writing[JALR_BTB_INDEX-1:0];

    btb_data_array btb_sram (
        // Port 0: Write-Only Port (commit)w
        .clk0       (clk),
        .csb0       (~update_btb),
        .addr0      (write_index), 
        .din0       (addr_writing),

        // Port 1: Read-Only Port (fetch)
        .clk1       (clk), 
        .csb1       ('0),       // always reading
        .addr1      (read_index),
        .dout1      (addr_prediction)
    );
    
    read_write_valid_array #(.S_INDEX(JALR_BTB_INDEX)) valid_array (
        .clk0       (clk),
        .rst0       (rst),
    
        // read only port (fetch)
        .csb0       ('0),       // always reading
        .addr0      (read_index),
        .dout0      (btb_valid),

        // write only port (commit)
        .csb1       (~update_btb),
        .addr1      (write_index),
        .din1       ('1)            // Writing establishes validity, so write 1
    );
    
endmodule