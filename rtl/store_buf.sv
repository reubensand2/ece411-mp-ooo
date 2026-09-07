// module store_buf 
// import rv32i_types::*;
// #(
//     parameter STORE_BUF_SIZE = 8,
//     parameter NUM_UPDATE_PORTS = 0,
//     parameter HEAD_TAIL_WIDTH = $clog2(STORE_BUF_SIZE),
//     parameter TOTAL_COUNT_WIDTH = $clog2(STORE_BUF_SIZE + 1)
// )(
//     input logic clk,
//     input logic rst,

//     input  logic enq_req,
//     input  sb_entry_t enq_data,
//     input  logic deq_req,
//     output sb_entry_t deq_data,

//     // Selective flush — invalidate entries newer than flush_order
//     input  logic        flush_en,
//     input  logic [23:0] flush_order,

//     output logic full,
//     output logic empty,
//     output logic [$clog2(STORE_BUF_SIZE+1)-1:0] curr_size
// );

//     localparam [TOTAL_COUNT_WIDTH-1:0] NUM_SLOTS_COUNT = STORE_BUF_SIZE;
//     localparam [HEAD_TAIL_WIDTH-1:0] LAST_SLOT = STORE_BUF_SIZE - 1;

//     logic enq_go, deq_go, enq_allowed, deq_allowed;

//     sb_entry_t cq [0:STORE_BUF_SIZE-1];

//     logic [HEAD_TAIL_WIDTH-1:0] head_ptr;
//     logic [HEAD_TAIL_WIDTH-1:0] tail_ptr;

//     logic [31:0] byte_mask;

//     // Count of entries that survive a flush (combinational)
//     logic [TOTAL_COUNT_WIDTH-1:0] flush_surviving;
//     logic [HEAD_TAIL_WIDTH-1:0]   flush_new_tail;

//     always_comb begin
//         empty = (curr_size == 0);
//         full  = (curr_size == NUM_SLOTS_COUNT);

//         deq_allowed = !empty;
//         enq_allowed = (!full) || (deq_req && deq_allowed);

//         enq_go  = enq_allowed && enq_req;
//         deq_go  = deq_allowed && deq_req;
//         deq_data = cq[head_ptr];

//         flush_surviving = '0;
//         flush_new_tail  = head_ptr;
//         for (integer unsigned off = 0; off < STORE_BUF_SIZE; off++) begin
//             if (TOTAL_COUNT_WIDTH'(off) < curr_size) begin  // widen curr_size to match integer unsigned
//                 automatic logic [HEAD_TAIL_WIDTH-1:0] idx;
//                 idx = head_ptr + HEAD_TAIL_WIDTH'(off);
//                 if (idx >= HEAD_TAIL_WIDTH'(STORE_BUF_SIZE))
//                     idx = idx - HEAD_TAIL_WIDTH'(STORE_BUF_SIZE);
//                 if (cq[idx].rvfi_packet.order[23:0] <= flush_order) begin
//                     flush_surviving = flush_surviving + 1'b1;
//                     flush_new_tail  = (idx == LAST_SLOT) ? '0 : idx + 1'b1;
//                 end
//             end
//         end
//     end

//     always_ff @(posedge clk) begin
//         if (rst) begin
//             head_ptr  <= '0;
//             tail_ptr  <= '0;
//             curr_size <= '0;
//             for (integer unsigned j = 0; j < STORE_BUF_SIZE; j++)
//                 cq[j] <= '0;

//         end else if (flush_en) begin
//             for (integer unsigned off = 0; off < STORE_BUF_SIZE; off++) begin
//                 if (TOTAL_COUNT_WIDTH'(off) < curr_size) begin
//                     logic [HEAD_TAIL_WIDTH-1:0] idx;
//                     idx = head_ptr + HEAD_TAIL_WIDTH'(off);
//                     if (idx >= HEAD_TAIL_WIDTH'(STORE_BUF_SIZE))
//                         idx = idx - HEAD_TAIL_WIDTH'(STORE_BUF_SIZE);
//                     if (cq[idx].rvfi_packet.order[23:0] > flush_order)
//                         cq[idx] <= '0;
//                 end
//             end
//             tail_ptr  <= flush_new_tail;
//             curr_size <= flush_surviving;

//         end else begin
//             if (enq_go && deq_go) begin
//                 cq[head_ptr] <= '0;
//                 cq[tail_ptr] <= enq_data;
//                 tail_ptr     <= bump_ptr(tail_ptr);
//                 head_ptr     <= bump_ptr(head_ptr);
//             end else if (enq_go) begin
//                 cq[tail_ptr] <= enq_data;
//                 tail_ptr     <= bump_ptr(tail_ptr);
//                 curr_size    <= curr_size + 1'b1;
//             end else if (deq_go) begin
//                 cq[head_ptr] <= '0;
//                 head_ptr     <= bump_ptr(head_ptr);
//                 curr_size    <= curr_size - 1'b1;
//             end
//         end
//     end

//     function automatic [HEAD_TAIL_WIDTH-1:0] bump_ptr;
//         input [HEAD_TAIL_WIDTH-1:0] ptr;
//         begin
//             if (ptr == LAST_SLOT)
//                 bump_ptr = '0;
//             else
//                 bump_ptr = ptr + 1'b1;
//         end
//     endfunction

// endmodule

module store_buf
import rv32i_types::*;
#(
    parameter STORE_BUF_SIZE   = 8,
    parameter NUM_UPDATE_PORTS = 0,
    parameter HEAD_TAIL_WIDTH  = $clog2(STORE_BUF_SIZE)
)(
    input  logic clk,
    input  logic rst,

    input  logic      enq_req,
    input  sb_entry_t enq_data,

    input  logic      deq_req,
    output sb_entry_t deq_data,

    // Selective flush — invalidate entries newer than flush_order
    input  logic        flush_en,
    input  logic [23:0] flush_order,

    output logic full,
    output logic empty,
    output logic [$clog2(STORE_BUF_SIZE+1)-1:0] curr_size
);

    sb_entry_t cq [0:STORE_BUF_SIZE-1];

    // Extra bit on pointers — full/empty derived without curr_size arithmetic
    logic [HEAD_TAIL_WIDTH:0] head_ptr, tail_ptr;

    logic enq_go, deq_go;

    assign empty    = (head_ptr == tail_ptr);
    assign full     = (head_ptr[HEAD_TAIL_WIDTH-1:0] == tail_ptr[HEAD_TAIL_WIDTH-1:0])
                   && (head_ptr[HEAD_TAIL_WIDTH] != tail_ptr[HEAD_TAIL_WIDTH]);

    // curr_size derivable from pointers — kept as output for compatibility
    assign curr_size = ($clog2(STORE_BUF_SIZE+1))'(tail_ptr - head_ptr);

    assign enq_go = enq_req && (!full || (deq_req && !empty));
    assign deq_go = deq_req && !empty;

    assign deq_data = cq[head_ptr[HEAD_TAIL_WIDTH-1:0]];

    // --- Flush scan (combinational) ---
    // Walk live entries from head; keep those with order <= flush_order.
    logic [HEAD_TAIL_WIDTH:0]   flush_new_tail;

    always_comb begin
        flush_new_tail = head_ptr;
        for (integer unsigned off = 0; off < STORE_BUF_SIZE; off++) begin
            if ($clog2(STORE_BUF_SIZE+1)'(off) < curr_size) begin
                automatic logic [HEAD_TAIL_WIDTH-1:0] idx;
                idx = head_ptr[HEAD_TAIL_WIDTH-1:0] + HEAD_TAIL_WIDTH'(off);
                if (idx >= HEAD_TAIL_WIDTH'(STORE_BUF_SIZE))
                    idx = idx - HEAD_TAIL_WIDTH'(STORE_BUF_SIZE);
                if (cq[idx].rvfi_packet.order[23:0] <= flush_order) begin
                    // This entry survives — new tail is one past it.
                    // Reconstruct a full-width pointer: top bit matches head if
                    // the surviving count hasn't wrapped past head's generation.
                    flush_new_tail = head_ptr + (HEAD_TAIL_WIDTH+1)'(off + 1);
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            head_ptr <= '0;
            tail_ptr <= '0;
            for (integer unsigned j = 0; j < STORE_BUF_SIZE; j++)
                cq[j] <= '0;

        end else if (flush_en) begin
            // Invalidate entries newer than flush_order
            for (integer unsigned off = 0; off < STORE_BUF_SIZE; off++) begin
                if ($clog2(STORE_BUF_SIZE+1)'(off) < curr_size) begin
                    automatic logic [HEAD_TAIL_WIDTH-1:0] idx;
                    idx = head_ptr[HEAD_TAIL_WIDTH-1:0] + HEAD_TAIL_WIDTH'(off);
                    if (idx >= HEAD_TAIL_WIDTH'(STORE_BUF_SIZE))
                        idx = idx - HEAD_TAIL_WIDTH'(STORE_BUF_SIZE);
                    if (cq[idx].rvfi_packet.order[23:0] > flush_order)
                        cq[idx] <= '0;
                end
            end
            tail_ptr <= flush_new_tail;
            // head_ptr unchanged — flushed entries are at the tail end

        end else begin
            if (enq_go) begin
                cq[tail_ptr[HEAD_TAIL_WIDTH-1:0]] <= enq_data;
                tail_ptr <= tail_ptr + 1'b1;
            end
            if (deq_go) begin
                cq[head_ptr[HEAD_TAIL_WIDTH-1:0]] <= '0;
                head_ptr <= head_ptr + 1'b1;
            end
        end
    end

endmodule