//------------------------------------------------------------------------------
// FILE: bpu_reference_state.sv     `include VAO trong than class bpu_reference
//
// Vai tro: phan bo nho cua mo hinh bong, soi guong bpu_reg.v -- sau bang cong GHR,
//   phep tinh chi muc, cac ham doc, reset va cac ham ghi tho.
//
//   Cac lenh ghi o day chay LAN LUOT, con RTL thi cung roi vao mot canh clock.
//   Dieu do quan trong voi local_pht (chi muc la local_bht) va global_pht (chi muc
//   qua ghr): ghi local_bht truoc se lam chi muc local_pht doi theo. Vi vay
//   write_*_raw() nhan san chi muc, va apply_update() chup het chi muc tu dau.
//
//------------------------------------------------------------------------------

//--------------------------------------------------------------------------
// Cac trang thai cua bo dem bao hoa 2 bit
//--------------------------------------------------------------------------
static const bit [1:0] SNT = 2'b00;   // chac chan KHONG re
static const bit [1:0] WNT = 2'b01;   // yeu, nghieng KHONG re
static const bit [1:0] WT  = 2'b10;   // yeu, nghieng RE
static const bit [1:0] ST  = 2'b11;   // chac chan RE

//--------------------------------------------------------------------------
// Cac bang bong -- dung kich thuoc va do rong nhu bpu_reg.v
//--------------------------------------------------------------------------
bit        btb_valid    [0:1023];
bit [31:0] btb_target   [0:1023];
bit [11:0] local_bht    [0:1023];
bit [1:0]  local_pht    [0:4095];
bit [1:0]  global_pht   [0:1023];
bit [1:0]  choice       [0:1023];
bit [9:0]  ghr;
bit [1:0]  bimodal_pht  [0:1023];   // chi de lam moc so sanh, RTL khong co bang nay

//--------------------------------------------------------------------------
// Cac ham tinh chi muc. Khong cho nao co truong tag, nen trung chi muc la chuyen
// binh thuong:
//   pc_index    = pc[11:2]            10 bit -> 1024
//   lpht_idx_pc = local_bht[pc_index] 12 bit -> 4096  (hai muc)
//   gpht_idx_pc = pc_index ^ ghr      10 bit -> 1024  (gshare)
//--------------------------------------------------------------------------
function automatic bit [9:0] get_pc_index(bit [31:0] pc);
   get_pc_index = pc[11:2];
endfunction

function automatic bit [9:0] get_nxpc_index(bit [31:0] nxpc);
   get_nxpc_index = nxpc[11:2];
endfunction

function automatic bit [11:0] get_local_pht_index_pc(bit [31:0] pc);
   get_local_pht_index_pc = local_bht[get_pc_index(pc)];
endfunction

function automatic bit [11:0] get_local_pht_index_nxpc(bit [31:0] nxpc);
   get_local_pht_index_nxpc = local_bht[get_nxpc_index(nxpc)];
endfunction

function automatic bit [9:0] get_global_pht_index_pc(bit [31:0] pc);
   get_global_pht_index_pc = get_pc_index(pc) ^ ghr;
endfunction

function automatic bit [9:0] get_global_pht_index_nxpc(bit [31:0] nxpc);
   get_global_pht_index_nxpc = get_nxpc_index(nxpc) ^ ghr;
endfunction

function automatic bit [9:0] get_nxpc2_index(bit [31:0] nxpc2);
   get_nxpc2_index = nxpc2[11:2];
endfunction

function automatic bit [11:0] get_local_pht_index_nxpc2(bit [31:0] nxpc2);
   get_local_pht_index_nxpc2 = local_bht[get_nxpc2_index(nxpc2)];
endfunction

function automatic bit [9:0] get_global_pht_index_nxpc2(bit [31:0] nxpc2);
   get_global_pht_index_nxpc2 = get_nxpc2_index(nxpc2) ^ ghr;
endfunction

//--------------------------------------------------------------------------
// Hai bit du doan tho tai nxpc2, dung de nap vao carry-down cho choice. Day la y
// kien RIENG cua tung bo du doan -- CO Y khong phai ket qua tournament.
//--------------------------------------------------------------------------
function automatic bit read_local_pht_bit_nxpc2(bit [31:0] nxpc2);
   read_local_pht_bit_nxpc2 = local_pht[get_local_pht_index_nxpc2(nxpc2)][1];
endfunction

function automatic bit read_global_pht_bit_nxpc2(bit [31:0] nxpc2);
   read_global_pht_bit_nxpc2 = global_pht[get_global_pht_index_nxpc2(nxpc2)][1];
endfunction

function automatic bit read_btb_valid_nxpc2(bit [31:0] nxpc2);
   read_btb_valid_nxpc2 = btb_valid[get_nxpc2_index(nxpc2)];
endfunction

function automatic bit [31:0] read_btb_target_nxpc2(bit [31:0] nxpc2);
   read_btb_target_nxpc2 = btb_target[get_nxpc2_index(nxpc2)];
endfunction

//--------------------------------------------------------------------------
// Cac ham doc, moi ham ung voi mot cong doc to hop cua bpu_reg.v. Cung mot bang,
// khac dia chi: _pc cho duong cap nhat, _nxpc cho tang du phong, _nxpc2 cho du
// doan o fetch.
//--------------------------------------------------------------------------
function automatic bit read_btb_valid_pc(bit [31:0] pc);
   read_btb_valid_pc = btb_valid[get_pc_index(pc)];
endfunction

function automatic bit [31:0] read_btb_target_pc(bit [31:0] pc);
   read_btb_target_pc = btb_target[get_pc_index(pc)];
endfunction

function automatic bit read_btb_valid_nxpc(bit [31:0] nxpc);
   read_btb_valid_nxpc = btb_valid[get_nxpc_index(nxpc)];
endfunction

function automatic bit [31:0] read_btb_target_nxpc(bit [31:0] nxpc);
   read_btb_target_nxpc = btb_target[get_nxpc_index(nxpc)];
endfunction

function automatic bit [11:0] read_local_bht_pc(bit [31:0] pc);
   read_local_bht_pc = local_bht[get_pc_index(pc)];
endfunction

function automatic bit [11:0] read_local_bht_nxpc(bit [31:0] nxpc);
   read_local_bht_nxpc = local_bht[get_nxpc_index(nxpc)];
endfunction

function automatic bit [1:0] read_local_pht_pc(bit [31:0] pc);
   read_local_pht_pc = local_pht[get_local_pht_index_pc(pc)];
endfunction

function automatic bit [1:0] read_local_pht_nxpc(bit [31:0] nxpc);
   read_local_pht_nxpc = local_pht[get_local_pht_index_nxpc(nxpc)];
endfunction

function automatic bit [1:0] read_global_pht_pc(bit [31:0] pc);
   read_global_pht_pc = global_pht[get_global_pht_index_pc(pc)];
endfunction

function automatic bit [1:0] read_global_pht_nxpc(bit [31:0] nxpc);
   read_global_pht_nxpc = global_pht[get_global_pht_index_nxpc(nxpc)];
endfunction

function automatic bit [1:0] read_choice_pc(bit [31:0] pc);
   read_choice_pc = choice[get_pc_index(pc)];
endfunction

function automatic bit [1:0] read_choice_nxpc(bit [31:0] nxpc);
   read_choice_nxpc = choice[get_nxpc_index(nxpc)];
endfunction

function automatic bit [9:0] read_ghr();
   read_ghr = ghr;
endfunction

//--------------------------------------------------------------------------
// reset_state -- reset khong dong bo, giong bpu_reg.v. Moi thu ve 0, tru choice ve
// WNT de tournament bat dau o phia local. Xoa luon cac thanh ghi carry-down khai
// bao ben bpu_reference.sv.
//--------------------------------------------------------------------------
function void reset_state();
   int i;
   for (i = 0; i < 1024; i++) begin
      btb_valid[i]   = 1'b0;
      btb_target[i]  = 32'h0;
      local_bht[i]   = 12'h0;
      global_pht[i]  = SNT;
      choice[i]      = WNT;
      bimodal_pht[i] = SNT;
   end
   for (i = 0; i < 4096; i++) begin
      local_pht[i]  = SNT;
   end
   ghr = 10'h0;
   cd_fetch_steer  = 1'b0;
   cd_fetch_hit    = 1'b0;
   cd_steer        = 1'b0;
   cd_hit          = 1'b0;
   cd_fetch_local  = 1'b0;
   cd_fetch_global = 1'b0;
   cd_local_b      = 1'b0;
   cd_global_b     = 1'b0;
   choice_local_carry  = 1'b0;
   choice_global_carry = 1'b0;
   `uvm_info("BPU_REF_STATE",
             "reset_state(): all tables cleared; choice[*]=WNT",
             UVM_HIGH)
endfunction

//--------------------------------------------------------------------------
// Cac ham ghi tho. Ghi vo dieu kien: apply_update() lo phan chan theo halt va
// is_branch, va truyen vao chi muc da chup truoc lenh ghi dau tien.
//--------------------------------------------------------------------------
// Ghi ca bit valid lan dia chi dich, giong RTL
function void write_btb_raw(bit [9:0] idx, bit [31:0] target);
   btb_valid[idx]  = 1'b1;
   btb_target[idx] = target;
endfunction

function void write_local_bht_raw(bit [9:0] idx, bit [11:0] data);
   local_bht[idx] = data;
endfunction

function void write_local_pht_raw(bit [11:0] idx, bit [1:0] data);
   local_pht[idx] = data;
endfunction

function void write_global_pht_raw(bit [9:0] idx, bit [1:0] data);
   global_pht[idx] = data;
endfunction

function void write_choice_raw(bit [9:0] idx, bit [1:0] data);
   choice[idx] = data;
endfunction

function void write_ghr_raw(bit [9:0] data);
   ghr = data;
endfunction
