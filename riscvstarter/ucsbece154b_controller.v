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
    output reg          RegWriteW_o,
    output reg    [1:0] ResultSrcW_o, 
    output reg    [1:0] ResultSrcM_o
);


 `include "ucsbece154b_defines.vh"

 // control signals
 // decode
 reg RegWriteD, MemWriteD, JumpD, BranchD, ALUSrcD; 
 reg [1:0] ResultSrcD;
 reg [2:0] ALUControlD;

 // execute
 reg RegWriteE, MemWriteE, JumpE, BranchE; 
 reg [1:0] ResultSrcE;

 // memory
 reg RegWriteM; 
 reg [1:0] ResultSrcM;

 assign PCSrcE_o = (ZeroE_i && BranchE) || JumpE; // assign PCSrc

 wire [1:0] ALUOp;
 reg [11:0] controls;

 // assign control unit outputs
 assign {RegWriteD,	
	ImmSrcD_o,
    ALUSrcD,
    MemWriteD,
    ResultSrcD,
	BranchD, 
	ALUOp,
	JumpD} = controls;

 always @ * begin
   case (op_i)          //          RW      ImmSrc      ALUSrc      MW      ResultSrc       br    ALUOp         jump
	instr_lw_op:        controls = {1'b1,   imm_Itype,  ALUSrc_imm, 1'b0,   ResultSrc_load, 1'b0, ALUop_mem,    1'b0};       
	instr_sw_op:        controls = {1'b0,   imm_Stype,  ALUSrc_imm, 1'b1,   2'b00,          1'b0, ALUop_mem,    1'b0};  
	instr_Rtype_op:     controls = {1'b1,   3'b000,     ALUSrc_reg, 1'b0,   ResultSrc_ALU,  1'b0, ALUop_other,  1'b0};   
	instr_beq_op:       controls = {1'b0,   imm_Btype,  ALUSrc_reg, 1'b0,   2'b00,          1'b1, ALUop_beq,    1'b0};   
	instr_ItypeALU_op:  controls = {1'b1,   imm_Itype,  ALUSrc_imm, 1'b0,   ResultSrc_ALU,  1'b0, ALUop_other,  1'b0};    
    instr_jal_op:       controls = {1'b1,   imm_Jtype,  ALUSrc_imm, 1'b0,   ResultSrc_jal,  1'b0, ALUop_other,  1'b1};
    instr_lui_op:       controls = {1'b1,   imm_Utype,  ALUSrc_imm, 1'b0,   ResultSrc_lui,  1'b0, ALUop_other,  1'b0};
	default: begin	    
            controls = 12'bx_xxx_x_x_xx_x_xx_x;       
            `ifdef SIM
                $warning("Unsupported op given: %h", op_i);
            `else
            ;
            `endif
            
        end 
   endcase
 end

 // ALU control decode
 wire RtypeSub;

 assign RtypeSub = funct7b5_i & op_i[5];

 always @ * begin
 case(ALUOp)
   ALUop_mem:                 ALUControlD = ALUcontrol_add;
   ALUop_beq:                 ALUControlD = ALUcontrol_sub;
   ALUop_other: 
       case(funct3_i)
           instr_addsub_funct3: 
                 if(RtypeSub) ALUControlD = ALUcontrol_sub;
                 else         ALUControlD = ALUcontrol_add;
           instr_slt_funct3:  ALUControlD = ALUcontrol_slt;  
           instr_or_funct3:   ALUControlD = ALUcontrol_or;
           instr_and_funct3:  ALUControlD = ALUcontrol_and;  
           default: begin
                              ALUControlD = 3'bxxx;
               `ifdef SIM
                   $warning("Unsupported funct3 given: %h", funct3_i);
               `else
                  ;
               `endif  
           end
       endcase
   default: 
      `ifdef SIM
          $warning("Unsupported ALUop given: %h", ALUOp);
      `else
          ;
      `endif   
  endcase
 end

 // Execute Stage Control Signals
 always @(posedge clk) begin
    if (reset) begin
        ALUSrcE_o <= 0;
    end
    else if (!StallD_o) begin
        ALUSrcE_o <= ALUSrcD;
    end
 end

 // Memory Stage Control Signals
 always @(posedge clk) begin
    if (reset) begin
        MemWriteM_o <= 0;
        ResultSrcM_o <= 0;
    end
    else begin
        MemWriteM_o <= MemWriteD;
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

 // Hazard Detection
 wire lwStall = ((Rs1D_i == RdE_i) || (Rs2D_i == RdE_i)) && (op_i == instr_lw_op);
 wire branchStall = BranchD && (RegWriteD && (RdE_i == Rs1D_i || RdE_i == Rs2D_i) ||
                   (MemWriteD && (RdE_i == Rs1D_i || RdE_i == Rs2D_i)));
 assign StallF_o = lwStall || branchStall;
 assign StallD_o = lwStall || branchStall;
 assign FlushD_o = PCSrcE_o || JumpD;
 assign FlushE_o = lwStall || PCSrcE_o;

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


endmodule

