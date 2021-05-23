// Write-through / FIFO / 2 way cache
module cache(
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
                                // Use proc_addr[3:2] as the set number of the cache
                                // Use proc_addr[29:4] as the tag of the cache
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
    
    wire [1:0]  set_num;
    reg [2:0]  index1, index2;
    wire hit1, hit2;
    wire [25:0] tag;
    wire [1:0]  offset;
    wire        hit;
    reg [31:0] target_cache_data1, target_cache_data2, target_mem_data; 

    wire ReadHit, ReadMiss, WriteHit, WriteMiss;

    //==== combinational circuit ==============================
    assign set_num = proc_addr[3:2];
    assign tag = proc_addr[29:4];
    assign offset = proc_addr[1:0];
    assign hit1 = ((proc_addr[29:4] == cache_tag[index1]) && cache_valid[index1]);
    assign hit2 = ((proc_addr[29:4] == cache_tag[index2]) && cache_valid[index2]);
    assign hit = hit1 || hit2;
    
    assign ReadHit = proc_read && hit;
    assign ReadMiss = proc_read && !hit;
    assign WriteHit = proc_write && hit;
    assign WriteMiss = proc_write && !hit;

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
                    proc_rdata = hit1 ? target_cache_data1 : target_cache_data2;
                end
                
                // read_miss -> stall and set the read mode of memory
                if(ReadMiss) begin
                    proc_stall = 1;
                    mem_addr = proc_addr[29:2];
                    mem_read = 1;
                end

                // write hit -> stall, update cache_data and set the write mode of memory
                if(WriteHit) begin
                    proc_stall = 1;
                    if(hit1) begin
                        next_cache_valid[index1] = 1;
                        next_cache_tag[index1] = tag;
                    end
                    else begin
                        next_cache_valid[index2] = 1;
                        next_cache_tag[index2] = tag;
                    end 
                    
                    case(offset)
                        3: begin
                            if(hit1)    next_cache_data[index1][127:96] = proc_wdata;
                            else        next_cache_data[index2][127:96] = proc_wdata;
                        end
                        2: begin
                            if(hit1)    next_cache_data[index1][95:64] = proc_wdata;
                            else        next_cache_data[index2][95:64] = proc_wdata;
                        end
                        1: begin
                            if(hit1)    next_cache_data[index1][63:32] = proc_wdata;
                            else        next_cache_data[index2][63:32] = proc_wdata;
                        end
                        0: begin
                            if(hit1)    next_cache_data[index1][31:0] = proc_wdata;
                            else        next_cache_data[index2][31:0] = proc_wdata;
                        end
                    endcase

                    // memory interface
                    mem_write = 1;
                    case(offset)
                        3: begin
                            if(hit1)    mem_wdata = {proc_wdata, cache_data[index1][95:0]}; 
                            else        mem_wdata = {proc_wdata, cache_data[index2][95:0]}; 
                        end
                        2: begin
                            if(hit1)    mem_wdata = {cache_data[index1][127:96], proc_wdata, cache_data[index1][63:0]};
                            else        mem_wdata = {cache_data[index2][127:96], proc_wdata, cache_data[index2][63:0]};
                        end
                        1: begin
                            if(hit1)    mem_wdata = {cache_data[index1][127:64], proc_wdata, cache_data[index1][31:0]};
                            else        mem_wdata = {cache_data[index2][127:64], proc_wdata, cache_data[index2][31:0]};
                        end
                        0: begin
                            if(hit1)    mem_wdata = {cache_data[index1][127:32], proc_wdata};
                            else        mem_wdata = {cache_data[index2][127:32], proc_wdata};
                        end
                    endcase
                end

                // write miss -> stall and set the read mode of memory
                if(WriteMiss) begin
                    proc_stall = 1; 
                    // memory interface
                    mem_read = 1;
                    mem_addr = proc_addr[29:2];
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
                    
                    // replace cache strategy
                    // First move the data to index2 in a set
                    next_cache_valid[index2] = next_cache_valid[index1];
                    next_cache_tag[index2] = next_cache_tag[index1];
                    next_cache_data[index2] = next_cache_data[index1];
                    // Then write the new data to the index1
                    // As a result index1 acts as the most recently used block
                    next_cache_valid[index1] = 1;
                    next_cache_tag[index1] = tag;
                    
                    if(ReadMiss) begin
                        proc_stall = 0;
                        proc_rdata = target_mem_data;
                        next_cache_data[index1] = mem_rdata;
                    end
                    if(WriteMiss) begin
                        case(offset)
                            3: next_cache_data[index1] = {proc_wdata, mem_rdata[95:0]}; 
                            2: next_cache_data[index1] = {mem_rdata[127:96], proc_wdata, mem_rdata[63:0]};  
                            1: next_cache_data[index1] = {mem_rdata[127:64], proc_wdata, mem_rdata[31:0]};
                            0: next_cache_data[index1] = {mem_rdata[127:32], proc_wdata};
                        endcase
                    end
                end
            end
            
            WRITEMEM: begin
                // default: stall and set the write mode of memory
                proc_stall = 1;
                mem_write = 1;
                mem_wdata = WriteHit ? (hit1 ? cache_data[index1] : cache_data[index2]) : cache_data[index1];
                mem_addr = proc_addr[29:2];
                
                // when mem ready (come from writehit), cancel the write mode
                // when mem ready (come from writemiss), cancel the write mode and update the cache data
                if(mem_ready) begin
                    mem_addr = 0;
                    mem_write = 0;
                    mem_wdata = 0;
                    proc_stall = 0;
                end
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

                // write hit -> go to WRITEMEM
                if(WriteHit) begin
                    next_state = WRITEMEM;
                end

                // write miss -> goto READMEM then WRITEMEM
                if(WriteMiss) begin
                    next_state = READMEM;
                end
            end
            
            READMEM: begin
                // when mem ready (come from readmiss), go back to REQUEST
                // when mem ready (come from writemiss), go to WRITEMEM
                if(mem_ready) begin
                    if(ReadMiss) begin
                        next_state = REQUEST;
                    end
                    else if(WriteMiss) begin
                        next_state = WRITEMEM;
                    end
                end
            end
           
            WRITEMEM: begin 
                // go back to REQUEST
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
