module sv_queue #(
    parameter DATA_WIDTH = 32,
    parameter NUM_SLOTS = 8,
    parameter HEAD_TAIL_WIDTH = $clog2(NUM_SLOTS), // 0->7
    parameter TOTAL_COUNT_WIDTH = $clog2(NUM_SLOTS + 1)
) (
    input  logic  clk,
    input  logic  rst,
    // Enqueuing
    input  logic  enq_req,
    output logic  enq_allowed,
    input  logic [DATA_WIDTH-1:0] enq_data,
    // Dequeuing
    input logic  deq_req,
    output logic  deq_allowed,
    output logic [DATA_WIDTH-1:0] deq_data,
    // Status
    output logic  full,
    output logic  empty,
    output logic [TOTAL_COUNT_WIDTH-1:0] curr_size // register
);
    localparam [TOTAL_COUNT_WIDTH-1:0] NUM_SLOTS_COUNT = NUM_SLOTS;
    localparam [HEAD_TAIL_WIDTH-1:0] LAST_SLOT = NUM_SLOTS - 1;

    logic enq_go, deq_go;

    // each cq slot has [7:0] and there are 0,1,2,3..to the NUM_SLOTS
    logic [DATA_WIDTH-1:0] cq [0:NUM_SLOTS-1]; // registers

    logic [HEAD_TAIL_WIDTH-1:0] head_ptr; //register
    logic [HEAD_TAIL_WIDTH-1:0] tail_ptr; 

    always_comb begin
        empty = (curr_size == 0);
        full = (curr_size == NUM_SLOTS_COUNT);

        //lets say queue is empty and enqueue comes in. curr_size must be updated on the next cycle.
        deq_allowed = !empty;
        // Allow enqueue on a full queue only if a dequeue also happens this cycle
        enq_allowed = (!full) || (deq_req && deq_allowed);

        enq_go = enq_allowed && enq_req;
        deq_go = deq_allowed && deq_req;
        deq_data  = cq[head_ptr];

        // Not synthesizable but only an issue if running autograder
        // if (enq_req && full)
        //     $warning("BUFFER OVERFLOW ATTEMPT");
        // if (deq_req && empty)
        //     $warning("BUFFER UNDERFLOW ATTEMPT");
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            head_ptr <= '0;
            tail_ptr <= '0;
            curr_size  <= '0;
        end else begin

            if (enq_go && deq_go) begin //both pop and push on a full queue
                cq[tail_ptr] <= enq_data;
                tail_ptr     <= bump_ptr(tail_ptr);
                head_ptr     <= bump_ptr(head_ptr);

                curr_size <= curr_size;
            end
            else if (enq_go) begin
                cq[tail_ptr] <= enq_data;
                tail_ptr     <= bump_ptr(tail_ptr);

                curr_size <= curr_size + 1'b1;
            end

            else if (deq_go) begin
                head_ptr     <= bump_ptr(head_ptr);
                
                curr_size <= curr_size - 1'b1;
            end
        end
    end


    function automatic [HEAD_TAIL_WIDTH-1:0] bump_ptr;
        input [HEAD_TAIL_WIDTH-1:0] ptr;
        begin
            if (ptr == LAST_SLOT)
                bump_ptr = '0;
            else
                bump_ptr = ptr + 1'b1;
        end
    endfunction

endmodule