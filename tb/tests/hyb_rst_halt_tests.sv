//------------------------------------------------------------------------------
// FILE: tests/hyb_rst_halt_tests.sv
//
//   1.1 rst_state_and_async        [B] sua rst_all_test
//   1.2 rst_outputs_and_recovery   [B] sua rst_outputs_test + rst_recovery_test
//   2.1 halt_block_and_resume      [B] gop halt_block_writes + halt_read + halt_deassert
//   2.2 halt_carry_freeze          [D] moi
//
// Ke thua hyb_fetch_base_test (tests/hyb_predict_tests.sv) -> include SAU tep do:
// ca bon muc deu can nguyen thuy apply() de lai theo TUNG CHU KY, va can doc
// truc tiep f_valid / d_valid / cac chan doc cua tang fetch.
//
//==============================================================================
// CAC MUC CU YEU O CHO NAO
//   rst_all_test      : extract_phase chi goi check_choice_reset_default() -- kiem
//                       DUY NHAT bang choice. Nam bang con lai, GHR va tam thanh
//                       ghi carry-down khong he duoc doc.
//   rst_outputs_test  : extract_phase chi in mot dong uvm_info, KHONG co mot phep
//                       kiem nao.
//   rst_recovery_test : chay bpu_simple_mcseq song song roi doc GHR sau moi lan
//                       reset -- kich thich da phat nhanh TRUOC khi doc, nen GHR
//                       khac 0 va test FAIL. Muc moi doc TRUOC roi moi phat nhanh.
//   halt_read_test    : chi dua vao scoreboard, khong quan sat rieng duong doc
//                       to hop nao trong luc halt.
//==============================================================================


//==============================================================================
// BASE cho nhom reset/halt: them anh chup TOAN BO trang thai va hai kieu reset.
//==============================================================================
class hyb_rsthalt_base_test extends hyb_fetch_base_test;

  // Anh chup toan bo sau bang + GHR
  protected bit        st_btb_v  [1024];
  protected bit [31:0] st_btb_t  [1024];
  protected bit [11:0] st_bht    [1024];
  protected bit [1:0]  st_lpht   [4096];
  protected bit [1:0]  st_gpht   [1024];
  protected bit [1:0]  st_choice [1024];
  protected bit [9:0]  st_ghr;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  protected function void snapshot_state();
    bpu_backdoor bd = tb.module_env.backdoor;
    int i;
    for (i = 0; i < 1024; i++) begin
      st_btb_v[i]  = bd.read_btb_valid(i);
      st_btb_t[i]  = bd.read_btb_target(i);
      st_bht[i]    = bd.read_local_bht(i);
      st_gpht[i]   = bd.read_global_pht(i);
      st_choice[i] = bd.read_choice(i);
    end
    for (i = 0; i < 4096; i++) st_lpht[i] = bd.read_local_pht(i);
    st_ghr = bd.read_ghr();
  endfunction

  // So sanh trang thai hien tai voi anh chup. Tra ve tong so o lech va phat
  // MOT loi cho moi bang (khong phat 4096 loi rieng le).
  protected function int compare_state(string tag);
    bpu_backdoor bd = tb.module_env.backdoor;
    int i, d_bv, d_bt, d_bh, d_lp, d_gp, d_ch, d_gh;
    d_bv = 0; d_bt = 0; d_bh = 0; d_lp = 0; d_gp = 0; d_ch = 0; d_gh = 0;
    for (i = 0; i < 1024; i++) begin
      if (bd.read_btb_valid(i)  !== st_btb_v[i])  d_bv++;
      if (bd.read_btb_target(i) !== st_btb_t[i])  d_bt++;
      if (bd.read_local_bht(i)  !== st_bht[i])    d_bh++;
      if (bd.read_global_pht(i) !== st_gpht[i])   d_gp++;
      if (bd.read_choice(i)     !== st_choice[i]) d_ch++;
    end
    for (i = 0; i < 4096; i++) if (bd.read_local_pht(i) !== st_lpht[i]) d_lp++;
    if (bd.read_ghr() !== st_ghr) d_gh = 1;
    chk(d_bv == 0, $sformatf("%s: btb_valid  lech %0d o", tag, d_bv));
    chk(d_bt == 0, $sformatf("%s: btb_target lech %0d o", tag, d_bt));
    chk(d_bh == 0, $sformatf("%s: local_bht  lech %0d o", tag, d_bh));
    chk(d_lp == 0, $sformatf("%s: local_pht  lech %0d o", tag, d_lp));
    chk(d_gp == 0, $sformatf("%s: global_pht lech %0d o", tag, d_gp));
    chk(d_ch == 0, $sformatf("%s: choice     lech %0d o", tag, d_ch));
    chk(d_gh == 0, $sformatf("%s: ghr        lech (0x%03h -> 0x%03h)", tag, st_ghr, bd.read_ghr()));
    return d_bv + d_bt + d_bh + d_lp + d_gp + d_ch + d_gh;
  endfunction

  //--------------------------------------------------------------------------
  // check_defaults -- SAU bang + GHR + TAM thanh ghi carry-down ve mac dinh.
  //   btb_valid / local_bht / local_pht(4096) / global_pht dung lai
  //   check_table_zero() cua backdoor da dung kich thuoc tung bang.
  //--------------------------------------------------------------------------
  protected function void check_defaults(string tag);
    bpu_backdoor bd = tb.module_env.backdoor;
    int m;
    m = bd.check_table_zero(0);
    chk(m == 0, $sformatf("%s: btb_valid  -- %0d/1024 o khac 0", tag, m));
    m = bd.count_btb_target_nonzero();
    chk(m == 0, $sformatf("%s: btb_target -- %0d/1024 o khac 0", tag, m));
    m = bd.check_table_zero(1);
    chk(m == 0, $sformatf("%s: local_bht  -- %0d/1024 o khac 0 (12 bit)", tag, m));
    m = bd.check_table_zero(2);
    chk(m == 0, $sformatf("%s: local_pht  -- %0d/4096 o khac SNT", tag, m));
    m = bd.check_table_zero(3);
    chk(m == 0, $sformatf("%s: global_pht -- %0d/1024 o khac SNT", tag, m));
    m = bd.count_choice_not_wnt();
    chk(m == 0, $sformatf("%s: choice     -- %0d/1024 o khac WNT(2'b01)", tag, m));
    chk(bd.read_ghr() === 10'd0, $sformatf("%s: ghr = 0x%03h, ky vong 0", tag, bd.read_ghr()));
    check_carry_zero(tag);
  endfunction

  protected function void check_carry_zero(string tag);
    bpu_backdoor bd = tb.module_env.backdoor;
    chk(bd.read_predic_taken_delay_1() === 1'b0, $sformatf("%s: predic_taken_delay_1 != 0", tag));
    chk(bd.read_predic_taken_delay_2() === 1'b0, $sformatf("%s: predic_taken_delay_2 != 0", tag));
    chk(bd.read_btb_hit_delay_1()      === 1'b0, $sformatf("%s: btb_hit_delay_1 != 0", tag));
    chk(bd.read_btb_hit_delay_2()      === 1'b0, $sformatf("%s: btb_hit_delay_2 != 0", tag));
    chk(bd.read_local_delay_1()        === 1'b0, $sformatf("%s: local_delay_1 != 0", tag));
    chk(bd.read_local_delay_2()        === 1'b0, $sformatf("%s: local_delay_2 != 0", tag));
    chk(bd.read_global_delay_1()       === 1'b0, $sformatf("%s: global_delay_1 != 0", tag));
    chk(bd.read_global_delay_2()       === 1'b0, $sformatf("%s: global_delay_2 != 0", tag));
  endfunction

  // Bo dem bao hoa 2 bit, ban sao cua bpu_predictor.v. Dung de doi chieu
  // gia tri PHT sau khi nha halt bang mot ky vong CHINH XAC, thay vi chi doi hoi
  // "phai khac gia tri cu" -- phep so do se vacuous khi bo dem dang o dau day.
  protected function bit [1:0] upd_ctr(bit [1:0] cur, bit taken);
    case (cur)
      `ST     : upd_ctr = taken ? `ST  : `WT ;
      `WT     : upd_ctr = taken ? `ST  : `WNT;
      `WNT    : upd_ctr = taken ? `WT  : `SNT;
      default : upd_ctr = taken ? `WNT : `SNT;   // SNT
    endcase
  endfunction

  // Dem so o KHAC mac dinh -- dung de chung minh phep kiem sau reset khong vacuous.
  protected function int count_dirty();
    bpu_backdoor bd = tb.module_env.backdoor;
    count_dirty = bd.check_table_zero(0) + bd.check_table_zero(1)
                + bd.check_table_zero(2) + bd.check_table_zero(3)
                + bd.count_btb_target_nonzero() + bd.count_choice_not_wnt()
                + ((bd.read_ghr() !== 10'd0) ? 1 : 0);
  endfunction

  //--------------------------------------------------------------------------
  // Lam ban toan bo trang thai bang DUONG CAP NHAT THAT (khong ep gi).
  //--------------------------------------------------------------------------
  protected task automatic dirty_state();
    setup_addresses();                       // TK: 24 re, NT: 6 khong re
    drive_branch(32'h0000_0500, 1'b1, 32'h80);
    drive_branch(32'h0000_0600, 1'b0, 32'h40);
    drive_branch(32'h0000_0700, 1'b1, 32'hFFFF_FFC0);
  endtask

  //--------------------------------------------------------------------------
  // reset_by_sequence -- chu trinh reset "that", di qua clock_and_reset UVC.
  //--------------------------------------------------------------------------
  protected task automatic reset_by_sequence();
    clk10_rst5_seq cr;
    cr = clk10_rst5_seq::type_id::create($sformatf("cr_%0t", $time));
    cr.start(tb.clock_and_reset.agent.sequencer);
    h.reset_pipe();
    #100ns;
  endtask

endclass : hyb_rsthalt_base_test


//==============================================================================
// 1.1 rst_state_and_async
//
// Sheet -- Flow: Pha A assert rst_n o nhieu thoi diem (khi nghi, giua luc dang
//   ghi, khi halt=1); doc lai toan bo bang bang backdoor. Pha B assert rst_n tai
//   thoi diem giua chu ky, khong trung canh len clk; quan sat thoi diem trang
//   thai ve mac dinh.
// Sheet -- Pass: btb_valid=0, btb_target=0, local_bht=0 (12 bit),
//   local_pht[0..4095]=SNT, global_pht[0..1023]=SNT, choice[0..1023]=WNT,
//   ghr=0, tam thanh ghi carry-down=0. Pha B: trang thai ve mac dinh NGAY khi
//   rst_n xuong thap, khong cho canh len clk.
// RTL Ref: bpu_reg.v ; bpu_ctrl.v
//==============================================================================
class rst_state_and_async_test extends hyb_rsthalt_base_test;
  `uvm_component_utils(rst_state_and_async_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_1_1 (rst_state_and_async)"; super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor bd;
    int          dirty;
    int          k;
    bit          clk_was_low;
    bit          rstn_after_force;

    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "1_1");
    #100ns;

    //---- PHA A0: ngay sau reset dau tien, moi thu da o mac dinh -------------
    phase_of("A0_after_power_on_reset");
    check_defaults("A0");

    //---- PHA A1: assert rst_n khi he thong DANG NGHI -----------------------
    phase_of("A1_reset_while_idle");
    dirty_state();
    dirty = count_dirty();
    chk(dirty > 0, "A1: trang thai chua bi lam ban -- phep kiem sau reset se vacuous");
    `uvm_info(test_label, $sformatf("A1: truoc reset co %0d o khac mac dinh", dirty), UVM_NONE)
    apply_idle(6);                      // dang nghi: is_branch = 0
    reset_by_force(3);
    check_defaults("A1");

    //---- PHA A2: assert rst_n GIUA LUC DANG GHI ----------------------------
    // Moi chu ky trong pha nay deu co is_branch=1 => ca sau wr_en tich cuc.
    // Reset danh trung giua chuoi ghi do.
    phase_of("A2_reset_while_writing");
    bus_free();
    dirty_state();
    dirty = count_dirty();
    chk(dirty > 0, "A2: trang thai chua bi lam ban");
    for (k = 0; k < 6; k++)
      apply(.pc(ADDR_TK), .nxpc(ADDR_TK + 4), .nxpc2(ADDR_TK), .opcode(OPC_BR),
            .btf(32'h40), .flush_in(2'd0), .halt(1'b0), .is_branch(1'b1),
            .taken(1'b1), .offset(32'h80));
    // Reset danh vao GIUA mot chu ky ghi: bus van dang giu is_branch=1 nen ca
    // sau wr_en (bpu_predictor.v) deu dang tich cuc.
    bd.force_tb_reset(1'b1);
    #0.2ns;
    chk(bd.read_tb_rst_n() === 1'b0, "A2: ep reset roi ma rst_n van = 1");
    check_defaults("A2_ngay_khi_reset_danh_vao");

    // Ngung phat lenh NGAY trong nua chu ky nay.
    //   Ly do: reference model xoa shadow state tai canh cua rst_n
    //   (reset_handler trong bpu_reference.sv) nhung KHONG mo hinh trang thai "dang bi giu
    //   trong reset" -- apply_update() cua no chi bi chan boi halt va is_branch.
    //   Neu de is_branch=1 di qua canh len ke tiep thi reference se ghi shadow
    //   trong khi DUT (dang bi rst_n keo thap) thi khong, va scoreboard bao lech.
    //   Day la gioi han cua mo hinh tham chieu, khong phai cua DUT.
    apply_now_idle();
    apply_idle(3);                      // van giu reset
    bd.release_tb_reset();
    apply_idle(4);
    bus_free();
    h.reset_pipe();
    #50ns;
    check_defaults("A2");

    //---- PHA A3: assert rst_n khi halt = 1 ---------------------------------
    phase_of("A3_reset_while_halted");
    bus_free();
    dirty_state();
    dirty = count_dirty();
    chk(dirty > 0, "A3: trang thai chua bi lam ban");
    for (k = 0; k < 4; k++)
      apply(.pc(ADDR_TK), .nxpc(ADDR_TK + 4), .nxpc2(ADDR_TK), .opcode(OPC_BR),
            .btf(32'h40), .flush_in(2'd0), .halt(1'b1), .is_branch(1'b1),
            .taken(1'b1), .offset(32'h80));
    bd.force_tb_reset(1'b1);     // halt=1 KHONG duoc chan reset
    #0.2ns;
    chk(bd.read_tb_rst_n() === 1'b0, "A3: ep reset roi ma rst_n van = 1");
    check_defaults("A3_ngay_khi_reset_danh_vao");
    repeat (3) begin
      apply(.pc(ADDR_TK), .nxpc(ADDR_TK + 4), .nxpc2(ADDR_TK), .opcode(OPC_BR),
            .btf(32'h40), .flush_in(2'd0), .halt(1'b1), .is_branch(1'b1),
            .taken(1'b1), .offset(32'h80));
    end
    bd.release_tb_reset();
    apply_idle(4);
    bus_free();
    h.reset_pipe();
    #50ns;
    check_defaults("A3");
    `uvm_info(test_label,
      "A3: halt=1 khong chan duoc reset -- bpu_reg.v kiem !rst_n TRUOC khi kiem halt", UVM_NONE)

    //=========================================================================
    // PHA B: reset BAT DONG BO -- assert giua chu ky, doc NGAY, chua qua canh len
    //=========================================================================
    phase_of("B_async_mid_cycle");
    bus_free();
    dirty_state();
    dirty = count_dirty();
    chk(dirty > 0, "B: trang thai chua bi lam ban");
    apply_idle(4);
    bus_free();

    // Dung o giua chu ky: sau canh XUONG thi clk = 0 cho toi canh len ke tiep.
    @(negedge pvif.clock);
    #1ns;
    chk(pvif.clock === 1'b0, "B: khong dung duoc o giua chu ky de assert reset");
    bd.force_tb_reset(1'b1);
    #0.2ns;                              // chi de cac khoi always bat dong bo chay
    rstn_after_force = bd.read_tb_rst_n();
    chk(rstn_after_force === 1'b0,
        $sformatf("B: ep reset roi ma rst_n = %0d, ky vong 0", rstn_after_force));

    // Doc toan bo trang thai -- moi phep doc deu la ham, khong ton thoi gian
    // mo phong, nen van con nam trong nua chu ky nay.
    check_defaults("B_async");
    clk_was_low = (pvif.clock === 1'b0);
    chk(clk_was_low,
        "B: da qua mot canh len clk truoc khi doc xong -- phep do KHONG chung minh duoc tinh bat dong bo");
    `uvm_info(test_label, $sformatf({
      "\n=== 1.1 PHA B: reset BAT DONG BO ===\n",
      "  assert rst_n tai t = %0t, giua chu ky (clk dang o muc thap).\n",
      "  Toan bo sau bang, GHR va tam thanh ghi carry-down da ve mac dinh NGAY,\n",
      "  khong cho canh len clk (clk van = %0d khi doc xong).\n",
      "===================================="}, $time, pvif.clock), UVM_NONE)

    bd.release_tb_reset();
    repeat (3) @(negedge pvif.clock);
    h.reset_pipe();
    #50ns;
    check_defaults("B_after_release");

    phase.drop_objection(this, "1_1");
  endtask
endclass : rst_state_and_async_test


//==============================================================================
// 1.2 rst_outputs_and_recovery
//
// Sheet -- Flow: reset, giu nghi vai chu ky, phat nhanh dau tien (BTB miss tai
//   nxpc2 va nxpc, fetch_opcode=BCC). Sau do lap muoi lan chu trinh reset/nha
//   reset, moi lan phat mot nhanh ngay sau khi nha.
// Sheet -- Pass: ngay sau reset bpu_nxpc2_valid=0 va bpu_flush=0. Nhanh dau:
//   f_valid=0, d_valid=1, bpu_nxpc2 = nxpc + branch_target_fetch. Vi carry-down=0
//   nen nhanh dau sau moi lan reset khong bi so voi quyet dinh cua lan chay
//   truoc; khong co xung nhieu tren ngo ra.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class rst_outputs_and_recovery_test extends hyb_rsthalt_base_test;
  `uvm_component_utils(rst_outputs_and_recovery_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_1_2 (rst_outputs_and_recovery)"; super.build_phase(phase);
  endfunction

  localparam int          N_CYCLE  = 10;               // 5 -> 10 theo sheet
  localparam bit [31:0]   FIRST_PC = 32'h0000_0B00;    // idx 704, chua tung ghi
  localparam bit [31:0]   BTF      = 32'h0000_0040;

  //--------------------------------------------------------------------------
  // Phat DUNG mot nhanh dau tien di theo duong backstop, doc rieng f_valid va
  // d_valid o tung tang. Tra ve ba quan sat F / F+1 / F+2.
  //--------------------------------------------------------------------------
  protected task automatic first_branch(input string tag, output bpu_fetch_obs_t oF,
                                        output bpu_fetch_obs_t oD, output bpu_fetch_obs_t oX);
    // F   : nxpc2 = FIRST_PC (BTB rong -> truot), tang decode con trong
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(FIRST_PC), .opcode(OPC_NOP),
          .btf(32'h0), .flush_in(2'd0));
    oF = snap();
    // F+1 : nxpc = FIRST_PC, fetch_opcode = BCC, BTB van truot -> backstop lai
    apply(.pc(NEU_PC), .nxpc(FIRST_PC), .nxpc2(NEU_NXPC2), .opcode(OPC_BR),
          .btf(BTF), .flush_in(2'd0));
    oD = snap();
    // F+2 : nhanh toi execute, thuc su re
    apply(.pc(FIRST_PC), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .btf(32'h0), .flush_in(2'd0), .halt(1'b0), .is_branch(1'b1),
          .taken(1'b1), .offset(32'h40));
    oX = snap();
  endtask

  protected function void check_first_branch(string tag, bpu_fetch_obs_t oF,
                                             bpu_fetch_obs_t oD, bpu_fetch_obs_t oX);
    chk(oF.fv === 1'b0, $sformatf("%s (F): f_valid=%0d, ky vong 0 (BTB rong tai nxpc2)", tag, oF.fv));
    chk(oF.outv === 1'b0, $sformatf("%s (F): bpu_nxpc2_valid=%0d, ky vong 0", tag, oF.outv));
    chk(oD.dv === 1'b1, $sformatf("%s (F+1): d_valid=%0d, ky vong 1 (BCC + BTB truot tai nxpc)", tag, oD.dv));
    chk(oD.fv === 1'b0, $sformatf("%s (F+1): f_valid=%0d, ky vong 0", tag, oD.fv));
    chk(oD.outv === 1'b1, $sformatf("%s (F+1): bpu_nxpc2_valid=%0d, ky vong 1", tag, oD.outv));
    chk(oD.outp === (FIRST_PC + BTF),
        $sformatf("%s (F+1): bpu_nxpc2=0x%08h, ky vong 0x%08h (nxpc + branch_target_fetch)",
                  tag, oD.outp, FIRST_PC + BTF));
    chk(oX.fl === 2'd1,
        $sformatf("%s (F+2): bpu_flush=%0d, ky vong 1 (BTB truot luc fetch + nhanh thuc su re)", tag, oX.fl));
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor    bd;
    bpu_fetch_obs_t oF, oD, oX;
    int             k, m;

    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "1_2");
    #100ns;

    //---- PHA A: ngo ra o trang thai nghi ngay sau reset --------------------
    // Day la phep kiem ma rst_outputs_test cu KHONG he co.
    phase_of("A_outputs_idle_after_reset");
    chk(bd.read_bpu_nxpc2_valid() === 1'b0,
        $sformatf("A: bpu_nxpc2_valid=%0d ngay sau reset, ky vong 0", bd.read_bpu_nxpc2_valid()));
    chk(bd.read_bpu_flush() === 2'd0,
        $sformatf("A: bpu_flush=%0d ngay sau reset, ky vong 0", bd.read_bpu_flush()));
    check_carry_zero("A");
    apply_idle(6);                       // "giu nghi vai chu ky"
    chk(bd.read_bpu_nxpc2_valid() === 1'b0,
        "A: bpu_nxpc2_valid != 0 sau vai chu ky nghi");
    chk(bd.read_bpu_flush() === 2'd0, "A: bpu_flush != 0 sau vai chu ky nghi");

    //---- PHA B: nhanh dau tien di theo duong backstop ----------------------
    phase_of("B_first_branch_backstop");
    first_branch("B", oF, oD, oX);
    `uvm_info(test_label, $sformatf({
      "\n=== 1.2 nhanh DAU TIEN sau reset ===\n",
      "  F   : f_valid=%0d d_valid=%0d -> bpu_nxpc2_valid=%0d\n",
      "  F+1 : f_valid=%0d d_valid=%0d -> bpu_nxpc2_valid=%0d bpu_nxpc2=0x%08h (nxpc+btf=0x%08h)\n",
      "  F+2 : pred_was_hit=%0d predicted_taken=%0d branch_taken=1 -> bpu_flush=%0d\n",
      "===================================="},
      oF.fv, oF.dv, oF.outv, oD.fv, oD.dv, oD.outv, oD.outp, FIRST_PC + BTF,
      bd.read_pred_was_hit(), bd.read_predicted_taken(), oX.fl), UVM_NONE)
    check_first_branch("B", oF, oD, oX);

    //---- PHA C: MUOI chu trinh reset / nha reset ---------------------------
    // Trinh tu da duoc sua so voi rst_recovery_test cu: DOC TRANG THAI TRUOC,
    // phat nhanh SAU. Test cu chay bpu_simple_mcseq song song nen da co nhanh
    // di qua truoc luc doc, lam GHR khac 0 va bao sai.
    phase_of("C_repeat_reset_x10");
    for (k = 0; k < N_CYCLE; k++) begin
      bus_free();
      reset_by_sequence();

      // (1) doc TRUOC khi phat bat ky nhanh nao
      chk(bd.read_ghr() === 10'd0,
          $sformatf("C vong %0d: ghr=0x%03h ngay sau reset, ky vong 0", k, bd.read_ghr()));
      m = bd.count_choice_not_wnt();
      chk(m == 0, $sformatf("C vong %0d: choice con %0d o khac WNT sau reset", k, m));
      m = bd.check_table_zero(0);
      chk(m == 0, $sformatf("C vong %0d: btb_valid con %0d o khac 0 sau reset", k, m));
      check_carry_zero($sformatf("C vong %0d", k));
      chk(bd.read_bpu_nxpc2_valid() === 1'b0,
          $sformatf("C vong %0d: bpu_nxpc2_valid=%0d ngay sau reset, ky vong 0", k, bd.read_bpu_nxpc2_valid()));
      chk(bd.read_bpu_flush() === 2'd0,
          $sformatf("C vong %0d: bpu_flush=%0d ngay sau reset, ky vong 0", k, bd.read_bpu_flush()));

      // (2) khong xung nhieu: hai chu ky nghi truoc nhanh dau
      apply_idle(2);
      chk(bd.read_bpu_nxpc2_valid() === 1'b0,
          $sformatf("C vong %0d: xung nhieu tren bpu_nxpc2_valid trong luc nghi", k));
      chk(bd.read_bpu_flush() === 2'd0,
          $sformatf("C vong %0d: xung nhieu tren bpu_flush trong luc nghi", k));

      // (3) nhanh dau sau khi nha reset -- phai cho DUNG ket qua nhu lan dau,
      //     chung to carry-down khong mang gi tu lan chay truoc sang
      first_branch($sformatf("C vong %0d", k), oF, oD, oX);
      check_first_branch($sformatf("C vong %0d", k), oF, oD, oX);
    end
    `uvm_info(test_label, $sformatf(
      "C: %0d chu trinh reset/nha reset, moi lan nhanh dau deu di dung duong backstop va cho bpu_flush=1",
      N_CYCLE), UVM_NONE)

    bus_free();
    phase.drop_objection(this, "1_2");
  endtask
endclass : rst_outputs_and_recovery_test


//==============================================================================
// 2.1 halt_block_and_resume
//
// Sheet -- Flow: nap truoc trang thai; phat nhanh sao cho moi tin hieu wr_en deu
//   tich cuc; giu halt=1 trong 100 chu ky dong thoi thay doi pc/nxpc/nxpc2; sau
//   do nha halt trong mot chu ky va quan sat.
// Sheet -- Pass: trong luc halt sau bang giu nguyen gia tri da nap; cac ngo ra to
//   hop (btb_target_pc, predict_taken_nxpc2, bpu_nxpc2, bpu_flush) van thay doi
//   theo ngo vao. Sau khi nha: BTB ghi target, PHT cap nhat bo dem, GHR dich dung
//   o chu ky ke tiep.
// RTL Ref: bpu_reg.v ; bpu_ctrl.v
//==============================================================================
class halt_block_and_resume_test extends hyb_rsthalt_base_test;
  `uvm_component_utils(halt_block_and_resume_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_2_1 (halt_block_and_resume)"; super.build_phase(phase);
  endfunction

  localparam int N_HALT = 100;           // 5 -> 100 theo sheet

  task run_phase(uvm_phase phase);
    bpu_backdoor    bd;
    bpu_fetch_obs_t o_tk, o_nt, o_ut, o;
    bit [11:0] lidx;
    int        gidx;
    bit [1:0]  lp0, gp0, ch0;
    bit [1:0]  exp_lp, exp_gp;
    bit [31:0] bt0;
    bit [11:0] bh0;
    bit [9:0]  ghr0;
    int        k, diffs;
    bit [31:0] pcs[4];

    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "2_1");
    #100ns;

    //---- PHA A: nap truoc trang thai --------------------------------------
    phase_of("A_preload");
    setup_addresses();
    lidx = bd.read_local_bht(ADDR_TK[11:2]);
    gidx = ADDR_TK[11:2] ^ bd.read_ghr();
    bt0  = bd.read_btb_target(ADDR_TK[11:2]);
    bh0  = bd.read_local_bht(ADDR_TK[11:2]);
    lp0  = bd.read_local_pht(lidx);
    gp0  = bd.read_global_pht(gidx);
    ch0  = bd.read_choice(ADDR_TK[11:2]);
    ghr0 = bd.read_ghr();
    chk(bd.read_btb_valid(ADDR_TK[11:2]) === 1'b1, "A: btb_valid[TK] phai = 1 sau khi nap");
    `uvm_info(test_label, $sformatf(
      "A nap xong: btb_target[TK]=0x%08h bht[TK]=0x%03h local_pht[0x%03h]=%02b global_pht[%0d]=%02b choice[TK]=%02b ghr=0x%03h",
      bt0, bh0, lidx, lp0, gidx, gp0, ch0, ghr0), UVM_NONE)

    //---- PHA B: dua bit carry-down vao trang thai BAT DONG THUAN ----------
    // choice_wr_en = disagree && is_branch && btb_valid_pc (bpu_predictor.v).
    // Hai chu ky is_branch=0 voi nxpc2 = ADDR_TK nap local_carry/global_carry tu
    // dung cap doc do; tai ADDR_TK local[1]=1 con global[1]=0 => disagree = 1.
    // Nho vay khi halt=1 o pha C thi CA SAU wr_en, ke ca choice_wr_en, deu tich cuc.
    phase_of("B_arm_choice_write_enable");
    observe_at(ADDR_TK, 2'd0, o_tk);
    show_fetch("B doc tai ADDR_TK", ADDR_TK, o_tk);
    chk(o_tk.lp[1] !== o_tk.gp[1],
        $sformatf("B: local[1]=%0d va global[1]=%0d phai KHAC nhau thi choice_wr_en moi tich cuc duoc",
                  o_tk.lp[1], o_tk.gp[1]));
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_TK), .opcode(OPC_NOP), .flush_in(2'd0));
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_TK), .opcode(OPC_NOP), .flush_in(2'd0));
    chk(bd.read_local_carry() !== bd.read_global_carry(), $sformatf(
        "B: local_carry=%0d global_carry=%0d -- can khac nhau de choice_wr_en tich cuc",
        bd.read_local_carry(), bd.read_global_carry()));
    snapshot_state();

    //---- PHA C: halt = 1 trong 100 chu ky ---------------------------------
    // pc/nxpc/nxpc2 doi trong luc halt; is_branch=1 suot => moi wr_en tich cuc.
    phase_of("C_halt_100_cycles");
    pcs = '{ADDR_TK, ADDR_NT, ADDR_UT, 32'h0000_0900};
    for (k = 0; k < N_HALT; k++)
      apply(.pc(pcs[k % 4]), .nxpc(pcs[(k+1) % 4]), .nxpc2(pcs[(k+2) % 4]),
            .opcode(OPC_BR), .btf(32'h40 + k), .flush_in(2'd0), .halt(1'b1),
            .is_branch(1'b1), .taken(k[0]), .offset(32'h80 + k));
    diffs = compare_state("C sau 100 chu ky halt");
    `uvm_info(test_label, $sformatf(
      "C: %0d chu ky halt=1 voi is_branch=1 va pc/nxpc/nxpc2/offset/taken doi lien tuc -> %0d o trang thai bi doi (ky vong 0)",
      N_HALT, diffs), UVM_NONE)

    //---- PHA D: trong luc halt, duong DOC to hop van chay -----------------
    // halt_read_test cu chi dua vao scoreboard; o day doc thang tung ngo ra.
    phase_of("D_combinational_reads_under_halt");
    // (1) btb_target_pc bam theo pc
    apply(.pc(ADDR_TK), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b1));
    chk(bd.read_btb_target_pc_port() === bt0, $sformatf(
        "D: halt=1, pc=ADDR_TK -> btb_target_pc=0x%08h, ky vong 0x%08h",
        bd.read_btb_target_pc_port(), bt0));
    chk(bd.read_btb_valid_pc_port() === 1'b1, "D: halt=1, pc=ADDR_TK -> btb_valid_pc phai = 1");
    apply(.pc(ADDR_UT), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b1));
    chk(bd.read_btb_valid_pc_port() === 1'b0,
        "D: halt=1, pc=ADDR_UT (chua ghi) -> btb_valid_pc phai = 0; duong doc BTB da chet trong luc halt");

    // (2) predict_taken_nxpc2 bam theo nxpc2
    observe_at(ADDR_TK, 2'd0, o_tk);          // van halt=0 o observe_at
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_TK), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b1));
    o = snap();
    chk(o.pt === 1'b1 && o.hit === 1'b1,
        $sformatf("D: halt=1, nxpc2=ADDR_TK -> hit=%0d predT=%0d, ky vong 1/1", o.hit, o.pt));
    chk(o.outv === 1'b1 && o.outp === bt0, $sformatf(
        "D: halt=1 -> bpu_nxpc2_valid=%0d bpu_nxpc2=0x%08h, ky vong 1 / 0x%08h", o.outv, o.outp, bt0));
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_NT), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b1));
    o_nt = snap();
    chk(o_nt.pt === 1'b0 && o_nt.hit === 1'b1,
        $sformatf("D: halt=1, nxpc2=ADDR_NT -> hit=%0d predT=%0d, ky vong 1/0", o_nt.hit, o_nt.pt));
    chk(o_nt.outv === 1'b0,
        $sformatf("D: halt=1, nxpc2=ADDR_NT -> bpu_nxpc2_valid=%0d, ky vong 0 (du doan khong re)", o_nt.outv));
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_UT), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b1));
    o_ut = snap();
    chk(o_ut.hit === 1'b0, $sformatf("D: halt=1, nxpc2=ADDR_UT -> btb_valid_nxpc2=%0d, ky vong 0", o_ut.hit));

    // (3) bpu_flush van doi theo ngo vao cua tang execute
    // predicted_taken hien = 0 (cac chu ky vua roi deu co f_valid=0 hoac bi halt);
    // dat pred_was_hit theo carry-down hien co roi doi rieng branch_taken.
    apply(.pc(ADDR_TK), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b1), .is_branch(1'b1), .taken(1'b1), .offset(32'h40));
    o = snap();
    apply(.pc(ADDR_TK), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b1), .is_branch(1'b1), .taken(1'b0), .offset(32'h40));
    o_nt = snap();
    `uvm_info(test_label, $sformatf(
      "D: halt=1, pred_was_hit=%0d predicted_taken=%0d -> branch_taken=1 cho bpu_flush=%0d, branch_taken=0 cho bpu_flush=%0d",
      bd.read_pred_was_hit(), bd.read_predicted_taken(), o.fl, o_nt.fl), UVM_NONE)
    chk(o.fl !== o_nt.fl, $sformatf(
      "D: bpu_flush khong doi theo branch_taken trong luc halt (%0d va %0d) -- duong to hop cua tang execute phai song",
      o.fl, o_nt.fl));

    // Toan bo pha D van khong duoc ghi gi
    diffs = compare_state("D sau cac phep doc to hop");
    chk(diffs == 0, "D: doc to hop trong luc halt da lam doi trang thai");

    //---- PHA E: nha halt -> ghi phuc hoi ngay o chu ky ke ------------------
    phase_of("E_resume_next_cycle");
    // DUNG MOT chu ky voi halt = 0: nhanh tai ADDR_TK, offset moi, KHONG re.
    //   Chon taken=0 co chu y: local_pht[0xFFF] dang o ST, mot nhanh re nua se
    //   giu no o ST (bo dem bao hoa) va phep kiem "PHT co cap nhat khong" se
    //   khong con y nghia. Voi taken=0 thi ST -> WT, thay ro.
    exp_lp = upd_ctr(lp0, 1'b0);
    exp_gp = upd_ctr(gp0, 1'b0);
    apply(.pc(ADDR_TK), .nxpc(NEU_NXPC), .nxpc2(ADDR_TK), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b0), .is_branch(1'b1), .taken(1'b0), .offset(32'h00C0));
    // Chu ky ke tiep tro lai halt=1 de chac chan chi co DUNG mot lan ghi
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b1));
    chk(bd.read_btb_target(ADDR_TK[11:2]) === (ADDR_TK + 32'h00C0), $sformatf(
      "E: btb_target[TK]=0x%08h sau khi nha halt, ky vong 0x%08h",
      bd.read_btb_target(ADDR_TK[11:2]), ADDR_TK + 32'h00C0));
    chk(bd.read_local_bht(ADDR_TK[11:2]) === {bh0[10:0], 1'b0}, $sformatf(
      "E: local_bht[TK]=0x%03h sau khi nha halt, ky vong 0x%03h (dich trai + 0)",
      bd.read_local_bht(ADDR_TK[11:2]), {bh0[10:0], 1'b0}));
    chk(bd.read_ghr() === {ghr0[8:0], 1'b0}, $sformatf(
      "E: ghr=0x%03h sau khi nha halt, ky vong 0x%03h (dich trai + 0)",
      bd.read_ghr(), {ghr0[8:0], 1'b0}));
    chk(bd.read_local_pht(lidx) === exp_lp, $sformatf(
      "E: local_pht[0x%03h]=%02b sau khi nha halt, ky vong %02b (bo dem tu %02b, taken=0)",
      lidx, bd.read_local_pht(lidx), exp_lp, lp0));
    chk(exp_lp !== lp0,
      "E: bo dem local_pht dang o dau day nen phep kiem cap nhat se vacuous -- doi trang thai nap truoc");
    chk(bd.read_global_pht(gidx) === exp_gp, $sformatf(
      "E: global_pht[%0d]=%02b sau khi nha halt, ky vong %02b (bo dem tu %02b, taken=0)",
      gidx, bd.read_global_pht(gidx), exp_gp, gp0));
    `uvm_info(test_label, $sformatf({
      "\n=== 2.1 nha halt: ghi phuc hoi NGAY o chu ky ke ===\n",
      "  btb_target[TK]   : 0x%08h -> 0x%08h\n",
      "  local_bht[TK]    : 0x%03h      -> 0x%03h\n",
      "  ghr              : 0x%03h      -> 0x%03h\n",
      "  local_pht[0x%03h]  : %02b        -> %02b\n",
      "  global_pht[%4d]  : %02b        -> %02b\n",
      "==================================================="},
      bt0, bd.read_btb_target(ADDR_TK[11:2]), bh0, bd.read_local_bht(ADDR_TK[11:2]),
      ghr0, bd.read_ghr(), lidx, lp0, bd.read_local_pht(lidx),
      gidx, gp0, bd.read_global_pht(gidx)), UVM_NONE)

    bus_free();
    phase.drop_objection(this, "2_1");
  endtask
endclass : halt_block_and_resume_test


//==============================================================================
// 2.2 halt_carry_freeze
//
// Sheet -- Flow: dua mot nhanh vao tang fetch; assert halt trong N chu ky khi
//   nhanh dang o giua duong ong; nha halt; theo nhanh do toi tang execute. Kiem
//   rieng bon thanh ghi tang mot va bon thanh ghi tang hai.
// Sheet -- Pass: predicted_taken, pred_was_hit, local_carry, global_carry giu
//   nguyen suot thoi gian halt; sau khi nha halt, nhanh toi execute van duoc so
//   voi dung quyet dinh luc fetch; bpu_flush va correction dung.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class halt_carry_freeze_test extends hyb_rsthalt_base_test;
  `uvm_component_utils(halt_carry_freeze_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_2_2 (halt_carry_freeze)"; super.build_phase(phase);
  endfunction

  localparam int N_HALT = 24;

  // Tam thanh ghi carry-down, doc trong MOT anh chup.
  protected bit cd[8];

  protected function void grab_cd();
    bpu_backdoor bd = tb.module_env.backdoor;
    cd[0] = bd.read_predic_taken_delay_1();
    cd[1] = bd.read_btb_hit_delay_1();
    cd[2] = bd.read_local_delay_1();
    cd[3] = bd.read_global_delay_1();
    cd[4] = bd.read_predic_taken_delay_2();
    cd[5] = bd.read_btb_hit_delay_2();
    cd[6] = bd.read_local_delay_2();
    cd[7] = bd.read_global_delay_2();
  endfunction

  protected function string cd_str();
    return $sformatf("tang1[steer=%0b hit=%0b local=%0b global=%0b] tang2[predT=%0b hit=%0b local=%0b global=%0b]",
                     cd[0], cd[1], cd[2], cd[3], cd[4], cd[5], cd[6], cd[7]);
  endfunction

  protected function void cmp_cd(string tag, bit ref_cd[8]);
    string nm[8];
    int i;
    nm = '{"predic_taken_delay_1", "btb_hit_delay_1", "local_delay_1", "global_delay_1",
           "predic_taken_delay_2", "btb_hit_delay_2", "local_delay_2", "global_delay_2"};
    grab_cd();
    for (i = 0; i < 8; i++)
      chk(cd[i] === ref_cd[i],
          $sformatf("%s: %s = %0b, ky vong %0b -- halt phai dong bang thanh ghi nay",
                    tag, nm[i], cd[i], ref_cd[i]));
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor    bd;
    bpu_fetch_obs_t o, oX;
    bit             frozen[8];
    int             k;
    bit [31:0]      exp_corr;

    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "2_2");
    #100ns;

    //---- PHA A: nap trang thai ---------------------------------------------
    phase_of("A_train");
    setup_addresses();
    apply_idle(4);
    check_carry_zero("A truoc phep do");

    //=========================================================================
    // PHA B: dua mot nhanh vao TANG FETCH roi dong bang tang MOT
    //   Chu ky F : nxpc2 = ADDR_TK (BTB trung + du doan re) => f_valid = 1
    //   Tai canh len cuoi chu ky F, tang mot nap {1, 1, local, global}.
    //=========================================================================
    phase_of("B_freeze_stage1");
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_TK), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b0));
    o = snap();
    chk(o.fv === 1'b1, $sformatf("B: f_valid=%0d tai chu ky F, ky vong 1", o.fv));

    // Chu ky ke: halt=1 NGAY, va doi luon nxpc2 sang ADDR_NT (du doan khong re,
    // f_valid=0). Neu tang mot khong bi dong bang thi no se nap 0 de len.
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_NT), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b1));
    grab_cd();
    frozen = cd;
    `uvm_info(test_label, $sformatf("B: moc luc bat dau halt -- %s", cd_str()), UVM_NONE)
    chk(frozen[0] === 1'b1, $sformatf("B: predic_taken_delay_1=%0b luc bat dau halt, ky vong 1", frozen[0]));
    chk(frozen[1] === 1'b1, $sformatf("B: btb_hit_delay_1=%0b luc bat dau halt, ky vong 1", frozen[1]));

    // N chu ky halt, ngo vao tang fetch doi lien tuc: gia tri chot phai tro
    for (k = 0; k < N_HALT; k++) begin
      apply(.pc((k[0] == 0) ? ADDR_NT : ADDR_UT),
            .nxpc(ADDR_UT), .nxpc2((k[0] == 0) ? ADDR_NT : ADDR_UT),
            .opcode(OPC_BR), .btf(32'h40), .flush_in(2'd0), .halt(1'b1),
            .is_branch(1'b1), .taken(k[1]), .offset(32'h40));
      cmp_cd($sformatf("B chu ky halt %0d", k), frozen);
    end
    `uvm_info(test_label, $sformatf(
      "B: %0d chu ky halt=1 voi nxpc2/pc/opcode/is_branch doi lien tuc -- ca tam thanh ghi giu nguyen: %s",
      N_HALT, cd_str()), UVM_NONE)

    //=========================================================================
    // PHA C: nha halt -- quyet dinh chay tiep tu dung cho no dung lai
    //=========================================================================
    phase_of("C_release_and_advance");
    // Chu ky F+1 (chu ky DAU TIEN co halt tro lai 0): nhanh o tang decode.
    // opcode = ADDI => d_valid = 0, nen predicted_taken cua no chi co the den tu
    // f_valid da chot o pha B.
    //
    // THOI DIEM: trong SUOT chu ky nay quyet dinh van con nam o tang MOT. Canh
    // len KET THUC chu ky nay moi la canh dau tien khong bi halt chan, va chinh
    // no day tang mot xuong tang hai (bpu_ctrl.v). Vi vay o day kiem tang
    // MOT con nguyen ven; tang HAI duoc kiem o pha D.
    apply(.pc(NEU_PC), .nxpc(ADDR_TK), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b0));
    grab_cd();
    chk(cd[0] === frozen[0], $sformatf(
      "C: predic_taken_delay_1=%0b o chu ky nha halt, ky vong %0b (quyet dinh chua roi tang mot)",
      cd[0], frozen[0]));
    chk(cd[1] === frozen[1], $sformatf("C: btb_hit_delay_1=%0b, ky vong %0b", cd[1], frozen[1]));
    chk(cd[2] === frozen[2], $sformatf("C: local_delay_1=%0b, ky vong %0b", cd[2], frozen[2]));
    chk(cd[3] === frozen[3], $sformatf("C: global_delay_1=%0b, ky vong %0b", cd[3], frozen[3]));
    chk(cd[4] === 1'b0, $sformatf(
      "C: predic_taken_delay_2=%0b, ky vong 0 -- tang hai chi duoc nap tai CANH LEN ket thuc chu ky nay",
      cd[4]));

    //=========================================================================
    // PHA D: nhanh toi execute -- so voi DUNG quyet dinh luc fetch
    //=========================================================================
    phase_of("D_execute_uses_fetch_decision");
    // D1: nhanh thuc su re -> du doan dung -> khong bong bong, khong correction
    apply(.pc(ADDR_TK), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b0), .is_branch(1'b1), .taken(1'b1), .offset(32'h40));
    oX = snap();
    // Bay gio quyet dinh da o tang HAI -- kiem rieng bon thanh ghi tang hai.
    grab_cd();
    chk(cd[4] === 1'b1, $sformatf(
      "D1: predic_taken_delay_2=%0b, ky vong 1 (quyet dinh luc fetch da qua tang hai)", cd[4]));
    chk(cd[5] === 1'b1, $sformatf("D1: btb_hit_delay_2=%0b, ky vong 1", cd[5]));
    chk(cd[6] === frozen[2], $sformatf(
      "D1: local_delay_2=%0b, ky vong %0b (dung bit da chot luc fetch)", cd[6], frozen[2]));
    chk(cd[7] === frozen[3], $sformatf(
      "D1: global_delay_2=%0b, ky vong %0b (dung bit da chot luc fetch)", cd[7], frozen[3]));
    chk(bd.read_predicted_taken() === 1'b1,
        $sformatf("D1: predicted_taken=%0d tai execute, ky vong 1", bd.read_predicted_taken()));
    chk(bd.read_pred_was_hit() === 1'b1,
        $sformatf("D1: pred_was_hit=%0d tai execute, ky vong 1", bd.read_pred_was_hit()));
    chk(oX.fl === 2'd0, $sformatf("D1: bpu_flush=%0d, ky vong 0 (du doan dung, khong bong bong)", oX.fl));
    chk(oX.cv === 1'b0, $sformatf("D1: corr_valid=%0d, ky vong 0", oX.cv));
    `uvm_info(test_label, $sformatf({
      "\n=== 2.2 sau khi nha halt, execute so voi quyet dinh luc FETCH ===\n",
      "  pred_was_hit=%0d predicted_taken=%0d branch_taken=1 -> bpu_flush=%0d corr_valid=%0d\n",
      "  (quyet dinh nay da nam yen suot %0d chu ky halt truoc do)\n",
      "================================================================"},
      bd.read_pred_was_hit(), bd.read_predicted_taken(), oX.fl, oX.cv, N_HALT), UVM_NONE)

    //---- PHA E: lam lai, lan nay nhanh KHONG re -> phai bao doan sai -------
    phase_of("E_mispredict_after_halt");
    apply_idle(4);
    check_carry_zero("E truoc phep do");
    // F
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_TK), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b0));
    o = snap();
    chk(o.fv === 1'b1, $sformatf("E: f_valid=%0d tai chu ky F, ky vong 1", o.fv));
    // halt giua duong ong
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_NT), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b1));
    grab_cd();
    frozen = cd;
    for (k = 0; k < N_HALT; k++) begin
      apply(.pc(ADDR_UT), .nxpc(ADDR_UT), .nxpc2(ADDR_NT), .opcode(OPC_BR),
            .btf(32'h40), .flush_in(2'd0), .halt(1'b1));
      cmp_cd($sformatf("E chu ky halt %0d", k), frozen);
    end
    // nha halt, tien mot tang
    apply(.pc(NEU_PC), .nxpc(ADDR_TK), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b0));
    // toi execute, nhanh KHONG re -> doan sai
    apply(.pc(ADDR_TK), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .flush_in(2'd0), .halt(1'b0), .is_branch(1'b1), .taken(1'b0), .offset(32'h40));
    oX = snap();
    exp_corr = ADDR_TK + 32'd4;
    chk(bd.read_predicted_taken() === 1'b1,
        $sformatf("E: predicted_taken=%0d tai execute, ky vong 1", bd.read_predicted_taken()));
    chk(oX.fl === 2'd2,
        $sformatf("E: bpu_flush=%0d, ky vong 2 (doan re nhung nhanh khong re)", oX.fl));
    chk(oX.cv === 1'b1, $sformatf("E: corr_valid=%0d, ky vong 1", oX.cv));
    chk(oX.outp === exp_corr, $sformatf(
      "E: bpu_nxpc2=0x%08h, ky vong 0x%08h (pc + 4, duong hieu chinh cho nhanh khong re)",
      oX.outp, exp_corr));
    chk(oX.outv === 1'b1, $sformatf("E: bpu_nxpc2_valid=%0d, ky vong 1", oX.outv));

    bus_free();
    phase.drop_objection(this, "2_2");
  endtask
endclass : halt_carry_freeze_test
