module SingleCycleCPU (
    input clk,
    input start
    
);

// When input start is zero, cpu should reset
// When input start is high, cpu start running

// TODO: connect wire to realize SingleCycleCPU
// The following provides simple template,

wire [31:0] pc_current; // Current PC output
wire [31:0] pc_next;    // Next PC input
PC m_PC(
    .clk(clk),
    .rst(start),       // reset when start=0
    .pc_i(pc_next),    // next PC
    .pc_o(pc_current)  // current PC
);

wire [31:0] pc_plus4;

Adder m_Adder_1(
    .a(pc_current),
    .b(32'd4),
    .sum(pc_plus4)
);

// output instruction wire
wire [31:0] instruction;
InstructionMemory m_InstMem(
    .readAddr(pc_current),   // address = current PC
    .inst(instruction)       // output instruction
);

// control unit wires
wire branch;
wire memRead;
wire memtoReg;
wire [1:0] ALUOp;
wire memWrite;
wire ALUSrc;
wire regWrite;

wire jal_sig,jalr_sig;
Control m_Control(
    .opcode(instruction[6:0]),  // opcode field
    .branch(branch),
    .memRead(memRead),
    .memtoReg(memtoReg),
    .ALUOp(ALUOp),
    .memWrite(memWrite),
    .ALUSrc(ALUSrc),
    .regWrite(regWrite),
    .jal_sig(jal_sig),
    .jalr_sig(jalr_sig)
);


// register file outputs
wire [31:0] readData1;
wire [31:0] readData2;

// write back data input signal (will come from mux - Mux_WriteData output)
wire [31:0] writeData;

Register m_Register(
    .clk(clk),
    .rst(start),
    .regWrite(regWrite),
    .readReg1(instruction[19:15]),  // rs1
    .readReg2(instruction[24:20]),  // rs2
    .writeReg(instruction[11:7]),   // rd
    .writeData(writeData),
    .readData1(readData1),
    .readData2(readData2)
);


wire [31:0] imm; // output from immgen unit
ImmGen m_ImmGen(
    .inst(instruction),
    .imm(imm)
);

wire [31:0] imm_shifted; //for branch instructions the immidiate will be shifted left by a bit
ShiftLeftOne m_ShiftLeftOne(
    .i(imm),
    .o(imm_shifted)
);


wire [31:0] branch_jal_target; // this will go to a mux which decides what next PC is...
// branch/jal target adder
Adder m_Adder_2(
    .a(pc_current),
    .b(imm_shifted),
    .sum(branch_jal_target)
);

wire [31:0] jalr_target;
Adder jalr_adder(.a(readData1),
                 .b(imm),
                 .sum(jalr_target));

wire branch_taken;
branch_control bcntrl(
    .branch(branch),
    .funct3(funct3),
    .zero(zero),
    .eff_sign(eff_sign),
    .branch_taken(branch_taken)
);

wire [31:0] w1; //intermidiary for cascaded mux begin made using 3 2:1 muxes

Mux2to1 m_Mux_PC0(
    .sel(branch_taken | jal_sig),
    .s0(jalr_target),        // jalr target 
    .s1(branch_jal_target),   // branch/jal target
    .out(w1)
);

wire mux1cntrl;
assign mux1cntrl = branch_taken | jal_sig | jalr_sig;
Mux2to1 m_Mux_PC1(
    .sel(mux1cntrl),
    .s0(pc_plus4), //pc + 4
    .s1(w1), //from mux0    
    .out(pc_next)
);


// This mux decides B input to the ALU
wire [31:0] alu_B; // goes as input to the ALU
Mux2to1 m_Mux_ALU(
    .sel(ALUSrc),     
    .s0(readData2),    
    .s1(imm),           
    .out(alu_B)
);

wire [3:0] ALUCtl; //output of ALU Control unit
wire [2:0] funct3;
wire funct7_bit;

assign funct3     = instruction[14:12];
assign funct7_bit = instruction[30]; //single fucnt7 bit sufficient to distinguish instructions

ALUCtrl m_ALUCtrl(
    .ALUOp(ALUOp),
    .funct7(funct7_bit),
    .funct3(funct3),
    .ALUCtl(ALUCtl)
);

wire [31:0] ALUOut; // output of the ALU
wire zero,eff_sign;
ALU m_ALU(
    .ALUCtl(ALUCtl),
    .A(readData1),
    .B(alu_B),        // from ALU mux 
    .ALUOut(ALUOut),
    .zero(zero),
    .eff_sign(eff_sign)
);

wire [31:0] memReadData; // data read out from the data memory when memRead is asserted

DataMemory m_DataMemory(
    .rst(start),
    .clk(clk),
    .memWrite(memWrite),
    .memRead(memRead),
    .address(ALUOut),        // address from ALU
    .writeData(readData2),   // rs2 value for sw
    .readData(memReadData)   // data read out for lw
);

wire [31:0] w2; //intermediary for writeback mux
Mux2to1 m_Mux_WriteData0(
    .sel(memtoReg),
    .s0(ALUOut),        // ALU result
    .s1(memReadData),   // Data memory read output (for lw)
    .out(w2)
);

//additional mux for PC + 4 write backs
Mux2to1 m_Mux_WriteData1(
    .sel(jal_sig | jalr_sig),  //will write back PC + 4 only for jal/jalr
    .s0(w2),        // ALU/Data Memory data
    .s1(pc_plus4),   // PC + 4
    .out(writeData)
);
endmodule



module PC (
    input clk,
    input rst,
    input [31:0] pc_i,
    output reg [31:0] pc_o
);

// PC register: updates to next PC on rising edge of clk, active low reset sets PC to 0

always @(posedge clk) begin
	if (~rst)
		pc_o <=32'b0;
	else
		pc_o <= pc_i;
end
endmodule


module Adder (
    input signed [31:0] a,
    input signed [31:0] b,
    output signed [31:0] sum
);
    // Adder computes sum = a + b
    // The module is useful for incrementing PC 
    // we will need 2 instantiations of the adder - one for PC + 4 , one for PC + offset
 assign sum = a + b;
endmodule


module Mux2to1 (
    input sel,
    input signed [31:0] s0,
    input signed [31:0] s1,
    output signed [31:0] out
);
assign out = sel ? s1 : s0;
endmodule




module Register (
    input clk,
    input rst,
    input regWrite,
    input [4:0] readReg1,
    input [4:0] readReg2,
    input [4:0] writeReg,
    input [31:0] writeData,
    output [31:0] readData1,
    output [31:0] readData2
);
    reg [31:0] regs [0:31]; //32 registers of 32 bits length

// Do not modify this file!
    assign readData1 = (readReg1!=0)?regs[readReg1]:0;
    assign readData2 = (readReg2!=0)?regs[readReg2]:0;
     
    always @(posedge clk) begin
        if(~rst) begin
            regs[0] <= 0; regs[1] <= 0; regs[2] <= 32'd128; regs[3] <= 0; 
            regs[4] <= 0; regs[5] <= 0; regs[6] <= 0; regs[7] <= 0; 
            regs[8] <= 0; regs[9] <= 0; regs[10] <= 0; regs[11] <= 0; 
            regs[12] <= 0; regs[13] <= 0; regs[14] <= 0; regs[15] <= 0; 
            regs[16] <= 0; regs[17] <= 0; regs[18] <= 0; regs[19] <= 0; 
            regs[20] <= 0; regs[21] <= 0; regs[22] <= 0; regs[23] <= 0; 
            regs[24] <= 0; regs[25] <= 0; regs[26] <= 0; regs[27] <= 0; 
            regs[28] <= 0; regs[29] <= 0; regs[30] <= 0; regs[31] <= 0;        
        end
        else if(regWrite)
            regs[writeReg] <= (writeReg == 0) ? 0 : writeData;
    end

endmodule


module InstructionMemory (
    input [31:0] readAddr,
    output [31:0] inst
);
    
    // Do not modify this file!

    reg [7:0] insts [127:0];
    
    assign inst = (readAddr >= 128) ? 32'b0 : {insts[readAddr], insts[readAddr + 1], insts[readAddr + 2], insts[readAddr + 3]};

    initial begin
        insts[0] = 8'b0;  insts[1] = 8'b0;  insts[2] = 8'b0;  insts[3] = 8'b0;
        insts[4] = 8'b0;  insts[5] = 8'b0;  insts[6] = 8'b0;  insts[7] = 8'b0;
        insts[8] = 8'b0;  insts[9] = 8'b0;  insts[10] = 8'b0; insts[11] = 8'b0;
        insts[12] = 8'b0; insts[13] = 8'b0; insts[14] = 8'b0; insts[15] = 8'b0;
        insts[16] = 8'b0; insts[17] = 8'b0; insts[18] = 8'b0; insts[19] = 8'b0;
        insts[20] = 8'b0; insts[21] = 8'b0; insts[22] = 8'b0; insts[23] = 8'b0;
        insts[24] = 8'b0; insts[25] = 8'b0; insts[26] = 8'b0; insts[27] = 8'b0;
        insts[28] = 8'b0; insts[29] = 8'b0; insts[30] = 8'b0; insts[31] = 8'b0;
        $readmemb("TEST_INSTRUCTIONS.dat", insts);
    end

endmodule


module DataMemory(
	input rst,
	input clk,
	input memWrite,
	input memRead,
	input [31:0] address,
	input [31:0] writeData,
	output reg [31:0] readData
);
	// Do not modify this file!

	reg [7:0] data_memory [127:0];
	always @ (posedge clk) begin
		if(~rst) begin
			data_memory[0] <= 8'b0;
			data_memory[1] <= 8'b0;
			data_memory[2] <= 8'b0;
			data_memory[3] <= 8'b0;
			data_memory[4] <= 8'b0;
			data_memory[5] <= 8'b0;
			data_memory[6] <= 8'b0;
			data_memory[7] <= 8'b0;
			data_memory[8] <= 8'b0;
			data_memory[9] <= 8'b0;
			data_memory[10] <= 8'b0;
			data_memory[11] <= 8'b0;
			data_memory[12] <= 8'b0;
			data_memory[13] <= 8'b0;
			data_memory[14] <= 8'b0;
			data_memory[15] <= 8'b0;
			data_memory[16] <= 8'b0;
			data_memory[17] <= 8'b0;
			data_memory[18] <= 8'b0;
			data_memory[19] <= 8'b0;
			data_memory[20] <= 8'b0;
			data_memory[21] <= 8'b0;
			data_memory[22] <= 8'b0;
			data_memory[23] <= 8'b0;
			data_memory[24] <= 8'b0;
			data_memory[25] <= 8'b0;
			data_memory[26] <= 8'b0;
			data_memory[27] <= 8'b0;
			data_memory[28] <= 8'b0;
			data_memory[29] <= 8'b0;
			data_memory[30] <= 8'b0;
			data_memory[31] <= 8'b0;
			data_memory[32] <= 8'b0;
			data_memory[33] <= 8'b0;
			data_memory[34] <= 8'b0;
			data_memory[35] <= 8'b0;
			data_memory[36] <= 8'b0;
			data_memory[37] <= 8'b0;
			data_memory[38] <= 8'b0;
			data_memory[39] <= 8'b0;
			data_memory[40] <= 8'b0;
			data_memory[41] <= 8'b0;
			data_memory[42] <= 8'b0;
			data_memory[43] <= 8'b0;
			data_memory[44] <= 8'b0;
			data_memory[45] <= 8'b0;
			data_memory[46] <= 8'b0;
			data_memory[47] <= 8'b0;
			data_memory[48] <= 8'b0;
			data_memory[49] <= 8'b0;
			data_memory[50] <= 8'b0;
			data_memory[51] <= 8'b0;
			data_memory[52] <= 8'b0;
			data_memory[53] <= 8'b0;
			data_memory[54] <= 8'b0;
			data_memory[55] <= 8'b0;
			data_memory[56] <= 8'b0;
			data_memory[57] <= 8'b0;
			data_memory[58] <= 8'b0;
			data_memory[59] <= 8'b0;
			data_memory[60] <= 8'b0;
			data_memory[61] <= 8'b0;
			data_memory[62] <= 8'b0;
			data_memory[63] <= 8'b0;
			data_memory[64] <= 8'b0;
			data_memory[65] <= 8'b0;
			data_memory[66] <= 8'b0;
			data_memory[67] <= 8'b0;
			data_memory[68] <= 8'b0;
			data_memory[69] <= 8'b0;
			data_memory[70] <= 8'b0;
			data_memory[71] <= 8'b0;
			data_memory[72] <= 8'b0;
			data_memory[73] <= 8'b0;
			data_memory[74] <= 8'b0;
			data_memory[75] <= 8'b0;
			data_memory[76] <= 8'b0;
			data_memory[77] <= 8'b0;
			data_memory[78] <= 8'b0;
			data_memory[79] <= 8'b0;
			data_memory[80] <= 8'b0;
			data_memory[81] <= 8'b0;
			data_memory[82] <= 8'b0;
			data_memory[83] <= 8'b0;
			data_memory[84] <= 8'b0;
			data_memory[85] <= 8'b0;
			data_memory[86] <= 8'b0;
			data_memory[87] <= 8'b0;
			data_memory[88] <= 8'b0;
			data_memory[89] <= 8'b0;
			data_memory[90] <= 8'b0;
			data_memory[91] <= 8'b0;
			data_memory[92] <= 8'b0;
			data_memory[93] <= 8'b0;
			data_memory[94] <= 8'b0;
			data_memory[95] <= 8'b0;
			data_memory[96] <= 8'b0;
			data_memory[97] <= 8'b0;
			data_memory[98] <= 8'b0;
			data_memory[99] <= 8'b0;
			data_memory[100] <= 8'b0;
			data_memory[101] <= 8'b0;
			data_memory[102] <= 8'b0;
			data_memory[103] <= 8'b0;
			data_memory[104] <= 8'b0;
			data_memory[105] <= 8'b0;
			data_memory[106] <= 8'b0;
			data_memory[107] <= 8'b0;
			data_memory[108] <= 8'b0;
			data_memory[109] <= 8'b0;
			data_memory[110] <= 8'b0;
			data_memory[111] <= 8'b0;
			data_memory[112] <= 8'b0;
			data_memory[113] <= 8'b0;
			data_memory[114] <= 8'b0;
			data_memory[115] <= 8'b0;
			data_memory[116] <= 8'b0;
			data_memory[117] <= 8'b0;
			data_memory[118] <= 8'b0;
			data_memory[119] <= 8'b0;
			data_memory[120] <= 8'b0;
			data_memory[121] <= 8'b0;
			data_memory[122] <= 8'b0;
			data_memory[123] <= 8'b0;
			data_memory[124] <= 8'b0;
			data_memory[125] <= 8'b0;
			data_memory[126] <= 8'b0;
			data_memory[127] <= 8'b0;
		end
		else begin
			if(memWrite) begin
				data_memory[address + 3] <= writeData[31:24];
				data_memory[address + 2] <= writeData[23:16];
				data_memory[address + 1] <= writeData[15:8];
				data_memory[address]     <= writeData[7:0];
			end

			end
	end       

	always @(*) begin
		if(memRead) begin
			readData[31:24]   = data_memory[address + 3];
			readData[23:16]   = data_memory[address + 2];
			readData[15:8]    = data_memory[address + 1];
			readData[7:0]     = data_memory[address];
		end
		else begin
			readData          = 32'b0;
		end
	end

endmodule

module Control (
    input [6:0] opcode,
    output reg branch,
    output reg memRead,
    output reg memtoReg,
    output reg [1:0] ALUOp,
    output reg memWrite,
    output reg ALUSrc,
    output reg regWrite,
    output jal_sig,
    output jalr_sig
    );
    assign jal_sig = (opcode == 7'b1101111);
    assign jalr_sig =  (opcode == 7'b1100111);
    // TODO: implement your Control here
    
    always @(*) begin
	casex(opcode)

    /*R-type instruction*/ 
    7'b0110011 :begin
    {branch,memRead,memtoReg,memWrite,ALUSrc,regWrite} = 6'b000001;
    ALUOp = 2'b10;
    end 

    /*Arithmetic I-Type instruction*/
    7'b0010011 :begin
    {branch,memRead,memtoReg,memWrite,ALUSrc,regWrite} = 6'b000011;
    ALUOp = 2'b11;   
    end   

    /*Load I-type instruction*/
    7'b0000011 :begin
    {branch,memRead,memtoReg,memWrite,ALUSrc,regWrite} = 6'b011011;
    ALUOp = 2'b00;
    end

    /*S-Type instruction*/
    7'b0100011 :begin
    {branch,memRead,memtoReg,memWrite,ALUSrc,regWrite} = 6'b000110;
    ALUOp = 2'b00;
    end      

    /*SB-type instruction*/
    7'b1100011 :begin
    {branch,memRead,memtoReg,memWrite,ALUSrc,regWrite} = 6'b100000;  
    ALUOp = 2'b01;
    end
    
    /* UJ-type instruction (jal) */
    7'b1101111 : begin
    {branch,memRead,memtoReg,memWrite,ALUSrc,regWrite} = 6'b000001;
    ALUOp = 2'b00;  
    end

    /* I-type Jump instruction (jalr) */
    7'b1100111 : begin
    {branch,memRead,memtoReg,memWrite,ALUSrc,regWrite} = 6'b000011;
    ALUOp = 2'b00;  // (rs1 + imm)
    end
    
    default :begin
    {branch,memRead,memtoReg,memWrite,ALUSrc,regWrite} = 6'b000000;
    ALUOp = 2'b00;   
    end 

    endcase
end

endmodule

module ALUCtrl (
    input [1:0] ALUOp,
    input funct7,
    input [2:0] funct3,
    output reg [3:0] ALUCtl
);

always @(*) begin
    casex({funct7, funct3, ALUOp})
    6'b000010: ALUCtl = 4'b0010; // add
    6'b100010: ALUCtl = 4'b0110; // sub
    6'b011010: ALUCtl = 4'b0001; // or
    6'b011110: ALUCtl = 4'b0000; // and
    6'b010010: ALUCtl = 4'b0011; // xor
    6'b000110: ALUCtl = 4'b0100; // sll
    6'b010110: ALUCtl = 4'b0101; // srl
    6'b110110: ALUCtl = 4'b0111; // sra
    6'b001010: ALUCtl = 4'b1000; // slt
    6'b001110: ALUCtl = 4'b1001; // sltu
    6'bx00011: ALUCtl = 4'b0010; // addi
    6'bx11111: ALUCtl = 4'b0000; // andi
    6'bx11011: ALUCtl = 4'b0001; // ori
    6'bx10011: ALUCtl = 4'b0011; // xori
    6'b000111: ALUCtl = 4'b0100; // slli
    6'b010111: ALUCtl = 4'b0101; // srli
    6'b110111: ALUCtl = 4'b0111; // srai
    6'bx01011: ALUCtl = 4'b1000; // slti
    6'bx01111: ALUCtl = 4'b1001; // sltiu
    6'bxxxxx0: ALUCtl = 4'b0010; // lw/sw 
    6'bxxxxx1: ALUCtl = 4'b0110; // branch (subtraction)

    default:   ALUCtl = 4'b0000;
endcase
end

endmodule



module ALU (
    input [3:0] ALUCtl,
    input [31:0] A,B,
    output reg [31:0] ALUOut,
    output zero,eff_sign
);
    // ALU has two operand, it execute different operator based on ALUctl wire 
    // output zero is for determining taking branch or not 

    // TODO: implement your ALU here
    // shift operations done directly in ALU
    wire sign, overflow; //adding sign and overflow flags

    assign zero = (ALUOut == 0);
    assign sign = (ALUOut[31]);
    assign overflow = (A[31] & ~B[31] & ~ALUOut[31]) | (~A[31] & B[31] & ALUOut[31]);
    assign eff_sign = sign^overflow;
    always @(*) begin
    case(ALUCtl)
        4'b0010: ALUOut = A + B;                 // add / addi / lw / sw
        4'b0110: ALUOut = A - B;                 // sub / beq
        4'b0000: ALUOut = A & B;                 // and / andi
        4'b0001: ALUOut = A | B;                 // or  / ori
        4'b0011: ALUOut = A ^ B;                 // xor / xori
        4'b0100: ALUOut = A << B[4:0];           // sll / slli (only first 5 bits of B are used for shifts)
        4'b0101: ALUOut = A >> B[4:0];           // srl / srli (only first 5 bits of B are used for shifts)
        4'b0111: ALUOut = $signed(A) >>> B[4:0]; // sra / srai
        4'b1000: ALUOut = ($signed(A) < $signed(B)) ? 1 : 0; // slt / slti
        4'b1001: ALUOut = (A < B) ? 1 : 0;       // sltu / sltiu
        default: ALUOut = 32'b0;                     
    endcase
    end
endmodule


module ImmGen (
    input [31:0] inst,
    output reg signed [31:0] imm
);
    wire [6:0] opcode = inst[6:0];

    always @(*) begin
        case(opcode)
            7'b0010011: imm = {{20{inst[31]}}, inst[31:20]}; //arithmetic I-type
            7'b0000011: imm = {{20{inst[31]}}, inst[31:20]}; //load I-type (lw)
            7'b0100011: imm = {{20{inst[31]}},inst[31:25],inst[11:7]}; // S-type (sw)
            7'b1100011: imm = {{19{inst[31]}},inst[31],inst[7],inst[30:25],inst[11:8]}; // SB-type (beq)
            7'b1101111: imm = {{12{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21]}; // UJ-type
            7'b1100111: imm = {{20{inst[31]}}, inst[31:20]}; // I-type (JALR)
            default:
                imm = 32'b0; // default 0 for others
        endcase
    end
endmodule

module ShiftLeftOne (
    input signed [31:0] i,
    output signed [31:0] o
);

   assign o = i << 1;

endmodule

module branch_control(branch, funct3, zero , eff_sign ,branch_taken);
input branch,zero,eff_sign;
input [2:0] funct3;
output reg branch_taken;
always @ (*) begin
    if(branch) begin
        case(funct3) 
        3'b000 : branch_taken = zero ; //beq
        3'b001 : branch_taken = ~zero; //bne
        3'b100 : branch_taken = eff_sign; //blt
        3'b101 : branch_taken = ~eff_sign; //bge
        default : branch_taken = 1'b0;
        endcase
    end
    else begin
        branch_taken = 1'b0;
    end
end
endmodule


module tb_riscv_sc;
// cpu testbench

reg clk;
reg start;

SingleCycleCPU riscv_DUT(clk, start);

// clock generation
initial
    forever #5 clk = ~clk;

initial begin
    // GTKWave dump setup
    $dumpfile("riscv.vcd");  //modifications for GTKWave simulation  
    $dumpvars(0, tb_riscv_sc);      

    clk = 0;
    start = 0;
    #10 start = 1;
    #3000 $finish;
end

endmodule

//final