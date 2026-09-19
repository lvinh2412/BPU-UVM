//------------------------------------------------------------------------------
//   5.1 gshare_index   : index = pc_idx XOR ghr (ghr=0 identity; ghr changes
//                        the entry for the same pc).
//   5.2 global_pht_counter : 2-bit saturating counter, all 8 transitions.
//   5.3 global_pht_init    : init WT on BTB miss, update on BTB hit.
//   5.4 gshare_ghr_index_aliasing : write uses OLD ghr as index + XOR aliasing
//                        (different pc/ghr with equal XOR collapse to one entry).
//------------------------------------------------------------------------------

`ifndef BPU_PHT_STATES
`define BPU_PHT_STATES
  `define SNT 2'b00
  `define WNT 2'b01
  `define WT  2'b10
  `define ST  2'b11
`endif


class global_pht_base_test extends bpu_base_test;
  string test_label = "GLOBAL_PHT";
  int    err = 0;
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  protected function void select_clock();
    uvm_config_wrapper::set(this,
        "tb.clock_and_reset.agent.sequencer.run_phase",
        "default_sequence", clk10_rst5_seq::get_type());
  endfunction

  // drive exactly one branch at the given pc
  task automatic drive_branch(bit [31:0] pc, bit tk);
    bpu_branch_vseq v;
    v = bpu_branch_vseq::type_id::create($sformatf("b_%0t", $time));
    v.pc = pc; v.taken = tk; v.offset = 32'h40;
    v.start(tb.bpu.tx_agent.sequencer);
    // #1ns thay cho #5ns: ban hai-UVC ket thuc vseq o NEGEDGE nen #5ns dua toi
    // POSEDGE va con nua chu ky du cho @(negedge) ke tiep. Ban mot-agent ket
    // thuc vseq o POSEDGE, nen #5ns dua toi DUNG NGAY NEGEDGE va lenh
    // @(negedge) ke tiep lo canh do, lam moi lan goi tre them mot chu ky.
    // Xem dau vet chan: gshare_aliasing / global_pht_rw_all lech +2.
    #1ns;
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (err == 0) `uvm_info(test_label, "PASSED", UVM_NONE)
    else          `uvm_error(test_label, $sformatf("FAILED: %0d mismatch(es)", err))
  endfunction
endclass : global_pht_base_test
//==============================================================================
// 5.4 : write-uses-OLD-ghr + XOR aliasing
//==============================================================================
class gshare_aliasing_test extends global_pht_base_test;
  `uvm_component_utils(gshare_aliasing_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_5_4 (gshare_ghr_index_aliasing)"; select_clock(); super.build_phase(phase);
  endfunction
  task run_phase(uvm_phase phase);
    bpu_backdoor bd; super.run_phase(phase); bd = tb.module_env.backdoor;
    phase.raise_objection(this, "gshare_alias");
    #100ns;

    // ---- (b) write uses OLD ghr as index ----
    //   ghr=5 (released so it shifts) ; miss -> entry 64^5=69 gets WT
    //   ghr shifts 5 -> {5[8:0],1}=11 ; entry 64^11=75 must be untouched
    bd.deposit_btb(64, 1'b0, 32'h0);   // miss
    bd.deposit_ghr(10'd5);               // ghr=5, free to shift
    drive_branch(32'h0000_0100, 1'b1);
    if (bd.read_global_pht(69) !== `WT) begin
      err++; `uvm_error(test_label, $sformatf("write-old: global_pht[69]=2'b%02b, expected WT (OLD ghr=5 -> 64^5)", bd.read_global_pht(69))) end
    if (bd.read_global_pht(75) !== `SNT) begin
      err++; `uvm_error(test_label, $sformatf("write-old: global_pht[75]=2'b%02b, expected SNT (NEW ghr=11 must NOT be written)", bd.read_global_pht(75))) end

    // ---- (c) XOR aliasing: (pc=0x100,ghr=0) and (pc=0x180,ghr=32) -> entry 64 ----
    bd.deposit_global_pht(64, `SNT);
    // ghr stays FORCED here (unlike part (b) above, where it was deposited and
    // deliberately left free to shift): the whole point of part (c) is that two
    // different (pc, ghr) pairs alias onto entry 64, which only holds if ghr is
    // exactly the stated value at the update edge. Scalar path -> works on both
    // simulators.
    bd.force_ghr(10'd0);
    bd.deposit_btb(64, 1'b1, 32'h0140);          // hit for pc=0x100 (idx 64)
    drive_branch(32'h0000_0100, 1'b1);           // entry 64: SNT -> WNT
    if (bd.read_global_pht(64) !== `WNT) begin
      err++; `uvm_error(test_label, $sformatf("alias-1: global_pht[64]=2'b%02b, expected WNT", bd.read_global_pht(64))) end

    bd.force_ghr(10'd32);
    bd.deposit_btb(96, 1'b1, 32'h0240);          // hit for pc=0x180 (idx 96)
    drive_branch(32'h0000_0180, 1'b1);           // 96^32 = 64 (SAME entry): WNT -> WT
    if (bd.read_global_pht(64) !== `WT) begin
      err++; `uvm_error(test_label, $sformatf("alias-2: global_pht[64]=2'b%02b, expected WT (aliased write from pc=0x180,ghr=32)", bd.read_global_pht(64))) end

    bd.release_ghr();
    phase.drop_objection(this, "gshare_alias");
  endtask
endclass : gshare_aliasing_test
