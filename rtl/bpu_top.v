//--------------------------------------------------------------------------------
//
// Module: bpu_top.v
//
// Vai tro: khoi du doan re nhanh hybrid, noi ba block bpu_reg (bo nho du doan),
//   bpu_predictor (logic doc/cap nhat) va bpu_ctrl (duong chuyen huong + flush)
//
//-------------------------------------------------------------------------------

`timescale 1ns / 1ps

module bpu_top(
     input          clk
    ,input          rst_n
    ,input          halt
    ,input  [6:0]   fetch_opcode
    ,input  [31:0]  branch_target_fetch
    ,input  [31:0]  nxpc                 
    ,input  [31:0]  nxpc2                
    ,input  [31:0]  pc
    ,input          is_branch
    ,input          branch_taken
    ,input  [31:0]  branch_offset
    ,input  [1:0]   flush_in
    ,output [31:0]  bpu_nxpc2
    ,output         bpu_nxpc2_valid
    ,output [1:0]   bpu_flush
);

// BTB
wire        btb_valid_pc, btb_valid_nxpc, btb_valid_nxpc2;
wire [31:0] btb_target_pc, btb_target_nxpc2;
wire        btb_wr_en;
wire [31:0] btb_wr_target;
// Local BHT
wire [11:0] local_bht_data_pc;
wire        local_bht_wr_en;
wire [11:0] local_bht_wr_data;
// Local PHT
wire [1:0]  local_pht_data_pc, local_pht_data_nxpc2;
wire        local_pht_wr_en;
wire [1:0]  local_pht_wr_data;
// Global PHT
wire [1:0]  global_pht_data_pc, global_pht_data_nxpc2;
wire        global_pht_wr_en;
wire [1:0]  global_pht_wr_data;
// Choice
wire [1:0]  choice_data_pc, choice_data_nxpc2;
wire        choice_wr_en;
wire [1:0]  choice_wr_data;
// GHR
wire [9:0]  ghr_out;
wire        ghr_wr_en;
wire [9:0]  ghr_wr_data;
// Prediction
wire        predict_taken_nxpc2;

// Carry-down: hai bit du doan local/global lay o tang fetch, bpu_ctrl tre 2 chu
// ky de luc cap nhat choice o execute thi dung dung bit da du doan nhanh nay.
wire local_carry;
wire global_carry;

// Bo nho du doan
bpu_reg u_bpu_reg(
     .clk                  (clk)
    ,.rst_n                (rst_n)
    ,.halt                 (halt)
    ,.pc                   (pc)
    ,.nxpc                 (nxpc)
    ,.nxpc2                (nxpc2)
    // BTB
    ,.btb_valid_pc         (btb_valid_pc)
    ,.btb_target_pc        (btb_target_pc)
    ,.btb_valid_nxpc       (btb_valid_nxpc)
    ,.btb_valid_nxpc2      (btb_valid_nxpc2)
    ,.btb_target_nxpc2     (btb_target_nxpc2)
    ,.btb_wr_en            (btb_wr_en)
    ,.btb_wr_target        (btb_wr_target)
    // Local BHT
    ,.local_bht_data_pc    (local_bht_data_pc)
    ,.local_bht_wr_en      (local_bht_wr_en)
    ,.local_bht_wr_data    (local_bht_wr_data)
    // Local PHT
    ,.local_pht_data_pc    (local_pht_data_pc)
    ,.local_pht_data_nxpc2 (local_pht_data_nxpc2)
    ,.local_pht_wr_en      (local_pht_wr_en)
    ,.local_pht_wr_data    (local_pht_wr_data)
    // Global PHT
    ,.global_pht_data_pc   (global_pht_data_pc)
    ,.global_pht_data_nxpc2(global_pht_data_nxpc2)
    ,.global_pht_wr_en     (global_pht_wr_en)
    ,.global_pht_wr_data   (global_pht_wr_data)
    // Choice
    ,.choice_data_pc       (choice_data_pc)
    ,.choice_data_nxpc2    (choice_data_nxpc2)
    ,.choice_wr_en         (choice_wr_en)
    ,.choice_wr_data       (choice_wr_data)
    // GHR
    ,.ghr_out              (ghr_out)
    ,.ghr_wr_en            (ghr_wr_en)
    ,.ghr_wr_data          (ghr_wr_data)
);

bpu_predictor u_bpu_predictor(
     .pc                   (pc)
    ,.is_branch            (is_branch)
    // BTB
    ,.branch_offset        (branch_offset)
    ,.btb_wr_en            (btb_wr_en)
    ,.btb_wr_target        (btb_wr_target)
    // Local BHT
    ,.branch_taken         (branch_taken)
    ,.local_bht_data_pc    (local_bht_data_pc)
    ,.local_bht_wr_en      (local_bht_wr_en)
    ,.local_bht_wr_data    (local_bht_wr_data)
    // Local PHT  
    ,.local_pht_data_pc    (local_pht_data_pc)
    ,.local_pht_data_nxpc2 (local_pht_data_nxpc2)
    ,.local_pht_wr_en      (local_pht_wr_en)
    ,.local_pht_wr_data    (local_pht_wr_data)
    // Global PHT
    ,.global_pht_data_pc   (global_pht_data_pc)
    ,.global_pht_data_nxpc2(global_pht_data_nxpc2)
    ,.global_pht_wr_en     (global_pht_wr_en)
    ,.global_pht_wr_data   (global_pht_wr_data)
    // Choice
    ,.btb_valid_pc         (btb_valid_pc)
    ,.choice_data_pc       (choice_data_pc)
    ,.choice_data_nxpc2    (choice_data_nxpc2)
    ,.choice_wr_en         (choice_wr_en)
    ,.choice_wr_data       (choice_wr_data)
    // GHR
    ,.ghr_out              (ghr_out)
    ,.ghr_wr_en            (ghr_wr_en)
    ,.ghr_wr_data          (ghr_wr_data)
    // Prediction
    ,.predict_taken_nxpc2  (predict_taken_nxpc2)
    // Carry-down cho viec cap nhat choice
	,.local_carry          (local_carry)
    ,.global_carry         (global_carry)
);

// Duong chuyen huong va ma flush
bpu_ctrl u_bpu_ctrl(
     .clk                  (clk)               
    ,.rst_n                (rst_n)             
    ,.halt                 (halt)              
    ,.pc                   (pc)
    ,.nxpc                 (nxpc)
    // pre-compute
    ,.fetch_opcode         (fetch_opcode)
    ,.flush_in             (flush_in)
    // execute (correction) 
    ,.is_branch            (is_branch)
    ,.branch_taken         (branch_taken)
    ,.branch_offset        (branch_offset)     
    ,.btb_target_pc        (btb_target_pc)
    ,.bpu_flush            (bpu_flush)
    // fetch (NXPC2)
    ,.btb_valid_nxpc2      (btb_valid_nxpc2)
    ,.predict_taken_nxpc2  (predict_taken_nxpc2)
    ,.btb_target_nxpc2     (btb_target_nxpc2)
    // decode (NXPC)
    ,.btb_valid_nxpc       (btb_valid_nxpc)
    ,.branch_target_fetch  (branch_target_fetch)
    // output MUX
    ,.bpu_nxpc2            (bpu_nxpc2)
    ,.bpu_nxpc2_valid      (bpu_nxpc2_valid)
	// Nguon carry-down: bit tho, chua qua MUX tournament
	,.local_pht_data_nxpc2 (local_pht_data_nxpc2)
	,.global_pht_data_nxpc2(global_pht_data_nxpc2)
	,.local_carry          (local_carry)
	,.global_carry         (global_carry)
);

endmodule
