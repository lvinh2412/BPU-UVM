parameter bit [6:0] BPU_OPCODE_BRANCH = 7'b1100011;

//------------------------------------------------------------------------------
//
// CLASS: bpu_item
//
// Vai tro: MOT chu ky tren toan bo interface cua BPU
//
//------------------------------------------------------------------------------

class bpu_item extends uvm_sequence_item;

  rand bit [31:0]  pc;
  rand bit [31:0]  nxpc;
  rand bit [31:0]  nxpc2;
  rand bit [6:0]   fetch_opcode;
  rand bit [31:0]  branch_target_fetch;
  rand bit [1:0]   flush_in;
  rand bit         halt;

  rand bit         is_branch;
  rand bit         branch_taken;
  rand bit [31:0]  branch_offset;

  bit [31:0]  bpu_nxpc2;
  bit         bpu_nxpc2_valid;
  bit [1:0]   bpu_flush;

  `uvm_object_utils_begin(bpu_item)
    `uvm_field_int(pc,                  UVM_ALL_ON)
    `uvm_field_int(nxpc,                UVM_ALL_ON)
    `uvm_field_int(nxpc2,               UVM_ALL_ON)
    `uvm_field_int(fetch_opcode,        UVM_ALL_ON)
    `uvm_field_int(branch_target_fetch, UVM_ALL_ON)
    `uvm_field_int(flush_in,            UVM_ALL_ON)
    `uvm_field_int(halt,                UVM_ALL_ON)
    `uvm_field_int(is_branch,           UVM_ALL_ON)
    `uvm_field_int(branch_taken,        UVM_ALL_ON)
    `uvm_field_int(branch_offset,       UVM_ALL_ON)
    `uvm_field_int(bpu_nxpc2,           UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_field_int(bpu_nxpc2_valid,     UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_field_int(bpu_flush,           UVM_ALL_ON | UVM_NOCOMPARE)
  `uvm_object_utils_end

  function new (string name = "bpu_item");
    super.new(name);
  endfunction : new

  constraint c_pc_aligned    { pc[1:0] == 2'b00; }
  constraint c_nxpc_aligned  { nxpc[1:0] == 2'b00; }
  constraint c_nxpc2_aligned { nxpc2[1:0] == 2'b00; }

  constraint c_nxpc2_seq     { soft nxpc2 == nxpc + 32'd4; }

  constraint c_flush_legal   { flush_in != 2'b11; }

  constraint c_offset_aligned { branch_offset[0] == 1'b0; }

endclass : bpu_item

//------------------------------------------------------------------------------
//
// CLASS: bpu_idle_item
//
// Vai tro: mot chu ky nghi -- dia chi tuan tu, opcode khong phai nhanh, khong halt,
// khong flush, va khong giai quyet nhanh nao
//
//------------------------------------------------------------------------------

class bpu_idle_item extends bpu_item;

  `uvm_object_utils(bpu_idle_item)

  function new (string name = "bpu_idle_item");
    super.new(name);
  endfunction : new

  // O day la rang buoc CUNG, khac ban mem cua lop cha
  constraint c_sequential   { nxpc == pc + 32'd4; }
  constraint c_nxpc2_idle   { nxpc2 == pc + 32'd8; }
  constraint c_no_halt      { halt == 1'b0; }
  constraint c_no_flush     { flush_in == 2'b00; }
  constraint c_non_branch   { fetch_opcode != BPU_OPCODE_BRANCH; }

  constraint c_no_branch    { is_branch == 1'b0; }
  constraint c_no_taken     { branch_taken == 1'b0; }
  constraint c_zero_offset  { branch_offset == 32'h0; }

endclass : bpu_idle_item
