// directed map L2-ICache (read-only)
module Icache_L2(
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
parameter NUM_OF_BLOCK = 64;
parameter BLOCK_OFFSET = 5;

parameter IDLE     = 1'd0;
parameter READ_MEM = 1'd1;

//==== wire/reg definition ================================
// outputs 
reg                    proc_ready;
reg [127:0]            proc_rdata;
reg                    mem_read, mem_write;
reg [ 27:0]            mem_addr;
reg [127:0]            mem_wdata;

// FFs
reg                    state, next_state;

reg [127:0]             data[0:NUM_OF_BLOCK-1],  next_data[0:NUM_OF_BLOCK-1];
reg [27-BLOCK_OFFSET:0] tag[0:NUM_OF_BLOCK-1],   next_tag[0:NUM_OF_BLOCK-1];
reg                     valid[0:NUM_OF_BLOCK-1], next_valid[0:NUM_OF_BLOCK-1];

reg                    mem_ready_FF, next_mem_ready_FF;

wire read;
wire [27-BLOCK_OFFSET:0] in_tag;
wire [ BLOCK_OFFSET-1:0] block_idx;

//==== combinational circuit ==============================
integer i;
assign read       = proc_read;
assign in_tag     = proc_addr[27:BLOCK_OFFSET];
assign block_idx  = proc_addr[BLOCK_OFFSET-1:0];

always @(*) begin
    next_mem_ready_FF = mem_ready;
    next_state = state;
    proc_ready = 1'b0;
    proc_rdata = 0;
    mem_read = 1'b0;
    mem_write = 1'b0;
    mem_addr = 0;
    mem_wdata = 127'b0;
    for (i = 0; i < NUM_OF_BLOCK; i=i+1) begin
        next_data[i] = data[i];
        next_tag[i] = tag[i];
        next_valid[i] = valid[i];
    end
    case (state)
        IDLE: begin
            if (read) begin
                if (valid[block_idx] && (tag[block_idx] == in_tag)) begin // hit
                    next_state = IDLE;
                    proc_rdata = data[block_idx];
                    proc_ready = 1'b1;
                end
                else begin
                    next_state = READ_MEM;
                    mem_read = 1'b1;
                    mem_addr = { in_tag, block_idx };
                end
            end
        end
        READ_MEM: begin
            if (mem_ready_FF) begin
                next_state = IDLE;
                proc_ready = 1'b1;
                next_valid[block_idx] = 1'b1;
                next_tag[block_idx] = in_tag;
                next_data[block_idx] = mem_rdata;
                proc_rdata = mem_rdata;
            end
            else begin
                next_state = READ_MEM;
                mem_read = 1'b1;
                mem_addr = { in_tag, block_idx };
            end
        end
    endcase
end

//==== sequential circuit =================================
integer j;
always@( posedge clk ) begin
    if( proc_reset ) begin
        mem_ready_FF <= 0;
        state <= IDLE;
        for (j = 0; j < NUM_OF_BLOCK; j=j+1) begin
            data[j] <= 128'b0;
            tag[j] <= 0;
            valid[j] <= 0;
        end
    end
    else begin
        mem_ready_FF <= next_mem_ready_FF;
        state <= next_state;
        for (j = 0; j < NUM_OF_BLOCK; j=j+1) begin
            data[j] <= next_data[j];
            tag[j] <= next_tag[j];
            valid[j] <= next_valid[j];
        end
    end
end

endmodule
