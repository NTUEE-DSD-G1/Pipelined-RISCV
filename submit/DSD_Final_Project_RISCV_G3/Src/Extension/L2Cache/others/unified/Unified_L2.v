module Unified_L2_Cache(
    clk,
    proc_reset,
    D_read,
    D_write,
    D_addr,
    D_rdata,
    D_wdata,
    D_ready,
    D_mem_read,
    D_mem_write,
    D_mem_addr,
    D_mem_rdata,
    D_mem_wdata,
    D_mem_ready,
    I_read,
    I_write,
    I_addr,
    I_rdata,
    I_wdata,
    I_ready,
    I_mem_read,
    I_mem_write,
    I_mem_addr,
    I_mem_rdata,
    I_mem_wdata,
    I_mem_ready,
);
    
//==== input/output definition ============================
    input          clk;
    input          proc_reset; 
    // L1-DCache interface
    input          D_read, D_write;
    input   [27:0] D_addr;
    input  [127:0] D_wdata;
    output         D_ready;
    output [127:0] D_rdata;
    // memory interface
    input  [127:0] D_mem_rdata;
    input          D_mem_ready;
    output         D_mem_read, D_mem_write;
    output  [27:0] D_mem_addr;
    output [127:0] D_mem_wdata;

    // L1-ICache interface
    input          I_read, I_write;
    input   [27:0] I_addr;
    input  [127:0] I_wdata;
    output         I_ready;
    output [127:0] I_rdata;
    // memory interface
    input  [127:0] I_mem_rdata;
    input          I_mem_ready;
    output         I_mem_read, I_mem_write;
    output  [27:0] I_mem_addr;
    output [127:0] I_mem_wdata;

//==== parameter ==========================================
parameter NUM_OF_SET = 128;
parameter NUM_OF_WAY = 2;
parameter SET_OFFSET = 7;

parameter IDLE          = 2'd0;
parameter READ_MEM      = 2'd1;
parameter DIRTY_WRITE   = 2'd2;
parameter DIRTY_READ    = 2'd3;

// request type
parameter D_CACHE = 1'b0;
parameter I_CACHE = 1'b1;

integer i, l;

//==== wire/reg definition ================================
// L1 in/out
reg         ready;
reg [127:0] rdata;
reg [127:0] wdata;
// mem in/out
reg         mem_request_type, next_mem_request_type;
reg         mem_read, mem_write;
reg         mem_ready;
reg [ 27:0] mem_addr;
reg [127:0] mem_rdata;
reg [127:0] mem_wdata;


// outputs 
reg         D_ready;
reg [127:0] D_rdata;
reg         D_mem_read, D_mem_write;
reg [ 27:0] D_mem_addr;
reg [127:0] D_mem_wdata;

reg         I_ready;
reg [127:0] I_rdata;
reg         I_mem_read, I_mem_write;
reg [ 27:0] I_mem_addr;
reg [127:0] I_mem_wdata;

// FFs
reg [1:0] state, next_state;

reg [127:0]            data[0:NUM_OF_SET-1][0:NUM_OF_WAY-1],  next_data[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg [27-SET_OFFSET:0]  tag[0:NUM_OF_SET-1][0:NUM_OF_WAY-1],   next_tag[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg                    valid[0:NUM_OF_SET-1][0:NUM_OF_WAY-1], next_valid[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg                    dirty[0:NUM_OF_SET-1][0:NUM_OF_WAY-1], next_dirty[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg                    type[0:NUM_OF_SET-1][0:NUM_OF_WAY-1], next_type[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg                    old[0:NUM_OF_SET-1], next_old[0:NUM_OF_SET-1];

reg                    D_mem_ready_FF, next_D_mem_ready_FF;
reg                    I_mem_ready_FF, next_I_mem_ready_FF;

reg request_type;
reg prev_request_type, next_prev_request_type;
reg read, write;
reg [27-SET_OFFSET:0] in_tag;
reg [ SET_OFFSET-1:0] set_idx;
//==== combinational circuit ==============================

// pre-process
always @(*) begin
    request_type = I_CACHE;
    read    = 0;
    write   = 0;
    in_tag  = 0;
    set_idx = 0;

    // only D-Cache will write
    wdata = D_wdata;

    if (state == IDLE) begin
        // D-Cache has higher priority
        if (D_read ^ D_write) begin
            request_type = D_CACHE;
            read = D_read & ~D_write;
            write = ~D_read & D_write;
            in_tag = D_addr[27:SET_OFFSET];
            set_idx = D_addr[SET_OFFSET-1:0];
        end
        else if (I_read) begin
            request_type = I_CACHE;
            read = I_read;
            in_tag = I_addr[27:SET_OFFSET];
            set_idx = I_addr[SET_OFFSET-1:0];
        end
    end
    else begin
        if (prev_request_type == I_CACHE) begin
            request_type = I_CACHE;
            read = I_read & ~I_write;
            write = ~I_read & I_write;
            in_tag = I_addr[27:SET_OFFSET];
            set_idx = I_addr[SET_OFFSET-1:0];
        end
        else begin
            request_type = D_CACHE;
            read = D_read & ~D_write;
            write = ~D_read & D_write;
            in_tag = D_addr[27:SET_OFFSET];
            set_idx = D_addr[SET_OFFSET-1:0];
        end
    end
    next_prev_request_type = request_type;

end

// post-process
always @(*) begin
    D_ready = 1'b0;
    D_rdata = 0;
    I_ready = 1'b0;
    I_rdata = 0;

    if (request_type == D_CACHE) begin
        D_ready = ready;
        D_rdata = rdata;
    end
    else begin
        I_ready = ready;
        I_rdata = rdata;
    end
end

// mem connection
always @(*) begin
    next_D_mem_ready_FF = D_mem_ready;
    next_I_mem_ready_FF = I_mem_ready;
    D_mem_read = 1'b0;
    D_mem_write = 1'b0;
    D_mem_addr = 0;
    D_mem_wdata = 127'b0;
    I_mem_read = 1'b0;
    I_mem_write = 1'b0;
    I_mem_addr = 0;
    I_mem_wdata = 127'b0;

    if (mem_request_type == D_CACHE) begin
        D_mem_read = mem_read;
        D_mem_write = mem_write;
        D_mem_addr = mem_addr;
        D_mem_wdata = mem_wdata;
        mem_ready = D_mem_ready_FF;
        mem_rdata = D_mem_rdata;
    end
    else begin
        I_mem_read = mem_read;
        I_mem_write = mem_write;
        I_mem_addr = mem_addr;
        I_mem_wdata = mem_wdata;
        mem_ready = I_mem_ready_FF;
        mem_rdata = I_mem_rdata;
    end
end
reg [31:0] miss, next_miss;
reg [31:0] total, next_total;
// normal cache operation
always @(*) begin
    next_miss = miss;
    next_total = total;
    next_state = state;
    next_mem_request_type = mem_request_type;

    ready = 1'b0;
    rdata = 127'b0;
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
            next_type[i][l] = type[i][l];
        end
    end
    case (state)
        IDLE: begin
            if (read ^ write) next_total = total+1;
            if (read) begin
                if (valid[set_idx][0] && (type[set_idx][0] == request_type) && (tag[set_idx][0] == in_tag)) begin // hit
                    next_state = IDLE;
                    next_old[set_idx] = 1'b1;
                    ready = 1'b1;
                    rdata = data[set_idx][0];
                end
                else if (valid[set_idx][1] && (type[set_idx][1] == request_type) && (tag[set_idx][1] == in_tag)) begin
                    next_state = IDLE;
                    next_old[set_idx] = 1'b0;
                    ready = 1'b1;
                    rdata = data[set_idx][1];
                end
                else begin
                    next_miss = miss+1;
                    if (dirty[set_idx][old[set_idx]]) begin // dirty, need write first
                        // it's impossible for I type data to be dirty (won't write instruction)
                        next_state = DIRTY_READ;
                        next_mem_request_type = D_CACHE;
                    end
                    else begin
                        next_state = READ_MEM;
                        next_mem_request_type = request_type;
                    end
                end
            end
            // only handle D-Cache writing
            if (write) begin
                if (valid[set_idx][0] && (type[set_idx][0] == D_CACHE) && (tag[set_idx][0] == in_tag)) begin
                    next_state = IDLE;
                    next_data[set_idx][0] = wdata;
                    next_dirty[set_idx][0] = 1'b1;
                    next_type[set_idx][0] = D_CACHE;
                    next_old[set_idx] = 1'b1;
                    ready = 1'b1;
                end
                else if (valid[set_idx][1] && (type[set_idx][1] == D_CACHE) && (tag[set_idx][1] == in_tag)) begin
                    next_state = IDLE;
                    next_data[set_idx][1] = wdata;
                    next_dirty[set_idx][1] = 1'b1;
                    next_type[set_idx][1] = D_CACHE;
                    next_old[set_idx] = 1'b0;
                    ready = 1'b1;
                end
                else begin
                    next_miss = miss+1;
                    if (dirty[set_idx][old[set_idx]]) begin
                        // it's impossible for I type data to be dirty (won't write instruction)
                        next_state = DIRTY_WRITE;
                        next_mem_request_type = D_CACHE;
                    end
                    else begin
                        next_state = IDLE;
                        ready = 1'b1;
                        next_old[set_idx] = ~old[set_idx];
                        next_valid[set_idx][old[set_idx]] = 1'b1;
                        next_tag[set_idx][old[set_idx]] = in_tag;
                        next_data[set_idx][old[set_idx]] = wdata;
                        next_dirty[set_idx][old[set_idx]] = 1'b1;
                        next_type[set_idx][old[set_idx]] = D_CACHE;
                    end
                end
            end    
        end
        READ_MEM: begin
            next_mem_request_type = mem_request_type;
            if (mem_ready) begin
                next_state = IDLE;
                ready = 1'b1;
                rdata = mem_rdata;
                next_old[set_idx] = ~old[set_idx];
                next_valid[set_idx][old[set_idx]] = 1'b1;
                next_tag[set_idx][old[set_idx]] = in_tag;
                next_data[set_idx][old[set_idx]] = mem_rdata;
                next_type[set_idx][old[set_idx]] = mem_request_type;
            end
            else begin
                next_state = READ_MEM;
                mem_read = 1'b1;
                mem_addr = { in_tag, set_idx };
            end
        end
        DIRTY_READ: begin
            if (mem_ready) begin
                next_dirty[set_idx][old[set_idx]] = 1'b0;
                next_mem_request_type = request_type;
                next_state = READ_MEM;
            end
            else begin
                next_state = DIRTY_READ;
                next_mem_request_type = D_CACHE;
                mem_write = 1'b1;
                mem_addr = { tag[set_idx][old[set_idx]], set_idx };
                mem_wdata = data[set_idx][old[set_idx]];
            end
        end
        DIRTY_WRITE: begin
            next_mem_request_type = D_CACHE;
            if (mem_ready) begin
                next_state = IDLE;
                ready = 1'b1;
                next_old[set_idx] = ~old[set_idx];
                next_valid[set_idx][old[set_idx]] = 1'b1;
                next_tag[set_idx][old[set_idx]] = in_tag;
                next_data[set_idx][old[set_idx]] = wdata;
                next_dirty[set_idx][old[set_idx]] = 1'b1;
                next_type[set_idx][old[set_idx]] = D_CACHE;
            end
            else begin
                next_state = DIRTY_WRITE;
                mem_write = 1'b1;
                mem_addr = { tag[set_idx][old[set_idx]], set_idx };
                mem_wdata = data[set_idx][old[set_idx]];
            end
        end

    endcase
end

//==== sequential circuit =================================
integer j, k;
always@( posedge clk ) begin
    if( proc_reset ) begin
        prev_request_type <= 0;
        miss <= 0;
        total <= 0;
        D_mem_ready_FF <= 0;
        I_mem_ready_FF <= 0;
        state <= IDLE;
        mem_request_type <= 0;
        for (j = 0; j < NUM_OF_SET; j=j+1) begin
            old[j] <= 0;
            for (k = 0; k < NUM_OF_WAY; k=k+1) begin
                data[j][k] <= 128'b0;
                tag[j][k] <= 0;
                valid[j][k] <= 0;
                dirty[j][k] <= 0;
                type[j][k] <= 0;
            end
        end
    end
    else begin
        prev_request_type <= next_prev_request_type;
        miss <= next_miss;
        total <= next_total;
        D_mem_ready_FF <= next_D_mem_ready_FF;
        I_mem_ready_FF <= next_I_mem_ready_FF;
        state <= next_state;
        mem_request_type <= next_mem_request_type;
        for (j = 0; j < NUM_OF_SET; j=j+1) begin
            old[j] <= next_old[j];
            for (k = 0; k < NUM_OF_WAY; k=k+1) begin
                data[j][k] <= next_data[j][k];
                tag[j][k] <= next_tag[j][k];
                valid[j][k] <= next_valid[j][k];
                dirty[j][k] <= next_dirty[j][k];
                type[j][k] <= next_type[j][k];
            end
        end
    end
end

endmodule
