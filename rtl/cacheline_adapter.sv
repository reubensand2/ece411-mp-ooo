module cacheline_adapter (
    input   logic               clk,
    input   logic               rst,

    output  logic   [31:0]      dram_addr, // set addr that is being requested
    output  logic               dram_read, // set high for one cycle to send request to dram
    output  logic               dram_write, // set high when writing burst of memory
    output  logic   [63:0]      dram_wdata,
    input   logic               dram_ready, // needs to be high to do anything


    input   logic   [31:0]      dram_raddr, // burstmem addr that is being read from
    input   logic   [63:0]      dram_rdata, // burst data dram sends on read
    input   logic               dram_rvalid, // when dram starts outputing

    input  logic   [31:0]       icache_addr,
    input  logic                icache_read,
    output logic   [255:0]      icache_rdata,
    output logic                icache_resp,

    input  logic   [31:0]       dcache_addr,
    input  logic                dcache_read,
    input  logic                dcache_write,
    output logic   [255:0]      dcache_rdata,
    input  logic   [255:0]      dcache_wdata,
    output logic                dcache_resp
);

    enum integer unsigned {
        idle,
        data,
        instruction
    } state, state_next;

    logic [1:0]     counter;
    logic [63:0]    read_data [4];
    logic           counter_done;
    logic           chunk_received;
    logic [31:0]    dummy;
    
    assign dummy = dram_raddr;  // gets rid of linting warning could remove if multiple issues not used

    assign chunk_received = (dram_rvalid || dram_write) && dram_ready;

    always_ff @(posedge clk) begin
        if (rst) begin
            state           <=  idle;
            counter         <=  '0;
            counter_done    <=  '0;
            read_data[0]    <=  'x;
            read_data[1]    <=  'x;
            read_data[2]    <=  'x;
            read_data[3]    <=  'x;
        end
        else begin
            state   <= state_next;

            // save read in data
            if(dram_rvalid && dram_ready)
                read_data[counter] <= dram_rdata;

            if (counter == 2'b11) begin     // last chunk
                counter      <= '0;
                counter_done <= '1;
            end
            else if(chunk_received) begin   // chunks 0-2 
                counter      <= counter + 1'b1;
                counter_done <= '0;
            end
            else begin                      // doing nothing
                counter_done <= '0;
            end
        end
    end



    always_comb begin
        state_next  = state;

        dram_addr   = 'x;
        dram_read   = '0;
        dram_write  = '0;
        dram_wdata  = 'x;

        icache_resp = '0;
        dcache_resp = '0;

        icache_rdata = 'x;
        dcache_rdata = 'x;

        unique case (state)
            /*  Priority: dcache then icache
                1. if dcache read or write
                    - go to data state
                    - pass addr, read/write signals, and first chunk of data to DRAM
                2. if icache read
                    - go to instruction state
                    - pass addr, read signals
            */
            idle : begin
                if ((dcache_read || dcache_write) && dram_ready) begin
                    state_next = data;

                    dram_addr = dcache_addr;
                    dram_read = dcache_read;
                    dram_write = dcache_write;
                    dram_wdata = dcache_wdata[63:0];
                end
                else if(icache_read && dram_ready) begin
                    state_next = instruction;
                    dram_read = icache_read;
                    dram_addr = icache_addr;
                end
            end 
            /* 
                1. for writes, hold address and write signal for all 4 cycles,
                   for reads these signals don't matter 
                2. for read, on 5th cycle respond to cache with registered chunks
                3. for write, on 4th cycle respond saying we passed data along
            */
            data : begin
                
                dram_addr = dcache_addr;
                dram_write = dcache_write;
                dram_wdata = dcache_wdata[64*counter +: 64];

                if (counter_done) begin
                    state_next = idle;
                    dcache_resp = '1;
                    dcache_rdata = {read_data[3], read_data[2], read_data[1], read_data[0]};
                end
                else if(dcache_write && counter == 2'b11) begin
                    state_next = idle;
                    dcache_resp = '1;
                end
            end
            /* 
                1. for read, on 5th cycle respond to cache with registered chunks
                (no need to hold addr or other signals since DRAM only needs 1 cycle)
            */
            instruction : begin
                if (counter_done) begin
                    state_next = idle;
                    icache_resp = '1;
                    icache_rdata = {read_data[3], read_data[2], read_data[1], read_data[0]};
                end

            end
            default: state_next = idle;
        endcase
    end

endmodule