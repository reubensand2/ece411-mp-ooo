module icache_pp
import rv32i_types::*;
(
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, ufp -> upward facing port
    input   logic   [31:0]  ufp_addr,
    input   logic   [3:0]   ufp_rmask,
    // output  logic   [31:0]  ufp_rdata,   fetch now indexes into the correct 4 byte word
    output  logic           ufp_resp,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    input   logic   [255:0] dfp_rdata,
    input   logic           dfp_resp,

    output  logic   [255:0] hit_cache_line,     // output cacheline instead
    output  logic   [31:0]  hit_cache_line_addr

);

    enum integer unsigned {
        s_compare,
        s_alloc,
        s_prime
    } state, state_next;

    logic stall;
    logic primed;

    cache_pp_reg_t cache_reg, cache_reg_next;

    logic [3:0]     way_hit;
    
    /*      data array      */ 
    // chip select always on
    logic [3:0]     data_write_enable;     
    logic [31:0]    data_wmask;
    logic [3:0]     data_index;  
    logic [255:0]   data_din; 
    logic [255:0]   data_dout   [4];

    /*      tag array      */ 
    // chip select always on
    logic [3:0]     tag_write_enable;
    logic [3:0]     tag_index;
    logic [22:0]    tag_din;
    logic [22:0]    tag_dout    [4];

    assign tag_index    = stall ? cache_reg.ufp_addr[8:5] : ufp_addr[8:5];
    assign data_index   = tag_index;    // no writes so follow tag_index

    /*      valid array      */ 
    logic           valid_select_fetch;
    logic [3:0]     valid_write_enable_fetch;
    logic [3:0]     valid_index_fetch;
    logic           valid_din_fetch;
    logic [3:0]     valid_dout_fetch;

    logic           valid_select_comp;
    logic [3:0]     valid_write_enable_comp;
    logic [3:0]     valid_index_comp;
    logic           valid_din_comp;
    logic [3:0]     valid_dout_comp;
    logic [3:0]     valid_corrected;

    assign valid_index_comp = cache_reg.ufp_addr[8:5];      // addr from comp stage
    assign valid_index_fetch = ufp_addr[8:5];               // addr from fetch stage

    /*      lru array      */
    logic           lru_select_fetch;
    logic           lru_write_enable_fetch;
    logic [3:0]     lru_index_fetch;
    logic [2:0]     lru_din_fetch;
    logic [2:0]     lru_dout_fetch;

    logic           lru_select_comp;
    logic           lru_write_enable_comp;
    logic [3:0]     lru_index_comp;
    logic [2:0]     lru_din_comp;
    logic [2:0]     lru_dout_comp;

    logic [1:0]     lru_decode;
    logic           lru_forward_enable, lru_forward_enable_reg;
    logic [2:0]     lru_forward_fetch, lru_dout_fetch_correct;
    logic [2:0]     lru_corrected;
    logic [1:0]     evict_way, evict_way_next;

    assign lru_index_comp = cache_reg.ufp_addr[8:5];
    assign lru_index_fetch = ufp_addr[8:5];

    assign lru_dout_fetch_correct = lru_forward_enable_reg ? lru_forward_fetch : lru_dout_fetch;
    
    assign valid_corrected = (state == s_compare) & ~primed ? valid_dout_fetch : valid_dout_comp;
    assign lru_corrected   = (state == s_compare) & ~primed ? lru_dout_fetch_correct : lru_dout_comp;

    generate for (genvar i = 0; i < 4; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       ('0),               // always enable SRAM
            .web0       (data_write_enable[i]),
            .wmask0     (data_wmask),
            .addr0      (data_index),
            .din0       (data_din),
            .dout0      (data_dout[i])
        );
        mp_cache_tag_array tag_array (
            .clk0       (clk),
            .csb0       ('0),               // always enable SRAM
            .web0       (tag_write_enable[i]),
            .addr0      (tag_index),
            .din0       (tag_din),
            .dout0      (tag_dout[i])
        );
        dp_ff_array valid_array (
            .clk0       (clk),
            .rst0       (rst),

            .csb0       (valid_select_comp),
            .web0       (valid_write_enable_comp[i]),
            .addr0      (valid_index_comp),
            .din0       (valid_din_comp),
            .dout0      (valid_dout_comp[i]),

            .csb1       (valid_select_fetch),
            .web1       (valid_write_enable_fetch[i]),
            .addr1      (valid_index_fetch),
            .din1       (valid_din_fetch),
            .dout1      (valid_dout_fetch[i])
        );
    end endgenerate

    dp_ff_array #(
        .WIDTH      (3)
    ) lru_array (
        .clk0       (clk),
        .rst0       (rst),

        .csb0       (lru_select_comp),
        .web0       (lru_write_enable_comp),
        .addr0      (lru_index_comp),
        .din0       (lru_din_comp),
        .dout0      (lru_dout_comp),

        .csb1       (lru_select_fetch),
        .web1       (lru_write_enable_fetch),
        .addr1      (lru_index_fetch),
        .din1       (lru_din_fetch),
        .dout1      (lru_dout_fetch)
    );

    // decode plru to find lru way
    always_comb begin
        unique casez (lru_corrected)
            3'b11?:  lru_decode = 2'd0; // replace way 0
            3'b10?:  lru_decode = 2'd1; // replace way 1
            3'b0?1:  lru_decode = 2'd2; // replace way 2
            3'b0?0:  lru_decode = 2'd3; // replace way 3
            default: lru_decode = 'x;                   
        endcase
    end


    always_ff @(posedge clk) begin
        if (rst) begin
            state                   <=  s_compare;
            cache_reg               <= '0;
            primed                  <= '0;
            lru_forward_fetch       <= '0;
            lru_forward_enable_reg  <= '0;
            evict_way       <= '0;
        end
        else begin
            state           <=  state_next;
            evict_way       <= evict_way_next;
            
            if(stall)
                cache_reg   <= cache_reg;
            else
                cache_reg   <= cache_reg_next;

            if (state == s_prime)
                primed  <=  '1;
            else
                primed  <=  '0;
        
            lru_forward_fetch       <= lru_din_comp;
            lru_forward_enable_reg  <= lru_forward_enable;
        end
    end

    always_comb begin
        state_next  =   state;
        evict_way_next  =   evict_way; // hold by default

        // cache outputs
        dfp_addr        =   'x;
        dfp_read        =   '0;
        ufp_resp        =   '0;

        // data init
        data_write_enable = '1;
        data_wmask      =   '0;
        data_din        =   'x;

        // tag init
        tag_write_enable =  '1;
        tag_din         =   'x;

        // valid init
        valid_select_comp   = '1;
        valid_select_fetch   = '1;
        valid_write_enable_comp = '1;
        valid_write_enable_fetch = '1;
        valid_din_comp  =   'x;
        valid_din_fetch  =   'x;

        // lru init
        lru_select_comp     = '1;
        lru_select_fetch    = '1;
        lru_write_enable_comp = '1;
        lru_write_enable_fetch = '1;
        lru_din_comp = 'x;
        lru_din_fetch = 'x;
        lru_forward_enable = '0;

        hit_cache_line  =   '0;
        hit_cache_line_addr = '0;

        stall           =   '0;
        
        cache_reg_next = '0;
        cache_reg_next.ufp_addr = ufp_addr;
        cache_reg_next.ufp_rmask = ufp_rmask;
        cache_reg_next.valid = '0;

        if (ufp_rmask != '0 && !stall) begin
            cache_reg_next.valid = '1;  // valid request
            
            // enable valid, dirty, and lru arrays
            valid_select_comp = '0;     
            valid_select_fetch = '0;

            lru_select_comp = '0;   
            lru_select_fetch = '0;
        end

        unique case (state)
            /* 
            
            */
            s_compare : begin
                if (cache_reg.valid | primed) begin
                    // check for tag matches in each way
                    for (integer i = 0; i < 4; i++) begin
                        way_hit[i] = valid_corrected[i] && (tag_dout[i] == cache_reg.ufp_addr[31:9]);
                    end

                    // hit
                    if(|way_hit) begin
                        lru_forward_enable = (cache_reg.ufp_addr[8:5] == ufp_addr[8:5]) ? '1 : '0;

                        // select cache line that matches tag
                        unique case (way_hit)
                            4'b0001:    hit_cache_line = data_dout[0]; 
                            4'b0010:    hit_cache_line = data_dout[1]; 
                            4'b0100:    hit_cache_line = data_dout[2]; 
                            4'b1000:    hit_cache_line = data_dout[3]; 
                            default:    hit_cache_line = '0;
                        endcase

                        hit_cache_line_addr = {cache_reg.ufp_addr[31:5], 5'd0};

                        // raise response and send byte(s)
                        ufp_resp = '1;

                        // write to lru array if hit
                        lru_select_comp = '0;
                        lru_write_enable_comp = '0;
                        
                        // update plru bits based on most recent hit
                        // [root, left, right]
                        unique case (way_hit)
                            4'b0001: lru_din_comp = {1'b0, 1'b0, lru_corrected[0]}; // Hit W0
                            4'b0010: lru_din_comp = {1'b0, 1'b1, lru_corrected[0]}; // Hit W1
                            4'b0100: lru_din_comp = {1'b1, lru_corrected[1], 1'b0}; // Hit W2
                            4'b1000: lru_din_comp = {1'b1, lru_corrected[1], 1'b1}; // Hit W3
                            default: lru_din_comp = lru_corrected;
                        endcase

                        state_next = s_compare;
                    end

                    // miss
                    else begin
                        stall = '1;
                        state_next = s_alloc;
                        evict_way_next  = lru_decode; // latch victim way here
                    end
                end
            end 
            /*

            */
            s_alloc : begin
                stall = '1;

                dfp_read = '1;
                dfp_addr = {cache_reg.ufp_addr[31:5], 5'b0};

                if (dfp_resp) begin
                    // enable write to cache line (tag already passed in)
                    valid_select_comp = '0;
                    
                    data_write_enable[evict_way] = '0;
                    data_wmask = '1;
                    data_din = dfp_rdata;

                    tag_write_enable[evict_way] = '0;
                    tag_din = cache_reg.ufp_addr[31:9];

                    valid_write_enable_comp[evict_way] = '0;
                    valid_din_comp = '1;

                    state_next = s_prime;
                end
            end
            s_prime : begin
                stall = '1;
                state_next = s_compare;

                valid_select_comp = '0;             
                lru_select_comp = '0;             
            end
            default: state_next = s_compare;
        endcase
    end

endmodule