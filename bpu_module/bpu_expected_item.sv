//------------------------------------------------------------------------------
//
// CLASS: bpu_expected_item
//
// Vai tro: ngo ra ma mo hinh tham chieu cho rang DUT phai xuat trong chu ky nay
//
//------------------------------------------------------------------------------

class bpu_expected_item extends uvm_sequence_item;

   bit [31:0] pc;
   bit [31:0] nxpc;
   bit [6:0]  fetch_opcode;
   bit [31:0] branch_target_fetch;
   bit [1:0]  flush_in;
   bit        halt;
   bit        is_branch;
   bit        branch_taken;
   bit [31:0] branch_offset;

   //--------------------------------------------------------------------------
   // Ba truong DUY NHAT ma scoreboard thuc su so sanh
   //--------------------------------------------------------------------------
   bit [31:0] expected_bpu_nxpc2;
   bit        expected_bpu_nxpc2_valid;
   bit [1:0]  expected_bpu_flush;

   //--------------------------------------------------------------------------
   // Trang thai noi bo 
   //--------------------------------------------------------------------------
   bit        predict_taken_pc;
   bit        predict_taken_nxpc;
   bit        predict_taken_nxpc2;
   bit        btb_valid_pc;
   bit        btb_valid_nxpc;
   bit        btb_valid_nxpc2;
   bit [31:0] nxpc2;
   bit        spec_valid;
   bit        corr_valid;
   bit [1:0]  spec_case;   // tang nao chuyen huong: 0=khong, 1=fetch, 2=du phong
   bit [1:0]  corr_case;   // 0=khong, 1=co hieu chinh o execute

   //--------------------------------------------------------------------------
   // Tu dong hoa truong cua UVM
   //--------------------------------------------------------------------------
   `uvm_object_utils_begin(bpu_expected_item)
      `uvm_field_int(pc,                       UVM_ALL_ON)
      `uvm_field_int(nxpc,                     UVM_ALL_ON)
      `uvm_field_int(fetch_opcode,             UVM_ALL_ON)
      `uvm_field_int(branch_target_fetch,      UVM_ALL_ON)
      `uvm_field_int(flush_in,                 UVM_ALL_ON)
      `uvm_field_int(halt,                     UVM_ALL_ON)
      `uvm_field_int(is_branch,                UVM_ALL_ON)
      `uvm_field_int(branch_taken,             UVM_ALL_ON)
      `uvm_field_int(branch_offset,            UVM_ALL_ON)
      `uvm_field_int(expected_bpu_nxpc2,       UVM_ALL_ON)
      `uvm_field_int(expected_bpu_nxpc2_valid, UVM_ALL_ON)
      `uvm_field_int(expected_bpu_flush,       UVM_ALL_ON)
      `uvm_field_int(predict_taken_pc,          UVM_ALL_ON)
      `uvm_field_int(predict_taken_nxpc,        UVM_ALL_ON)
      `uvm_field_int(predict_taken_nxpc2,       UVM_ALL_ON | UVM_NOCOMPARE)
      `uvm_field_int(btb_valid_pc,              UVM_ALL_ON)
      `uvm_field_int(btb_valid_nxpc,            UVM_ALL_ON)
      `uvm_field_int(btb_valid_nxpc2,           UVM_ALL_ON | UVM_NOCOMPARE)
      `uvm_field_int(nxpc2,                     UVM_ALL_ON | UVM_NOCOMPARE)
      `uvm_field_int(spec_valid,               UVM_ALL_ON)
      `uvm_field_int(corr_valid,               UVM_ALL_ON)
      `uvm_field_int(spec_case,                UVM_ALL_ON)
      `uvm_field_int(corr_case,                UVM_ALL_ON)
   `uvm_object_utils_end

   function new (string name = "bpu_expected_item");
      super.new(name);
   endfunction : new

endclass : bpu_expected_item
