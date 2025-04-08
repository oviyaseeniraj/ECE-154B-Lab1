module ucsbece154b_controller (
    input                clk, reset,
    input         [6:0]  op_i, 
    input         [2:0]  funct3_i,
    input                funct7b5_i,
    input                ZeroE_i,
    input         [4:0]  Rs1D_i,
    input         [4:0]  Rs2D_i,
    input         [4:0]  Rs1E_i,
    input         [4:0]  Rs2E_i,
    input         [4:0]  RdE_i,
    input         [4:0]  RdM_i,
    input         [4:0]  RdW_i,
    output wire          StallF_o,  
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
wire JumpD = (op_i == instr_jal_op) | (op_i == instr_jalr_op);
wire LuiD = (op_i == instr_lui_op);
wire MemWriteD = (op_i == instr_sw_op);
wire ALUSrcD = (op_i == instr_lw_op || op_i == instr_sw_op || op_i == instr_ItypeALU_op);
wire RegWriteD = (op_i == instr_lw_op || op_i == instr_Rtype_op || 
                 op_i == instr_ItypeALU_op || op_i == instr_jal_op || 
                 op_i == instr_jalr_op || op_i == instr_lui_op);

// ALU Decoder
wire [1:0] ALUOpD = (op_i == instr_Rtype_op || op_i == instr_ItypeALU_op) ? ALUop_other :
                   (op_i == instr_beq_op) ? ALUop_beq : ALUop_mem;
wire RtypeSub = funct7b5_i & (op_i == instr_Rtype_op);

// ALU Control
always @ * begin
    case (ALUOpD)
        ALUop_mem:   ALUControlE_o = ALUcontrol_add;
        ALUop_beq:   ALUControlE_o = ALUcontrol_sub;
        ALUop_other: begin
            case (funct3_i)
                instr_addsub_funct3: ALUControlE_o = RtypeSub ? ALUcontrol_sub : ALUcontrol_add;
                instr_slt_funct3:    ALUControlE_o = ALUcontrol_slt;
                instr_or_funct3:     ALUControlE_o = ALUcontrol_or;
                instr_and_funct3:    ALUControlE_o = ALUcontrol_and;
                default:            ALUControlE_o = ALUcontrol_add;
            endcase
        end
        default:     ALUControlE_o = ALUcontrol_add;
    endcase
end

// Immediate Generator
assign ImmSrcD_o = (op_i == instr_lw_op || op_i == instr_ItypeALU_op || op_i == instr_jalr_op) ? imm_Itype :
                  (op_i == instr_sw_op) ? imm_Stype :
                  (op_i == instr_beq_op) ? imm_Btype :
                  (op_i == instr_jal_op) ? imm_Jtype :
                  (op_i == instr_lui_op) ? imm_Utype : imm_Itype;

// Hazard Detection
wire lwStall = ((Rs1D_i == RdE_i) || (Rs2D_i == RdE_i)) && (op_i == instr_lw_op);
wire branchStall = BranchD && (RegWriteD && (RdE_i == Rs1D_i || RdE_i == Rs2D_i) ||
                  (MemWriteD && (RdE_i == Rs1D_i || RdE_i == Rs2D_i)));
assign StallF_o = lwStall || branchStall;
assign StallD_o = lwStall || branchStall;
assign FlushD_o = PCSrcE_o || JumpD;
assign FlushE_o = lwStall || branchStall;

// Forwarding Unit
always @ * begin
    // ForwardAE
    if ((Rs1E_i != 0) && (Rs1E_i == RdM_i) && RegWriteW_o)
        ForwardAE_o = forward_mem;
    else if ((Rs1E_i != 0) && (Rs1E_i == RdW_i) && RegWriteW_o)
        ForwardAE_o = forward_wb;
    else
        ForwardAE_o = forward_ex;
    
    // ForwardBE
    if ((Rs2E_i != 0) && (Rs2E_i == RdM_i) && RegWriteW_o)
        ForwardBE_o = forward_mem;
    else if ((Rs2E_i != 0) && (Rs2E_i == RdW_i) && RegWriteW_o)
        ForwardBE_o = forward_wb;
    else
        ForwardBE_o = forward_ex;
end

// Pipeline Control Signals
assign PCSrcE_o = (BranchD & ZeroE_i) | JumpD;

// Execute Stage Control
always @(posedge clk) begin
    if (reset) begin
        ALUSrcE_o <= SrcB_reg;
    end else if (!StallD_o) begin
        ALUSrcE_o <= ALUSrcD;
    end
end

// Memory Stage Control
always @(posedge clk) begin
    if (reset) begin
        MemWriteM_o <= 1'b0;
        ResultSrcM_o <= MuxResult_aluout;
    end else begin
        MemWriteM_o <= MemWriteD;
        ResultSrcM_o <= (op_i == instr_lw_op) ? MuxResult_mem : MuxResult_aluout;
    end
end

// Writeback Stage Control
always @(posedge clk) begin
    if (reset) begin
        RegWriteW_o <= 1'b0;
        ResultSrcW_o <= MuxResult_aluout;
    end else begin
        RegWriteW_o <= RegWriteD;
        ResultSrcW_o <= (op_i == instr_lw_op) ? MuxResult_mem : 
                       ((op_i == instr_jal_op || op_i == instr_jalr_op) ? MuxResult_PCPlus4 :
                       ((op_i == instr_lui_op) ? MuxResult_imm : MuxResult_aluout));
    end
end

endmodule