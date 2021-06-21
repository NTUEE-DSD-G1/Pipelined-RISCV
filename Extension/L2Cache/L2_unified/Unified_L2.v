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
parameter NUM_OF_SET = 32;
parameter NUM_OF_WAY = 2;
parameter SET_OFFSET = 4;

parameter IDLE          = 3'd0;
parameter D_READ_MEM    = 3'd1;
parameter DIRTY_WRITE   = 3'd2;
parameter DIRTY_READ    = 3'd3;
parameter I_READ_MEM    = 3'd4;

// request type
parameter D_CACHE = 1'b0;
parameter I_CACHE = 1'b1;

//==== wire/reg definition ================================
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
reg [2:0] state, next_state;

reg [127:0]            data[0:NUM_OF_SET-1][0:NUM_OF_WAY-1],  next_data[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg [27-SET_OFFSET:0]  tag[0:NUM_OF_SET-1][0:NUM_OF_WAY-1],   next_tag[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg                    valid[0:NUM_OF_SET-1][0:NUM_OF_WAY-1], next_valid[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg                    dirty[0:NUM_OF_SET-1][0:NUM_OF_WAY-1], next_dirty[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg                    type[0:NUM_OF_SET-1][0:NUM_OF_WAY-1], next_type[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg                    old[0:NUM_OF_SET-1], next_old[0:NUM_OF_SET-1];

reg                    D_mem_ready_FF, next_D_mem_ready_FF;
reg                    I_mem_ready_FF, next_I_mem_ready_FF;

reg request_type;
reg read, write;
reg [27-SET_OFFSET:0] in_tag;
reg [ SET_OFFSET-1:0] set_idx;
reg error;
//==== combinational circuit ==============================
integer i, l;

wire conflict;
assign conflict = (D_read ^ D_write) && (I_read ^ I_write);

// pre-process
always @(*) begin
  request_type = I_CACHE;
  read    = 0;
  write   = 0;
  in_tag  = 0;
  set_idx = 0;
  // D-Cache has higher priority
  if (D_read ^ D_write) begin
    request_type = D_CACHE;
    read = D_read & ~D_write;
    write = ~D_read & D_write;
    in_tag = D_addr[27:SET_OFFSET];
    set_idx = D_addr[SET_OFFSET-1:0];
  end
  else if (I_read ^ I_write) begin
    request_type = I_CACHE;
    read = I_read & ~I_write;
    write = ~I_read & I_write;
    in_tag = I_addr[27:SET_OFFSET];
    set_idx = I_addr[SET_OFFSET-1:0];
  end
end

// post-process

// normal cache operation
always @(*) begin
    next_D_mem_ready_FF = D_mem_ready;
    next_I_mem_ready_FF = I_mem_ready;
    next_state = state;
    D_ready = 1'b0;
    D_rdata = 0;
    D_mem_read = 1'b0;
    D_mem_write = 1'b0;
    D_mem_addr = 0;
    D_mem_wdata = 127'b0;
    I_ready = 1'b0;
    I_rdata = 0;
    I_mem_read = 1'b0;
    I_mem_write = 1'b0;
    I_mem_addr = 0;
    I_mem_wdata = 127'b0;
    error = 0;
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
            if (read) begin
                if (valid[set_idx][0] && (type[set_idx][0] == request_type) && (tag[set_idx][0] == in_tag)) begin // hit
                    next_state = IDLE;
                    next_old[set_idx] = 1'b1;
                    if (request_type == D_CACHE) begin
                        D_rdata = data[set_idx][0];
                        D_ready = 1'b1;
                    end
                    else begin
                        I_rdata = data[set_idx][0];
                        I_ready = 1'b1;
                    end
                end
                else if (valid[set_idx][1] && (type[set_idx][1] == request_type) && (tag[set_idx][1] == in_tag)) begin
                    next_state = IDLE;
                    next_old[set_idx] = 1'b0;
                    if (request_type == D_CACHE) begin
                        D_rdata = data[set_idx][1];
                        D_ready = 1'b1;
                    end
                    else begin
                        I_rdata = data[set_idx][1];
                        I_ready = 1'b1;
                    end
                end
                else begin
                    if (dirty[set_idx][old[set_idx]]) begin // dirty, need write first
                        // it's impossible for I type data to be dirty (won't write instruction)
                        next_state = DIRTY_READ;
                        D_mem_write = 1'b1;
                        D_mem_addr = { tag[set_idx][old[set_idx]], set_idx };
                        D_mem_wdata = data[set_idx][old[set_idx]];
                    end
                    else begin
                        if (request_type == D_CACHE) begin
                            next_state = D_READ_MEM;
                            D_mem_read = 1'b1;
                            D_mem_addr = { in_tag, set_idx };
                        end
                        else begin
                            next_state = I_READ_MEM;
                            I_mem_read = 1'b1;
                            I_mem_addr = { in_tag, set_idx };
                        end
                    end
                end
            end
            // only handle D-Cache writing
            if (write) begin
                if (valid[set_idx][0] && (type[set_idx][0] == D_CACHE) && (tag[set_idx][0] == in_tag)) begin
                    next_state = IDLE;
                    next_data[set_idx][0] = D_wdata;
                    next_dirty[set_idx][0] = 1'b1;
                    next_type[set_idx][0] = D_CACHE;
                    next_old[set_idx] = 1'b1;
                    D_ready = 1'b1;
                end
                else if (valid[set_idx][1] && (type[set_idx][1] == D_CACHE) && (tag[set_idx][1] == in_tag)) begin
                    next_state = IDLE;
                    next_data[set_idx][1] = D_wdata;
                    next_dirty[set_idx][1] = 1'b1;
                    next_type[set_idx][1] = D_CACHE;
                    next_old[set_idx] = 1'b0;
                    D_ready = 1'b1;
                end
                else begin
                    if (dirty[set_idx][old[set_idx]]) begin
                        // it's impossible for I type data to be dirty (won't write instruction)
                        if (type[set_idx][old[set_idx]] == I_CACHE) error = 1'b1;
                        next_state = DIRTY_WRITE;
                        D_mem_write = 1'b1;
                        D_mem_addr = { tag[set_idx][old[set_idx]], set_idx };
                        D_mem_wdata = data[set_idx][old[set_idx]];
                    end
                    else begin
                        next_state = IDLE;
                        D_ready = 1'b1;
                        next_old[set_idx] = ~old[set_idx];
                        next_valid[set_idx][old[set_idx]] = 1'b1;
                        next_tag[set_idx][old[set_idx]] = in_tag;
                        next_data[set_idx][old[set_idx]] = D_wdata;
                        next_dirty[set_idx][old[set_idx]] = 1'b1;
                        next_type[set_idx][old[set_idx]] = D_CACHE;
                    end
                end
            end    
        end
        D_READ_MEM: begin
            if (D_mem_ready_FF) begin
                next_state = IDLE;
                D_ready = 1'b1;
                D_rdata = D_mem_rdata;
                next_old[set_idx] = ~old[set_idx];
                next_valid[set_idx][old[set_idx]] = 1'b1;
                next_tag[set_idx][old[set_idx]] = in_tag;
                next_data[set_idx][old[set_idx]] = D_mem_rdata;
                next_type[set_idx][old[set_idx]] = D_CACHE;
            end
            else begin
                next_state = D_READ_MEM;
                D_mem_read = 1'b1;
                D_mem_addr = { in_tag, set_idx };
            end
        end
        I_READ_MEM: begin
            if (I_mem_ready_FF) begin
                next_state = IDLE;
                I_ready = 1'b1;
                I_rdata = I_mem_rdata;
                next_old[set_idx] = ~old[set_idx];
                next_valid[set_idx][old[set_idx]] = 1'b1;
                next_tag[set_idx][old[set_idx]] = in_tag;
                next_data[set_idx][old[set_idx]] = I_mem_rdata;
                next_type[set_idx][old[set_idx]] = I_CACHE;
            end
            else begin
                next_state = I_READ_MEM;
                I_mem_read = 1'b1;
                I_mem_addr = { in_tag, set_idx };
            end
        end
        DIRTY_READ: begin
            if (D_mem_ready_FF) begin
                next_dirty[set_idx][old[set_idx]] = 1'b0;
                if (request_type == D_CACHE) begin
                    next_state = D_READ_MEM;
                    D_mem_read = 1'b1;
                    D_mem_addr = { in_tag, set_idx };
                end
                else begin
                    next_state = I_READ_MEM;
                    I_mem_read = 1'b1;
                    I_mem_addr = { in_tag, set_idx };
                end
            end
            else begin
                next_state = DIRTY_READ;
                D_mem_write = 1'b1;
                D_mem_addr = { tag[set_idx][old[set_idx]], set_idx };
                D_mem_wdata = data[set_idx][old[set_idx]];
            end
        end
        DIRTY_WRITE: begin
            if (D_mem_ready_FF) begin
                next_state = IDLE;
                D_ready = 1'b1;
                next_old[set_idx] = ~old[set_idx];
                next_valid[set_idx][old[set_idx]] = 1'b1;
                next_tag[set_idx][old[set_idx]] = in_tag;
                next_data[set_idx][old[set_idx]] = D_wdata;
                next_dirty[set_idx][old[set_idx]] = 1'b1;
                next_type[set_idx][old[set_idx]] = D_CACHE;
            end
            else begin
                next_state = DIRTY_WRITE;
                D_mem_write = 1'b1;
                D_mem_addr = { tag[set_idx][old[set_idx]], set_idx };
                D_mem_wdata = data[set_idx][old[set_idx]];
            end
        end

    endcase
end

//==== sequential circuit =================================
integer j, k;
always@( posedge clk ) begin
    if( proc_reset ) begin
        D_mem_ready_FF <= 0;
        I_mem_ready_FF <= 0;
        state <= IDLE;
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
        D_mem_ready_FF <= next_D_mem_ready_FF;
        I_mem_ready_FF <= next_I_mem_ready_FF;
        state <= next_state;
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
