module gshare 
import rv32i_types::*;
(
    input logic   clk,
    input logic   rst,

    // new prediction
    input logic [31:0]                  pc_next,
    output logic [$clog2(PHT_SIZE)-1:0] new_pht_index,
    output logic [1:0]                  new_prediction,
    
    // commited branch
    input logic                         update_predictor,
    input logic                         br_outcome,
    input logic [1:0]                   rob_old_prediction,
    input logic [$clog2(PHT_SIZE)-1:0]  rob_pht_index
);
    // read signals
    logic [$clog2(PHT_SIZE)-1:0]    read_index_next, read_index_curr;
    logic [1:0]                     read_prediction_curr;

    // write signals
    logic [1:0]                     updated_prediction;

    // forwarding signals
    logic [$clog2(PHT_SIZE)-1:0]    index_updated_last_cycle;
    logic                           updated_last_cycle;
    logic [1:0]                     prediction_updated_last_cycle;

    // state
    logic [GHR_SIZE-1:0]    global_history_reg;
    logic [PHT_SIZE-1:0]    valid_array;

    gshare_pht_array pht_sram (
        // Port 0: Write-Only Port
        .clk0       (clk),
        .csb0       (~update_predictor), // Active-low chip select acts as the write enable
        .addr0      (rob_pht_index), 
        .din0       (updated_prediction),

        // Port 1: Read-Only Port
        .clk1       (clk), 
        .csb1       ('0),                // Active-low, always reading
        .addr1      (read_index_next),
        .dout1      (read_prediction_curr)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            global_history_reg              <=  '0;
            valid_array                     <=  '0;
            index_updated_last_cycle        <=  '0;
            updated_last_cycle              <=  '0;
            prediction_updated_last_cycle   <=  '0;
            read_index_curr                 <=  '0;
        end
        else begin
            read_index_curr     <= read_index_next;
            updated_last_cycle  <= update_predictor;

            // update GHR
            if (update_predictor) begin
                global_history_reg              <= {global_history_reg[GHR_SIZE-2:0], br_outcome};
                index_updated_last_cycle        <= rob_pht_index;
                prediction_updated_last_cycle   <= updated_prediction;
                valid_array[rob_pht_index]      <= '1;
            end

        end
    end

    always_comb begin
        // next prediction address 
        // read_index_next = pc_next[31:25] ^ pc_next[24:18] ^ pc_next[17:11] ^ pc_next[10:4] ^ global_history_reg;
        // Use bits [8:2] as the primary base to avoid aliasing within a cache line
        // read_index_next = pc_next[31:25] ^ pc_next[24:18] ^ pc_next[17:11] ^ pc_next[8:2] ^ global_history_reg;
        read_index_next = pc_next[GHR_SIZE+1:2] ^ global_history_reg;
        
        /*      making prediction      */
        // forward prediction (RAW hazard)
        if (read_index_curr == index_updated_last_cycle && updated_last_cycle)
            new_prediction = prediction_updated_last_cycle;
        // valid predictor
        else if (valid_array[read_index_curr])
            new_prediction = read_prediction_curr;
        // first access to predictor
        else
            new_prediction = 2'b01;

        new_pht_index = read_index_curr;

        /*      updating prediction      */
        updated_prediction = rob_old_prediction; // default hold
        if (br_outcome && rob_old_prediction != 2'b11) begin
            updated_prediction = rob_old_prediction + 2'd1;
        end 
        else if (!br_outcome && rob_old_prediction != 2'b00) begin
            updated_prediction = rob_old_prediction - 2'd1;
        end
    end

endmodule