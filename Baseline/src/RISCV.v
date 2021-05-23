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

    // ---------------------- parameter for Forwarding unit ----------------------
    parameter ORI   = 2'b00;    // pass data from regfile to LUA
    parameter MEM   = 2'b01;    // pass data from ALU to ALU
    parameter WB    = 2'b10;    // pass data from MEM to ALU
    // ---------------------- Wire/Reg declaration ----------------------
    integer i;
    
    // PC
    reg     [31:0]  IF_PC;
    reg     [31:0]  ID_PC;
    reg     [31:0]  next_PC;

    // register file
    reg     [31:0]  regfile_w [0:31];  
    reg     [31:0]  regfile_r [0:31];
    reg     [31:0]  ID_busRS1, ID_busRS2;
    wire    [4:0]   ID_RS1, ID_RS2, ID_RD;
    reg     [4:0]   WB_RD, MEM_RD, EX_RD;
    wire    [31:0]  WB_busRD;
    reg     [31:0]  WB_DCACHE_rdata;   

    // instruction
    reg     [31:0]  IR;               
    reg     [31:0]  next_IR;
    wire    [2:0]   funct3;
    wire    [6:0]   opcode;

    // ALU
    reg     [31:0]  EX_busRS1, EX_busRS2;
    reg     [3:0]   ID_ctrl;
    reg signed [31:0] EX_din_1, EX_din_2;
    reg     [31:0]  MEM_busRS2;
    reg     [3:0]   EX_ctrl;
    reg     [31:0]  EX_dout, MEM_dout, WB_dout;

    // immgen;
    reg     [31:0]  ID_immgen;
    reg     [31:0]  EX_immgen;

    // Branch and Jalr and Jal
    wire            ID_Equal;
    wire    [31:0]  ID_addr;

    // Forwarding unit
    reg     [1:0]   ForwardA, ForwardB;
    reg     [4:0]   EX_RS1, EX_RS2;

    // Hazard detection unit  
    reg             IF_PCWrite;
    reg             IF_Write;
    reg             ID_stall;      

    // Control signals
    wire            IF_flush;
    wire            ID_Branch;          // ID
    wire            ID_BranchNot;       // ID
    wire            ID_Jalr;            // ID
    wire            ID_Jal;             // ID
    wire            ID_ALUSrc;          // ID->EX
    wire            ID_ALUOp;           // ID->EX
    wire            ID_MemWrite;        // ID->EX->MEM
    wire            ID_MemRead;         // ID->EX->MEM
    wire            ID_MemtoReg;        // ID->EX->MEM->WB
    wire            ID_RegWrite;        // ID->EX->MEM->WB
        
        // Control signals after hazard mux
        wire            ID_ALUSrc_h;          // ID->EX
        wire            ID_ALUOp_h;           // ID->EX
        wire            ID_MemWrite_h;        // ID->EX->MEM
        wire            ID_MemRead_h;         // ID->EX->MEM
        wire            ID_MemtoReg_h;        // ID->EX->MEM->WB
        wire            ID_RegWrite_h;        // ID->EX->MEM->WB
    
    reg             EX_ALUSrc;
    reg             EX_ALUOp;
    reg             EX_MemWrite, MEM_MemWrite;
    reg             EX_MemRead, MEM_MemRead;     
    reg             EX_MemtoReg, MEM_MemtoReg, WB_MemtoReg;
    reg             EX_RegWrite, MEM_RegWrite, WB_RegWrite;

    // ICACHE stall strategy:
    // keep doing NOP until the ICACHE is ready

    // DCACHE stall strategy:
    // keep everthing in the flipflop unchanged

    // ---------------------- Combinational part ----------------------
    // ICACHE
    assign ICACHE_ren = 1;
    assign ICACHE_wen = 0;
    assign ICACHE_addr = IF_PC[31:2];
    assign ICACHE_wdata = 0;
    
    // PC
    always@(*) begin
        // if ICACHE is not ready, keep PC the same
        if(ICACHE_stall) begin
            next_PC = IF_PC;
        end
        else if(IF_PCWrite) begin
            if(IF_flush | ID_Jal) begin
                next_PC = ID_addr;
            end
            else begin
                next_PC = IF_PC + 4;
            end
        end
        else begin
            next_PC = IF_PC;
        end
    end 
    
    // instruction
    always@(*) begin
        if(IF_flush | ICACHE_stall) begin
            // NOP: addi $r0 $r0 0 
            next_IR = 32'b00000000000000000000000000010011;
        end
        else begin 
            // Endian conversion
            next_IR = IF_Write ? {ICACHE_rdata[7:0], ICACHE_rdata[15:8], ICACHE_rdata[23:16], ICACHE_rdata[31:24]} : IR;
        end
    end
    
    // ID:
    assign funct3 = IR[14:12];
    assign opcode = IR[6:0];

    // ID: Control signals
    assign ID_Branch   = (IR[6:0] == 7'b1100011) & (funct3 == 3'b000);          // branch
    assign ID_BranchNot= (IR[6:0] == 7'b1100011) & (funct3 == 3'b001);          // branch not
    assign ID_Jal      = (IR[6:0] == 7'b1101111);          // jal
    assign ID_Jalr     = (IR[6:0] == 7'b1100111);          // jalr
    assign ID_MemRead  = (IR[6:0] == 7'b0000011);          // lw
    assign ID_MemtoReg = ID_MemRead;                          // lw
    assign ID_ALUOp    = (IR[3:0] == 4'b0011);             // R-type, Itype, beq
    assign ID_MemWrite = (IR[6:0] == 7'b0100011);          // sw
    assign ID_ALUSrc   = (IR[6:0] == 7'b0010011)           // I-type(addi, andi...)
                        || (IR[6:0] == 7'b0000011)         // lw
                        || (IR[6:0] == 7'b0100011);        // sw
    assign ID_RegWrite = (IR[6:0] == 7'b0110011)           // R-type
                        || (IR[6:0] == 7'b0010011)         // I-type(addi, andi...)
                        || (IR[6:0] == 7'b0000011)         // lw
                        || (IR[6:0] == 7'b1101111)         // jal
                        || (IR[6:0] == 7'b1100111);        // jalr
    assign IF_flush    = (ID_Branch & ID_Equal) | (ID_BranchNot & ~(ID_Equal));

    // ID: Control signals after hazard mux
    assign ID_ALUSrc_h      = ID_stall ? 0 : ID_ALUSrc;
    assign ID_ALUOp_h       = ID_stall ? 0 : ID_ALUOp;
    assign ID_MemWrite_h    = ID_stall ? 0 : ID_MemWrite;
    assign ID_MemRead_h     = ID_stall ? 0 : ID_MemRead;
    assign ID_MemtoReg_h    = ID_stall ? 0 : ID_MemtoReg;
    assign ID_RegWrite_h    = ID_stall ? 0 : ID_RegWrite;
    
    // ID: register file (read)
    always@(*)begin
        ID_busRS1 = regfile_r[ID_RS1];
        ID_busRS2 = regfile_r[ID_RS2];
    end

    // ID: register file signals
    assign ID_RS1 = IR[19:15];
    assign ID_RS2 = IR[24:20];
    assign ID_RD = IR[11:7];
    
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
        else if(opcode == 7'b0000011 || opcode == 7'b0100011) begin
            if(funct3 == 3'b010) begin
                ID_ctrl = ADD;
            end
    
        end
    end

    // ID: Branch and Jalr and Jal
    assign ID_Equal = (ID_busRS1 == ID_busRS2);
    assign ID_addr = $signed(ID_immgen) + $signed((ID_Jalr ? ID_busRS1 : ID_PC));
    
    // ID: immgen
    always@(*) begin
        if(ID_Branch)   
            ID_immgen = {{20{IR[31]}}, IR[7], IR[30:25], IR[11:8], 1'b0};
        else if(ID_Jal)
            ID_immgen = {{12{IR[31]}}, IR[19:12], IR[20], IR[30:25], IR[24:21], 1'b0};
        else if(ID_MemWrite) 
            ID_immgen = {{21{IR[31]}}, IR[30:25], IR[11:7]};
        else if(funct3 == 3'b001 | funct3 == 3'b101) 
            ID_immgen = {{27{1'b0}}, IR[24:20]};
        else 
            ID_immgen = {{21{IR[31]}}, IR[30:20]};
    end

    // EX: ALU inputs with forwarding unit
    always@(*) begin
        EX_din_1 = EX_busRS1;
        EX_din_2 = 0;
        case(ForwardA)
            ORI: EX_din_1 = EX_busRS1;
            MEM: EX_din_1 = MEM_dout;
            WB:  EX_din_1 = WB_busRD;
        endcase
        // if the 2nd input is from immgen, don't forwarding 
        if(~EX_ALUSrc) begin    
            case(ForwardB)
                ORI: EX_din_2 = EX_busRS2;
                MEM: EX_din_2 = MEM_dout;
                WB:  EX_din_2 = WB_busRD;
            endcase
        end
        else EX_din_2 = EX_immgen;
    end
    
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


    // Forwarding unit
    always@(*) begin
        // default
        ForwardA = ORI;
        ForwardB = ORI;

        // check MEM stage first because it's more recent result
        if(MEM_RegWrite & (MEM_RD != 0) & (MEM_RD == EX_RS1)) begin
            ForwardA = MEM;
        end 
        // Then check WB stage
        else if(WB_RegWrite & (WB_RD != 0) & (WB_RD == EX_RS1)) begin
            ForwardA = WB;
        end

        if(MEM_RegWrite & (MEM_RD != 0) & (MEM_RD == EX_RS2)) begin
            ForwardB = MEM;
        end 
        else if(WB_RegWrite & (WB_RD != 0) & (WB_RD == EX_RS2)) begin
            ForwardB = WB;
        end
    end

    // Hazard detection unit
    always@(*) begin
        IF_PCWrite = 1; // can write new value to PC
        IF_Write = 1;   // can write new value to IR
        ID_stall = 0;
        // lw and (RD of lw == RS1 or RS2)  (make sure that the RS2 is not immgen)
        // load use situation occurs
        if(((EX_RD == ID_RS1) | ((EX_RD == ID_RS2) & (~ID_ALUSrc))) & (EX_MemRead)) begin
            IF_PCWrite = 0;
            IF_Write = 0;
            ID_stall = 1;
        end
    end 

    // MEM: access data cache
    assign DCACHE_ren = MEM_MemRead;
    assign DCACHE_wen = MEM_MemWrite;
    assign DCACHE_addr = MEM_dout[31:2];
        // Endian Conversion
    assign DCACHE_wdata = {MEM_busRS2[7:0], MEM_busRS2[15:8], MEM_busRS2[23:16], MEM_busRS2[31:24]};

    // WB: mux
        // Endian Conversion
    assign WB_busRD = WB_MemtoReg ? {WB_DCACHE_rdata[7:0], WB_DCACHE_rdata[15:8], WB_DCACHE_rdata[23:16], WB_DCACHE_rdata[31:24]} : WB_dout;
    
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
    // PC and instruction
    always@(posedge clk) begin
        if(!rst_n) begin
            IF_PC <= 0;
            ID_PC <= 0;
            IR    <= 0;
        end
        else begin
            IF_PC <= DCACHE_stall ? IF_PC : next_PC;
            ID_PC <= DCACHE_stall ? ID_PC : IF_PC;
            IR    <= DCACHE_stall ? IR : next_IR;
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
            EX_ALUSrc       <= 0;
            EX_ALUOp        <= 0;
            EX_MemWrite     <= 0;
            EX_MemRead      <= 0;
            EX_MemtoReg     <= 0;
            EX_RegWrite     <= 0;
            
            MEM_MemWrite    <= 0;
            MEM_MemRead     <= 0;     
            MEM_MemtoReg    <= 0;
            MEM_RegWrite    <= 0;
            
            WB_MemtoReg     <= 0;
            WB_RegWrite     <= 0;
        end
        else begin
            EX_ALUSrc       <= DCACHE_stall ? EX_ALUSrc : ID_ALUSrc_h;
            EX_ALUOp        <= DCACHE_stall ? EX_ALUOp : ID_ALUOp_h;
            EX_MemWrite     <= DCACHE_stall ? EX_MemWrite : ID_MemWrite_h;
            EX_MemRead      <= DCACHE_stall ? EX_MemRead : ID_MemRead_h;
            EX_MemtoReg     <= DCACHE_stall ? EX_MemtoReg : ID_MemtoReg_h;
            EX_RegWrite     <= DCACHE_stall ? EX_RegWrite : ID_RegWrite_h;
            
            MEM_MemWrite    <= DCACHE_stall ? MEM_MemWrite : EX_MemWrite;
            MEM_MemRead     <= DCACHE_stall ? MEM_MemRead : EX_MemRead;     
            MEM_MemtoReg    <= DCACHE_stall ? MEM_MemtoReg : EX_MemtoReg;
            MEM_RegWrite    <= DCACHE_stall ? MEM_RegWrite : EX_RegWrite;
            
            // write_back -> no need to stall 
            WB_MemtoReg     <= MEM_MemtoReg;
            WB_RegWrite     <= MEM_RegWrite;
        end
    end

    // ALU-related signals & immgen
    always@(posedge clk) begin
        if(!rst_n) begin
            EX_busRS1       <= 0;
            EX_busRS2       <= 0;
            EX_ctrl         <= 0;
            EX_immgen       <= 0;
            MEM_dout        <= 0;
            MEM_busRS2      <= 0;
            WB_dout         <= 0;
        end
        else begin
            EX_busRS1       <= DCACHE_stall ? EX_busRS1 : ID_busRS1;
            EX_busRS2       <= DCACHE_stall ? EX_busRS2 : ID_busRS2;
            EX_ctrl         <= DCACHE_stall ? EX_ctrl : ID_ctrl;
            EX_immgen       <= DCACHE_stall ? EX_immgen : ID_immgen;
            MEM_dout        <= DCACHE_stall ? MEM_dout : EX_dout;
            MEM_busRS2       <= DCACHE_stall ? MEM_busRS2 : EX_busRS2;
            
            // write_back -> no need to stall 
            WB_dout         <= MEM_dout;
        end
    end

    // register-related signals
    always@(posedge clk) begin
        if(!rst_n) begin
            WB_RD           <= 0;
            MEM_RD          <= 0;
            EX_RD           <= 0;
            // forwarding unit using
            EX_RS1          <= 0;
            EX_RS2          <= 0;
            WB_DCACHE_rdata <= 0;
        end
        else begin
            WB_RD           <= MEM_RD;
            WB_DCACHE_rdata <= DCACHE_rdata;
            
            MEM_RD          <= DCACHE_stall ? MEM_RD : EX_RD;
            EX_RD           <= DCACHE_stall ? EX_RD : ID_RD;
            // forwarding unit using
            EX_RS1          <= DCACHE_stall ? EX_RS1 : ID_RS1;
            EX_RS2          <= DCACHE_stall ? EX_RS2 : ID_RS2;
        end
    end
endmodule