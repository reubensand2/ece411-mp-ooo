module linebuffer (
    input  logic         clk, rst,
    input  logic [255:0] hit_icache_line,
    input  logic [31:0]  hit_cache_line_addr,
    input  logic         imem_resp,

    // new: fetch tells us current PC and whether it's stalled on a demand miss
    input  logic [31:0]  pc,
    input  logic         demand_miss_inflight,

    // new: prefetch request out to fetch/icache arbiter
    output logic         pf_req,
    output logic [31:0]  pf_addr,
    input  logic         pf_issued,          // arbiter granted us the port this cycle
    input  logic         resp_is_prefetch,   // fetch tells us what the response is for

    // lookup interface — fetch matches pc against either slot
    output logic [255:0] line0, line1,
    output logic [31:0]  addr0, addr1,
    output logic         valid0, valid1
);

    logic [31:0] inflight_pf_addr;
    logic        inflight_pf_valid;
    logic        victim; // which slot to overwrite next (simple toggle or LRU)

    // prefetch target = next line after current PC
    logic [31:0] pf_target;
    assign pf_target = {pc[31:5] + 27'd1, 5'b0};

    logic already_have;
    assign already_have = (valid0 && addr0[31:5] == pf_target[31:5]) ||
                          (valid1 && addr1[31:5] == pf_target[31:5]) ||
                          (inflight_pf_valid && inflight_pf_addr[31:5] == pf_target[31:5]);

    assign pf_req  = !demand_miss_inflight && !already_have && !inflight_pf_valid;
    assign pf_addr = pf_target;

    always_ff @(posedge clk) begin
        if (rst) begin
            valid0 <= '0;
            valid1 <= '0;
            inflight_pf_valid <= '0;
            victim <= '0;
        end else begin
            // track in-flight prefetch
            if (pf_issued) begin
                inflight_pf_addr  <= pf_addr;
                inflight_pf_valid <= '1;
            end
            if (imem_resp && resp_is_prefetch) inflight_pf_valid <= '0;

            // fill on response
            if (imem_resp) begin
                if (resp_is_prefetch) begin
                    // write to victim slot
                    if (victim == 0) begin
                        line0 <= hit_icache_line;
                        addr0 <= hit_cache_line_addr;
                        valid0 <= '1;
                    end else begin
                        line1 <= hit_icache_line;
                        addr1 <= hit_cache_line_addr;
                        valid1 <= '1;
                    end
                    victim <= ~victim;
                end else begin
                    // demand fill — write to the slot that isn't the current demand line,
                    // or just always slot 0 and let prefetches go to slot 1
                    line0 <= hit_icache_line;
                    addr0 <= hit_cache_line_addr;
                    valid0 <= '1;
                end
            end
        end
    end
endmodule