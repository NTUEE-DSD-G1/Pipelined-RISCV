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

    // ---------------------- parameter for ALU ----------------------
    parameter ADD   = 4'd9;
    parameter SUB   = 4'd1;
    parameter AND   = 4'd2;
    parameter OR    = 4'd3;
    parameter XOR   = 4'd4;
    parameter SLL   = 4'd5;
    parameter SRA   = 4'd6;
    parameter SRL   = 4'd7;
    parameter SLT   = 4'd8;

    // ---------------------- Wire/Reg declaration ----------------------
    integer i;
    // PC
    reg     [31:0]  IF_PC;
    reg     [31:0]  ID_PC;
    wire    [31:0]  next_PC;

    // register file
    reg     [31:0]  regfile_w [0:31];  
    reg     [31:0]  regfile_r [0:31];
    reg     [31:0]  ID_busRS1, ID_busRS2;
    wire    [4:0]   ID_RS1, ID_RS2, ID_RD;
    reg     [4:0]   WB_RD, MEM_RD, EX_RD;
    reg     [31:0]  WB_busRD;

    // instruction
    wire    [31:0]  IR;                 // Endian Conversion from ICACHE
    wire    [2:0]   funct3;
    wire    [6:0]   opcode;

    // ALU
    wire    [31:0]  ID_din_1, ID_din_2;
    wire    [3:0]   ID_ctrl;
    reg signed [31:0] EX_din_1, EX_din_2;
    reg     [31:0]  MEM_din_2;
    reg     [3:0]   EX_ctrl;
    reg     [31:0]  EX_dout, MEM_dout, WB_dout;

    // immgen;
    wire    [31:0]  ID_immgen;

    // Branch and Jalr and Jal
    wire            ID_Equal;
    wire    [31:0]  ID_addr;      

    // Control signals
    wire            ID_Branch;          // ID
    wire            ID_Jalr;            // ID
    wire            ID_Jal;             // ID
    wire            ID_ALUSrc;          // ID
    wire            ID_ALUOp;           // ID->EX
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

    // ---------------------- Combinational part ----------------------
    // PC
    assign next_PC = (((ID_Branch & ID_Equal) | ID_Jal) | (ID_Jalr)) ? ID_addr : (IF_PC + 4); 
    
    // ID: Endian Conversion
    assign IR = {ICACHE_rdata[7:0], ICACHE_rdata[15:8], ICACHE_rdata[23:16], ICACHE_rdata[31:24]};
    assign funct3 = IR[14:12];
    assign opcode = IR[6:0];

    // ID: Control signals
    assign ID_Branch   = (IR[6:0] == 7'b1100011);          // branch
    assign ID_Jal      = (IR[6:0] == 7'b1101111);          // jal
    assign ID_Jalr     = (IR[6:0] == 7'b1100111);          // jalr
    assign ID_MemRead  = (IR[6:0] == 7'b0000011);          // lw
    assign ID_MemtoReg = MemRead;                          // lw
    assign ID_ALUOp    = (IR[3:0] == 4'b0011);             // R-type, Itype, beq
    assign ID_MemWrite = (IR[6:0] == 7'b0100011);          // sw
    assign ID_ALUSrc   = (IR[4:0] == 5'b00011) & (!IR[6]); // lw or sw
    assign ID_RegWrite = (IR[6:0] == 7'b0110011)           // R-type
                        || (IR[6:0] == 7'b0010011)         // I-type(addi, andi...)
                        || (IR[6:0] == 7'b0000011)         // lw
                        || (IR[6:0] == 7'b1101111)         // jal
                        || (IR[6:0] == 7'b1100111);        // jalr
    
    // ID: register file (read)
    always@(*)begin
        ID_busRS1 = regfile_r[ID_RS1];
        ID_busRS2 = regfile_r[ID_RS2];
    end

    // ID: register file signals
    assign ID_RS1 = IR[19:15];
    assign ID_RS2 = IR[24:20];
    assign ID_RD = IR[11:7];
    
    // ID: ALU related signals
    assign ID_din_2 = ID_ALUSrc ? ID_immgen : ID_busRS2;
    assign ID_din_1 = ID_busRS1;
    
    always@(*) begin
        ID_ctrl = 0;
        if(opcode == 7'b0110011) begin
            case(funct3)
                3'b000: ID_ctrl = IR[30] ? SUB : ADD;
                3'b010: ID_ctrl = SLT;
                3'b100: ID_ctrl = XOR;
                3'b110: ID_ctrl = OR;
                3'b111: ID_ctrl = AND; 
                default: ID_ctrl = 0;
            endcase
        end
        else if(opcode == 7'b0010011) begin
            case(funct3)
                3'b000: ID_ctrl = ADD;
                3'b001: ID_ctrl = SLL;
                3'b010: ID_ctrl = SLT;
                3'b100: ID_ctrl = XOR;
                3'b101: ID_ctrl = IR[30] ? SRA : SRL;
                3'b110: ID_ctrl = OR;
                3'b111: ID_ctrl = AND;
                default: ID_ctrl = 0;
            endcase
        end 
        else if(opcode == 7'b0000011 || opcode == 7'b1100011) begin
            if(funct3 == 3'b000 || funct3 == 3'b001) begin
                ID_ctrl = ADD;
            end
    
        end
    end

    // ID: Branch and Jalr and Jal
    assign ID_Equal = (ID_din_1 == ID_din_2);
    assign ID_addr = $signed(immgen) + $signed((Jalr ? ID_din_1 : ID_PC));
    
    // EX: ALU
    always@(*) begin
        EX_dout = 0;
        if(EX_ALUOp) begin
            case(EX_ctrl)
                ADD: EX_dout = EX_din_1 + EX_din_2;                    // 9:add
                SUB: EX_dout = EX_din_1 - EX_din_2;                    // 1:sub
                AND: EX_dout = EX_din_1 & EX_din_2;                    // 2:and
                OR:  EX_dout = EX_din_1 | EX_din_2;                    // 3:or
                XOR: EX_dout = EX_din_1 ^ EX_din_2;                    // 4:xor
                SLL: EX_dout = EX_din_1 << EX_din_2;                   // 5:shift left (logical)
                SRA: EX_dout = EX_din_1 >>> EX_din_2;                  // 6:shift right (arithmetic)
                SRL: EX_dout = EX_din_1 >> EX_din_2;                   // 7:shift right (logical)
                SLT: EX_dout = (EX_din_1 < EX_din_2) ? 32'd1 : 32'd0;  // 8: set on less than
                default: EX_dout = 0;
            endcase
        end
    end

    // ID: immgen
    assign ID_immgen =  ID_Branch ? {{20{IR[31]}}, IR[7], IR[30:25], IR[11:8], 1'b0} :
                        ID_Jal    ? {{12{IR[31]}}, IR[19:12], IR[20], IR[30:25], IR[24:21], 1'b0} : 
                        ID_MemWrite ? {{21{IR[31]}}, IR[30:25], IR[11:7]} :
                        {{21{IR[31]}}, IR[30:20] };

    // MEM: access data cache
    assign DCACHE_ren = MEM_MemRead;
    assign DCACHE_wen = MEM_MemWrite;
    assign DCACHE_addr = MEM_dout[31:2];
        // Endian Conversion
    assign DCACHE_wdata = {MEM_din_2[7:0], MEM_din_2[15:8], MEM_din_2[23:16], MEM_din_2[31:24]};

    // WB: mux
        // Endian Conversion
    assign WB_busRD = WB_MemtoReg ? {DCACHE_rdata[7:0], DCACHE_rdata[15:8], DCACHE_rdata[23:16], DCACHE_rdata[31:24]} : WB_dout;
    
    // WB: register file (write)
    always@(*)begin
        // default
        for(i = 0; i < 32; i = i+1) begin
            regfile_w[i] = regfile_r[i];
        end
        
        if(WB_RegWrite && (WB_RD != 0)) begin
            regfile_w[WB_RD] = WB_busRD;
        end
    end

    // ---------------------- Sequential part ----------------------
    // PC
    always@(posedge clk) begin
        if(!rst_n) begin
            IF_PC <= 0;
            ID_PC <= 0;
        end
        else begin
            IF_PC <= next_PC;
            ID_PC <= IF_PC;
        end
    end
    
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

    // ALU-related signals
    always@(posedge clk) begin
        if(!rst_n) begin
            EX_din_1        <= 0;
            EX_din_2        <= 0;
            EX_ctrl         <= 0;
            MEM_dout        <= 0;
            MEM_din_2       <= 0;
            WB_dout         <= 0;
        end
        else begin
            EX_din_1        <= ID_din_1;
            EX_din_2        <= ID_din_2;
            EX_ctrl         <= ID_ctrl;
            MEM_dout        <= EX_dout;
            MEM_din_2       <= EX_din_2;
            WB_dout         <= MEM_dout;
        end
    end

    // register-related signals
    always@(posedge clk) begin
        if(!rst_n) begin
            WB_RD           <= 0;
            MEM_RD          <= 0;
            EX_RD           <= 0;
        end
        else begin
            WB_RD           <= MEM_RD;
            MEM_RD          <= EX_RD;
            EX_RD           <= ID_RD;
        end
    end
endmodule