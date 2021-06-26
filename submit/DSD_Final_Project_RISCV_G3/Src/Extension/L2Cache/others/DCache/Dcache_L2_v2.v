module Dcache_L2(
    clk,
    proc_reset,
    proc_read,
    proc_write,
    proc_addr,
    proc_rdata,
    proc_wdata,
    proc_ready,
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
    input   [27:0] proc_addr;
    input  [127:0] proc_wdata;
    output         proc_ready;
    output [127:0] proc_rdata;
    // memory interface
    input  [127:0] mem_rdata;
    input          mem_ready;
    output         mem_read, mem_write;
    output  [27:0] mem_addr;
    output [127:0] mem_wdata;

//==== parameter ==========================================
// SPEC
parameter NUM_OF_SET = 16;
parameter NUM_OF_WAY = 2;
parameter SET_OFFSET = 4;

// cache state
parameter IDLE        = 2'd0;
parameter READ_MEM    = 2'd1;
parameter DIRTY_WRITE = 2'd2;
parameter DIRTY_READ  = 2'd3;

// write buffer mode
parameter WRITE_IDLE  = 2'd0;
parameter WRITE_CACHE = 2'd1;
parameter WRITE_STALL = 2'd2;
parameter WRITE_MEM   = 2'd3;

//==== wire/reg definition ================================
// outputs 
reg         proc_ready;
reg [127:0] proc_rdata;
reg         mem_read, mem_write;
reg [ 27:0] mem_addr;
reg [127:0] mem_wdata;

// FFs
reg [1:0] state, next_state;

reg [127:0]            data[0:NUM_OF_SET-1][0:NUM_OF_WAY-1],  next_data[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg [27-SET_OFFSET:0]  tag[0:NUM_OF_SET-1][0:NUM_OF_WAY-1],   next_tag[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg                    valid[0:NUM_OF_SET-1][0:NUM_OF_WAY-1], next_valid[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg                    dirty[0:NUM_OF_SET-1][0:NUM_OF_WAY-1], next_dirty[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg                    old[0:NUM_OF_SET-1], next_old[0:NUM_OF_SET-1];

reg [127:0]            write_buffer, next_write_buffer;
reg [ 27:0]            write_addr, next_write_addr;
reg [  1:0]            write_buffer_mode, next_write_buffer_mode;
wire [27-SET_OFFSET:0] write_tag;
wire [ SET_OFFSET-1:0] write_set_idx;

reg                    mem_ready_FF, next_mem_ready_FF;
wire read, write;
wire [27-SET_OFFSET:0] in_tag;
wire [ SET_OFFSET-1:0] set_idx;

//==== combinational circuit ==============================
integer i, l;
assign read     = proc_read & ~proc_write;
assign write    = ~proc_read & proc_write;
assign in_tag   = proc_addr[27:SET_OFFSET];
assign set_idx  = proc_addr[SET_OFFSET-1:0];
assign write_tag = write_addr[27:SET_OFFSET];
assign write_set_idx  = write_addr[SET_OFFSET-1:0];
// reg [31:0] miss, next_miss;
// reg [31:0] total, next_total;
always @(*) begin
    // next_miss = miss;
    // next_total = total;
    next_write_buffer = proc_wdata;
    next_write_addr = proc_addr;
    next_write_buffer_mode = write_buffer_mode;
    next_mem_ready_FF = mem_ready;
    next_state = state;
    proc_ready = 1'b0;
    proc_rdata = 0;
    mem_read = 1'b0;
    mem_write = 1'b0;
    mem_addr = 0;
    mem_wdata = 127'b0;
    for (i = 0; i < NUM_OF_SET; i=i+1) begin
        next_old[i] = old[i];
        for (l = 0; l < NUM_OF_WAY; l=l+1) begin
            next_data[i][l] = data[i][l];
            next_tag[i][l] = tag[i][l];
            next_valid[i][l] = valid[i][l];
            next_dirty[i][l] = dirty[i][l];
        end
    end
    case (state)
        IDLE: begin
            // if (read ^ write) next_total = total+1;
            if (read) begin
                // if write buffer is writing cache and fetch same address
                if ((write_buffer_mode == WRITE_CACHE) && (proc_addr == write_addr)) begin
                    next_state = IDLE;
                    proc_rdata = write_buffer;
                    proc_ready = 1'b1;
                end
                else if (valid[set_idx][0] && (tag[set_idx][0] == in_tag)) begin // hit
                    next_state = IDLE;
                    proc_rdata = data[set_idx][0];
                    proc_ready = 1'b1;
                    next_old[set_idx] = 1'b1;
                end
                else if (valid[set_idx][1] && (tag[set_idx][1] == in_tag)) begin
                    next_state = IDLE;
                    proc_rdata = data[set_idx][1];
                    proc_ready = 1'b1;
                    next_old[set_idx] = 1'b0;
                end
                else begin
                    // next_miss = miss+1;
                    // if write buffer is writing thru mem, stall process
                    if (write_buffer_mode == WRITE_MEM && !mem_ready_FF) begin
                        proc_ready = 1'b0;
                    end
                    else if (dirty[set_idx][old[set_idx]]) begin // dirty, use write buffer and read first
                        next_state = READ_MEM;
                        write_buffer_mode = WRITE_STALL;
                        write_addr = { tag[set_idx][old[set_idx]], set_idx };
                        write_buffer = data[set_idx][old[set_idx]];
                    end
                    else begin
                        next_state = READ_MEM;
                        mem_read = 1'b1;
                        mem_addr = { in_tag, set_idx };
                    end
                end
            end
            if (write) begin
                if ((valid[set_idx][0] && (tag[set_idx][0] == in_tag)) || 
                    (valid[set_idx][1] && (tag[set_idx][1] == in_tag))) begin
                    next_state = IDLE;
                    proc_ready = 1'b1;
                    next_write_buffer_mode = WRITE_CACHE;
                end
                else begin
                    // next_miss = miss+1;
                    // if write buffer is writing thru mem, stall process
                    if (write_buffer_mode == WRITE_MEM) begin
                        proc_ready = 1'b0;
                    end
                    else if (dirty[set_idx][old[set_idx]]) begin
                        next_state = DIRTY_WRITE;
                        mem_write = 1'b1;
                        mem_addr = { tag[set_idx][old[set_idx]], set_idx };
                        mem_wdata = data[set_idx][old[set_idx]];
                    end
                    else begin
                        next_state = IDLE;
                        proc_ready = 1'b1;
                        next_write_buffer_mode = WRITE_CACHE;
                    end
                end
            end    
        end
        READ_MEM: begin
            if (mem_ready_FF) begin
                next_state = IDLE;
                proc_ready = 1'b1;
                next_old[set_idx] = ~old[set_idx];
                next_valid[set_idx][old[set_idx]] = 1'b1;
                next_tag[set_idx][old[set_idx]] = in_tag;
                next_data[set_idx][old[set_idx]] = mem_rdata;
                proc_rdata = mem_rdata;
            end
            else begin
                next_state = READ_MEM;
                mem_read = 1'b1;
                mem_addr = { in_tag, set_idx };
            end
        end
        DIRTY_READ: begin
            if (mem_ready_FF) begin
                next_state = READ_MEM;
                mem_read = 1'b1;
                mem_addr = { in_tag, set_idx };
                next_dirty[set_idx][old[set_idx]] = 1'b0;
            end
            else begin
                next_state = DIRTY_READ;
                mem_addr = { tag[set_idx][old[set_idx]], set_idx };
                mem_wdata = data[set_idx][old[set_idx]];
                mem_write = 1'b1;
            end
        end
        DIRTY_WRITE: begin
            if (mem_ready_FF) begin
                next_state = IDLE;
                proc_ready = 1'b1;
                next_old[set_idx] = ~old[set_idx];
                next_valid[set_idx][old[set_idx]] = 1'b1;
                next_tag[set_idx][old[set_idx]] = in_tag;
                next_data[set_idx][old[set_idx]] = proc_wdata;
                next_dirty[set_idx][old[set_idx]] = 1'b1;
            end
            else begin
                next_state = DIRTY_WRITE;
                mem_write = 1'b1;
                mem_addr = { tag[set_idx][old[set_idx]], set_idx };
                mem_wdata = data[set_idx][old[set_idx]];
            end
        end
    endcase

    // handle write buffer
    case (write_buffer_mode) 
        WRITE_CACHE: begin
            next_write_buffer_mode = WRITE_IDLE;
            if (valid[write_set_idx][0] && (tag[write_set_idx][0] == write_tag)) begin
                next_data[write_set_idx][0] = write_buffer;
                next_dirty[write_set_idx][0] = 1'b1;
                next_old[write_set_idx] = 1'b1;
            end
            else if (valid[write_set_idx][1] && (tag[write_set_idx][1] == write_tag))begin
                next_data[write_set_idx][1] = write_buffer;
                next_dirty[write_set_idx][1] = 1'b1;
                next_old[write_set_idx] = 1'b0;
            end
            else begin
                next_old[write_set_idx] = ~old[write_set_idx];
                next_valid[write_set_idx][old[write_set_idx]] = 1'b1;
                next_tag[write_set_idx][old[write_set_idx]] = write_tag;
                next_data[write_set_idx][old[write_set_idx]] = write_buffer;
                next_dirty[write_set_idx][old[write_set_idx]] = 1'b1;
            end
        end
        WRITE_STALL: begin
            if ((state == READ_MEM) && mem_ready_FF) begin// read finish
                next_write_buffer_mode = WRITE_MEM;
                next_write_buffer = write_buffer;
                next_write_addr = write_addr;
                mem_write = 1'b1;
                mem_wdata = write_buffer;
                mem_addr  = write_addr;
            end
        end
        WRITE_MEM: begin
            if (mem_ready_FF) begin
                next_write_buffer_mode = WRITE_IDLE;
            end
            else begin
                next_write_buffer_mode = WRITE_MEM;
                next_write_buffer = write_buffer;
                next_write_addr = write_addr;
                mem_write = 1'b1;
                mem_wdata = write_buffer;
                mem_addr  = write_addr;
            end
        end
    endcase
end

//==== sequential circuit =================================
integer j, k;
always@( posedge clk ) begin
    if( proc_reset ) begin
        // miss <= 0;
        // total <= 0;
        write_buffer <= 127'd0;
        write_buffer_mode <= WRITE_IDLE;
        write_addr <= next_write_addr;
        mem_ready_FF <= 0;
        state <= IDLE;
        for (j = 0; j < NUM_OF_SET; j=j+1) begin
            old[j] <= 0;
            for (k = 0; k < NUM_OF_WAY; k=k+1) begin
                data[j][k] <= 128'b0;
                tag[j][k] <= 0;
                valid[j][k] <= 0;
                dirty[j][k] <= 0;
            end
        end
    end
    else begin
        // miss <= next_miss;
        // total <= next_total;
        write_buffer <= next_write_buffer;
        write_buffer_mode <= next_write_buffer_mode;
        write_addr <= next_write_addr;
        mem_ready_FF <= next_mem_ready_FF;
        state <= next_state;
        for (j = 0; j < NUM_OF_SET; j=j+1) begin
            old[j] <= next_old[j];
            for (k = 0; k < NUM_OF_WAY; k=k+1) begin
                data[j][k] <= next_data[j][k];
                tag[j][k] <= next_tag[j][k];
                valid[j][k] <= next_valid[j][k];
                dirty[j][k] <= next_dirty[j][k];
            end
        end
    end
end

endmodule
