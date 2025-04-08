// ucsbece154b_controller.v
// ECE 154B, RISC-V pipelined processor 
// All Rights Reserved
// Copyright (c) 2024 UCSB ECE
// Distribution Prohibited

module ucsbece154b_controller (
    input                clk, reset,
    input         [6:0]  op_i, 
    input         [2:0]  funct3_i,
    input                funct7b5_i,
    input 	         ZeroE_i,
    input         [4:0]  Rs1D_i,
    input         [4:0]  Rs2D_i,
    input         [4:0]  Rs1E_i,
    input         [4:0]  Rs2E_i,
    input         [4:0]  RdE_i,
    input         [4:0]  RdM_i,
    input         [4:0]  RdW_i,
    output wire		 StallF_o,  
    output wire          StallD_o,
    output wire          FlushD_o,
    output wire    [2:0] ImmSrcD_o,
    output wire          PCSrcE_o,
    output reg     [2:0] ALUControlE_o,
    output reg           ALUSrcE_o,
    output wire          FlushE_o,
    output reg     [1:0] ForwardAE_o,
    output reg     [1:0] ForwardBE_o,
    output reg           MemWriteM_o,
    output reg           RegWriteW_o,
    output reg    [1:0] ResultSrcW_o, 
    output reg    [1:0] ResultSrcM_o
);

 `include "ucsbece154b_defines.vh"

 // Main Decoder
 wire BranchD = (op_i == instr_beq_op);
 wire JumpD = (op_i == instr_jal_op);
 wire LuiD = (op_i == instr_lui_op);
 wire MemWriteD = (op_i == instr_sw_op);
 wire ALUSrcD = (op_i == instr_lw_op || op_i == instr_sw_op || op_i == instr_ItypeALU_op);
 wire RegWriteD = (op_i == instr_lw_op || op_i == instr_Rtype_op || 
                  op_i == instr_ItypeALU_op || op_i == instr_jal_op || op_i == instr_lui_op);
 wire [1:0] ResultSrcD = (op_i == instr_lw_op) ? 2'b01 : 
                         (op_i == instr_jal_op) ? 2'b10 : 
                         (op_i == instr_lui_op) ? 2'b11 : 2'b00;

 // ALU Decoder
 wire [1:0] ALUOpD = (op_i == instr_Rtype_op || op_i == instr_ItypeALU_op) ? 2'b10 :
                     (op_i == instr_beq_op) ? 2'b01 : 2'b00;
 wire RtypeSub = funct7b5_i & op_i[5];

 wire RegWriteE_o, RegWriteM_o;

 always @ * begin
    case (ALUOpD)
      2'b00: ALUControlE_o = ALUcontrol_add;  // Load/Store uses ADD
      2'b01: ALUControlE_o = ALUcontrol_sub;  // Branch uses SUB
      2'b10: begin // R-type or I-type ALU instructions
        case (funct3_i)
          instr_addsub_funct3: ALUControlE_o = (RtypeSub) ? ALUcontrol_sub : ALUcontrol_add;
          instr_slt_funct3:    ALUControlE_o = ALUcontrol_slt;
          instr_or_funct3:      ALUControlE_o = ALUcontrol_or;
          instr_and_funct3:    ALUControlE_o = ALUcontrol_and;
          default:              ALUControlE_o = ALUcontrol_add;
        endcase
      end
      default: ALUControlE_o = ALUcontrol_add;
    endcase
 end

 // Immediate Generator
 assign ImmSrcD_o = (op_i == instr_lw_op) ? 3'b000 :
                   (op_i == instr_sw_op) ? 3'b001 :
                   (op_i == instr_beq_op) ? 3'b010 :
                   (op_i == instr_jal_op) ? 3'b011 :
                   (op_i == instr_lui_op) ? 3'b100 : 3'b000;

 // Hazard Detection
 wire lwStall = ((Rs1D_i == RdE_i) || (Rs2D_i == RdE_i)) && (op_i == instr_lw_op);
 wire branchStall = BranchD && (RegWriteD && (RdE_i == Rs1D_i || RdE_i == Rs2D_i) ||
                   (MemWriteD && (RdE_i == Rs1D_i || RdE_i == Rs2D_i)));
 assign StallF_o = lwStall || branchStall;
 assign StallD_o = lwStall || branchStall;
 assign FlushD_o = PCSrcE_o || JumpD;

 // Forwarding Unit
 always @ * begin
    // ForwardAE
    if ((Rs1E_i != 0) && (Rs1E_i == RdM_i) && RegWriteM_o)
        ForwardAE_o = 2'b10;
    else if ((Rs1E_i != 0) && (Rs1E_i == RdW_i) && RegWriteW_o)
        ForwardAE_o = 2'b01;
    else
        ForwardAE_o = 2'b00;
    
    // ForwardBE
    if ((Rs2E_i != 0) && (Rs2E_i == RdM_i) && RegWriteM_o)
        ForwardBE_o = 2'b10;
    else if ((Rs2E_i != 0) && (Rs2E_i == RdW_i) && RegWriteW_o)
        ForwardBE_o = 2'b01;
    else
        ForwardBE_o = 2'b00;
 end

 // Pipeline Control Signals
 assign PCSrcE_o = BranchD & ZeroE_i | JumpD;
 assign FlushE_o = lwStall || branchStall;

 // Execute Stage Control Signals
 always @(posedge clk) begin
    if (reset) begin
        ALUSrcE_o <= 0;
        RegWriteE_o <= 0;
    end
    else if (!StallD_o) begin
        ALUSrcE_o <= ALUSrcD;
        RegWriteE_o <= RegWriteD;
    end
 end

 // Memory Stage Control Signals
 always @(posedge clk) begin
    if (reset) begin
        MemWriteM_o <= 0;
        RegWriteM_o <= 0;
        ResultSrcM_o <= 0;
    end
    else begin
        MemWriteM_o <= MemWriteD;
        RegWriteM_o <= RegWriteE_o;
        ResultSrcM_o <= ResultSrcD;
    end
 end

 // Writeback Stage Control Signals
 always @(posedge clk) begin
    if (reset) begin
        RegWriteW_o <= 0;
        ResultSrcW_o <= 0;
    end
    else begin
        RegWriteW_o <= RegWriteD;
        ResultSrcW_o <= ResultSrcD;
    end
 end


endmodule