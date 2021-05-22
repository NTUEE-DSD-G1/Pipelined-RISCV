// Five stage:
// IF  (instrction fetch)
// ID  (instruction decode and register read)
// EX  (execution or address calculation)
// MEM (data memory access)
// WB  (write back)
module RISCV_Pipeline(
    clk,
    rst_n,
    ICACHE_ren,
    ICACHE_wen,
    ICACHE_addr,
    ICACHE_wdata,
    ICACHE_stall,
    ICACHE_rdata,

    DCACHE_ren,
    DCACHE_wen,
    DCACHE_addr,
    DCACHE_wdata,
    DCACHE_stall,
    DCACHE_rdata
);
    input           clk;
    input           rst_n;

    // ICACHE 
    output          ICACHE_ren;
    output          ICACHE_wen;
    output  [29:0]  ICACHE_addr;
    output  [31:0]  ICACHE_wdata;
    input           ICACHE_stall;
    input   [31:0]  ICACHE_rdata;

    // DCACHE
    output          DCACHE_ren;
    output          DCACHE_wen;
    output  [29:0]  DCACHE_addr;
    output  [31:0]  DCACHE_wdata;
    input           DCACHE_stall;
    input   [31:0]  DCACHE_rdata;

    // -- Wire/Reg declaration --
    integer i;
    // register file
    reg     [31:0]  regfile_w [0:31];  
    reg     [31:0]  regfile_r [0:31];
    reg     [31:0]  busX, busY;
    wire    [4:0]   RW, RX, RY;
    wire            WEN;
    wire    [31:0]  busW;

    wire    [31:0]  IR;                 // Endian Conversion from ICACHE
    // Control signals
    wire            ID_Branch;          // ID
    wire            ID_Jalr;            // ID
    wire            ID_Jal;             // ID
    wire            ID_ALUOp;           // ID->EX
    wire            ID_ALUSrc;          // ID->EX
    wire            ID_MemWrite;        // ID->EX->MEM
    wire            ID_MemRead;         // ID->EX->MEM
    wire            ID_MemtoReg;        // ID->EX->MEM->WB
    wire            ID_RegWrite;        // ID->EX->MEM->WB
    
    reg             EX_ALUOp;
    reg             EX_ALUSrc;
    reg             EX_MemWrite, MEM_MemWrite;
    reg             EX_MemRead, MEM_MemRead;     
    reg             EX_MemtoReg, MEM_MemtoReg, WB_MemtoReg;
    reg             EX_RegWrite, MEM_RegWrite, WB_RegWrite;

    // -- Combinational part --
    // Endian Conversion
    assign IR = {ICACHE_rdata[7:0], ICACHE_rdata[15:8], ICACHE_rdata[23:16], ICACHE_rdata[31:24]};
    // Control signals
    assign ID_Branch   = (IR[6:0] == 7'b1100011);          // branch
    assign ID_Jal      = (IR[6:0] == 7'b1101111);          // jal
    assign ID_Jalr     = (IR[6:0] == 7'b1100111);          // jalr
    assign ID_MemRead  = (IR[6:0] == 7'b0000011);          // lw
    assign ID_MemtoReg = MemRead;                          // lw
    assign ID_ALUOp    = (IR[3:0] == 4'b0011);             // R-type, Itype, beq
    assign ID_MemWrite = (IR[6:0] == 7'b0100011);          // sw
    assign ID_ALUSrc   = (IR[4:0] == 5'b00011) & (!IR[6]); // lw or sw
    assign ID_RegWrite = (IR[6:0] == 7'b0110011)          // R-type
                        || (IR[6:0] == 7'b0010011)          // I-type(addi, andi...)
                        || (IR[6:0] == 7'b0000011)          // lw
                        || (IR[6:0] == 7'b1101111)          // jal
                        || (IR[6:0] == 7'b1100111);         // jalr
    
    // register file
    always@(*)begin
        // default
        for(i = 0; i < 32; i = i+1) begin
            regfile_w[i] = regfile_r[i];
        end
        busX = busX[RX];
        busY = busY[RY];
        if(WEN && (RW != 0)) begin
            regfile_w[RW] = busW;
        end
    end

    // -- Sequential part --
    // register file
    always@(posedge clk) begin
        if(!rst_n) begin
            for(i = 0; i < 32; i = i+1) begin
                regfile_r[i] <= 0;
            end
        end
        else begin
            for(i = 0; i < 32; i = i+1) begin
                regfile_r[i] <= regfile_w[i];
            end
        end
    end

    // control signals
    always@(posedge clk) begin
        if(!rst_n) begin
            EX_ALUOp        <= 0;
            EX_ALUSrc       <= 0;
            EX_MemWrite     <= 0;
            MEM_MemWrite    <= 0;
            EX_MemRead      <= 0;
            MEM_MemRead     <= 0;     
            EX_MemtoReg     <= 0;
            MEM_MemtoReg    <= 0;
            WB_MemtoReg     <= 0;
            EX_RegWrite     <= 0;
            MEM_RegWrite    <= 0;
            WB_RegWrite     <= 0;
        end
        else begin
            EX_ALUOp        <= ID_ALUOp;
            EX_ALUSrc       <= ID_ALUSrc;
            EX_MemWrite     <= ID_MemWrite;
            MEM_MemWrite    <= EX_MemWrite;
            EX_MemRead      <= ID_MemRead;
            MEM_MemRead     <= EX_MemRead;     
            EX_MemtoReg     <= ID_MemtoReg;
            MEM_MemtoReg    <= EX_MemtoReg;
            WB_MemtoReg     <= MEM_MemtoReg;
            EX_RegWrite     <= ID_RegWrite;
            MEM_RegWrite    <= EX_RegWrite;
            WB_RegWrite     <= MEM_RegWrite;
        end
    end
endmodule