// directed map ICache (read-only)
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
parameter NUM_OF_BLOCK = 8;
parameter BLOCK_OFFSET = 3;

parameter IDLE = 1'd0;
parameter READ_MEM = 1'd1;

//==== wire/reg definition ================================
// outputs 
reg         proc_stall;
reg [ 31:0] proc_rdata;
reg         mem_read, mem_write;
reg [ 29:0] mem_addr;
reg [ 31:0] mem_wdata;

// FFs
reg                   state, next_state;

reg [127:0]             data[0:NUM_OF_BLOCK-1],  next_data[0:NUM_OF_BLOCK-1];
reg [27-BLOCK_OFFSET:0] tag[0:NUM_OF_BLOCK-1],   next_tag[0:NUM_OF_BLOCK-1];
reg                     valid[0:NUM_OF_BLOCK-1], next_valid[0:NUM_OF_BLOCK-1];

reg                   mem_ready_FF, next_mem_ready_FF;
reg [127:0]           mem_rdata_FF, next_mem_rdata_FF;

wire read;
wire [27-BLOCK_OFFSET:0] in_tag;
wire [BLOCK_OFFSET-1:0] block_idx;
wire [1:0] word_idx;

//==== combinational circuit ==============================
integer i;
assign read     = proc_read;
assign in_tag   = proc_addr[29:2+BLOCK_OFFSET];
assign block_idx  = proc_addr[1+BLOCK_OFFSET:2];
assign word_idx = proc_addr[1:0];

always @(*) begin
    next_mem_ready_FF = mem_ready;
    next_mem_rdata_FF = mem_rdata;
    next_state = state;
    proc_stall = 1'b0;
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
                    proc_rdata = data[block_idx][(word_idx+1)*32-1 -: 32];
                end
                else begin
                    next_state = READ_MEM;
                    mem_read = 1'b1;
                    mem_addr = { in_tag, block_idx };
                    proc_stall = 1'b1;
                end
            end
        end
        READ_MEM: begin
            if (mem_ready_FF) begin
                next_state = IDLE;
                proc_stall = 1'b0;
                next_valid[block_idx] = 1'b1;
                next_tag[block_idx] = in_tag;
                next_data[block_idx] = mem_rdata_FF;
                proc_rdata = mem_rdata_FF[(word_idx+1)*32-1 -: 32];
            end
            else begin
                next_state = READ_MEM;
                mem_read = 1'b1;
                mem_addr = { in_tag, block_idx };
                proc_stall = 1'b1;
            end
        end
    endcase
end

//==== sequential circuit =================================
integer j;
always@( posedge clk ) begin
    if( proc_reset ) begin
        mem_ready_FF <= 0;
        mem_rdata_FF <= 128'b0;
        state <= IDLE;
        for (j = 0; j < NUM_OF_BLOCK; j=j+1) begin
            data[j]  <= 128'b0;
            tag[j]   <= 0;
            valid[j] <= 0;
        end
    end
    else begin
        mem_ready_FF <= next_mem_ready_FF;
        mem_rdata_FF <= next_mem_rdata_FF;
        state <= next_state;
        for (j = 0; j < NUM_OF_BLOCK; j=j+1) begin
            data[j]  <= next_data[j];
            tag[j]   <= next_tag[j];
            valid[j] <= next_valid[j];
        end
    end
end

endmodule
