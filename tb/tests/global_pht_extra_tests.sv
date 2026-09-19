//------------------------------------------------------------------------------
//   5.5 global_pht_rw_all  : all 1024 entries (storage independence via backdoor
//                            + addressing reaches high indices via pc/ghr drive).
//   5.6 global_prediction  : predict_taken_pc == global_pht[1] when choice=global
//                            (choice=ST, MSB=1). Revealed via a C3 correction.
//   5.7 gshare_corr_pattern: alternating 1,0,1,0,... -> two opposite histories
//                            converge to opposite states.
//                            (Python-modeled: entry 746 -> ST, entry 277 -> SNT.)
//------------------------------------------------------------------------------


//==============================================================================
// 5.5 : all 1024 entries
//   Part A (addressing): drive at idx 0, 512, 1023 via ghr (pc=0x100, pc_idx=64)
//     idx=0    -> ghr=64    (64^64)
//     idx=512  -> ghr=576   (64^512)
//     idx=1023 -> ghr=959   (64^1023, needs all 10 bits)
//   Part B (storage): force/read all 1024 with distinct values (independent).
//==============================================================================
class global_pht_rw_all_test extends global_pht_base_test;
  `uvm_component_utils(global_pht_rw_all_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_5_5 (global_pht_rw_all)"; select_clock(); super.build_phase(phase);
  endfunction

  // ghr stays FORCED for the whole of drive_branch: the write index is
  // pc_index^ghr, so if the RTL were allowed to shift ghr mid-scenario the
  // entry under test would move and Part A would no longer be an addressing
  // check. ghr is a scalar, so the force works on both simulators.
  task automatic addr_check(bit [9:0] ghr_v, int idx);
    bpu_backdoor bd = tb.module_env.backdoor;
    bd.force_ghr(ghr_v);
    bd.deposit_global_pht(idx, `SNT);
    drive_branch(32'h0000_0100, 1'b1);                 // pht[idx]: SNT -> WNT
    if (bd.read_global_pht(idx) !== `WNT) begin
      err++; `uvm_error(test_label, $sformatf("addr: pht[%0d] (ghr=%0d) =2'b%02b, expected WNT (index unreachable/truncated)", idx, ghr_v, bd.read_global_pht(idx))) end
  endtask

  task run_phase(uvm_phase phase);
    bpu_backdoor bd; super.run_phase(phase); bd = tb.module_env.backdoor;
    phase.raise_objection(this, "rw_all");
    #100ns;
    // Deposit, not force: the RTL only ever writes btb_valid[64] <= 1'b1 on a
    // taken branch (bpu_reg.v BTB write), so the hit this part needs survives
    // the DUT's own writes without having to block them.
    bd.deposit_btb(64, 1'b1, 32'h0140);   // hit path (pc_idx=64)

    // ---- Part A: addressing reaches low/mid/high indices ----
    addr_check(10'd64,  0);     // 64^64   = 0
    addr_check(10'd576, 512);   // 64^576  = 512
    addr_check(10'd959, 1023);  // 64^959  = 1023 (all 10 bits)

    bd.release_ghr();

    // ---- Part B: storage independence (all 1024 entries hold their own value) ----
    // Write-then-read-back in zero simulation time, so no clock edge can
    // intervene: a deposit is all the residency this needs.
    for (int i = 0; i < 1024; i++) bd.deposit_global_pht(i, i[1:0]);
    for (int i = 0; i < 1024; i++)
      if (bd.read_global_pht(i) !== i[1:0]) begin
        err++; if (err <= 8) `uvm_error(test_label, $sformatf("storage: pht[%0d]=2'b%02b, expected 2'b%02b", i, bd.read_global_pht(i), i[1:0])) end

    phase.drop_objection(this, "rw_all");
  endtask
endclass : global_pht_rw_all_test

// 5.6 global_prediction_test: khong o tep nay. Muc 8.1 predict_mux_nxpc2
//   (tests/hyb_predict_tests.sv) pha D doi GHR de chung minh du doan lay tu
//   nguon global tai nxpc2, tuc da phu cung mot noi dung.


//==============================================================================
// 5.7 gshare_corr_pattern_test: khong o tep nay. Cung mot mau xen ke nhu
//   pattern_alternating_test, chi khac do dai (20 vs 200), nen hai muc da GOP
//   thanh 15.2 pattern_alternating
//   (tests/hyb_pattern_tests.sv), chay tren bo sinh nhat quan duong ong; pha B
//   cua muc do giu nguyen phep kiem hai o global_pht phan ky ([746]=ST,
//   [277]=SNT) va da xac nhan lai hai chi muc nay bang so do.
