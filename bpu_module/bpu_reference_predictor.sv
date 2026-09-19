//------------------------------------------------------------------------------
// FILE: bpu_reference_predictor.sv    `include VAO trong than class bpu_reference
//
// Vai tro: soi guong bpu_predictor.v -- du doan tournament va du lieu ghi cho moi
//   bang.
//
//   Moi ham o day CHI DOC trang thai bong, khong ham nao sua. compute_*_wr_data()
//   tra ve gia tri SE duoc ghi; con viec chan theo is_branch/halt va ghi that thi
//   apply_update() lo.
//
//   Phai `include SAU bpu_reference_state.sv (dung hang so va cac ham read_* cua
//   tep do).
//
//------------------------------------------------------------------------------

//==========================================================================
// Bo dem bao hoa 2 bit
//==========================================================================
function automatic bit [1:0] update_counter(bit [1:0] current, bit taken);
   case (current)
      ST:  update_counter = taken ? ST  : WT ;
      WT:  update_counter = taken ? ST  : WNT;
      WNT: update_counter = taken ? WT  : SNT;
      SNT: update_counter = taken ? WNT : SNT;
      default: update_counter = WT;       // khop nhanh default cua RTL
   endcase
endfunction

//==========================================================================
// Du doan tournament, tai ca ba dia chi doc
//   predict_taken = choice[1] ? global_pht[1] : local_pht[1]
// Chi ban nxpc2 la thuc su lai DUT; hai ban kia chi de coverage.
//==========================================================================
function automatic bit predict_taken_pc(bit [31:0] pc);
   bit [1:0] choice_val;
   bit [1:0] local_pht_val;
   bit [1:0] global_pht_val;
   choice_val     = read_choice_pc(pc);
   local_pht_val  = read_local_pht_pc(pc);
   global_pht_val = read_global_pht_pc(pc);
   predict_taken_pc = choice_val[1] ? global_pht_val[1] : local_pht_val[1];
endfunction

function automatic bit predict_taken_nxpc(bit [31:0] nxpc);
   bit [1:0] choice_val;
   bit [1:0] local_pht_val;
   bit [1:0] global_pht_val;
   choice_val     = read_choice_nxpc(nxpc);
   local_pht_val  = read_local_pht_nxpc(nxpc);
   global_pht_val = read_global_pht_nxpc(nxpc);
   predict_taken_nxpc = choice_val[1] ? global_pht_val[1] : local_pht_val[1];
endfunction

function automatic bit predict_taken_nxpc2(bit [31:0] nxpc2);
   bit [1:0] choice_val;
   bit [1:0] local_pht_val;
   bit [1:0] global_pht_val;
   choice_val     = choice[get_nxpc2_index(nxpc2)];
   local_pht_val  = local_pht[get_local_pht_index_nxpc2(nxpc2)];
   global_pht_val = global_pht[get_global_pht_index_nxpc2(nxpc2)];
   predict_taken_nxpc2 = choice_val[1] ? global_pht_val[1] : local_pht_val[1];
endfunction

//==========================================================================
// Du lieu ghi BTB: pc + branch_offset
//==========================================================================
function automatic bit [31:0] compute_btb_wr_target(bit [31:0] pc,
                                                    bit [31:0] branch_offset);
   compute_btb_wr_target = pc + branch_offset;
endfunction

//==========================================================================
// Du lieu ghi Local BHT: dich branch_taken vao lich su 12 bit
//==========================================================================
function automatic bit [11:0] compute_local_bht_wr_data(bit [31:0] pc,
                                                        bit        branch_taken);
   bit [11:0] cur_bht;
   cur_bht = read_local_bht_pc(pc);
   compute_local_bht_wr_data = {cur_bht[10:0], branch_taken};
endfunction

//==========================================================================
// Du lieu ghi Local PHT: BTB trung thi cap nhat bao hoa, truot thi khoi tao WT
//==========================================================================
function automatic bit [1:0] compute_local_pht_wr_data(bit [31:0] pc,
                                                       bit        branch_taken);
   bit       btb_valid;
   bit [1:0] cur_pht;
   btb_valid = read_btb_valid_pc(pc);
   cur_pht   = read_local_pht_pc(pc);
   compute_local_pht_wr_data = btb_valid ? update_counter(cur_pht, branch_taken)
                                         : WT;
endfunction

//==========================================================================
// Du lieu ghi Global PHT: cung quy tac voi local PHT
//==========================================================================
function automatic bit [1:0] compute_global_pht_wr_data(bit [31:0] pc,
                                                        bit        branch_taken);
   bit       btb_valid;
   bit [1:0] cur_pht;
   btb_valid = read_btb_valid_pc(pc);
   cur_pht   = read_global_pht_pc(pc);
   compute_global_pht_wr_data = btb_valid ? update_counter(cur_pht, branch_taken)
                                          : WT;
endfunction

//==========================================================================
// Cho phep ghi Choice: chi khi hai bo du doan BAT DONG va BTB trung. Khong kiem
// is_branch o day -- apply_update() da chan truoc roi.
//
// local_carry/global_carry la carry-down cua hai bit du doan tho tai nxpc2, nen
// choice duoc cham diem theo cai DA doc luc fetch, khong phai doc lai cung bang
// do o thoi diem execute.
//==========================================================================
function automatic bit compute_choice_should_write(bit [31:0] pc,
                                                    bit        local_carry,
                                                    bit        global_carry);
   bit disagree;
   bit btb_valid;
   disagree  = (local_carry != global_carry);
   btb_valid = read_btb_valid_pc(pc);
   compute_choice_should_write = disagree && btb_valid;
endfunction

//==========================================================================
// Du lieu ghi Choice
//   chi global dung -> dem len   (ve phia global)
//   chi local dung  -> dem xuong (ve phia local)
//   hai ben giong nhau -> giu nguyen
//==========================================================================
function automatic bit [1:0] compute_choice_wr_data(bit [31:0] pc,
                                                    bit        branch_taken,
                                                    bit        local_carry,
                                                    bit        global_carry);
   bit [1:0] cur_choice;
   bit       local_corr;
   bit       global_corr;

   cur_choice  = read_choice_pc(pc);
   local_corr  = (local_carry  == branch_taken);
   global_corr = (global_carry == branch_taken);

   if (!local_corr && global_corr)
      compute_choice_wr_data = update_counter(cur_choice, 1'b1);
   else if (local_corr && !global_corr)
      compute_choice_wr_data = update_counter(cur_choice, 1'b0);
   else
      compute_choice_wr_data = cur_choice;
endfunction

//==========================================================================
// Du lieu ghi GHR: dich branch_taken vao lich su toan cuc 10 bit
//==========================================================================
function automatic bit [9:0] compute_ghr_wr_data(bit branch_taken);
   bit [9:0] cur_ghr;
   cur_ghr = read_ghr();
   compute_ghr_wr_data = {cur_ghr[8:0], branch_taken};
endfunction
