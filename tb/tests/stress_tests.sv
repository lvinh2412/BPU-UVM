//------------------------------------------------------------------------------
// FILE: tests/stress_tests.sv
//
//   16.3 stress_btb_full : [A] DUNG LAI -- thuan kiem trang thai bang BTB bang
//        backdoor, khong phu thuoc thay doi hybrid nen giu nguyen.
//
//   Cac muc ngau nhien khac cua tep nay nay nam o tests/hyb_stress_tests.sv:
//     16.1 random_pipeline_coherent  (thay random_branch / random_ctrl / stress_random)
//     16.2 stress_long_run
//   Chung phai chuyen sang bo sinh nhat quan duong ong: kich thich cu lai
//   bpu_drive_seq voi auto_nxpc2, tuc nxpc2 = pc + 8 trong CUNG mot chu ky,
//   nen ba tang khong bao gio noi ve cung mot lenh.
//------------------------------------------------------------------------------

// 15.4 : fill 1024 unique BTB entries, then 500 aliasing accesses
class stress_btb_fill_mcseq extends bpu_base_seq;
  `uvm_object_utils(stress_btb_fill_mcseq)
  function new(string name="stress_btb_fill_mcseq"); super.new(name); endfunction
  virtual task body();
    bpu_branch_vseq v;  int i;
    // fill: pc=i*4 (idx i), offset 0x40 -> target = i*4 + 0x40
    for (i = 0; i < 1024; i++) begin
      v = bpu_branch_vseq::type_id::create($sformatf("fill_%0d", i));
      v.pc = i << 2; v.taken = 1'b1; v.offset = 32'h40; v.btf = 32'h40;
      v.start(m_sequencer, this);
    end
    // aliasing: pc=(1024+i)*4 (idx i again, i<500), offset 0x80 -> target replaced
    for (i = 0; i < 500; i++) begin
      v = bpu_branch_vseq::type_id::create($sformatf("alias_%0d", i));
      v.pc = (1024 + i) << 2; v.taken = 1'b1; v.offset = 32'h80; v.btf = 32'h80;
      v.start(m_sequencer, this);
    end
  endtask
endclass

class stress_base_test extends bpu_base_test;
  string test_label = "STRESS";
  int    err = 0;
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  protected function void select_clock();
    uvm_config_wrapper::set(this,
        "tb.clock_and_reset.agent.sequencer.run_phase",
        "default_sequence", clk10_rst5_seq::get_type());
  endfunction
  protected function void set_seq(uvm_object_wrapper seq);
    uvm_config_wrapper::set(this, "tb.bpu.tx_agent.sequencer.run_phase", "default_sequence", seq);
  endfunction
  // robustness core: DUT matched reference the whole run
  protected function void check_no_miscompare(int min_compares);
    bpu_scoreboard sb = tb.module_env.scoreboard;
    `uvm_info(test_label, $sformatf("scoreboard: compares=%0d match=%0d miscompare=%0d",
              sb.total_compares, sb.match_count, sb.miscompare_count), UVM_NONE)
    if (sb.miscompare_count != 0) begin
      err++; `uvm_error(test_label, $sformatf("%0d miscompare(s) -- DUT diverged from reference under stress", sb.miscompare_count)) end
    if (sb.total_compares < min_compares) begin
      err++; `uvm_error(test_label, $sformatf("only %0d compares (< %0d) -- possible hang", sb.total_compares, min_compares)) end
  endfunction
  protected function void check_no_x();
    bpu_backdoor bd = tb.module_env.backdoor;
    if ($isunknown(bd.read_bpu_nxpc2()) || $isunknown(bd.read_bpu_nxpc2_valid()) || $isunknown(bd.read_bpu_flush())) begin
      err++; `uvm_error(test_label, "X detected on BPU outputs") end
  endfunction
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (err == 0) `uvm_info(test_label, "PASSED", UVM_NONE)
    else          `uvm_error(test_label, $sformatf("FAILED: %0d issue(s)", err));
  endfunction
endclass : stress_base_test

//==============================================================================
// 15.4 : BTB fills to 1024, then 500 aliasing -> replace aliased, keep rest.
//   fill   idx i (i<1024): target = i*4 + 0x40
//   alias  idx i (i<500) : target REPLACED with (1024+i)*4 + 0x80
//   keep   idx i (500..1023): target stays i*4 + 0x40
//==============================================================================
class stress_btb_full_test extends stress_base_test;
  `uvm_component_utils(stress_btb_full_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_15_4 (stress_btb_full)";
    select_clock(); set_seq(stress_btb_fill_mcseq::get_type());
    super.build_phase(phase);
  endfunction
  function void extract_phase(uvm_phase phase);
    bpu_backdoor bd;  int i, n_valid, n_bad_repl, n_bad_keep;
    bit [31:0] exp;
    super.extract_phase(phase);
    bd = tb.module_env.backdoor;
    n_valid = 0; n_bad_repl = 0; n_bad_keep = 0;

    // (a) all 1024 entries valid after fill
    for (i = 0; i < 1024; i++)
      if (bd.read_btb_valid(i) === 1'b1) n_valid++;
    if (n_valid != 1024) begin
      err++; `uvm_error(test_label, $sformatf("only %0d/1024 BTB entries valid after fill", n_valid)) end

    // (b) aliased entries (idx 0..499) replaced with new target
    for (i = 0; i < 500; i++) begin
      exp = ((1024 + i) << 2) + 32'h80;
      if (bd.read_btb_target(i) !== exp) n_bad_repl++;
    end
    if (n_bad_repl != 0) begin
      err++; `uvm_error(test_label, $sformatf("%0d aliased entries NOT replaced correctly", n_bad_repl)) end

    // (c) non-aliased entries (idx 500..1023) preserved
    for (i = 500; i < 1024; i++) begin
      exp = (i << 2) + 32'h40;
      if (bd.read_btb_target(i) !== exp) n_bad_keep++;
    end
    if (n_bad_keep != 0) begin
      err++; `uvm_error(test_label, $sformatf("%0d non-aliased entries NOT preserved", n_bad_keep)) end

    `uvm_info(test_label, $sformatf("valid=%0d/1024  replaced_ok=%0d/500  preserved_ok=%0d/524",
              n_valid, 500-n_bad_repl, 524-n_bad_keep), UVM_NONE)
  endfunction
endclass
