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
    input               clk;
    // processor interface
    input               proc_reset;
    input               proc_read, proc_write;
    input       [29:0]  proc_addr;      // proc_addr[1:0] is the offset
                                        // proc_addr[29:2] is the mem_addr when accessing the memory
                                        // Use proc_addr[3:2] as the set number of the cache
                                        // Use proc_addr[29:4] as the tag of the cache
    input       [31:0]  proc_wdata;
    output reg          proc_stall;
    output reg  [31:0]  proc_rdata;
    
    // memory interface
    input       [127:0] mem_rdata;
    input               mem_ready;
    output reg          mem_read, mem_write;
    output reg [27:0]   mem_addr;
    output reg [127:0]  mem_wdata;

    // state parameters
    parameter REQUEST       = 3'b000;
    parameter READMEM       = 3'b001;
    parameter PRELOAD       = 3'b010;
    
    //==== wire/reg definition ================================
    integer i;
    
    // the storage of the cache (8 blocks, each with 4 words (128-bits))
    reg  [127:0] cache_data         [0:7]; 
    reg  [127:0] next_cache_data    [0:7];  
    reg  [24:0]  cache_tag          [0:7];
    reg  [24:0]  next_cache_tag     [0:7];
    reg          cache_valid        [0:7];
    reg          next_cache_valid   [0:7];

    // state
    reg  [2:0]   state, next_state;
    
    wire [1:0]  set_num;
    reg  [2:0]  index1, index2;
    wire        hit1, hit2;
    wire [25:0] tag;
    wire [1:0]  offset;
    wire        hit;
    reg  [31:0] target_cache_data1, target_cache_data2, target_mem_data; 

    wire        ReadHit, ReadMiss;

    //==== additional wire/reg definition ================================
    wire [25:0] preload_tag;
    wire [1:0]  preload_set_num;
    wire [27:0] preload_addr;
    wire [2:0]  preload_index;

    //==== combinational circuit ==============================
    assign set_num = proc_addr[3:2];
    assign tag = proc_addr[29:4];
    assign offset = proc_addr[1:0];
    assign hit1 = ((proc_addr[29:4] == cache_tag[index1]) && cache_valid[index1]);
    assign hit2 = ((proc_addr[29:4] == cache_tag[index2]) && cache_valid[index2]);
    assign hit = hit1 || hit2;
    
    assign ReadHit = proc_read && hit;
    assign ReadMiss = proc_read && !hit;

    //=========================================================
    assign preload_tag = (set_num == 2'b11) ? (tag + 1) : tag;
    assign preload_set_num = set_num + 1;
    assign preload_addr = {preload_tag, preload_set_num};
    assign preload_index = {preload_set_num, 1'b0};

    always@(*) begin
        case(set_num)
            0: begin
                index1 = 3'd0;
                index2 = 3'd1;
            end
            1: begin
                index1 = 3'd2;
                index2 = 3'd3;
            end
            2: begin
                index1 = 3'd4;
                index2 = 3'd5;
            end
            3: begin
                index1 = 3'd6;
                index2 = 3'd7;
            end
        endcase
    end

    always@(*) begin
        case(offset)
            3: begin
                target_cache_data1 = cache_data[index1][127:96];
                target_cache_data2 = cache_data[index2][127:96];
                target_mem_data = mem_rdata[127:96];
            end
            2: begin
                target_cache_data1 = cache_data[index1][95:64];
                target_cache_data2 = cache_data[index2][95:64];
                target_mem_data = mem_rdata[95:64];
            end
            1: begin
                target_cache_data1 = cache_data[index1][63:32];
                target_cache_data2 = cache_data[index2][63:32];
                target_mem_data = mem_rdata[63:32];
            end
            0: begin
                target_cache_data1 = cache_data[index1][31:0];
                target_cache_data2 = cache_data[index2][31:0];
                target_mem_data = mem_rdata[31:0];
            end
            default: begin
                target_cache_data1 = 0;
                target_cache_data2 = 0;
                target_mem_data = 0;
            end
        endcase
    end
    
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
                    // ========================================================================
                    // Prefetch_strategy: Set memory in read mode when sequentially HIT appears
                    // ========================================================================
                    mem_read = 1;
                    mem_addr = preload_addr;
                    proc_rdata = hit1 ? target_cache_data1 : target_cache_data2;
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
                if(mem_ready) begin
                    
                    // ========================================================================
                    // Prefetch_strategy: Set memory in read mode when sequentially HIT appears
                    // ========================================================================
                    mem_read = 1;
                    mem_addr = preload_addr;
                    
                    // replace cache strategy
                    // First move the data to index2 in a set
                    next_cache_valid[index2] = cache_valid[index1];
                    next_cache_tag[index2] = cache_tag[index1];
                    next_cache_data[index2] = cache_data[index1];
                    
                    // Then write the new data to the index1
                    next_cache_valid[index1] = 1;
                    next_cache_tag[index1] = tag;
                    
                    if(ReadMiss) begin
                        proc_stall = 0;
                        proc_rdata = target_mem_data;
                        next_cache_data[index1] = mem_rdata;
                    end
                end
            end
            
        endcase
    end

    // next state logic
    always@(*) begin
        next_state = state;
        case(state)
            REQUEST: begin
                // read hit -> remain REQUEST
                if(ReadHit) begin
                    next_state = REQUEST;
                end
                
                // read_miss -> go to READMEM
                if(ReadMiss) begin
                    next_state = READMEM;
                end
            end
            
            READMEM: begin
                // when mem ready (come from readmiss), go back to REQUEST
                if(mem_ready) begin
                    next_state = REQUEST;
                end
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
