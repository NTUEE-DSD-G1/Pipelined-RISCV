// Directed mapped: only one choice
// (Block address) modulo (# of Blocks in cache)
module Icache(
    clk,
    proc_reset,
    proc_read,
    proc_write,
    proc_addr,
    proc_rdata,
    proc_wdata,
    proc_stall,
    mem_read,
    mem_write,
    mem_addr,
    mem_rdata,
    mem_wdata,
    mem_ready
);
    
    //==== input/output definition ============================
    input          clk;
    // processor interface
    input          proc_reset;
    input          proc_read, proc_write;
    input   [29:0] proc_addr;   // proc_addr[1:0] is the offset
                                // proc_addr[29:2] is the mem_addr when accessing the memory
                                // Use proc_addr[4:2] as the index of the cache
                                // Use proc_addr[29:5] as the tag of the cache
    input   [31:0] proc_wdata;
    output reg         proc_stall;
    output reg  [31:0] proc_rdata;
    
    // memory interface
    input  [127:0] mem_rdata;
    input          mem_ready;
    output reg         mem_read, mem_write;
    output reg [27:0] mem_addr;
    output reg [127:0] mem_wdata;

    // state parameters
    parameter REQUEST       = 3'b000;
    parameter READMEM       = 3'b001;
    parameter WRITECACHE    = 3'b010;
    parameter WRITEMEM      = 3'b011;
    
    //==== wire/reg definition ================================
    integer i;
    
    // the storage of the cache (8 blocks, each with 4 words (128-bits))
    reg [127:0] cache_data      [0:7]; 
    reg [127:0] next_cache_data [0:7];  
    reg [24:0]  cache_tag       [0:7];
    reg [24:0]  next_cache_tag  [0:7];
    reg         cache_valid     [0:7];
    reg         next_cache_valid[0:7];

    // state
    reg [2:0]   state, next_state;
    
    wire [2:0]  index;
    wire [24:0] tag;
    wire [1:0]  offset;
    wire        hit;

    wire ReadHit, ReadMiss, WriteHit, WriteMiss;

    //==== combinational circuit ==============================
    assign index = proc_addr[4:2];
    assign tag = proc_addr[29:5];
    assign offset = proc_addr[1:0];
    assign hit = (proc_addr[29:5] == cache_tag[index]) && cache_valid[index]; 
    
    assign ReadHit = proc_read && hit;
    assign ReadMiss = proc_read && !hit;
    assign WriteHit = proc_write && hit;
    assign WriteMiss = proc_write && !hit;

    // output, variable logic
    always@(*) begin
        // default value (FF) 
        for (i = 0; i < 8; i = i+1) begin
            next_cache_data[i] = cache_data[i];
            next_cache_tag[i] = cache_tag[i];
            next_cache_valid[i] = cache_valid[i];
        end
        
        // default value (output)
        proc_stall = 0;
        proc_rdata = 0;
        mem_read = 0;
        mem_write = 0;
        mem_addr = 0;
        mem_wdata = 0;

        case(state)
            REQUEST: begin
                // read hit -> directly return the data
                if(ReadHit) begin
                    case(offset)
                        3: proc_rdata = cache_data[index][127:96];
                        2: proc_rdata = cache_data[index][95:64];
                        1: proc_rdata = cache_data[index][63:32];
                        0: proc_rdata = cache_data[index][31:0];
                    endcase
                end
                
                // read_miss -> stall and set the read mode of memory
                if(ReadMiss) begin
                    proc_stall = 1;
                    mem_addr = proc_addr[29:2];
                    mem_read = 1;
                end

            end
            
            READMEM: begin
                // default: set the read mode of memory
                mem_addr = proc_addr[29:2];
                mem_read = 1;
                proc_stall = 1;
                // when mem ready (come from readmiss), cancel the read mode, update the cache data, tag 
                // and return the target data (read from memory)
                // when mem ready (come from writemiss), cancel the read mode, update the cache data, tag
                if(mem_ready) begin
                    mem_read = 0;
                    mem_addr = 0;
                end
            end

            WRITECACHE: begin
                next_cache_valid[index] = 1;
                next_cache_tag[index] = tag;
                next_cache_data[index] = mem_rdata;
                case(offset)
                    3: proc_rdata = mem_rdata[127:96];
                    2: proc_rdata = mem_rdata[95:64];
                    1: proc_rdata = mem_rdata[63:32];
                    0: proc_rdata = mem_rdata[31:0];
                endcase
                proc_stall = 0;
            end
            default: begin
            end
        endcase
    end

    // next state logic
    always@(*) begin
        next_state = state;
        case(state)
            REQUEST: begin
                // read hit -> remain REQUEST
                
                // read_miss -> go to READMEM
                if(ReadMiss) begin
                    next_state = READMEM;
                end
            end
            
            READMEM: begin
                // when mem ready (come from readmiss), go back to REQUEST
                // when mem ready (come from writemiss), go to WRITEMEM
                if(mem_ready) begin
                    next_state = WRITECACHE;
                end
            end

            WRITECACHE: begin
                next_state = REQUEST;
            end
           
            default: begin
                next_state = state;
            end
        endcase
    end


    //==== sequential circuit =================================
    always@( posedge clk ) begin
        if( proc_reset ) begin
            for (i = 0; i < 8; i = i+1) begin
                cache_data[i] <= 0;
                cache_tag[i] <= 0;
                cache_valid[i] <= 0;
            end
            state <= 0; // request
        end
        else begin
            for (i = 0; i < 8; i = i+1) begin
                cache_data[i] <= next_cache_data[i];
                cache_tag[i] <= next_cache_tag[i];
                cache_valid[i] <= next_cache_valid[i];
            end
            state <= next_state;
        end
    end

endmodule
