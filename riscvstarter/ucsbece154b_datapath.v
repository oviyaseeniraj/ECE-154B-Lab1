// ucsbece154b_datapath.v
// ECE 154B, RISC-V pipelined processor 
// All Rights Reserved
// Copyright (c) 2024 UCSB ECE
// Distribution Prohibited


module ucsbece154b_datapath (
    input                clk, reset,
    input                PCSrcE_i,
    input                StallF_i,
    output reg    [31:0] PCF_o,
    input                StallD_i,
    input                FlushD_i,
    input         [31:0] InstrF_i,
    output wire    [6:0] op_o,
    output wire    [2:0] funct3_o,
    output wire          funct7b5_o,
    input                RegWriteW_i,
    input          [2:0] ImmSrcD_i,
    output wire    [4:0] Rs1D_o,
    output wire    [4:0] Rs2D_o,
    input  wire          FlushE_i,
    output reg     [4:0] Rs1E_o,
    output reg     [4:0] Rs2E_o, 
    output reg     [4:0] RdE_o, 
    input                ALUSrcE_i,
    input          [2:0] ALUControlE_i,
    input          [1:0] ForwardAE_i,
    input          [1:0] ForwardBE_i,
    output               ZeroE_o,
    output reg     [4:0] RdM_o, 
    output reg    [31:0] ALUResultM_o,
    output reg    [31:0] WriteDataM_o,
    input         [31:0] ReadDataM_i,
    input          [1:0] ResultSrcW_i,
    output reg     [4:0] RdW_o,
    input          [1:0] ResultSrcM_i
);

`include "ucsbece154b_defines.vh"

// Pipeline registers
reg [31:0] InstrD, PCPlus4D, ImmExtD, PCD, PCE;
reg [31:0] RD1E, RD2E, ImmExtE, ImmExtM, PCPlus4E, ImmExtW;
reg [31:0] ALUResultW, ReadDataW, PCPlus4W, PCPlus4M;
reg [31:0] WriteDataE;

// Internal signals
wire [31:0] RD1D, RD2D;
wire [31:0] PCNext, PCPlus4F, PCTargetE;
wire [31:0] SrcAE, SrcBE, ALUResultE;
wire [31:0] ResultW;
wire [31:0] ForwardAEMuxOut, ForwardBEMuxOut;
wire [31:0] ALUSrcBMuxOut;
wire [4:0] RdD;

// Instruction fields
assign op_o = InstrD[6:0];
assign RdD = InstrD[11:7];
assign funct3_o = InstrD[14:12];
assign funct7b5_o = InstrD[30];
assign Rs1D_o = InstrD[19:15];
assign Rs2D_o = InstrD[24:20];

assign PCTargetE = PCPlus4E + (ImmExtE << 1);
assign PCPlus4F = PCF_o + 4;
assign PCNext = PCSrcE_i ? PCTargetE : PCPlus4F; 

// Immediate generator
always @ * begin
    case (ImmSrcD_i)
        imm_Itype: ImmExtD = {{20{InstrD[31]}}, InstrD[31:20]};
        imm_Stype: ImmExtD = {{20{InstrD[31]}}, InstrD[31:25], InstrD[11:7]};
        imm_Btype: ImmExtD = {{20{InstrD[31]}}, InstrD[7], InstrD[30:25], InstrD[11:8], 1'b0};
        imm_Utype: ImmExtD = {InstrD[31:12], 12'b0};
        imm_Jtype: ImmExtD = {{12{InstrD[31]}}, InstrD[19:12], InstrD[20], InstrD[30:21], 1'b0};
        default:   ImmExtD = 32'b0;
    endcase
end

// Register file
ucsbece154b_rf rf (
    .clk(clk),
    .a1_i(Rs1D_o),
    .a2_i(Rs2D_o),
    .a3_i(RdW_o),
    .rd1_o(RD1D),
    .rd2_o(RD2D),
    .we3_i(RegWriteW_i),
    .wd3_i(ResultW)
);

// ALU
ucsbece154b_alu alu (
    .a_i(SrcAE),
    .b_i(SrcBE),
    .alucontrol_i(ALUControlE_i),
    .result_o(ALUResultE),
    .zero_o(ZeroE_o)
);

// Fetch-D pipeline register
always @(posedge clk) begin
    if (FlushD_i) begin
        InstrD <= 32'b0;
        PCD <= 32'b0;
        PCPlus4D <= 32'b0;
    end
    if (StallD_i) begin
        // do nothing
    end
    else begin
        InstrD <= InstrF_i;
        PCD <= PCF_o;
        PCPlus4D <= PCPlus4F;
    end
end

// Decode-Execute pipeline register
always @(posedge clk) begin
    if (FlushE_i) begin
        RD1E <= 32'b0;
        RD2E <= 32'b0;
        PCE <= 32'b0;
        ImmExtE <= 32'b0;
        Rs1E_o <= 5'b0;
        Rs2E_o <= 5'b0;
        RdE_o <= 5'b0;
        PCPlus4E <= 32'b0;
    end
    else begin
        RD1E <= RD1D;
        RD2E <= RD2D;
        PCE <= PCD;
        ImmExtE <= ImmExtD;
        Rs1E_o <= Rs1D_o;
        Rs2E_o <= Rs2D_o;
        RdE_o <= RdD;
        PCPlus4E <= PCPlus4D;
    end
end

// Execute-Memory pipeline register
always @(posedge clk) begin
    begin
        ALUResultM_o <= ALUResultE;
        WriteDataM_o <= ForwardBEMuxOut;
        ImmExtM <= ImmExtE;
        RdM_o <= RdE_o;
        PCPlus4M <= PCPlus4E;
    end
end

// Memory-Writeback pipeline register
always @(posedge clk) begin
    begin
        ALUResultW <= ALUResultM_o;
        ReadDataW <= ReadDataM_i;
        ImmExtW <= ImmExtM;
        PCPlus4W <= PCPlus4M;
        RdW_o <= RdM_o;
    end
end

// Forwarding muxes
assign ForwardAEMuxOut = (ForwardAE_i == 2'b10) ? ALUResultM_o :
                        (ForwardAE_i == 2'b01) ? ResultW :
                        RD1E;

assign ForwardBEMuxOut = (ForwardBE_i == 2'b10) ? ALUResultM_o :
                        (ForwardBE_i == 2'b01) ? ResultW :
                        RD2E;

// ALU source muxes
assign SrcAE = ForwardAEMuxOut;
assign ALUSrcBMuxOut = (ALUSrcE_i) ? ImmExtE : ForwardBEMuxOut;
assign SrcBE = ALUSrcBMuxOut;

always @ (posedge reset or posedge clk) begin
    if (reset)
        PCF_o <= pc_start;
    else
        PCF_o <= PCNext;
end

// Result mux
assign ResultW = (ResultSrcW_i == 2'b00) ? ALUResultW :
                (ResultSrcW_i == 2'b01) ? ReadDataW :
                (ResultSrcW_i == 2'b10) ? PCPlus4W :
                (ResultSrcW_i == 2'b11) ? ImmExtW :
                32'b0;

endmodule
