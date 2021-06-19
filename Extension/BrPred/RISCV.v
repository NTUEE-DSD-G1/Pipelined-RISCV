// Original RISCV (no stall cycle for jalr hazard)

module RISCV_Pipeline (
    clk           ,
    rst_n         ,
//----------I cache interface-------		
    ICACHE_ren    ,
    ICACHE_wen    ,
    ICACHE_addr   ,
    ICACHE_wdata  ,
    ICACHE_stall  ,
    ICACHE_rdata  ,
//----------D cache interface-------
    DCACHE_ren    ,
    DCACHE_wen    ,
    DCACHE_addr   ,
    DCACHE_wdata  ,
    DCACHE_stall  ,
    DCACHE_rdata
);

// --------------------------------------------
//                    INOUT
// --------------------------------------------

input            clk, rst_n;
//----------I cache interface-------		
input            ICACHE_stall;  
input  [31:0]    ICACHE_rdata;  
output           ICACHE_ren;    
output           ICACHE_wen;    
output [29:0]    ICACHE_addr;   
output [31:0]    ICACHE_wdata;  
//----------D cache interface-------
input            DCACHE_stall;  
input  [31:0]    DCACHE_rdata;
output           DCACHE_ren;    
output           DCACHE_wen;    
output [29:0]    DCACHE_addr;   
output [31:0]    DCACHE_wdata;  

// --------------------------------------------
//                    MACRO
// --------------------------------------------

parameter REG_AMOUNT = 32;

// instruction
parameter NO_OPERATION = 32'b00000000000000000000000000010011;

// alu control
parameter ALU_ADD = 4'd1;
parameter ALU_SUB = 4'd2;
parameter ALU_AND = 4'd3;
parameter ALU_OR  = 4'd4;
parameter ALU_XOR = 4'd5;
parameter ALU_SLL = 4'd6;
parameter ALU_SRA = 4'd7;
parameter ALU_SRL = 4'd8;
parameter ALU_SLT = 4'd9;
parameter ALU_NO  = 4'd0; // no operation

// data hazard
parameter NO_HAZARD   = 2'b00;
parameter EX_FORWARD  = 2'b01;
parameter MEM_FORWARD = 2'b10;
parameter WB_FORWARD  = 2'b11;

// opcode
parameter OPCODE_JAL    = 7'b1101111;
parameter OPCODE_JALR   = 7'b1100111;
parameter OPCODE_BRANCH = 7'b1100011;
parameter OPCODE_LW     = 7'b0000011;
parameter OPCODE_SW     = 7'b0100011;
parameter OPCODE_R_TYPE = 7'b0110011;
parameter OPCODE_I_TYPE = 7'b0010011;

integer i;

// --------------------------------------------
//                  REG & WIRE
// --------------------------------------------

// feedback FFs
wire [31:0] real_PC; // FIXME
reg  [29:0] PC, next_PC; // use 30 bits for PC
reg  [31:0] reg_file [0:REG_AMOUNT-1];
reg  [31:0] next_reg_file [0:REG_AMOUNT-1];

// ---------------pipeline FFs------------------

// IF/ID
reg  [31:0] ID_instr,       next_ID_instr;       // instruction
reg  [29:0] ID_PC,          next_ID_PC;          // use 30 bits for PC
wire [31:0] real_ID_PC; // FIXME
assign real_ID_PC = ID_PC << 2;

// ID/EX
reg   [4:0] EX_reg_rd,      next_EX_reg_rd;      // register rd
reg         EX_jal,         next_EX_jal;         // jal
reg         EX_jalr,        next_EX_jalr;        // jalr

reg   [3:0] EX_alu_control, next_EX_alu_control; // alu control
reg         EX_reg_write,   next_EX_reg_write;   // register write
reg         EX_mem_read,    next_EX_mem_read;    // memory read
reg         EX_mem_write,   next_EX_mem_write;   // memory write
reg signed  [31:0] EX_bus1, next_EX_bus1;        // register read bus1
reg signed  [31:0] EX_bus2, next_EX_bus2;        // register read bus2
reg   [1:0] EX_data_hazard_A, next_EX_data_hazard_A;
reg   [1:0] EX_data_hazard_B, next_EX_data_hazard_B;


// EX/MEM
reg  [31:0] MEM_alu_out,    next_MEM_alu_out;
reg   [4:0] MEM_reg_rd,     next_MEM_reg_rd;
reg         MEM_reg_write,  next_MEM_reg_write;
reg         MEM_mem_read,   next_MEM_mem_read;
reg         MEM_mem_write,  next_MEM_mem_write;

// MEM/WB
reg  [31:0] WB_wb_data,     next_WB_wb_data;
reg   [4:0] WB_reg_rd,      next_WB_reg_rd;
reg         WB_reg_write,   next_WB_reg_write;   

// ----------reg & wire in diff stages---------

// IF
wire        PC_jump; // 0 for PC+4, 1 for branch, jal, jalr

// ID
// controls
wire  [6:0] opcode;
wire  [2:0] func3;
wire  [4:0] rs1, rs2, rd;
wire        jal;
wire        jalr;
wire        beq;
wire        bne;
reg         branch_jump; // 1 for beq or bne need to jump

reg   [3:0] alu_control;
wire        reg_write;
wire        mem_read;
wire        mem_write;

reg  [31:0] imm;         // generated immediate
reg  [31:0] reg_file_r1; // read data from reg_file
reg  [31:0] reg_file_r2; // read data from reg_file
reg  [31:0] jump_addr;   // instruction address for branch, jal, jalr jumping
reg  [31:0] jump_addr_add1;
// reg  [31:0] jump_addr_adder_in1, jump_addr_adder_in2;
// wire [31:0] jump_addr_adder_out;

reg         load_use_hazard;
// reg         jalr_hazard;
reg   [2:0] ID_data_hazard_A;
reg   [2:0] ID_data_hazard_B;

// EX
reg  signed [31:0] alu_in_1;
reg  signed [31:0] alu_in_2;
reg  [31:0] alu_out;
reg  [31:0] alu_sub_result;

// Beq Prediction Unit
wire [31:0] IF_instr;
wire        IF_Jal;
reg  [31:0] IF_imm;
wire [31:0] IF_BJ_addr;         // beq, bne, jal

// --------------------------------------------
//                COMBINATIONAL
// --------------------------------------------

// -----------------IF stage-------------------

// Branch Prediction
assign IF_instr = { ICACHE_rdata[7:0], ICACHE_rdata[15:8], ICACHE_rdata[23:16], ICACHE_rdata[31:24]};
assign IF_Jal = (IF_instr[6:0] == OPCODE_JAL);
assign IF_BJ_addr = $signed(PC << 2) + $signed(IF_imm); 
always@(*) begin
    IF_imm = { {12{IF_instr[31]}}, IF_instr[19:12], IF_instr[20], IF_instr[30:25], IF_instr[24:21], 1'b0};
end

assign real_PC = PC << 2; // FIXME
// read I-CACHE
assign ICACHE_ren   = 1'b1;
assign ICACHE_wen   = 1'b0;
assign ICACHE_addr  = PC;
assign ICACHE_wdata = 32'd0;

assign PC_jump = branch_jump | jalr;
always @(*) begin
    next_PC = PC;
    if (ICACHE_stall || DCACHE_stall || load_use_hazard) begin
        next_PC = PC;
    end
    else if(branch_jump || jalr)begin
        next_PC = jump_addr[31:2];
    end
    else if(IF_Jal) begin
        next_PC = IF_BJ_addr[31:2];
    end
    else next_PC = jump_addr[31:2];
end

// IF/ID FFs
always @(*) begin
    if (ICACHE_stall || DCACHE_stall || load_use_hazard) begin
        next_ID_PC = ID_PC;
        next_ID_instr = ID_instr;
    end
    else if (PC_jump) begin
        next_ID_PC = 0;
        next_ID_instr = NO_OPERATION;
    end
    else begin
        next_ID_PC = PC;
        next_ID_instr = { ICACHE_rdata[7:0],   ICACHE_rdata[15:8], 
                          ICACHE_rdata[23:16], ICACHE_rdata[31:24] };
    end
end

// -----------------ID stage-------------------

// decode instruction
assign opcode = ID_instr[ 6: 0];
assign func3  = ID_instr[14:12];
assign rs1    = ID_instr[19:15];
assign rs2    = ID_instr[24:20];
assign rd     = ID_instr[11: 7];

assign jal    = (opcode == OPCODE_JAL);
assign jalr   = (opcode == OPCODE_JALR);
assign beq    = (opcode == OPCODE_BRANCH) & (func3 == 3'b000);
assign bne    = (opcode == OPCODE_BRANCH) & (func3 == 3'b001);

assign reg_write  = (opcode == OPCODE_R_TYPE)
                  | (opcode == OPCODE_I_TYPE)
                  | (opcode == OPCODE_LW)
                  | (opcode == OPCODE_JAL)
                  | (opcode == OPCODE_JALR);
assign mem_read   = (opcode == OPCODE_LW);
assign mem_write  = (opcode == OPCODE_SW);

// alu control
always @(*) begin
    if (opcode == OPCODE_R_TYPE) begin
        case(func3)
            3'b000:  alu_control = ID_instr[30] ? ALU_SUB : ALU_ADD;
            3'b010:  alu_control = ALU_SLT;
            3'b100:  alu_control = ALU_XOR;
            3'b110:  alu_control = ALU_OR;
            3'b111:  alu_control = ALU_AND;
            default: alu_control = ALU_NO;
        endcase
    end
    else if (opcode == OPCODE_I_TYPE) begin
        case(func3)
            3'b000:  alu_control = ALU_ADD;
            3'b001:  alu_control = ALU_SLL;
            3'b010:  alu_control = ALU_SLT;
            3'b100:  alu_control = ALU_XOR;
            3'b101:  alu_control = ID_instr[30] ? ALU_SRA : ALU_SRL;
            3'b110:  alu_control = ALU_OR;
            3'b111:  alu_control = ALU_AND;
            default: alu_control = ALU_NO;
        endcase
    end
    else if (jal || jalr || mem_read || mem_write) begin // jal, jalr, lw, sw
        alu_control = ALU_ADD;
    end
    else alu_control = ALU_NO;
end

// detect load-use hazard
always @(*) begin
    load_use_hazard = 1'b0;
    if (EX_mem_read) begin // lw
        if (opcode == OPCODE_R_TYPE) begin // R-type
            if (EX_reg_rd == rs1 || EX_reg_rd == rs2) begin
                load_use_hazard = 1'b1;
            end
        end
        else if (opcode == OPCODE_I_TYPE || mem_read || mem_write || jalr) begin // I-type
            if (EX_reg_rd == rs1) begin
                load_use_hazard = 1'b1;
            end
        end
    end
end

// detect jalr hazard
// always @(*) begin
//     jalr_hazard = 1'b0;
//     // if (!load_use_hazard) begin
//         if (jalr) begin
//             // ID_data_hazard_A == EX_FORWARD
//             if (EX_reg_rd != 0 && EX_reg_rd == rs1 && !EX_mem_read && EX_reg_write) begin
//                 jalr_hazard = 1'b1;
//             end
//             // ex: lw + jalr, critical path will be Dcache in >> Dcache hit >> Dcache_rdata >> PC adder
//             // ID_data_hazard_A == MEM_FORWARD && MEM_mem_read
//             else if ((MEM_reg_rd != 0 && MEM_reg_rd == rs1 && MEM_reg_write) && MEM_mem_read) begin
//                 jalr_hazard = 1'b1;
//             end
//         end
//         else if (beq || bne) begin
//             // ID_data_hazard_A == EX_FORWARD || ID_data_hazard_B == EX_FORWARD
//             if ((EX_reg_rd != 0 && EX_reg_rd == rs1 && !EX_mem_read && EX_reg_write) ||
//                 (EX_reg_rd != 0 && EX_reg_rd == rs2 && !EX_mem_read && EX_reg_write)) begin
//                 jalr_hazard = 1'b1;
//             end
//             // ex: lw + jalr, critical path will be Dcache in >> Dcache hit >> Dcache_rdata >> PC adder
//             // (ID_data_hazard_A == MEM_FORWARD || ID_data_hazard_B == MEM_FORWARD) && MEM_mem_read
//             else if (((MEM_reg_rd != 0 && MEM_reg_rd == rs1 && MEM_reg_write) ||
//                       (MEM_reg_rd != 0 && MEM_reg_rd == rs2 && MEM_reg_write)) && MEM_mem_read) begin
//                 jalr_hazard = 1'b1;
//             end
//         end
//     //end
// end

// immediate generate
always @(*) begin
    if (beq | bne) begin // branch equal or branch not equal
        imm = { {20{ID_instr[31]}}, ID_instr[7],
               ID_instr[30:25], ID_instr[11:8], 1'b0 };
    end
    // else if (jal)  begin // jal
    //     imm = { {12{ID_instr[31]}}, ID_instr[19:12], 
    //             ID_instr[20], ID_instr[30:25], ID_instr[24:21], 1'b0};
    // end
    else if (mem_write)  begin // sw
        imm = {{21{ID_instr[31]}}, ID_instr[30:25], ID_instr[11:7]};
    end
    else if (func3 == 3'b001 | func3 == 3'b101) begin // SRAI, SRLI, SLLI
        imm = {{27{1'b0}}, ID_instr[24:20]};
    end
    else begin // rest I-type, lw, sw, jalr
        imm = {{21{ID_instr[31]}}, ID_instr[30:20]};
    end
end

// register file
always @(*) begin
    // in, WB stage
    for (i = 0; i < REG_AMOUNT; i=i+1) begin
        next_reg_file[i] = reg_file[i];
    end
    if (WB_reg_write && WB_reg_rd != 0) begin
        next_reg_file[WB_reg_rd] = WB_wb_data;
    end
end

// detect ID data hazard
always@ (*) begin
    if (EX_reg_rd != 0 && EX_reg_rd == rs1 && !EX_mem_read && EX_reg_write) begin // FIXME->this line can be deleted
        ID_data_hazard_A = EX_FORWARD;
    end
    else if (MEM_reg_rd != 0 && MEM_reg_rd == rs1 && MEM_reg_write) begin
        ID_data_hazard_A = MEM_FORWARD;
    end
    else if (WB_reg_rd != 0 && WB_reg_rd == rs1 && WB_reg_write) begin
        ID_data_hazard_A = WB_FORWARD;
    end
    else begin
        ID_data_hazard_A = NO_HAZARD;
    end

    if (EX_reg_rd != 0 && EX_reg_rd == rs2 && !EX_mem_read && EX_reg_write) begin // FIXME->this line can be deleted
        ID_data_hazard_B = EX_FORWARD;
    end
    else if (MEM_reg_rd != 0 && MEM_reg_rd == rs2 && MEM_reg_write) begin
        ID_data_hazard_B = MEM_FORWARD;
    end
    else if (WB_reg_rd != 0 && WB_reg_rd == rs2 && WB_reg_write) begin
        ID_data_hazard_B = WB_FORWARD;
    end
    else begin
        ID_data_hazard_B = NO_HAZARD;
    end
end

// forwarding
always @(*) begin // FIXME:  only consider WB_FORWARD
    case(ID_data_hazard_A)
        NO_HAZARD:   reg_file_r1 = reg_file[rs1];
        EX_FORWARD:  reg_file_r1 = alu_out;
        MEM_FORWARD: reg_file_r1 = next_WB_wb_data;
        WB_FORWARD:  reg_file_r1 = WB_wb_data;
        default:     reg_file_r1 = reg_file[rs1];
    endcase

    case(ID_data_hazard_B)
        NO_HAZARD:   reg_file_r2 = reg_file[rs2];
        EX_FORWARD:  reg_file_r2 = alu_out;
        MEM_FORWARD: reg_file_r2 = next_WB_wb_data;
        WB_FORWARD:  reg_file_r2 = WB_wb_data;
        default:     reg_file_r2 = reg_file[rs2];
    endcase
end

// branch jump and jal, jalr
reg  [31:0] cmp_in_1, cmp_in_2;
wire        cmp_out;
assign cmp_out = cmp_in_1 == cmp_in_2;
always @(*) begin
    branch_jump = ((beq && cmp_out) || (bne && !cmp_out));
    cmp_in_1 = 0;
    cmp_in_2 = 0;
    if (beq || bne) begin
        case(ID_data_hazard_A)
            EX_FORWARD:  cmp_in_1 = alu_out;
            MEM_FORWARD: cmp_in_1 = MEM_alu_out;
            WB_FORWARD:  cmp_in_1 = WB_wb_data;
            default:     cmp_in_1 = reg_file[rs1];
        endcase
        case(ID_data_hazard_B)
            EX_FORWARD:  cmp_in_2 = alu_out;
            MEM_FORWARD: cmp_in_2 = MEM_alu_out;
            WB_FORWARD:  cmp_in_2 = WB_wb_data;
            default:     cmp_in_2 = reg_file[rs2];
        endcase
    end
end
// assign branch_jump = !jalr_hazard &&
//                      ((beq && (reg_file_r1 == reg_file_r2)) ||
//                      (bne && (reg_file_r1 != reg_file_r2)));

// jump address
// assign jump_addr_adder_out = jump_addr_adder_in1 + jump_addr_adder_in2;
reg  [31:0]  branch_jal_addr, default_addr;
wire [31:0] jalr_addr;
assign jalr_addr = $signed(jump_addr_add1) + $signed(imm);
always @(*) begin
    // jump_addr = jump_addr_adder_out;
    branch_jal_addr = $signed(ID_PC << 2) + $signed(imm);

    case(ID_data_hazard_A)
        EX_FORWARD:  jump_addr_add1 = alu_out;
        MEM_FORWARD: jump_addr_add1 = MEM_alu_out;
        WB_FORWARD:  jump_addr_add1 = WB_wb_data;
        default:     jump_addr_add1 = reg_file[rs1];
    endcase
    // if(MEM_reg_rd != 0 && MEM_reg_rd == rs1 && MEM_reg_write) jump_addr_add1 = MEM_alu_out;
    // else if(WB_reg_rd != 0 && WB_reg_rd == rs1 && WB_reg_write) jump_addr_add1 =  WB_wb_data;
    // else jump_addr_add1 = reg_file[rs1];

    default_addr = $signed(PC << 2) + 4;

    if (branch_jump) begin
        jump_addr = branch_jal_addr;
    end
    else if (jalr) begin
        jump_addr = jalr_addr;
    end
    else begin
        jump_addr = default_addr;
    end
end

// detect EX data hazard from ID stage
always @(*) begin
    if (DCACHE_stall) begin
        next_EX_data_hazard_A = EX_data_hazard_A;
        next_EX_data_hazard_B = EX_data_hazard_B;
    end
    else if (load_use_hazard || ICACHE_stall) begin
        next_EX_data_hazard_A = NO_HAZARD;
        next_EX_data_hazard_B = NO_HAZARD;
    end
    else begin
        // R-type, I-type, lw, sw will use R[rs1] as input of ALU
        if (EX_reg_write && (EX_reg_rd != 0) && (EX_reg_rd == rs1) &&
            (opcode == OPCODE_R_TYPE || opcode == OPCODE_I_TYPE || mem_read || mem_write)) begin
            next_EX_data_hazard_A = MEM_FORWARD;
        end
        else if (MEM_reg_write && (MEM_reg_rd != 0) && (MEM_reg_rd == rs1) &&
            (opcode == OPCODE_R_TYPE || opcode == OPCODE_I_TYPE || mem_read || mem_write)) begin
            next_EX_data_hazard_A = WB_FORWARD;
        end
        else begin
            next_EX_data_hazard_A = NO_HAZARD;
        end

        // R-type will use R[rs2] as input of ALU
        if (EX_reg_write && (EX_reg_rd != 0) && (EX_reg_rd == rs2) && (opcode == OPCODE_R_TYPE)) begin
            next_EX_data_hazard_B = MEM_FORWARD;
        end
        else if (MEM_reg_write && (MEM_reg_rd != 0) && (MEM_reg_rd == rs2) && (opcode == OPCODE_R_TYPE)) begin
            next_EX_data_hazard_B = WB_FORWARD;
        end
        else begin
            next_EX_data_hazard_B = NO_HAZARD;
        end
    end
    
end

// ID/EX FFs
always @(*) begin
    next_EX_jal         = DCACHE_stall    ? EX_jal         : // DCACHE_stall >> do again
                          load_use_hazard || ICACHE_stall ? 0              : // load use hazard >> bubble
                          jal;
    next_EX_jalr        = DCACHE_stall    ? EX_jalr        : 
                          load_use_hazard || ICACHE_stall ? 0              :
                          jalr;
    next_EX_alu_control = DCACHE_stall    ? EX_alu_control :
                          load_use_hazard || ICACHE_stall ? ALU_NO         :
                          alu_control;
    next_EX_reg_write   = DCACHE_stall    ? EX_reg_write   :
                          load_use_hazard || ICACHE_stall ? 0              :
                          reg_write;
    next_EX_mem_read    = DCACHE_stall    ? EX_mem_read    :
                          load_use_hazard || ICACHE_stall ? 0              :
                          mem_read;
    next_EX_mem_write   = DCACHE_stall    ? EX_mem_write   :
                          load_use_hazard || ICACHE_stall ? 0              :
                          mem_write;

    // rd
    if (DCACHE_stall) begin
        next_EX_reg_rd = EX_reg_rd;
    end
    else if (mem_write) begin // sw
        next_EX_reg_rd = rs2;
    end
    else begin
        next_EX_reg_rd = rd;
    end

    // bus1 & bus2
    if (DCACHE_stall) begin
        next_EX_bus1 = EX_bus1;
        next_EX_bus2 = EX_bus2;
    end
    else if (jal || jalr) begin // use 30 bits for PC
        next_EX_bus1 = ID_PC << 2; // extend 30 bits PC to 32 bits
        next_EX_bus2 = 32'd4;
    end
    else if (opcode == OPCODE_R_TYPE) begin // R-type
        next_EX_bus1 = reg_file_r1;
        next_EX_bus2 = reg_file_r2;
    end
    else begin // I-type & lw & sw
        next_EX_bus1 = reg_file_r1;
        next_EX_bus2 = imm;
    end
end

// -----------------EX stage-------------------

// handle alu_in for hazard
always @(*) begin
    case (EX_data_hazard_A)
        NO_HAZARD:   alu_in_1 = EX_bus1;
        MEM_FORWARD: alu_in_1 = MEM_alu_out;
        WB_FORWARD:  alu_in_1 = WB_wb_data;
        default:     alu_in_1 = EX_bus1;
    endcase
    case (EX_data_hazard_B)
        NO_HAZARD:   alu_in_2 = EX_bus2;
        MEM_FORWARD: alu_in_2 = MEM_alu_out;
        WB_FORWARD:  alu_in_2 = WB_wb_data;
        default:     alu_in_2 = EX_bus2;
    endcase
end

// ALU
always @(*) begin
    alu_sub_result = alu_in_1 - alu_in_2;
    case(EX_alu_control)
        ALU_ADD: alu_out = alu_in_1 + alu_in_2;
        ALU_SUB: alu_out = alu_sub_result;
        ALU_AND: alu_out = alu_in_1 & alu_in_2;
        ALU_OR : alu_out = alu_in_1 | alu_in_2;
        ALU_XOR: alu_out = alu_in_1 ^ alu_in_2;
        ALU_SLL: alu_out = alu_in_1 << alu_in_2;
        ALU_SRA: alu_out = alu_in_1 >>> alu_in_2;
        ALU_SRL: alu_out = alu_in_1 >> alu_in_2;
        ALU_SLT: alu_out = (alu_sub_result[31]) ? 32'b1 : 32'b0;
        default: alu_out = 32'b0;
    endcase
end

// EX/MEM FFs
always @(*) begin
    next_MEM_alu_out    = DCACHE_stall ? MEM_alu_out   : alu_out;
    next_MEM_reg_rd     = DCACHE_stall ? MEM_reg_rd    : EX_reg_rd;
    next_MEM_reg_write  = DCACHE_stall ? MEM_reg_write : EX_reg_write;
    next_MEM_mem_read   = DCACHE_stall ? MEM_mem_read  : EX_mem_read;
    next_MEM_mem_write  = DCACHE_stall ? MEM_mem_write : EX_mem_write;
end

// -----------------MEM stage-------------------

// read/write DCACHE
assign DCACHE_ren   = MEM_mem_read;
assign DCACHE_wen   = MEM_mem_write;
assign DCACHE_addr  = MEM_alu_out[31:2];
assign DCACHE_wdata = { reg_file[MEM_reg_rd][7:0]  , reg_file[MEM_reg_rd][15:8],
                        reg_file[MEM_reg_rd][23:16], reg_file[MEM_reg_rd][31:24] }; // FIXME


wire  [31:0] answer;
assign answer = reg_file[MEM_reg_rd];

// MEM/WB FFs
always @(*) begin
    if (MEM_mem_read) begin // lw
        next_WB_wb_data = { DCACHE_rdata[7:0]  , DCACHE_rdata[15:8],
                            DCACHE_rdata[23:16], DCACHE_rdata[31:24] };
    end
    else begin
        next_WB_wb_data = MEM_alu_out;
    end
    next_WB_reg_rd = MEM_reg_rd;
    next_WB_reg_write = MEM_reg_write;
end

// -----------------WB stage-------------------

// write data back to reg_file
// implemented in ID stage

// --------------------------------------------
//                 SEQUENTIAL
// --------------------------------------------
// feedback FFs

always @(posedge clk) begin
    if (~rst_n) begin
        for (i = 0; i < REG_AMOUNT; i=i+1) begin
            reg_file[i] <= 32'd0;
        end
        PC <= 30'd0;
    end
    else begin
        reg_file[0] <= 32'd0;
        for (i = 1; i < REG_AMOUNT; i=i+1) begin
            reg_file[i] <= next_reg_file[i];
        end
        PC <= next_PC;
    end
end

// pipeline FFs
always @(posedge clk) begin
    if (~rst_n) begin
        ID_instr       <= 32'd0;
        ID_PC          <= 30'd0;

        EX_reg_rd      <= 5'd0;
        EX_jal         <= 1'd0;
        EX_jalr        <= 1'd0;
        EX_alu_control <= 4'd0;
        EX_reg_write   <= 1'd0;
        EX_mem_read    <= 1'd0;
        EX_mem_write   <= 1'd0;
        EX_bus1        <= 32'd0;
        EX_bus2        <= 32'd0;
        EX_data_hazard_A <= 2'd0;
        EX_data_hazard_B <= 2'd0;

        MEM_alu_out    <= 32'd0;
        MEM_reg_rd     <= 5'd0;
        MEM_reg_write  <= 1'd0;
        MEM_mem_read   <= 1'd0;
        MEM_mem_write  <= 1'd0;

        WB_wb_data     <= 32'd0;
        WB_reg_rd      <= 5'd0;
        WB_reg_write   <= 1'd0;
    end
    else begin
        ID_instr       <= next_ID_instr;
        ID_PC          <= next_ID_PC;

        EX_reg_rd      <= next_EX_reg_rd;
        EX_jal         <= next_EX_jal;
        EX_jalr        <= next_EX_jalr;
        EX_alu_control <= next_EX_alu_control;
        EX_reg_write   <= next_EX_reg_write;
        EX_mem_read    <= next_EX_mem_read;
        EX_mem_write   <= next_EX_mem_write;
        EX_bus1        <= next_EX_bus1;
        EX_bus2        <= next_EX_bus2;
        EX_data_hazard_A <= next_EX_data_hazard_A;
        EX_data_hazard_B <= next_EX_data_hazard_B;

        MEM_alu_out    <= next_MEM_alu_out;
        MEM_reg_rd     <= next_MEM_reg_rd;
        MEM_reg_write  <= next_MEM_reg_write;
        MEM_mem_read   <= next_MEM_mem_read;
        MEM_mem_write  <= next_MEM_mem_write;

        WB_wb_data     <= next_WB_wb_data;
        WB_reg_rd      <= next_WB_reg_rd;
        WB_reg_write   <= next_WB_reg_write;
    end
    
end

endmodule