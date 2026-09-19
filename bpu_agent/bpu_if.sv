//=============================================================================
// File: bpu_if.sv
//
// Vai tro: dong goi TOAN BO chan cua DUT -- 10 ngo vao do testbench lai va 3 ngo
//   ra do DUT phat.
//
//=============================================================================

interface bpu_if (input bit clock, input bit reset);
   timeunit      1ns;
   timeprecision 100ps;

   import uvm_pkg::*;
   `include "uvm_macros.svh"

   //==========================================================================
   // SIGNALS
   //==========================================================================

   // Do driver lai -- phia fetch
   //   pc    -> tang execute: nhanh dang duoc giai quyet
   //   nxpc  -> tang decode:  tra bang cho tang du phong
   //   nxpc2 -> tang fetch:   tra bang de du doan
   logic              halt;
   logic       [6:0]  fetch_opcode;
   logic      [31:0]  branch_target_fetch;
   logic      [31:0]  nxpc;
   logic      [31:0]  nxpc2;
   logic      [31:0]  pc;
   logic       [1:0]  flush_in;

   // Do driver lai -- phia execute
   //   is_branch      chu ky nay co nhanh dang duoc giai quyet -- cung la wr_en cua
   //                  MOI bang, nen khong co no thi khong gi trong BPU thay doi
   //   branch_taken   ket qua that
   //   branch_offset  immediate B-type da mo rong dau
   logic              is_branch;
   logic              branch_taken;
   logic      [31:0]  branch_offset;

   // Do monitor lay mau -- ba ngo ra cua DUT
   logic      [31:0]  bpu_nxpc2;
   logic              bpu_nxpc2_valid;
   logic       [1:0]  bpu_flush;

   // Xung danh dau transaction de xem tren song; driver cho drvstart de begin_tr
   // trung khop voi chan tin hieu
   bit drvstart;
   bit monstart;

   // ASSERTION bi tat cho toi khi thay tron mot chu ky reset, de khong bao loi vi
   // cac gia tri X luc thoi diem 0
   bit reset_done = 1'b0;
   initial begin
      @(posedge reset);
      @(negedge reset);
      reset_done = 1'b1;
   end

   //==========================================================================
   // bpu_reset -- cho toi khi reset len, xoa ngo vao va bo lan lai dang do, de
   // mot chu ky lai dang do khong song sot qua reset.
   //==========================================================================
   task bpu_reset();
      @(posedge reset);
      `uvm_info("BPU_IF", "Reset observed; clearing BPU inputs", UVM_MEDIUM)
      halt                <= 1'b0;
      fetch_opcode        <= 7'h0;
      branch_target_fetch <= 32'h0;
      nxpc                <= 32'h0;
      nxpc2               <= 32'h0;
      pc                  <= 32'h0;
      flush_in            <= 2'b00;
      is_branch           <= 1'b0;
      branch_taken        <= 1'b0;
      branch_offset       <= 32'h0;
      drvstart            <= 1'b0;
      disable drive_bpu_input;
   endtask : bpu_reset

   //==========================================================================
   // drive_bpu_input -- mot chu ky ngo vao, dat o negedge
   //==========================================================================
   task drive_bpu_input(
      input bit          in_halt,
      input bit  [6:0]   in_fetch_opcode,
      input bit [31:0]   in_branch_target_fetch,
      input bit [31:0]   in_nxpc,
      input bit [31:0]   in_nxpc2,
      input bit [31:0]   in_pc,
      input bit  [1:0]   in_flush_in,
      input bit          in_is_branch,
      input bit          in_branch_taken,
      input bit [31:0]   in_branch_offset
   );
      @(negedge clock);
      drvstart            <= 1'b1;
      halt                <= in_halt;
      fetch_opcode        <= in_fetch_opcode;
      branch_target_fetch <= in_branch_target_fetch;
      nxpc                <= in_nxpc;
      nxpc2               <= in_nxpc2;
      pc                  <= in_pc;
      flush_in            <= in_flush_in;
      is_branch           <= in_is_branch;
      branch_taken        <= in_branch_taken;
      branch_offset       <= in_branch_offset;
      @(posedge clock);
      drvstart            <= 1'b0;
   endtask : drive_bpu_input

   //==========================================================================
   // park_bus -- ha ba tin hieu phia execute khi dong item can.
   //
   // Khong tieu thu thoi gian: nguoi goi tu canh thoi diem (negedge).
   //==========================================================================
   task park_bus();
      is_branch     <= 1'b0;
      branch_taken  <= 1'b0;
      branch_offset <= 32'h0;
   endtask : park_bus

   //==========================================================================
   // sample_bpu_all -- chup mot lan o posedge toan bo tin hieu cua interface.
   //==========================================================================
   task sample_bpu_all(
      output bit          out_halt,
      output bit [6:0]    out_fetch_opcode,
      output bit [31:0]   out_branch_target_fetch,
      output bit [31:0]   out_nxpc,
      output bit [31:0]   out_nxpc2,
      output bit [31:0]   out_pc,
      output bit [1:0]    out_flush_in,
      output bit          out_is_branch,
      output bit          out_branch_taken,
      output bit [31:0]   out_branch_offset,
      output bit [31:0]   out_bpu_nxpc2,
      output bit          out_bpu_nxpc2_valid,
      output bit [1:0]    out_bpu_flush
   );
      @(posedge clock);
      monstart                = 1'b1;
      // Ngo vao -- phia fetch
      out_halt                = halt;
      out_fetch_opcode        = fetch_opcode;
      out_branch_target_fetch = branch_target_fetch;
      out_nxpc                = nxpc;
      out_nxpc2               = nxpc2;
      out_pc                  = pc;
      out_flush_in            = flush_in;
      // Ngo vao -- phia execute
      out_is_branch           = is_branch;
      out_branch_taken        = branch_taken;
      out_branch_offset       = branch_offset;
      // Ngo ra
      out_bpu_nxpc2           = bpu_nxpc2;
      out_bpu_nxpc2_valid     = bpu_nxpc2_valid;
      out_bpu_flush           = bpu_flush;
      monstart                = 1'b0;
   endtask : sample_bpu_all

   //==========================================================================
   // ASSERTION (SVA)
   //
   //==========================================================================

   // A1: flush_in khong duoc X/Z sau khi reset da on.
   //
   property prop_flush_in_valid;
      @(posedge clock)
         reset_done |-> !$isunknown(flush_in);
   endproperty

   ASRT_FLUSH_IN_VALID: assert property (prop_flush_in_valid)
      else
         `uvm_error("BPU_PREDICT_IF",
            $sformatf("flush_in = %0d contains X or Z", flush_in))

`ifdef BPU_PREDICT_IF_STRICT_FLUSH_IN
   property prop_flush_in_strict;
      @(posedge clock)
         reset_done |-> flush_in inside {2'b00, 2'b01, 2'b10};
   endproperty

   ASRT_FLUSH_IN_STRICT: assert property (prop_flush_in_strict)
      else
         `uvm_error("BPU_PREDICT_IF",
            $sformatf("flush_in = %0d (strict mode allows only 0, 1, 2)", flush_in))
`endif

   // A2: NGO RA flush, khac voi ngo vao, thi that su chi duoc 0, 1 va 2
   property prop_bpu_flush_valid;
      @(posedge clock)
         reset_done |-> bpu_flush inside {2'b00, 2'b01, 2'b10};
   endproperty

   ASRT_BPU_FLUSH_VALID: assert property (prop_bpu_flush_valid)
      else
         `uvm_error("BPU_PREDICT_IF",
            $sformatf("bpu_flush = %0d invalid (must be 0, 1, or 2)", bpu_flush))

   // A3: fetch_opcode khong duoc X/Z khi dang khong reset
   property prop_fetch_opcode_no_x;
      @(posedge clock)
         reset_done |-> !$isunknown(fetch_opcode);
   endproperty

   ASRT_FETCH_OPCODE_NO_X: assert property (prop_fetch_opcode_no_x)
      else
         `uvm_error("BPU_PREDICT_IF", "fetch_opcode contains X or Z")

   // A4: da bao valid thi phai kem mot dia chi dung duoc
   property prop_nxpc2_no_x_when_valid;
      @(posedge clock)
         (reset_done && bpu_nxpc2_valid) |-> !$isunknown(bpu_nxpc2);
   endproperty

   ASRT_NXPC2_NO_X_WHEN_VALID: assert property (prop_nxpc2_no_x_when_valid)
      else
         `uvm_error("BPU_PREDICT_IF", "bpu_nxpc2 contains X when bpu_nxpc2_valid=1")

   //--------------------------------------------------------------------------
   // A5..A7 -- tat bang `define BPU_UPDATE_IF_NO_ASSERTS
   //--------------------------------------------------------------------------
`ifndef BPU_UPDATE_IF_NO_ASSERTS

  // A5: is_branch chan moi lenh ghi bang, nen mot gia tri X o day se lam hong trang
  // thai mot cach am tham thay vi bao loi ro rang
  property p_no_x_is_branch;
    @(posedge clock)
      reset_done |-> !$isunknown(is_branch);
  endproperty
  A_NO_X_IS_BRANCH: assert property (p_no_x_is_branch)
    else `uvm_error("BPU_UPDATE_IF", "is_branch has X/Z value")

  // A6: hai tin hieu con lai chi can xac dinh o chu ky co giai quyet nhanh
  property p_branch_signals_valid;
    @(posedge clock)
      (reset_done && (is_branch == 1'b1)) |->
        (!$isunknown(branch_taken) && !$isunknown(branch_offset));
  endproperty
  A_BRANCH_SIGNALS_VALID: assert property (p_branch_signals_valid)
    else `uvm_error("BPU_UPDATE_IF",
         "When is_branch=1, branch_taken or branch_offset has X/Z")

  // A7: mot nhanh that luon co immediate khac 0 -- offset 0 se nhay vao chinh no.
  //     Chi canh bao chu khong bao loi: vai test directed co y dung offset 0 de
  //     tach rieng duong ghi BTB.
  property p_branch_offset_nonzero;
    @(posedge clock)
      (reset_done && (is_branch == 1'b1)) |-> (branch_offset != 32'h0);
  endproperty
  A_BRANCH_OFFSET_NONZERO: assert property (p_branch_offset_nonzero)
    else `uvm_warning("BPU_UPDATE_IF",
         "is_branch=1 but branch_offset=0 (possibly a test edge case)")

`endif // BPU_UPDATE_IF_NO_ASSERTS

endinterface : bpu_if
