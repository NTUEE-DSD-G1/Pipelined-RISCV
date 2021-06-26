module Dcache(
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
    input   [29:0] proc_addr;
    input   [31:0] proc_wdata;
    output         proc_stall;
    output  [31:0] proc_rdata;
    // memory interface
    input  [127:0] mem_rdata;
    input          mem_ready;
    output         mem_read, mem_write;
    output  [27:0] mem_addr;
    output [127:0] mem_wdata;

//==== parameter ==========================================
parameter NUM_OF_SET = 4;
parameter NUM_OF_WAY = 2;
parameter SET_OFFSET = 2;

parameter IDLE        = 3'd1;
parameter READ_MEM    = 3'd2;
parameter WRITE_MEM   = 3'd3;
parameter DIRTY_WRITE = 3'd4;
parameter DIRTY_READ  = 3'd5;

//==== wire/reg definition ================================
// outputs 
reg         proc_stall;
reg [ 31:0] proc_rdata;
reg         mem_read, mem_write;
reg [ 27:0] mem_addr;
reg [127:0] mem_wdata;

// FFs
reg [3:0] state, next_state;

reg [127:0]           data[0:NUM_OF_SET-1][0:NUM_OF_WAY-1],  next_data[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg [27-SET_OFFSET:0] tag[0:NUM_OF_SET-1][0:NUM_OF_WAY-1],   next_tag[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg                   valid[0:NUM_OF_SET-1][0:NUM_OF_WAY-1], next_valid[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg                   dirty[0:NUM_OF_SET-1][0:NUM_OF_WAY-1], next_dirty[0:NUM_OF_SET-1][0:NUM_OF_WAY-1];
reg                   old[0:NUM_OF_SET-1], next_old[0:NUM_OF_SET-1];

reg                   mem_ready_FF, next_mem_ready_FF;
reg [127:0]           mem_rdata_FF, next_mem_rdata_FF;

wire read, write;
wire [27-SET_OFFSET:0] in_tag;
wire [1:0] set_idx;
wire [1:0] word_idx;

//==== combinational circuit ==============================
integer i, l;
assign read     = proc_read & ~proc_write;
assign write    = ~proc_read & proc_write;
assign in_tag   = proc_addr[29:2+SET_OFFSET];
assign set_idx  = proc_addr[1+SET_OFFSET:2];
assign word_idx = proc_addr[1:0];
// reg [31:0] miss, next_miss;
// reg [31:0] total, next_total;
always @(*) begin
    // next_miss = miss;
    // next_total = total;
    next_mem_ready_FF = mem_ready;
    next_mem_rdata_FF = mem_rdata;
    next_state = state;
    proc_stall = 1'b0;
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
                if (valid[set_idx][0] && (tag[set_idx][0] == in_tag)) begin // hit
                    next_state = IDLE;
                    proc_rdata = data[set_idx][0][(word_idx+1)*32-1 -: 32];
                    next_old[set_idx] = 1'b1;
                end
                else if (valid[set_idx][1] && (tag[set_idx][1] == in_tag)) begin
                    next_state = IDLE;
                    proc_rdata = data[set_idx][1][(word_idx+1)*32-1 -: 32];
                    next_old[set_idx] = 1'b0;
                end
                else begin
                    // next_miss = miss+1;
                    if (dirty[set_idx][old[set_idx]]) begin // dirty, need to write L2 first
                        next_state = DIRTY_READ;
                        proc_stall = 1'b1;
                        mem_write = 1'b1;
                        mem_addr = { tag[set_idx][old[set_idx]], set_idx };
                        mem_wdata = data[set_idx][old[set_idx]];
                    end
                    else begin // not dirty, just read from L2
                        next_state = READ_MEM;
                        proc_stall = 1'b1;
                        mem_read = 1'b1;
                        mem_addr = { in_tag, set_idx };
                    end
                end
            end
            if (write) begin
                if (valid[set_idx][0] && (tag[set_idx][0] == in_tag)) begin
                    next_state = IDLE;
                    next_data[set_idx][0][(word_idx+1)*32-1 -: 32] = proc_wdata;
                    next_dirty[set_idx][0] = 1'b1;
                    next_old[set_idx] = 1'b1;
                end
                else if (valid[set_idx][1] && (tag[set_idx][1] == in_tag)) begin
                    next_state = IDLE;
                    next_data[set_idx][1][(word_idx+1)*32-1 -: 32] = proc_wdata;
                    next_dirty[set_idx][1] = 1'b1;
                    next_old[set_idx] = 1'b0;
                end
                else begin
                    // next_miss = miss+1;
                    if (dirty[set_idx][old[set_idx]]) begin // dirty, need to write L2 first
                        next_state = DIRTY_WRITE;
                        proc_stall = 1'b1;
                        mem_write = 1'b1;
                        mem_addr = { tag[set_idx][old[set_idx]], set_idx };
                        mem_wdata = data[set_idx][old[set_idx]];
                    end
                    else begin // not dirty, just read from L2
                        next_state = WRITE_MEM;
                        proc_stall = 1'b1;
                        mem_read = 1'b1;
                        mem_addr = { in_tag, set_idx };
                    end
                end
            end    
        end
        READ_MEM: begin
            if (mem_ready_FF) begin
                next_state = IDLE;
                proc_stall = 1'b0;
                next_old[set_idx] = ~old[set_idx];
                next_valid[set_idx][old[set_idx]] = 1'b1;
                next_tag[set_idx][old[set_idx]] = in_tag;
                next_data[set_idx][old[set_idx]] = mem_rdata_FF;
                proc_rdata = mem_rdata_FF[(word_idx+1)*32-1 -: 32];
            end
            else begin
                next_state = READ_MEM;
                proc_stall = 1'b1;
                mem_read = 1'b1;
                mem_addr = { in_tag, set_idx };
            end
        end
        WRITE_MEM: begin
            if (mem_ready_FF) begin
                next_state = IDLE;
                proc_stall = 1'b0;
                next_old[set_idx] = ~old[set_idx];
                next_valid[set_idx][old[set_idx]] = 1'b1;
                next_tag[set_idx][old[set_idx]] = in_tag;
                next_data[set_idx][old[set_idx]] = mem_rdata_FF;
                next_data[set_idx][old[set_idx]][(word_idx+1)*32-1 -: 32] = proc_wdata;
            end
            else begin
                next_state = WRITE_MEM;
                proc_stall = 1'b1;
                mem_read = 1'b1;
                mem_addr = { in_tag, set_idx };
            end
        end
        DIRTY_READ: begin
            if (mem_ready_FF) begin
                next_state = READ_MEM;
                proc_stall = 1'b1;
                mem_read = 1'b1;
                mem_addr = { in_tag, set_idx };
                next_dirty[set_idx][old[set_idx]] = 1'b0;
            end
            else begin
                next_state = DIRTY_READ;
                proc_stall = 1'b1;
                mem_write = 1'b1;
                mem_addr = { tag[set_idx][old[set_idx]], set_idx };
                mem_wdata = data[set_idx][old[set_idx]];
            end
        end
        DIRTY_WRITE: begin
            if (mem_ready_FF) begin
                next_state = WRITE_MEM;
                proc_stall = 1'b1;
                mem_read = 1'b1;
                mem_addr = { in_tag, set_idx };
                next_dirty[set_idx][old[set_idx]] = 1'b0;
            end
            else begin
                next_state = DIRTY_WRITE;
                proc_stall = 1'b1;
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
        // miss <= 0;
        // total <= 0;
        mem_ready_FF <= 0;
        mem_rdata_FF <= 128'd0;
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
        mem_ready_FF <= next_mem_ready_FF;
        mem_rdata_FF <= next_mem_rdata_FF;
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
