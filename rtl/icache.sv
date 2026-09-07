module icache (
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, ufp -> upward facing port
    input   logic   [31:0]  ufp_addr,
    input   logic   [3:0]   ufp_rmask,
    // output  logic   [31:0]  ufp_rdata,       fetch now indexes into the correct 4 byte word
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
        s_idle,
        s_hit,
        s_alloc
    } state, state_next;

    logic [31:0]    ufp_addr_reg; 

    logic [22:0]    ufp_tag_reg;
    logic [3:0]     ufp_index;

    logic [3:0]     way_hit;

    logic [31:0]    hit_word;

    assign ufp_index    = (state == s_idle) ? ufp_addr[8:5] : ufp_addr_reg[8:5];
    assign ufp_tag_reg  = ufp_addr_reg[31:9];

    logic [3:0]     write_enable;           // 1 is read, 0 is write (1 bit for each way)
    logic [31:0]    data_wmask;
    logic [255:0]   data_din; 
    logic [255:0]   data_dout   [4];

    logic [22:0]    tag_dout    [4];

    logic           valid_din;
    logic [3:0]     valid_dout;

    assign valid_din = '1;                  // always write in valid (data only invalid on reset)

    logic           write_enable_lru;
    logic [1:0]     lru_decode;
    logic [2:0]     lru_din;
    logic [2:0]     lru_dout;

    generate for (genvar i = 0; i < 4; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       ('0),               // always enable SRAM
            .web0       (write_enable[i]),
            .wmask0     (data_wmask),
            .addr0      (ufp_index),
            .din0       (data_din),
            .dout0      (data_dout[i])
        );
        mp_cache_tag_array tag_array (
            .clk0       (clk),
            .csb0       ('0),               // always enable SRAM
            .web0       (write_enable[i]),
            .addr0      (ufp_index),
            .din0       (ufp_tag_reg),
            .dout0      (tag_dout[i])
        );
        sp_ff_array valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       ('0),               // always enable FF array
            .web0       (write_enable[i]),
            .addr0      (ufp_index),
            .din0       (valid_din),
            .dout0      (valid_dout[i])
        );
    end endgenerate

    sp_ff_array #(
        .WIDTH      (3)
    ) lru_array (
        .clk0       (clk),
        .rst0       (rst),
        .csb0       ('0),
        .web0       (write_enable_lru),
        .addr0      (ufp_index),
        .din0       (lru_din),
        .dout0      (lru_dout)
    );

    // decode plru to find lru way
    always_comb begin
        unique casez (lru_dout)
            3'b11?:  lru_decode = 2'd0; // replace way 0
            3'b10?:  lru_decode = 2'd1; // replace way 1
            3'b0?1:  lru_decode = 2'd2; // replace way 2
            3'b0?0:  lru_decode = 2'd3; // replace way 3
            default: lru_decode = 'x;                   
        endcase
    end


    always_ff @(posedge clk) begin
        if (rst) begin
            state           <=  s_idle;
            ufp_addr_reg    <=  '0;
        end
        else begin
            state           <=  state_next;
            ufp_addr_reg    <=  ufp_addr;
        end 
    end

    always_comb begin
        state_next  =   state;

        // cache outputs
        dfp_addr        =   'x;
        dfp_read        =   '0;
        ufp_resp        =   '0;
        // ufp_rdata       =   'x;

        // data array init
        write_enable    =   '1;
        data_wmask      =   '0;
        data_din        =   'x;

        // lru init
        write_enable_lru =  '1;
        lru_din = 'x;

        hit_cache_line      =   'x;
        hit_cache_line_addr =   'x;



        unique case (state)
            /*
                1. If ufp sends a read request switch to hit state
            */
            s_idle : begin
                if (|ufp_rmask)
                    state_next = s_hit;
            end
            /* 
                0. Indexed using cpu addr to get the set
                1. Compare tags against valid ways
                2. If hit 
                    - select correct data line and index into correct word
                    - respond with data
                    - update LRU tree
                3. If miss
                    - go to allocate
            */
            s_hit : begin
                // check for tag matches in each way
                for (integer i = 0; i < 4; i++) begin
                    way_hit[i] = valid_dout[i] && (tag_dout[i] == ufp_tag_reg);
                end

                // select cache line that matches tag
                unique case (way_hit)
                    4'b0001:    hit_cache_line = data_dout[0]; 
                    4'b0010:    hit_cache_line = data_dout[1]; 
                    4'b0100:    hit_cache_line = data_dout[2]; 
                    4'b1000:    hit_cache_line = data_dout[3]; 
                    default:    hit_cache_line = 'x;
                endcase

                // index to correct word in cache line
                hit_word = hit_cache_line[32*ufp_addr_reg[4:2] +: 32];
                hit_cache_line_addr = ufp_addr_reg;
                
                // hit
                if(|way_hit) begin
                    // raise response and send byte(s)
                    ufp_resp = '1;
                    // ufp_rdata = hit_word;

                    // write to lru array if hit
                    write_enable_lru = '0;
                    
                    // update plru bits based on most recent hit
                    // [root, left, right]
                    unique case (way_hit)
                        4'b0001: lru_din = {1'b0, 1'b0, lru_dout[0]}; // Hit W0
                        4'b0010: lru_din = {1'b0, 1'b1, lru_dout[0]}; // Hit W1
                        4'b0100: lru_din = {1'b1, lru_dout[1], 1'b0}; // Hit W2
                        4'b1000: lru_din = {1'b1, lru_dout[1], 1'b1}; // Hit W3
                        default: lru_din = lru_dout;
                    endcase

                    state_next = s_idle;
                end
                // miss
                else 
                    state_next = s_alloc;
            end 
            /*
                1. initiate dfp read, with requested address
                2. wait for dfp_resp
                    - write dfp data to replaced cache line
                    - move back to idle
            */
            s_alloc : begin
                dfp_read = '1;
                dfp_addr = {ufp_addr_reg[31:5], 5'b0};

                if (dfp_resp) begin
                    // enable write to cache line (tag already passed in)
                    write_enable[lru_decode] = '0;
                    data_din = dfp_rdata;
                    data_wmask = '1;

                    state_next = s_idle;
                end
            end
            default: state_next = s_idle;
        endcase
    end

endmodule : icache