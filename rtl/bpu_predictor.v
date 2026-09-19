//--------------------------------------------------------------------------------
//
// Module: bpu_predictor.v
//
// Vai tro: logic to hop doc/cap nhat quanh bpu_reg -- sinh du doan tournament tai
//   nxpc2 va du lieu ghi cho moi bang. Moi wr_en deu la is_branch, nen bang chi
//   doi khi co nhanh duoc giai quyet o execute.
//
//-------------------------------------------------------------------------------

`timescale 1ns / 1ps

module bpu_predictor(
     input 	[31:0] 	pc
    ,input         	is_branch
    ,input         	branch_taken
    ,input  [31:0] 	branch_offset
    // BTB
    ,input         	btb_valid_pc
	,output         btb_wr_en
    ,output [31:0]  btb_wr_target
    // Local BHT
    ,input  [11:0]  local_bht_data_pc
    ,output       	local_bht_wr_en
    ,output [11:0]  local_bht_wr_data
    // Local PHT
    ,input  [1:0]  	local_pht_data_pc
    ,input  [1:0]  	local_pht_data_nxpc2        
  	,output         local_pht_wr_en
    ,output [1:0]   local_pht_wr_data
    // Global PHT
    ,input  [1:0]  	global_pht_data_pc
    ,input  [1:0]  	global_pht_data_nxpc2       
    ,output         global_pht_wr_en
    ,output [1:0]   global_pht_wr_data
    // Choice
    ,input  [1:0]  	choice_data_pc
    ,input  [1:0]  	choice_data_nxpc2           
	,output         choice_wr_en
    ,output [1:0]   choice_wr_data
    // GHR
    ,input  [9:0]  	ghr_out
	,output         ghr_wr_en
    ,output [9:0]   ghr_wr_data
    // Prediction output
    ,output        	predict_taken_nxpc2         
    ,input          local_carry    
    ,input          global_carry   
);

parameter SNT = 2'b00;
parameter WNT = 2'b01;
parameter WT  = 2'b10;
parameter ST  = 2'b11;

// Du doan tournament: MSB cua choice chon tin bo nao
//   choice[1]=1 -> global (gshare), choice[1]=0 -> local (lich su rieng tung PC)
assign predict_taken_nxpc2 = choice_data_nxpc2[1] ? global_pht_data_nxpc2[1] : local_pht_data_nxpc2[1];

// Bo dem bao hoa 2 bit: SNT <-> WNT <-> WT <-> ST
function [1:0] update_counter;
	input [1:0] current;
	input taken;
	begin
		case(current)
			ST:  update_counter = taken ? ST  : WT ;
			WT:  update_counter = taken ? ST  : WNT;
			WNT: update_counter = taken ? WT  : SNT;
			SNT: update_counter = taken ? WNT : SNT;
			default: update_counter = WT;
		endcase
	end
endfunction

// BTB: ghi lai dia chi dich da giai quyet cua PC nay
assign btb_wr_en 	 = is_branch;
assign btb_wr_target = pc + branch_offset;

// Local BHT: dich ket qua vao lich su 12 bit cua rieng PC nay
assign local_bht_wr_en 	 = is_branch;
assign local_bht_wr_data = is_branch	? {local_bht_data_pc[10:0], branch_taken}	:
									 	  local_bht_data_pc;

// Local PHT: BTB trung thi cap nhat bao hoa, BTB truot thi khoi tao WT (lan dau
// gap PC nay thi chua co bo dem nao dang de cap nhat)
assign local_pht_wr_en 	 = is_branch;
assign local_pht_wr_data = btb_valid_pc	? update_counter(local_pht_data_pc, branch_taken)	:
										  WT;

// Global PHT: cung quy tac voi local PHT
assign global_pht_wr_en   = is_branch;
assign global_pht_wr_data = btb_valid_pc	? update_counter(global_pht_data_pc, branch_taken)	:
											  WT;

// Choice: cham diem theo bit carry-down, tuc hai bit local/global doc luc fetch
// cua CHINH nhanh nay, khong phai hai bit doc o execute dung ben tren.
wire   disagree       = (local_carry  != global_carry);
wire   local_correct  = (local_carry  == branch_taken);   
wire   global_correct = (global_carry == branch_taken);   

// Chi doi choice khi hai bo du doan BAT DONG; neu chung dong y thi ket qua khong
// noi len bo nao tot hon.
assign choice_wr_en   = disagree && is_branch && btb_valid_pc;

// Chi global dung thi dem len (ve phia global), chi local dung thi dem xuong.
assign choice_wr_data = (!local_correct && global_correct)	? update_counter(choice_data_pc, 1'b1)	:
						(local_correct && !global_correct)	? update_counter(choice_data_pc, 1'b0)	:
										   					  choice_data_pc						;

// GHR: dich ket qua vao lich su toan cuc 10 bit
assign ghr_wr_en   = is_branch;
assign ghr_wr_data = is_branch	? {ghr_out[8:0], branch_taken}	:
								  ghr_out						;

endmodule
