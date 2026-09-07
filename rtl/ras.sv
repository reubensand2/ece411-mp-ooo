module ras 
import rv32i_types::*;
(
    input  logic        clk,
    input  logic        rst,

    // Interface for Fetch
    input  logic push,
    input  logic pop,
    input  logic [31:0] din,
    output logic [31:0] dout,

    // Recovery Interface (from ROB/Retirement)
    input  logic restore_en,
    input  logic [RAS_P_WIDTH-1:0] restore_ptr,

    // Snapshot outputs (to be stored in the ROB)
    output logic [RAS_P_WIDTH-1:0] ptr_to_rob
);

    logic [31:0] stack [RAS_DEPTH];
    logic [31:0] stack_next [RAS_DEPTH];
    logic [RAS_P_WIDTH-1:0] ptr, ptr_next;

    always_ff @(posedge clk) begin
        if (rst) begin
            for(integer unsigned i = 0; i < RAS_DEPTH; i++)
                stack[i] <= '0;
            ptr <= '1;      // -1, first push indexes to 0
        end else begin
            ptr     <= ptr_next;
            stack   <= stack_next;
        end
    end

    always_comb begin
        ptr_next    = ptr;
        dout        = 'x;
        stack_next  = stack;
        ptr_to_rob  = ptr;


        if (restore_en) 
            ptr_next = restore_ptr;
        else begin
            if (pop) begin
                dout = stack[ptr];
                ptr_next = ptr - 1'b1;
            end
            else if (push) begin
                ptr_next = ptr + 1'b1;
                stack_next[ptr_next] = din; 
            end
            ptr_to_rob = ptr_next;
        end
    end
    
endmodule