module dcache (
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, ufp -> upward facing port
    input   logic   [31:0]  ufp_addr,
    input   logic   [3:0]   ufp_rmask,
    input   logic   [3:0]   ufp_wmask,
    output  logic   [31:0]  ufp_rdata,
    input   logic   [31:0]  ufp_wdata,
    output  logic           ufp_resp,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    input   logic   [255:0] dfp_rdata,
    output  logic   [255:0] dfp_wdata,
    input   logic           dfp_resp
);
    /**
        Questions: 
        - how does writing to data array work? 1 byte at a time? what addr?
        - should rdata have don't cares or 0's if not all rmask assert
        - point of valid?
        - should we expect only one hit per way?
        - does openram make the data and tag array ip for us?

    */
    logic [22:0] tag_addr;
    logic [3:0] set_addr;
    logic [4:0] offset_addr; // how is this handled?
    logic [31:0] ufp_addr_reg;
    logic [3:0] ufp_rmask_reg;
    logic [3:0] ufp_wmask_reg;
    logic [31:0] ufp_wdata_reg;

    assign tag_addr = ufp_addr_reg[31:9];
    // assign set_addr = ufp_addr_reg[8:5];
    // assign set_addr = (state == s_idle) ? ufp_addr[8:5] : ufp_addr_reg[8:5];
    assign offset_addr = ufp_addr_reg[4:0];

    logic [3:0] web; // 1 bit for each way

    logic [3:0] valid_rdata; // TODO: why we need valid?
    logic valid_wdata;
    logic [3:0] dirty_rdata;
    logic dirty_wdata;
    logic [22:0] tag_rdata [4];
    logic [255:0] rdata [4]; // read data from all 4 ways

    logic hit; //signal for hit/miss

    logic [2:0] lru_din;
    logic [2:0] lru_dout;
    logic [1:0] lru_way;

    logic [31:0] data_wmask;
    logic [255:0] wdata;

    generate for (genvar i = 0; i < 4; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       (1'b0),
            .web0       (web[i]),
            .wmask0     (data_wmask), // this should be 32-bit
            .addr0      (set_addr), // indexing into set
            .din0       (wdata), // 256-bit
            .dout0      (rdata[i])
        );
        mp_cache_tag_array tag_array (
            .clk0       (clk),
            .csb0       (1'b0),
            .web0       (web[i]),
            .addr0      (set_addr), // indexing into set
            .din0       (tag_addr),
            .dout0      (tag_rdata[i])
        );
        sp_ff_array valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (1'b0),
            .web0       (web[i]),
            .addr0      (set_addr),
            .din0       (valid_wdata),
            .dout0      (valid_rdata[i])
        );
        sp_ff_array dirty_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (1'b0),
            .web0       (web[i]),
            .addr0      (set_addr),
            .din0       (dirty_wdata),
            .dout0      (dirty_rdata[i])
        );
    end endgenerate

    sp_ff_array #(
        .WIDTH      (3)
    ) lru_array (
        .clk0       (clk),
        .rst0       (rst),
        .csb0       (1'b0),
        .web0       (!ufp_resp), // should write if after read/write
        .addr0      (set_addr),
        .din0       (lru_din),
        .dout0      (lru_dout)
    );

    enum integer unsigned {
        s_idle,
        s_hit,
        s_allocate,
        s_writeback
    } state, state_next;
    
    assign set_addr = (state == s_idle) ? ufp_addr[8:5] : ufp_addr_reg[8:5];


    always_ff @(posedge clk) begin
        if (rst) begin
            state <= s_idle;
            ufp_addr_reg <= '0;
            ufp_rmask_reg <= '0;
            ufp_wmask_reg <= '0;
            ufp_wdata_reg <= '0;
        end
        else begin
            state <= state_next;
            ufp_addr_reg <= ufp_addr;
            ufp_rmask_reg <= ufp_rmask;
            ufp_wmask_reg <= ufp_wmask;
            ufp_wdata_reg <= ufp_wdata;

        end
    end

    logic [31:0] rdata_offset[4];
    
    always_comb begin
        state_next = state;
        ufp_rdata = '0;
        ufp_resp = '0;
        dfp_read = '0;
        dfp_addr = '0;
        dfp_write = '0;
        dfp_wdata = '0;

        web = '1;
        valid_wdata = '0;
        dirty_wdata = '0;
        lru_din = '0;
        lru_way = '0;
        
        data_wmask = '0;
        wdata = '0;

        // if (lru_dout[0]) begin // Way 2 or 3
        //     if (lru_dout[2]) lru_way = 2'd3;
        //     else lru_way = 2'd2;
        // end
        // else begin // Way 0 or 1
        //     if (lru_dout[1]) lru_way = 2'd1;
        //     else lru_way = 2'd0;
        // end
        unique casez (lru_dout)
            3'b?11: lru_way = 2'd0;
            3'b?01: lru_way = 2'd1;
            3'b1?0: lru_way = 2'd2;
            3'b0?0: lru_way = 2'd3;
            default: lru_way = 2'd0;
        endcase

        unique case (state) 
            s_idle: begin
                if (|ufp_rmask || |ufp_wmask) begin
                    state_next = s_hit;
                end
            end
            s_hit: begin
                for (integer i = 0; i < 4; i++) begin
                    if (valid_rdata[i] && tag_addr == tag_rdata[i]) begin // should only one hit per way
                        dfp_addr = {ufp_addr_reg[31:5], {5{1'b0}}};
                        ufp_resp = '1;
                        rdata_offset[i]= rdata[i][(8*offset_addr)+:32];    
                        if (|ufp_wmask_reg) begin   
                            web[i] = '0;
                            dirty_wdata = '1;
                            valid_wdata = '1;
                            data_wmask = {{28{1'b0}}, ufp_wmask_reg} << (4*offset_addr[4:2]);
                            if (ufp_wmask_reg[0]) wdata[8*offset_addr +:8] = ufp_wdata_reg[7:0];
                            if (ufp_wmask_reg[1]) wdata[(8*offset_addr+8) +:8] = ufp_wdata_reg[15:8];
                            if (ufp_wmask_reg[2]) wdata[(8*offset_addr+16) +:8] = ufp_wdata_reg[23:16];
                            if (ufp_wmask_reg[3]) wdata[(8*offset_addr+24) +:8] = ufp_wdata_reg[31:24];
                        end
                        else begin
                            if (ufp_rmask_reg[0]) ufp_rdata[7:0] = rdata_offset[i][7:0];
                            if (ufp_rmask_reg[1]) ufp_rdata[15:8] = rdata_offset[i][15:8];
                            if (ufp_rmask_reg[2]) ufp_rdata[23:16] = rdata_offset[i][23:16];
                            if (ufp_rmask_reg[3]) ufp_rdata[31:24] = rdata_offset[i][31:24];
                        end     
                        state_next = s_idle;

                        // update lru
                        unique case (i)
                            0: lru_din = {lru_dout[2], 1'b0, 1'b0};
                            1: lru_din = {lru_dout[2], 1'b1, 1'b0};
                            2: lru_din = {1'b0, lru_dout[1], 1'b1};
                            3: lru_din = {1'b1, lru_dout[1], 1'b1};
                            default: lru_din = 3'b000;
                        endcase

                    end 
                end
                if (!ufp_resp) begin
                    if (dirty_rdata[lru_way]) state_next = s_writeback;
                    else state_next = s_allocate;  
                end
            end
            s_allocate: begin
                dfp_read = '1;
                dfp_addr = {ufp_addr_reg[31:5], {5{1'b0}}}; // 256-bit aligned
                if (dfp_resp) begin
                    state_next = s_idle; 
                    // allocate into cache. i think tag already accounted for
                    web[lru_way] = '0; // write data into set and evict if needed
                    dirty_wdata = '0; // set evicted line clean
                    valid_wdata = '1; // set data valid since its populated
                    data_wmask = '1; // ignored if web deasserted
                    wdata = dfp_rdata;
                end
            end
            s_writeback: begin
                dfp_write = '1;
                dfp_addr = {tag_rdata[lru_way], set_addr, {5{1'b0}}}; // concat tag and lru_way as addr
                dfp_wdata = rdata[lru_way]; // update data in dram
                if (dfp_resp) state_next = s_allocate;
            end
            default: begin

            end
        endcase

    end

endmodule