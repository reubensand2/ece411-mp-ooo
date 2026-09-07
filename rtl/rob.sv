module rob
import rv32i_types::*;
#(
    parameter ROB_SIZE        = 8,
    parameter NUM_UPDATE_PORTS = 1,
    parameter HEAD_TAIL_WIDTH = $clog2(ROB_SIZE)
)(
    input  logic clk,
    input  logic rst,

    input  logic        enq_req,
    input  rob_entry_t  enq_data,
    output logic [HEAD_TAIL_WIDTH-1:0] rob_enq_idx,

    input  logic        deq_req,
    input  logic        deq_two,       // NEW: advance head by 2 this cycle
    output rob_entry_t  deq_data,
    output rob_entry_t  deq_data_1,    // NEW: head+1 entry

    input  logic [NUM_UPDATE_PORTS-1:0]      rob_update_wen,
    input  logic [HEAD_TAIL_WIDTH-1:0]       rob_update_idx    [NUM_UPDATE_PORTS],
    input  rvfi_packet_t                     cdb_rvfi_packet   [NUM_UPDATE_PORTS],
    input  logic                             cdb_branch_mispredict [NUM_UPDATE_PORTS],
    input  logic                             cdb_branch_outcome    [NUM_UPDATE_PORTS],

    output logic full,
    output logic empty,
    output logic empty_1               // NEW: fewer than 2 entries
);

    rob_entry_t cq [0:ROB_SIZE-1];
    logic [HEAD_TAIL_WIDTH:0] head_ptr, tail_ptr;
    logic enq_go, deq_go;
    logic [HEAD_TAIL_WIDTH:0] curr_size;

    assign curr_size = tail_ptr - head_ptr;
    assign empty     = (head_ptr == tail_ptr);
    assign empty_1   = (curr_size < 2);         // NEW
    assign full      = (head_ptr[HEAD_TAIL_WIDTH-1:0] == tail_ptr[HEAD_TAIL_WIDTH-1:0])
                    && (head_ptr[HEAD_TAIL_WIDTH] != tail_ptr[HEAD_TAIL_WIDTH]);

    assign enq_go = enq_req && (!full || (deq_req && !empty));
    assign deq_go = deq_req && !empty;

    assign rob_enq_idx = tail_ptr[HEAD_TAIL_WIDTH-1:0];
    assign deq_data    = cq[head_ptr[HEAD_TAIL_WIDTH-1:0]];
    assign deq_data_1  = cq[(head_ptr[HEAD_TAIL_WIDTH-1:0] + 1'b1) & (HEAD_TAIL_WIDTH)'(ROB_SIZE-1)]; // NEW

    always_ff @(posedge clk) begin
        if (rst) begin
            head_ptr <= '0;
            tail_ptr <= '0;
        end else begin
            if (enq_go) begin
                cq[tail_ptr[HEAD_TAIL_WIDTH-1:0]] <= enq_data;
                tail_ptr <= tail_ptr + 1'b1;
            end
            if (deq_go) begin
                // advance by 2 if dual commit, else 1
                head_ptr <= deq_two ? head_ptr + 2'd2 : head_ptr + 1'b1;
            end

            for (integer unsigned i = 0; i < NUM_UPDATE_PORTS; i++) begin
                if (rob_update_wen[i]) begin
                    cq[rob_update_idx[i]].ready             <= 1'b1;
                    cq[rob_update_idx[i]].rvfi_packet       <= cdb_rvfi_packet[i];
                    cq[rob_update_idx[i]].branch_mispredict <= cdb_branch_mispredict[i];
                    cq[rob_update_idx[i]].branch_outcome    <= cdb_branch_outcome[i];
                end
            end
        end
    end

endmodule