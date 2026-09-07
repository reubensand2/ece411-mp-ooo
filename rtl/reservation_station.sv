module reservation_station 
import rv32i_types::*;
#(
    parameter type RES_STATION_ENTRY_T = alu_res_station_entry_t,
    parameter integer unsigned NUM_SLOTS = 4,
    parameter TOTAL_COUNT_WIDTH = $clog2(NUM_SLOTS + 1),
    parameter PRF_IDX_WIDTH = 6, // for 64 physical register files
    parameter NUM_WAKEUP_PORTS = 3
)   
(
    input   logic           clk,
    input   logic           rst,

    //  Dispatch (add) interface
    input   logic           add_entry_en, // might need mult ports later one for superscalars
    input   RES_STATION_ENTRY_T   wdata,

    // CBD wakeup
    input   logic    [NUM_WAKEUP_PORTS-1:0] rs_wakeup, 
    input   logic   [PRF_IDX_WIDTH-1:0]   rs_ready_addr[NUM_WAKEUP_PORTS],

    // Issue (clear) Interface
    input   logic           clear_entry_en,
    input   logic   [($clog2(NUM_SLOTS)-1):0] clear_entry_idx,

    // branch mispredict
    input   logic   flush_pipeline,
    
    output logic    full,
    output  RES_STATION_ENTRY_T   data[NUM_SLOTS] 
);

    logic [TOTAL_COUNT_WIDTH-1:0] curr_size;

    logic [$clog2(NUM_SLOTS)-1:0] free_idx;
    logic found_free;
    logic    empty;

    always_comb begin
        empty = (curr_size == 0);
        full = (curr_size == TOTAL_COUNT_WIDTH'(NUM_SLOTS));

        free_idx = '0;
        found_free = '0;

        // First look for naturally empty slots
        for (integer unsigned i = 0; i < NUM_SLOTS; i++) begin
            if (!data[i].valid && !found_free) begin
                free_idx = $clog2(NUM_SLOTS)'(i);
                found_free = '1;
            end
        end

        // If no empty slot found, but one is being cleared this cycle, use that
        if (!found_free && clear_entry_en) begin
            free_idx = clear_entry_idx;
            found_free = '1;
        end

        // RS can accept if not full, OR if full but clearing one this cycle
        full = (curr_size == TOTAL_COUNT_WIDTH'(NUM_SLOTS)) && !clear_entry_en;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            curr_size <= '0;
            for (integer unsigned i = 0; i < NUM_SLOTS; i++)
                data[i] <= '0;
        end 
        else if (flush_pipeline) begin
            curr_size <= '0;
            for (integer unsigned i = 0; i < NUM_SLOTS; i++)
                data[i].valid <= '0;
        end
        else begin
            // update size counter to handle simultaneous add & clear
            if (add_entry_en && !full && clear_entry_en)
                curr_size <= curr_size; // no change
            else if (add_entry_en && !full) 
                curr_size <= curr_size + 1'd1;
            else if (clear_entry_en) 
                curr_size <= curr_size - 1'd1;

            // clear an entry (Issue)
            if (clear_entry_en)
                data[clear_entry_idx] <= '0;

            // add entry (Dispatch)
            if (add_entry_en && !full && found_free)
                data[free_idx] <= wdata;

            // wakeup operands (CDB Snooping)
            for (integer unsigned port = 0; port < NUM_WAKEUP_PORTS; port++) begin
                if (rs_wakeup[port] && !empty) begin
                    for (integer unsigned i = 0; i< NUM_SLOTS; i++) begin
                        // Only wake up valid entries, and don't bother waking up 
                        // an entry we are actively clearing this cycle.
                        if (data[i].valid) begin
                            if (data[i].rs1_paddr == rs_ready_addr[port])
                                data[i].rs1_ready <= '1;
                            if (data[i].rs2_paddr == rs_ready_addr[port])
                                data[i].rs2_ready <= '1;
                        end
                    end
                end
            end
        end
    end

endmodule