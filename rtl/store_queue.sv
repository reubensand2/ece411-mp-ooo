module store_queue
import rv32i_types::*;
#(
    parameter SQ_SIZE          = 8,
    parameter NUM_UPDATE_PORTS = 0,
    parameter HEAD_TAIL_WIDTH  = $clog2(SQ_SIZE)
)(
    input  logic clk,
    input  logic rst,

    input  logic      enq_req,
    input  sq_entry_t enq_data,

    input  logic      deq_req,
    output sq_entry_t deq_data,

    // CDB snooping
    input  logic [NUM_UPDATE_PORTS-1:0] rs_wakeup,
    input  logic [PRF_IDX_WIDTH-1:0]  rs_ready_addr [NUM_UPDATE_PORTS],

    output logic full,
    output logic empty
);

    sq_entry_t cq [0:SQ_SIZE-1];

    // Extra bit on pointers — no curr_size counter needed
    logic [HEAD_TAIL_WIDTH:0] head_ptr, tail_ptr;

    logic enq_go, deq_go;

    assign empty = (head_ptr == tail_ptr);
    assign full  = (head_ptr[HEAD_TAIL_WIDTH-1:0] == tail_ptr[HEAD_TAIL_WIDTH-1:0])
                && (head_ptr[HEAD_TAIL_WIDTH] != tail_ptr[HEAD_TAIL_WIDTH]);

    assign enq_go = enq_req && (!full || (deq_req && !empty));
    assign deq_go = deq_req && !empty;

    assign deq_data = cq[head_ptr[HEAD_TAIL_WIDTH-1:0]];

    always_ff @(posedge clk) begin
        if (rst) begin
            head_ptr <= '0;
            tail_ptr <= '0;
            for (integer unsigned j = 0; j < SQ_SIZE; j++)
                cq[j] <= '0;
        end else begin
            if (enq_go) begin
                cq[tail_ptr[HEAD_TAIL_WIDTH-1:0]] <= enq_data;
                tail_ptr <= tail_ptr + 1'b1;
            end
            if (deq_go) begin
                cq[head_ptr[HEAD_TAIL_WIDTH-1:0]] <= '0;
                head_ptr <= head_ptr + 1'b1;
            end

            // CDB snooping — wake up matching entries
            for (integer unsigned port = 0; port < NUM_UPDATE_PORTS; port++) begin
                if (rs_wakeup[port] && !empty) begin
                    for (integer unsigned i = 0; i < SQ_SIZE; i++) begin
                        if (cq[i].valid) begin
                            if (cq[i].rs1_paddr == rs_ready_addr[port])
                                cq[i].rs1_ready <= 1'b1;
                            if (cq[i].rs2_paddr == rs_ready_addr[port])
                                cq[i].rs2_ready <= 1'b1;
                        end
                    end
                end
            end
        end
    end

endmodule