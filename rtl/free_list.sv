module free_list #(
    parameter NUM_PHYS_REGS = 64
)(
    input  logic clk,
    input  logic rst,
    input  logic                               allocate_req,
    output logic [$clog2(NUM_PHYS_REGS)-1:0]  allocate_id,
    output logic                               empty,
    // slot 0 commit return
    input  logic                               rrat_insert_req,
    input  logic [$clog2(NUM_PHYS_REGS)-1:0]  rrat_insert_paddr,
    // slot 1 commit return — NEW
    input  logic                               rrat_insert_req_1,
    input  logic [$clog2(NUM_PHYS_REGS)-1:0]  rrat_insert_paddr_1,
    // WAW: slot 0 allocated paddr is dead, free it directly — NEW
    input  logic                               waw_free_req,
    input  logic [$clog2(NUM_PHYS_REGS)-1:0]  waw_free_paddr,
    input  logic                               restore_req,
    input  logic [NUM_PHYS_REGS-1:0]          restore_bitmask
);
    // 1 = Allocated/Busy, 0 = Free
    logic [NUM_PHYS_REGS-1:0] free_mask;
    
    logic [$clog2(NUM_PHYS_REGS)-1:0] next_free_idx;
    logic is_empty;

    // --- Priority Encoder (Find the first '0') ---
    always_comb begin
        next_free_idx = '0;
        is_empty = 1'b1; // Default to empty
        
        // Start from index 1! Physical Register 0 is tied to x0 and is NEVER free.
        for (integer unsigned i = 1; i < NUM_PHYS_REGS; i++) begin
            if (free_mask[i] == 1'b0) begin
                next_free_idx = $clog2(NUM_PHYS_REGS)'(i);
                is_empty = 1'b0;
                break; // Found one, exit the loop
            end
        end
    end

    // Output assignments
    assign allocate_id = next_free_idx;
    assign empty       = is_empty;

    always_ff @(posedge clk) begin
        if (rst) begin
            free_mask    <= '0;
            free_mask[0] <= 1'b1;
        end else if (restore_req) begin
            free_mask <= restore_bitmask;
        end else begin
            if (allocate_req && !is_empty)
                free_mask[next_free_idx] <= 1'b1;
            if (rrat_insert_req)
                free_mask[rrat_insert_paddr]   <= 1'b0;
            if (rrat_insert_req_1)
                free_mask[rrat_insert_paddr_1] <= 1'b0;
            // WAW: slot 0's newly-allocated paddr is dead — free it back
            if (waw_free_req)
                free_mask[waw_free_paddr]      <= 1'b0;
        end
    end

endmodule