//------------------------------------------------------------------------------
//ALU运算单元（最底层模块）
//------------------------------------------------------------------------------

module ALU_8(
    output reg [31:0] ALUResult,
    output reg Zero, // 结果为0时置1（支持beq）
    input [31:0] A,
    input [31:0] B,
    input [3:0] ALU_OP
);
    always @(*) begin
        case (ALU_OP)
            4'b0000: ALUResult = A & B;          // and（课件ALU_OP=0）
            4'b0001: ALUResult = A | B;          // or（课件ALU_OP=1）
            4'b0100: ALUResult = A + B;          // add（课件ALU_OP=5）
            4'b0101: ALUResult = A - B;          // sub（课件ALU_OP=6）
            4'b0110: ALUResult = (A < B) ? 32'h00000001 : 32'h00000000; // slt
            default: ALUResult = 32'h00000000;   // 默认加法
        endcase
        Zero = (ALUResult == 32'h00000000) ? 1'b1 : 1'b0;
    end
endmodule


//------------------------------------------------------------------------------
//寄存器组
//------------------------------------------------------------------------------

module RegFile(
    input clk,
    input RegWrite,
    input [4:0] Rs,
    input [4:0] Rt,
    input [4:0] WriteReg,
    input [31:0] WriteData,
    output reg [31:0] ReadData1,
    output reg [31:0] ReadData2
);
    reg [31:0] regs [0:31]; // 32个32位寄存器，0号恒为0

    // 初始化：0号寄存器置0，其余初始化为0
        integer i;
    initial begin

        for (i = 0; i < 32; i = i + 1) begin
            regs[i] = 32'h00000000;
        end
    end

    // 异步读：Rs/Rt对应寄存器值，0号强制为0
    always @(*) begin
        ReadData1 = (Rs == 5'b00000) ? 32'h00000000 : regs[Rs];
        ReadData2 = (Rt == 5'b00000) ? 32'h00000000 : regs[Rt];
    end

    // 同步写：上升沿触发，0号寄存器不可写
    always @(posedge clk) begin
        if (RegWrite && WriteReg != 5'b00000) begin
            regs[WriteReg] <= WriteData;
            $display("Time=%0t: RegFile Write: $%d = %h", $time, WriteReg, WriteData);
        end
    end
endmodule


//-------------------------------------------------------------------------------------------
//指令存储器
//-----------------------------------------------------------------------------------------------------

module IMem(
    input [31:0] addr,
    output reg [31:0] instr
);
    reg [31:0] mem [0:63]; // 64字容量（字节地址0~255）

    // 初始化测试指令序列（包含所有要求指令）
            integer i;
    initial begin
        mem[0]  = 32'h20010005; // addi $1, $0, 5    # $1=5
        mem[1]  = 32'h20020003; // addi $2, $0, 3    # $2=3
        mem[2]  = 32'h00221020; // add $2, $1, $2    # $2=5+3=8（R型）
        mem[3]  = 32'h00221822; // sub $3, $1, $2    # $3=5-8=-3（R型）
        mem[4]  = 32'h20640002; // addi $4, $3, 2    # $4=-3+2=-1
        mem[5]  = 32'hAC040008; // sw $4, 8($0)      # 数据存地址8
        mem[6]  = 32'h8C050008; // lw $5, 8($0)      # 从地址8读数据到$5
        mem[7]  = 32'h10250002; // beq $1, $5, 2     # $1≠$5，不跳转
        mem[8]  = 32'h00000000; // nop               # 空指令
        mem[9]  = 32'h08000000; // j 0               # 无条件跳转到地址0
        // 其余地址填充nop

        for (i = 10; i < 64; i = i + 1) begin
            mem[i] = 32'h00000000;
        end
    end

    // 异步读取：字节地址转字地址（取低6位）
    always @(*) begin
        instr = mem[addr[7:2]];
    end
endmodule


//------------------------------------------------------------------------------
//数据存储器
//------------------------------------------------------------------------------

module DMem(
    input clk,
    input MemWrite,
    input [31:0] addr,
    input [31:0] WriteData,
    output reg [31:0] ReadData
);
    reg [31:0] mem [0:63]; // 64字容量（字节地址0~255）

    // 初始化：所有单元置0
            integer i;
    initial begin

        for (i = 0; i < 64; i = i + 1) begin
            mem[i] = 32'h00000000;
        end
    end

    // 异步读：字节地址转字地址
    always @(*) begin
        ReadData = mem[addr[7:2]];
    end

    // 同步写：上升沿触发，MemWrite有效时写
    always @(posedge clk) begin
        if (MemWrite) begin
            mem[addr[7:2]] <= WriteData;
            $display("Time=%0t: DMem Write: addr=%h, data=%h", $time, addr, WriteData);
        end
    end
endmodule





//------------------------------------------------------------------------------
//主译码器
//------------------------------------------------------------------------------

module MainDec(
    input [5:0] Op, Funct,
    output MemToReg, MemWrite,
    output Branch, ALUSrc,
    output RegDst, RegWrite,
    output Jump,
    output [1:0] ALUOp
);
    reg [8:0] Controls; // {RegWrite, RegDst, ALUSrc, Branch, MemWrite, MemToReg, Jump, ALUOp[1:0]}
    assign {RegWrite, RegDst, ALUSrc, Branch, MemWrite, MemToReg, Jump, ALUOp} = Controls;

    always@(*) begin
        case(Op)
            6'b000000: begin // R型指令（add/sub/nop）
                if (Funct == 6'b000000) Controls <= 9'b000000000; // nop：全0
                else Controls <= 9'b110000010; // add/sub：RegWrite=1, RegDst=1, ALUOp=10
            end
            6'b001000: Controls <= 9'b101000000; // addi：RegWrite=1, ALUSrc=1, ALUOp=00
            6'b100011: Controls <= 9'b101001000; // lw：RegWrite=1, ALUSrc=1, MemToReg=1, ALUOp=00
            6'b101011: Controls <= 9'b001010000; // sw：MemWrite=1, ALUSrc=1, ALUOp=00
            6'b000100: Controls <= 9'b000100001; // beq：Branch=1, ALUOp=01
            6'b000010: Controls <= 9'b000000100; // j：Jump=1, ALUOp=00
            default: Controls <= 9'b000000000; // 默认nop
        endcase
    end
endmodule




//------------------------------------------------------------------------------
//ALU译码器
//------------------------------------------------------------------------------

module ALUDec(
    input [5:0] Funct,
    input [1:0] ALUOp,
    output reg [2:0] ALUControl
);
    always@(*) begin
        case(ALUOp)
            2'b00: ALUControl <= 3'b010; // 加法（lw/sw/addi）
            2'b01: ALUControl <= 3'b110; // 减法（beq）
            2'b10: begin // R型指令：按Funct译码
                case(Funct)
                    6'b100000: ALUControl <= 3'b010; // add
                    6'b100010: ALUControl <= 3'b110; // sub
                    6'b100100: ALUControl <= 3'b000; // and
                    6'b100101: ALUControl <= 3'b001; // or
                    6'b101010: ALUControl <= 3'b111; // slt
                    default: ALUControl <= 3'b010; // 默认加法
                endcase
            end
            default: ALUControl <= 3'b010; // 默认加法
        endcase
    end
endmodule




//------------------------------------------------------------------------------
//顶层控制单元（调用MainDec和ALUDec）
//------------------------------------------------------------------------------

module Controller(
    input [5:0] Op, Funct,
    output MemToReg, MemWrite,
    output ALUSrc, RegDst, RegWrite,
    output Jump, Branch,
    output [2:0] ALUControl
);
    wire [1:0] ALUOp;

    // 实例化主译码器和ALU译码器
    MainDec MainDec_1(
        Op, Funct,
        MemToReg, MemWrite,
        Branch, ALUSrc,
        RegDst, RegWrite,
        Jump, ALUOp
    );

    ALUDec ALUDec_1(
        Funct, ALUOp,
        ALUControl
    );
endmodule





//------------------------------------------------------------------------------
//流水线寄存器1（IF到ID)
//------------------------------------------------------------------------------

module IF_ID_Reg(
    input clk, reset, flush,
    input Stall,
    input [31:0] PC_plus_4_IF, Instruction_IF,
    output reg [31:0] PC_plus_4_ID, Instruction_ID
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            PC_plus_4_ID <= 0;
            Instruction_ID <= 0;
        end else if (flush) begin // 刷新：插入nop
            PC_plus_4_ID <= 0;
            Instruction_ID <= 32'h00000000;
        end else if (!Stall) begin // 不停顿则传递数据
            PC_plus_4_ID <= PC_plus_4_IF;
            Instruction_ID <= Instruction_IF;
        end
    end
endmodule




//------------------------------------------------------------------------------
//流水线寄存器2（ID到EX）
//------------------------------------------------------------------------------

module ID_EX_Reg(
    input clk, reset,
    input Stall, Flush,
    input [31:0] PC_plus_4_ID, ReadData1_ID, ReadData2_ID, SignExtImm_ID,
    input [4:0] Rs_ID, Rt_ID, Rd_ID,
    input RegWrite_ID, MemToReg_ID, MemWrite_ID, ALUSrc_ID, RegDst_ID, Branch_ID,
    input [2:0] ALUControl_ID,
    output reg [31:0] PC_plus_4_EX, ReadData1_EX, ReadData2_EX, SignExtImm_EX,
    output reg [4:0] Rs_EX, Rt_EX, Rd_EX,
    output reg RegWrite_EX, MemToReg_EX, MemWrite_EX, ALUSrc_EX, RegDst_EX, Branch_EX,
    output reg [2:0] ALUControl_EX
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            PC_plus_4_EX <= 0; ReadData1_EX <= 0; ReadData2_EX <= 0; SignExtImm_EX <= 0;
            Rs_EX <= 0; Rt_EX <= 0; Rd_EX <= 0;
            RegWrite_EX <= 0; MemToReg_EX <= 0; MemWrite_EX <= 0; ALUSrc_EX <= 0; RegDst_EX <= 0; Branch_EX <= 0;
            ALUControl_EX <= 0;
        end else if (Flush) begin // 刷新：仅清零控制信号
            RegWrite_EX <= 0; MemToReg_EX <= 0; MemWrite_EX <= 0; ALUSrc_EX <= 0; RegDst_EX <= 0; Branch_EX <= 0;
            ALUControl_EX <= 0;
        end else if (!Stall) begin // 不停顿则传递所有信号
            PC_plus_4_EX <= PC_plus_4_ID; ReadData1_EX <= ReadData1_ID; ReadData2_EX <= ReadData2_ID; SignExtImm_EX <= SignExtImm_ID;
            Rs_EX <= Rs_ID; Rt_EX <= Rt_ID; Rd_EX <= Rd_ID;
            RegWrite_EX <= RegWrite_ID; MemToReg_EX <= MemToReg_ID; MemWrite_EX <= MemWrite_ID; ALUSrc_EX <= ALUSrc_ID; RegDst_EX <= RegDst_ID; Branch_EX <= Branch_ID;
            ALUControl_EX <= ALUControl_ID;
        end
    end
endmodule






//------------------------------------------------------------------------------
//流水线寄存器3（EX到MEM)
//------------------------------------------------------------------------------


module EX_MEM_Reg(
    input clk, reset,
    input [31:0] ALUResult_EX, WriteData_EX, PC_plus_4_EX,
    input [4:0] WriteReg_EX,
    input RegWrite_EX, MemToReg_EX, MemWrite_EX,
    output reg [31:0] ALUResult_MEM, WriteData_MEM, PC_plus_4_MEM,
    output reg [4:0] WriteReg_MEM,
    output reg RegWrite_MEM, MemToReg_MEM, MemWrite_MEM
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ALUResult_MEM <= 0; WriteData_MEM <= 0; PC_plus_4_MEM <= 0; WriteReg_MEM <= 0;
            RegWrite_MEM <= 0; MemToReg_MEM <= 0; MemWrite_MEM <= 0;
        end else begin // 时钟上升沿直接传递
            ALUResult_MEM <= ALUResult_EX; WriteData_MEM <= WriteData_EX; PC_plus_4_MEM <= PC_plus_4_EX; WriteReg_MEM <= WriteReg_EX;
            RegWrite_MEM <= RegWrite_EX; MemToReg_MEM <= MemToReg_EX; MemWrite_MEM <= MemWrite_EX;
        end
    end
endmodule








//------------------------------------------------------------------------------
//流水线寄存器4（MEM到WB）
//------------------------------------------------------------------------------

module MEM_WB_Reg(
    input clk, reset,
    input [31:0] ALUResult_MEM, ReadData_MEM, PC_plus_4_MEM,
    input [4:0] WriteReg_MEM,
    input RegWrite_MEM, MemToReg_MEM,
    output reg [31:0] ALUResult_WB, ReadData_WB, PC_plus_4_WB,
    output reg [4:0] WriteReg_WB,
    output reg RegWrite_WB, MemToReg_WB
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ALUResult_WB <= 0; ReadData_WB <= 0; PC_plus_4_WB <= 0; WriteReg_WB <= 0;
            RegWrite_WB <= 0; MemToReg_WB <= 0;
        end else begin // 时钟上升沿直接传递
            ALUResult_WB <= ALUResult_MEM; ReadData_WB <= ReadData_MEM; PC_plus_4_WB <= PC_plus_4_MEM; WriteReg_WB <= WriteReg_MEM;
            RegWrite_WB <= RegWrite_MEM; MemToReg_WB <= MemToReg_MEM;
        end
    end
endmodule






//------------------------------------------------------------------------------
//前推单元
//------------------------------------------------------------------------------


module ForwardingUnit(
    input [4:0] Rs_EX, Rt_EX,
    input [4:0] WriteReg_MEM, WriteReg_WB,
    input RegWrite_MEM, RegWrite_WB,
    input MemToReg_MEM, MemToReg_WB,
    output reg [1:0] ForwardA, ForwardB
);
    always @(*) begin
        // 前推ALU_A（Rs_EX）：MEM阶段优先于WB阶段
        if (Rs_EX != 0 && Rs_EX == WriteReg_MEM && RegWrite_MEM) begin
            ForwardA = 2'b10; // 数据来自MEM阶段
        end else if (Rs_EX != 0 && Rs_EX == WriteReg_WB && RegWrite_WB) begin
            ForwardA = 2'b01; // 数据来自WB阶段
        end else begin
            ForwardA = 2'b00; // 无前置
        end

        // 前推ALU_B（Rt_EX）：同ALU_A逻辑
        if (Rt_EX != 0 && Rt_EX == WriteReg_MEM && RegWrite_MEM) begin
            ForwardB = 2'b10;
        end else if (Rt_EX != 0 && Rt_EX == WriteReg_WB && RegWrite_WB) begin
            ForwardB = 2'b01;
        end else begin
            ForwardB = 2'b00;
        end
    end
endmodule



//------------------------------------------------------------------------------
//冒险检测单元
//------------------------------------------------------------------------------


module HazardDetectionUnit(
    input clk, reset,
    input [4:0] Rs_ID, Rt_ID,
    input MemToReg_EX,
    input [4:0] WriteReg_EX,
    input Branch_EX, Jump_ID, PCSrc_EX,
    output reg Stall, Flush
);
    reg [1:0] stall_cnt;
    wire ctrl_hazard = PCSrc_EX || Jump_ID; // 控制冒险：分支成功或跳转
    // 数据冒险：lw指令后立即使用其结果（排除控制冒险）
    wire lw_hazard = MemToReg_EX && WriteReg_EX != 0 &&
                    (Rs_ID == WriteReg_EX || Rt_ID == WriteReg_EX) &&
                    !ctrl_hazard;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            stall_cnt <= 2'b00;
            Stall <= 0;
            Flush <= 0;
        end else begin
            // 控制冒险：立即刷新流水线
            if (ctrl_hazard) begin
                Stall <= 0;
                Flush <= 1;
                stall_cnt <= 2'b00;
            end
            // lw数据冒险：停顿2周期（等待内存读完成）
            else if (lw_hazard && stall_cnt == 2'b00) begin
                stall_cnt <= 2'b01;
                Stall <= 1;
                Flush <= 1;
            end else if (stall_cnt == 2'b01) begin
                stall_cnt <= 2'b10;
                Stall <= 1;
                Flush <= 1;
            end else if (stall_cnt == 2'b10) begin
                stall_cnt <= 2'b00;
                Stall <= 0;
                Flush <= 0;
            end
            // 无冒险：正常执行
            else begin
                Stall <= 0;
                Flush <= 0;
            end
        end
    end
endmodule






//------------------------------------------------------------------------------
//CPU顶层模块
//------------------------------------------------------------------------------


module MIPS_Pipeline_CPU(
    input clk, reset
);
    // IF阶段信号
    wire [31:0] PC_IF, PC_plus_4_IF, Instruction_IF;
    wire [31:0] NextPC;

    // ID阶段信号
    wire [31:0] PC_plus_4_ID, Instruction_ID;
    wire [31:0] ReadData1_ID, ReadData2_ID, SignExtImm_ID;
    wire [4:0] Rs_ID, Rt_ID, Rd_ID;
    wire RegWrite_ID, MemToReg_ID, MemWrite_ID, ALUSrc_ID, RegDst_ID, Branch_ID, Jump_ID;
    wire [2:0] ALUControl_ID;
    wire Stall_ID, Flush_ID;

    // EX阶段信号
    wire [31:0] PC_plus_4_EX, ReadData1_EX, ReadData2_EX, SignExtImm_EX;
    wire [31:0] ALUResult_EX, WriteData_EX, ALU_A, ALU_B;
    wire [4:0] Rs_EX, Rt_EX, Rd_EX, WriteReg_EX;
    wire RegWrite_EX, MemToReg_EX, MemWrite_EX, ALUSrc_EX, RegDst_EX, Branch_EX;
    wire [2:0] ALUControl_EX;
    wire [1:0] ForwardA, ForwardB;
    wire Zero_EX;
    wire PCSrc_EX = Branch_EX & Zero_EX;
    wire [3:0] ALU_OP;

    // MEM阶段信号
    wire [31:0] ALUResult_MEM, WriteData_MEM, PC_plus_4_MEM, ReadData_MEM;
    wire [4:0] WriteReg_MEM;
    wire RegWrite_MEM, MemToReg_MEM, MemWrite_MEM;

    // WB阶段信号
    wire [31:0] ALUResult_WB, ReadData_WB, PC_plus_4_WB, Result_WB;
    wire [4:0] WriteReg_WB;
    wire RegWrite_WB, MemToReg_WB;

    // 程序计数器（PC）
    reg [31:0] PC;
    always @(posedge clk or posedge reset) begin
        if (reset) PC <= 32'h00000000;
        else if (!Stall_ID) PC <= NextPC; // 不停顿则更新PC
    end

    // 模块实例化
    // 1. 指令存储器
    IMem imem(PC_IF, Instruction_IF);

    // 2. 寄存器组
    RegFile rf(
        clk, RegWrite_WB,
        Rs_ID, Rt_ID, WriteReg_WB,
        Result_WB, ReadData1_ID, ReadData2_ID
    );

    // 3. 控制单元
    Controller ctrl(
        Instruction_ID[31:26], Instruction_ID[5:0],
        MemToReg_ID, MemWrite_ID,
        ALUSrc_ID, RegDst_ID, RegWrite_ID,
        Jump_ID, Branch_ID,
        ALUControl_ID
    );

    // 4. 流水线寄存器
    IF_ID_Reg if_id_reg(
        clk, reset, Flush_ID, Stall_ID,
        PC_plus_4_IF, Instruction_IF,
        PC_plus_4_ID, Instruction_ID
    );

    ID_EX_Reg id_ex_reg(
        clk, reset, Stall_ID, Flush_ID,
        PC_plus_4_ID, ReadData1_ID, ReadData2_ID, SignExtImm_ID,
        Rs_ID, Rt_ID, Rd_ID,
        RegWrite_ID, MemToReg_ID, MemWrite_ID, ALUSrc_ID, RegDst_ID, Branch_ID,
        ALUControl_ID,
        PC_plus_4_EX, ReadData1_EX, ReadData2_EX, SignExtImm_EX,
        Rs_EX, Rt_EX, Rd_EX,
        RegWrite_EX, MemToReg_EX, MemWrite_EX, ALUSrc_EX, RegDst_EX, Branch_EX,
        ALUControl_EX
    );

    EX_MEM_Reg ex_mem_reg(
        clk, reset,
        ALUResult_EX, WriteData_EX, PC_plus_4_EX,
        WriteReg_EX,
        RegWrite_EX, MemToReg_EX, MemWrite_EX,
        ALUResult_MEM, WriteData_MEM, PC_plus_4_MEM,
        WriteReg_MEM,
        RegWrite_MEM, MemToReg_MEM, MemWrite_MEM
    );

    MEM_WB_Reg mem_wb_reg(
        clk, reset,
        ALUResult_MEM, ReadData_MEM, PC_plus_4_MEM,
        WriteReg_MEM,
        RegWrite_MEM, MemToReg_MEM,
        ALUResult_WB, ReadData_WB, PC_plus_4_WB,
        WriteReg_WB,
        RegWrite_WB, MemToReg_WB
    );

    // 5. 冒险处理单元
    ForwardingUnit fwd_unit(
        Rs_EX, Rt_EX,
        WriteReg_MEM, WriteReg_WB,
        RegWrite_MEM, RegWrite_WB,
        MemToReg_MEM, MemToReg_WB,
        ForwardA, ForwardB
    );

    HazardDetectionUnit hazard_unit(
        clk, reset,
        Rs_ID, Rt_ID,
        MemToReg_EX, WriteReg_EX,
        Branch_EX, Jump_ID, PCSrc_EX,
        Stall_ID, Flush_ID
    );

    // 6. 数据存储器
    DMem dmem(
        clk, MemWrite_MEM,
        ALUResult_MEM, WriteData_MEM,
        ReadData_MEM
    );

    // 7. ALU模块
    ALU_8 alu(
        ALUResult_EX, Zero_EX,
        ALU_A, ALU_B,
        ALU_OP
    );

    // IF阶段逻辑
    assign PC_IF = PC;
    assign PC_plus_4_IF = PC + 4;

    // ID阶段逻辑
    assign Rs_ID = Instruction_ID[25:21];
    assign Rt_ID = Instruction_ID[20:16];
    assign Rd_ID = Instruction_ID[15:11];
    assign SignExtImm_ID = {{16{Instruction_ID[15]}}, Instruction_ID[15:0]}; // 符号扩展

    // EX阶段逻辑
    assign WriteReg_EX = RegDst_EX ? Rd_EX : Rt_EX; // 目标寄存器选择

    // ALU操作数前推逻辑
    assign ALU_A = (ForwardA == 2'b10) ? (MemToReg_MEM ? ReadData_MEM : ALUResult_MEM) :
                   (ForwardA == 2'b01) ? (MemToReg_WB ? ReadData_WB : ALUResult_WB) :
                   ReadData1_EX;

    assign ALU_B = ALUSrc_EX ? SignExtImm_EX :
                   (ForwardB == 2'b10) ? (MemToReg_MEM ? ReadData_MEM : ALUResult_MEM) :
                   (ForwardB == 2'b01) ? (MemToReg_WB ? ReadData_WB : ALUResult_WB) :
                   ReadData2_EX;

    // sw指令写数据前推
    assign WriteData_EX = (ForwardB == 2'b10) ? (MemToReg_MEM ? ReadData_MEM : ALUResult_MEM) :
                         (ForwardB == 2'b01) ? (MemToReg_WB ? ReadData_WB : ALUResult_WB) :
                         ReadData2_EX;

    // ALU_OP映射（Controller的ALUControl到ALU模块的操作码）
    assign ALU_OP = (ALUControl_EX == 3'b010) ? 4'b0100 : // add
                   (ALUControl_EX == 3'b110) ? 4'b0101 : // sub
                   (ALUControl_EX == 3'b000) ? 4'b0000 : // and
                   (ALUControl_EX == 3'b001) ? 4'b0001 : // or
                   (ALUControl_EX == 3'b111) ? 4'b0110 : // slt
                   4'b0100; // 默认加法

    // WB阶段逻辑：写回数据选择
    assign Result_WB = MemToReg_WB ? ReadData_WB : ALUResult_WB;

    // PC更新逻辑（分支/跳转/顺序）
    assign NextPC = PCSrc_EX ? (PC_plus_4_EX + (SignExtImm_EX << 2)) : // 分支地址
                    Jump_ID ? {PC_plus_4_ID[31:28], Instruction_ID[25:0], 2'b00} : // 跳转地址
                    PC_plus_4_IF; // 顺序地址

    // 调试信息打印
    always @(posedge clk) begin
        $display("Time=%0t: PC=%h, Instr=%h", $time, PC_IF, Instruction_IF);
        if (RegWrite_WB) begin
            $display("Time=%0t: WB: $%d = %h (MemToReg=%b)", $time, WriteReg_WB, Result_WB, MemToReg_WB);
        end
    end
endmodule





//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------

//测试模块

//------------------------------------------------------------------------------


module Testbench;
    reg clk, reset;
    MIPS_Pipeline_CPU cpu(clk, reset);

    // 生成时钟（10ns周期）
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 初始化和复位
    initial begin
        reset = 1;
        #10 reset = 0; // 10ns后释放复位
        #200 $finish; // 200ns后结束仿真
    end

    // 波形文件生成（供ModelSim查看）
    initial begin
        $dumpfile("cpu_wave.vcd");
        $dumpvars(0, Testbench);
    end
endmodule
