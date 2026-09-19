//------------------------------------------------------------------------------
// FILE: tests/hyb_carry_tests.sv
//
//   14.1 carry_depth_and_merge        [D] do sau 2 chu ky + phep hop f | d
//   14.2 carry_paths_and_gating_scope [D] ba duong con lai + bat doi xung N1
//   14.3 carry_across_flush           [D] DIEU TRA DesignNotes R2
//   14.4 carry_back_to_back           [D] nhanh sat nhau, khong xuyen nhieu
//
// Ke thua hyb_base_test (tests/hyb_btb_tests.sv) -> include SAU tep do.
// Dung helper bpu_pipe_helper: helper tu chup quan sat tai dung
// canh len, test KHONG bao gio tu doc tin hieu phu thuoc carry-down.
//
// CONG THUC THAM CHIEU (bpu_ctrl.v):
//     predic_taken_delay_1 <= f_valid
//     predic_taken_delay_2 <= predic_taken_delay_1 | d_valid
//   => predicted_taken tai F+2  =  f_valid(F)  |  d_valid(F+1)
//   Ba duong con lai (dong 68-70, 73-75) chi la dich thuan, KHONG co phep hop
//   va KHONG qua fetch_ready.
//------------------------------------------------------------------------------


//==============================================================================
// BASE cho nhom 14: them helper duong ong + tien ich huan luyen.
//==============================================================================
class hyb_carry_base_test extends hyb_base_test;

  bpu_pipe_helper h;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    select_clock();
    super.build_phase(phase);
    h = bpu_pipe_helper::type_id::create("h");
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    h.connect(tb.bpu.tx_agent.sequencer, tb.module_env.backdoor);
  endfunction

  // Huan luyen mot dia chi thanh "BTB hit + du doan RE tai nxpc2".
  //   Duong GHI dung chi muc local_bht[pc_index]; duong DOC du doan tai nxpc2
  //   dung local_bht[nxpc2_index]. Khi nxpc2 == pc thi hai chi muc trung nhau,
  //   nen huan luyen o phia pc la du -- khong can ep gi.
  //   LUU Y: BHT rong 12 bit nen lich su bao hoa 0xFFF
  //   sau 12 nhanh, va local_pht[0xFFF] chi BAT DAU duoc ghi tu nhanh thu 13.
  //   Vi vay phai >= ~20 vong, KHONG dung 12.
  protected task automatic train_predict_taken(bit [31:0] pc, int n = 24);
    repeat (n) drive_branch(pc, 1'b1, 32'h40);
  endtask

  // Huan luyen thanh "BTB hit + du doan KHONG re tai nxpc2".
  //   Nhanh not-taken khong lam dich lich su (chen bit 0 vao 0 -> van 0), nen
  //   moi lan deu dung chi muc 0: WT (init khi miss) -> WNT -> SNT.
  protected task automatic train_predict_not_taken(bit [31:0] pc, int n = 6);
    repeat (n) drive_branch(pc, 1'b0, 32'h40);
  endtask

  protected function void show(string tag, bpu_pipe_obs_t o);
    `uvm_info(test_label, $sformatf(
      "%-22s cyc=%0d pc=0x%08h | predT=%0d hit=%0d locC=%0d glbC=%0d | flush=%0d nxpc2=0x%08h vld=%0d",
      tag, o.cycle, o.pc, o.predicted_taken, o.pred_was_hit, o.local_carry, o.global_carry,
      o.bpu_flush, o.bpu_nxpc2, o.bpu_nxpc2_valid), UVM_NONE)
  endfunction

endclass : hyb_carry_base_test


//==============================================================================
// 14.1 carry_depth_and_merge
//
// Sheet -- Flow: phat mot xung quyet dinh duy nhat tai chu ky F va quan sat
//   predicted_taken cung pred_was_hit tai F, F+1, F+2 va F+3; sau do chay ba
//   kich ban: chi f_valid tai F, chi d_valid tai F+1, va ca hai cung tich cuc.
// Sheet -- Pass: quyet dinh xuat hien dung tai F+2, khong phai F+1 hay F+3; sau
//   reset toan bo tam thanh ghi bang 0; predicted_taken bang 1 tai F+2 trong ca
//   ba kich ban, xac nhan d_valid duoc lay tai F+1 chu khong phai tai F.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class carry_depth_and_merge_test extends hyb_carry_base_test;
  `uvm_component_utils(carry_depth_and_merge_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    test_label = "TEST_14_1 (carry_depth_and_merge)";
    super.build_phase(phase);
  endfunction

  // Day mot nhanh don le qua ba tang va tra ve quan sat tai F..F+3.
  protected task automatic single_shot(bit [31:0] pc,
                                       bit        ovr,
                                       bit [31:0] nx2,
                                       output bpu_pipe_obs_t o[4]);
    int base, k;
    h.idle(4);                       // don sach duong ong truoc khi do
    base = h.num_cycles();
    h.push_branch(.pc(pc), .taken(1'b1), .offset(32'h40),
                  .ovr_nxpc2(ovr), .nxpc2(nx2));
    h.idle(3);                       // F+1, F+2, F+3
    for (k = 0; k < 4; k++) o[k] = h.obs_at_cycle(base + k);
  endtask

  task run_phase(uvm_phase phase);
    bpu_backdoor   bd;
    bpu_pipe_obs_t o[4];
    int k;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "14_1");
    #100ns;

    //---- PHA A: sau reset, ca TAM thanh ghi carry-down = 0 -----------------
    phase_of("A_all_eight_zero_after_reset");
    chk(bd.read_predic_taken_delay_1() === 1'b0, "predic_taken_delay_1 != 0 sau reset");
    chk(bd.read_predic_taken_delay_2() === 1'b0, "predic_taken_delay_2 != 0 sau reset");
    chk(bd.read_btb_hit_delay_1()      === 1'b0, "btb_hit_delay_1 != 0 sau reset");
    chk(bd.read_btb_hit_delay_2()      === 1'b0, "btb_hit_delay_2 != 0 sau reset");
    chk(bd.read_local_delay_1()        === 1'b0, "local_delay_1 != 0 sau reset");
    chk(bd.read_local_delay_2()        === 1'b0, "local_delay_2 != 0 sau reset");
    chk(bd.read_global_delay_1()       === 1'b0, "global_delay_1 != 0 sau reset");
    chk(bd.read_global_delay_2()       === 1'b0, "global_delay_2 != 0 sau reset");

    // Huan luyen A = 0x100 -> BTB hit + du doan RE tai nxpc2 = 0x100
    train_predict_taken(32'h0000_0100, 24);

    //---- PHA B: do sau DUNG hai chu ky ------------------------------------
    phase_of("B_depth_exactly_two");
    single_shot(32'h0000_0100, 1'b1, 32'h0000_0100, o);
    for (k = 0; k < 4; k++) show($sformatf("do sau T+%0d", k), o[k]);
    chk(o[0].predicted_taken === 1'b0, "T  : predicted_taken=1 -- duong ong chua sach truoc phep do");
    chk(o[1].predicted_taken === 1'b0, "T+1: predicted_taken=1 -- do sau chi MOT chu ky, SAI");
    chk(o[2].predicted_taken === 1'b1, "T+2: predicted_taken=0 -- quyet dinh khong toi dung chu ky");
    chk(o[3].predicted_taken === 1'b0, "T+3: predicted_taken van=1 -- quyet dinh khong roi di");
    chk(o[2].pred_was_hit    === 1'b1, "T+2: pred_was_hit=0 du BTB trung tai nxpc2 luc T");
    chk(o[1].pred_was_hit    === 1'b0, "T+1: pred_was_hit=1 -- duong BTB cung phai tre 2 chu ky");

    //---- PHA C: kich ban 1 -- CHI f_valid tai F ---------------------------
    // nxpc2 = 0x100 (da huan luyen, du doan RE) -> f_valid(F) = 1
    // tai F+1 nhanh o DECODE voi nxpc = 0x100, BTB da hop le -> d_valid = 0
    phase_of("C_merge_f_only");
    single_shot(32'h0000_0100, 1'b1, 32'h0000_0100, o);
    show("chi f_valid", o[2]);
    chk(o[2].predicted_taken === 1'b1,
        "chi f_valid tai F: predicted_taken tai F+2 phai = 1");

    //---- PHA D: kich ban 2 -- CHI d_valid tai F+1 -------------------------
    // Dia chi C = 0x900 CHUA tung gap:
    //   tai F  : btb_valid_nxpc2 = 0 -> f_valid = 0
    //   tai F+1: nxpc = 0x900, opcode = BCC, BTB van chua hop le -> d_valid = 1
    // Neu RTL lay d_valid tai F (thay vi F+1) thi predicted_taken se = 0 -> fail.
    phase_of("D_merge_d_only");
    chk(bd.read_btb_valid(576) === 1'b0, "chuan bi: btb_valid[576] (pc=0x900) phai = 0");
    single_shot(32'h0000_0900, 1'b0, 32'h0, o);
    show("chi d_valid", o[2]);
    chk(o[0].predicted_taken === 1'b0, "F  : f_valid phai = 0 cho dia chi chua huan luyen");
    chk(o[2].predicted_taken === 1'b1,
        "chi d_valid tai F+1: predicted_taken tai F+2 phai = 1 (phep hop lay d o F+1)");
    chk(o[2].pred_was_hit    === 1'b0,
        "chi d_valid: pred_was_hit phai = 0 (BTB truot tai nxpc2 luc F)");

    //---- PHA E: kich ban 3 -- CA HAI cung tich cuc ------------------------
    // pc = 0xA00 chua tung gap  -> tai F+1 d_valid = 1
    // ghi de nxpc2 = 0x100      -> tai F   f_valid = 1
    phase_of("E_merge_both");
    chk(bd.read_btb_valid(640) === 1'b0, "chuan bi: btb_valid[640] (pc=0xA00) phai = 0");
    single_shot(32'h0000_0A00, 1'b1, 32'h0000_0100, o);
    show("ca f va d", o[2]);
    chk(o[2].predicted_taken === 1'b1, "ca hai: predicted_taken tai F+2 phai = 1");
    chk(o[2].pred_was_hit    === 1'b1, "ca hai: pred_was_hit phai = 1 (BTB trung tai nxpc2 = 0x100)");

    phase.drop_objection(this, "14_1");
  endtask
endclass : carry_depth_and_merge_test


//==============================================================================
// 14.2 carry_paths_and_gating_scope
//
// Sheet -- Flow: dat btb_valid_nxpc2=1 kem du doan khong re (nen f_valid=0) tai
//   F; dat du bon to hop (local[1], global[1]) tai F; lap lai toan bo voi
//   flush_in=2 tai F trong khi BTB trung va du doan re, roi cap branch_taken=1
//   tai F+2.
// Sheet -- Pass: pred_was_hit=1 tai F+2 du predicted_taken=0; local_carry va
//   global_carry khop gia tri tai F va quyet dinh huong cap nhat bo chon. Voi
//   flush_in=2 tai F: predicted_taken=0 do f_valid bi chan, nhung pred_was_hit=1
//   do KHONG bi chan, nen nhanh re cho mispredict=1, bpu_flush=2 va
//   corr_nxpc2 = btb_target_pc -- bat doi xung ve pham vi chan (DesignNotes N1).
// RTL Ref: bpu_ctrl.v
//==============================================================================
class carry_paths_and_gating_scope_test extends hyb_carry_base_test;
  `uvm_component_utils(carry_paths_and_gating_scope_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  localparam bit [31:0] A_PC   = 32'h0000_0100;   // idx 64
  localparam int        A_IDX  = 64;
  localparam bit [31:0] A_TGT  = 32'h0000_1234;   // btb_target[64] duoc ep
  localparam int        L_IDX  = 12'h345;         // chi muc local_pht duoc ghim

  function void build_phase(uvm_phase phase);
    test_label = "TEST_14_2 (carry_paths_and_gating_scope)";
    super.build_phase(phase);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    scoreboard_not_applicable(
      "phai ep local_pht/global_pht/choice/GHR/BTB de dat DOC LAP hai bit du doan local va global tai nxpc2");
  endfunction

  //--------------------------------------------------------------------------
  // report_phase -- giai thich RO nguon goc cua cac lan scoreboard bao lech.
  //
  //   Muc nay ep btb_valid[64] = 1 bang backdoor (set_scene). Reference model
  //   khong nhin thay lenh ep do, nen shadow state cua no van giu btb_valid = 0.
  //   Hai ben vi vay danh gia tang BACKSTOP khac nhau (bpu_ctrl.v):
  //
  //       d_valid = fetch_is_branch && !btb_valid_nxpc && fetch_ready
  //
  //     - DUT  : btb_valid_nxpc = 1 (da ep) -> d_valid = 0 -> bpu_nxpc2_valid = 0
  //     - REF  : btb_valid_nxpc = 0         -> d_valid = 1 -> bpu_nxpc2_valid = 1
  //                                            va bpu_nxpc2 = nxpc + btf = 0x140
  //
  //   Moi lan dung canh (set_scene) sinh ra vai chu ky lech kieu nay: do la he
  //   qua cua viec ep trang thai noi bo, khong phai loi cua DUT. Vi the muc nay
  //   goi scoreboard_not_applicable() -- scoreboard khong con la checker hop le,
  //   phep kiem that nam o cac chk() doc backdoor.
  //
  //   PHU THUOC CONG CU: muc nay chi chay duoc duoi Xcelium. force/release tren
  //   MOT PHAN TU cua mang khong goi ten (vd bpu_reg.btb_valid[64]) bi QuestaSim
  //   tu choi voi loi vsim-16133, du read/deposit tren dung duong dan do lai
  //   thanh cong. bpu_backdoor bay gio bao `uvm_fatal khi bi tu choi, nen duoi
  //   Questa muc nay dung ngay tai lenh ep chu khong chay tiep roi bao sai.
  //--------------------------------------------------------------------------
  function void report_phase(uvm_phase phase);
    bpu_scoreboard sb;
    super.report_phase(phase);
    sb = tb.module_env.scoreboard;
    `uvm_info(test_label, $sformatf({
      "\n=== GIAI THICH %0d LAN SCOREBOARD BAO LECH ===\n",
      "  Muc nay ep btb_valid[%0d]=1 bang backdoor; reference model khong thay\n",
      "  lenh ep nen shadow cua no van co btb_valid=0. Hai ben do danh gia tang\n",
      "  backstop khac nhau (bpu_ctrl.v): DUT cho d_valid=0, reference cho\n",
      "  d_valid=1 va bpu_nxpc2 = nxpc + branch_target_fetch.\n",
      "  Day la he qua DA BIET cua viec ep trang thai noi bo, khong phai loi DUT.\n",
      "  Phep kiem that cua muc nay nam o cac chk() doc backdoor, khong o scoreboard.\n",
      "======================================="},
      sb.miscompare_count, A_IDX), UVM_NONE)
  endfunction

  // Dung canh: BTB trung tai A, choice chon LOCAL, hai bit du doan dat theo y.
  //
  // Cac BANG deu dung DEPOSIT: set_scene duoc goi lai o dau moi to hop, va
  // giua set_scene voi diem quan sat chi co h.idle(4) -- khong co lenh ghi nao
  // cua DUT (is_branch = 0), nen mot lan dat la du. Giu force o day thi con CHE
  // luon lenh ghi choice cua DUT -- dung cai ma muc nay dang di do.
  //
  // GHR thi NGUOC LAI, phai FORCE: chi muc gshare la pc_index ^ ghr, nen ghr
  // khong chi la mot gia tri ban dau ma la mot phan cua DIA CHI o duoc quan
  // sat. Nhanh cua to hop truoc dich ghr o cuoi h.drain(); neu chi deposit thi
  // toi luc doc, ghr da khac 0 va duong global doc nham o -> global_carry ve 0
  // o moi to hop co G=1. Do la truong hop (b). ghr la duong vo huong nen force
  // chay duoc tren ca hai trinh mo phong.
  protected task automatic set_scene(bit loc_bit, bit glb_bit);
    bpu_backdoor bd = tb.module_env.backdoor;
    bd.deposit_btb(A_IDX, 1'b1, A_TGT);
    bd.force_ghr(10'd0);                                  // chi muc global = A_IDX
    bd.deposit_choice(A_IDX, `WNT);                       // choice[1]=0 -> chon local
    bd.deposit_local_bht(A_IDX, L_IDX[11:0]);             // chi muc local_pht = L_IDX
    bd.deposit_local_pht(L_IDX, loc_bit ? `ST : `SNT);
    bd.deposit_global_pht(A_IDX, glb_bit ? `ST : `SNT);
  endtask

  // Chi con GHR phai tha; cac bang deu la deposit nen khong co gi de tra lai.
  protected task automatic clear_scene();
    bpu_backdoor bd = tb.module_env.backdoor;
    bd.release_ghr();
  endtask

  task run_phase(uvm_phase phase);
    bpu_backdoor   bd;
    bpu_pipe_obs_t o;
    bit [1:0] ch_before, ch_after;
    int  combo;
    bit  L, G;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "14_2");
    #100ns;

    //---- PHA A: duong BTB doc lap voi duong quyet dinh ---------------------
    // btb_valid_nxpc2 = 1 nhung du doan KHONG re -> f_valid = 0.
    // Ky vong tai F+2: pred_was_hit = 1 (duong BTB van mang xuong) trong khi
    // predicted_taken = 0 (khong co chuyen huong). Hai duong hoan toan tach roi.
    phase_of("A_btb_path_independent_of_decision");
    set_scene(.loc_bit(1'b0), .glb_bit(1'b0));    // local du doan KHONG re
    h.idle(4);
    h.push_branch(.pc(A_PC), .taken(1'b0), .offset(32'h40),
                  .ovr_nxpc2(1'b1), .nxpc2(A_PC));
    h.drain();
    o = h.obs_of(h.last_id);
    show("btb path", o);
    chk(o.pred_was_hit    === 1'b1,
        "pred_was_hit = 0 -- duong BTB phai mang xuong DU khong co chuyen huong");
    chk(o.predicted_taken === 1'b0,
        "predicted_taken = 1 -- du doan la KHONG re nen f_valid phai = 0");
    clear_scene();

    //---- PHA B: du BON to hop (local[1], global[1]) ------------------------
    phase_of("B_four_local_global_combos");
    for (combo = 0; combo < 4; combo++) begin
      L = combo[1]; G = combo[0];
      set_scene(.loc_bit(L), .glb_bit(G));
      h.idle(4);
      ch_before = bd.read_choice(A_IDX);
      // branch_taken = 1 -> local dung khi L=1, global dung khi G=1
      h.push_branch(.pc(A_PC), .taken(1'b1), .offset(32'h40),
                    .ovr_nxpc2(1'b1), .nxpc2(A_PC));
      h.drain();
      o = h.obs_of(h.last_id);
      // Lenh ghi choice roi vao canh len cua chu ky F+2, ma helper tra ve NGAY
      // tai canh len do (vung active, truoc NBA) -- doc luc nay se ra gia tri CU.
      // Phai di them mot chu ky nua thi gia tri moi da on.
      h.idle(1);
      ch_after = bd.read_choice(A_IDX);
      show($sformatf("combo L=%0d G=%0d", L, G), o);

      chk(o.local_carry  === L,
          $sformatf("combo L=%0d G=%0d: local_carry=%0d, ky vong %0d (gia tri tai F)",
                    L, G, o.local_carry, L));
      chk(o.global_carry === G,
          $sformatf("combo L=%0d G=%0d: global_carry=%0d, ky vong %0d (gia tri tai F)",
                    L, G, o.global_carry, G));

      // Huong cap nhat bo chon (bpu_predictor.v), branch_taken = 1:
      //   L=0,G=1 -> chi global dung  -> choice tang (ve phia global)
      //   L=1,G=0 -> chi local dung   -> choice giam (ve phia local)
      //   L=G     -> disagree=0       -> choice GIU NGUYEN
      if (L === G)
        chk(ch_after === ch_before,
            $sformatf("combo L=%0d G=%0d: choice %0d->%0d, ky vong GIU (khong bat dong)",
                      L, G, ch_before, ch_after));
      else if (G === 1'b1)
        chk(ch_after > ch_before,
            $sformatf("combo L=%0d G=%0d: choice %0d->%0d, ky vong TANG (global dung)",
                      L, G, ch_before, ch_after));
      else
        chk(ch_after < ch_before,
            $sformatf("combo L=%0d G=%0d: choice %0d->%0d, ky vong GIAM (local dung)",
                      L, G, ch_before, ch_after));
      clear_scene();
    end

    //---- PHA C: BAT DOI XUNG N1 -- fetch_ready chan f_valid, KHONG chan BTB
    // Tai F: BTB trung + du doan RE, nhung flush_in = 2 -> fetch_ready = 0.
    //   f_valid bi chan          -> predicted_taken(F+2) = 0
    //   btb_hit_delay_1 KHONG bi chan -> pred_was_hit(F+2) = 1
    // Tai F+2 cap branch_taken = 1:
    //   mispredict = 1 -> bpu_flush = 2, corr_nxpc2 = btb_target_pc
    phase_of("C_N1_gating_asymmetry");
    set_scene(.loc_bit(1'b1), .glb_bit(1'b1));    // du doan RE
    h.idle(4);
    h.push_branch(.pc(A_PC), .taken(1'b1), .offset(32'h40),
                  .flush_in(2'd2),                 // <-- chan tai CHINH chu ky F
                  .ovr_nxpc2(1'b1), .nxpc2(A_PC));
    h.drain();                                     // F+1, F+2 voi flush_in = 0
    o = h.obs_of(h.last_id);
    show("N1 flush_in=2 @F", o);

    `uvm_info(test_label, $sformatf({
      "\n=== BANG CHUNG N1 (bat doi xung pham vi cua fetch_ready) ===\n",
      "  Tai F   : BTB trung tai nxpc2 = 1, du doan = RE, flush_in = 2\n",
      "  Tai F+2 : predicted_taken = %0d  (f_valid BI CHAN boi fetch_ready)\n",
      "            pred_was_hit    = %0d  (btb_hit_delay KHONG bi chan)\n",
      "            branch_taken    = 1  -> mispredict\n",
      "            bpu_flush       = %0d  (ky vong 2)\n",
      "            bpu_nxpc2       = 0x%08h (ky vong btb_target_pc = 0x%08h)\n",
      "  => fetch_ready chan f_valid nhung KHONG chan ba duong mang xuong con lai.\n",
      "     Day la bat doi xung CO CHU DICH: predicted_taken mo ta 'front-end co\n",
      "     chuyen huong hay khong', con pred_was_hit mo ta 'co thong tin BTB hay\n",
      "     khong' (dung de chon DANG dia chi hieu chinh).\n",
      "============================================================"},
      o.predicted_taken, o.pred_was_hit, o.bpu_flush, o.bpu_nxpc2, A_TGT), UVM_NONE)

    chk(o.predicted_taken === 1'b0,
        "N1: predicted_taken != 0 -- fetch_ready phai chan f_valid");
    chk(o.pred_was_hit    === 1'b1,
        "N1: pred_was_hit != 1 -- fetch_ready KHONG duoc chan duong BTB");
    chk(o.bpu_flush       === 2'd2,
        $sformatf("N1: bpu_flush=%0d, ky vong 2 (mispredict khi BTB trung)", o.bpu_flush));
    chk(o.bpu_nxpc2_valid === 1'b1, "N1: bpu_nxpc2_valid != 1 (phai co hieu chinh)");
    chk(o.bpu_nxpc2       === A_TGT,
        $sformatf("N1: corr_nxpc2=0x%08h, ky vong btb_target_pc=0x%08h", o.bpu_nxpc2, A_TGT));
    clear_scene();

    phase.drop_objection(this, "14_2");
  endtask
endclass : carry_paths_and_gating_scope_test


//==============================================================================
// 14.3 carry_across_flush        --- MUC DIEU TRA (DesignNotes R2)
//
// Sheet -- Flow: dua nhanh vao tang fetch tai F; dat flush_in=2 tai F+1 de mo
//   phong duong ong bi xoa boi mot nhanh truoc do; theo doi toi F+2.
// Sheet -- Pass: GHI NHAN -- dieu kien san sang chan f_valid va d_valid nhung
//   khong chan ba duong con lai. Xac minh khong phat sinh du doan sai hoac hieu
//   chinh gia cho lenh da bi xoa.
// RTL Ref: bpu_ctrl.v
//
// DAY LA MUC DIEU TRA, khong phai muc khang dinh: nhiem vu la GHI NHAN hanh vi
// thuc te. Vi vay cac chk() duoi day chi rang buoc nhung dieu doc truc tiep tu
// RTL (is_branch=0 thi bpu_flush=0 va corr_valid=0), con phan quan sat thi in ra
// log de doi chieu voi docs/DESIGNNOTES_R1_R2_R3.md.
//==============================================================================
class carry_across_flush_test extends hyb_carry_base_test;
  `uvm_component_utils(carry_across_flush_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    test_label = "TEST_14_3 (carry_across_flush)";
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor   bd;
    bpu_pipe_obs_t oA, oB, oC;
    int base;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "14_3");
    #100ns;

    train_predict_taken(32'h0000_0100, 24);      // A = 0x100 -> BTB hit + du doan RE

    //---- PHA A: lenh VAN toi execute -- flush_in=2 chi o F+1 ---------------
    // Kiem tra ba duong mang xuong co bi flush_in chan hay khong.
    phase_of("A_flush_at_Fplus1_branch_survives");
    h.idle(4);
    h.push_branch(.pc(32'h0000_0100), .taken(1'b1), .offset(32'h40),
                  .ovr_nxpc2(1'b1), .nxpc2(32'h0000_0100));   // F: f_valid = 1
    h.drain(.flush_in_d(2'd2), .halt_d(1'b0),                 // F+1: flush_in = 2
            .flush_in_x(2'd0), .halt_x(1'b0));                // F+2: binh thuong
    oA = h.obs_of(h.last_id);
    show("A: flush@F+1, song sot", oA);
    chk(oA.predicted_taken === 1'b1,
        "A: predicted_taken=0 -- quyet dinh tai F bi mat du flush_in chi dat o F+1");
    chk(oA.pred_was_hit    === 1'b1,
        "A: pred_was_hit=0 -- duong BTB bi flush_in chan (khong dung theo RTL)");
    chk(oA.bpu_flush       === 2'd0,
        $sformatf("A: bpu_flush=%0d, ky vong 0 (du doan RE va thuc te RE)", oA.bpu_flush));

    //---- PHA B: lenh BI XOA -- toi execute voi is_branch = 0 ---------------
    // Quyet dinh cua lenh da bi xoa VAN nam trong duong ong tai F+2. Cau hoi:
    // no co sinh ra flush hay hieu chinh gia khong?
    phase_of("B_killed_instruction_no_spurious");
    h.idle(4);
    base = h.num_cycles();
    h.push_branch(.pc(32'h0000_0100), .taken(1'b1), .offset(32'h40),
                  .ovr_nxpc2(1'b1), .nxpc2(32'h0000_0100));   // F: f_valid = 1
    h.idle(1, 2'd2, 1'b0);                                    // F+1: flush_in = 2
    // F+2: lenh da bi xoa -> KHONG toi execute -> is_branch = 0
    h.push_branch(.pc(32'h0000_0FF0), .taken(1'b0), .offset(32'h0),
                  .is_branch(1'b0));
    h.idle(2);
    oB = h.obs_at_cycle(base + 2);                            // chinh chu ky F+2
    show("B: lenh bi xoa @F+2", oB);
    chk(oB.predicted_taken === 1'b1,
        "B: predicted_taken=0 -- duong ong PHAI van mang quyet dinh cu (RTL khong xoa theo flush)");
    chk(oB.bpu_flush       === 2'd0,
        $sformatf("B: bpu_flush=%0d, ky vong 0 -- is_branch=0 phai ep flush=0 (bpu_ctrl.v)",
                  oB.bpu_flush));

    //---- PHA C: nhanh KE TIEP co bi lay nham quyet dinh cu khong? ----------
    // W duoc day vao fetch tai F+1 voi f_valid = 0 (dia chi chua huan luyen).
    // W toi execute tai F+3. Neu duong ong bi "dinh" quyet dinh cua lenh da xoa
    // thi W se thay predicted_taken = 1 -- do la xuyen nhiem that su.
    phase_of("C_next_branch_not_contaminated");
    // W phai duoc huan luyen truoc de btb_valid[704] = 1 -> tai chu ky DECODE
    // cua W thi d_valid = 0. Neu khong, backstop cua CHINH W se bat va cho
    // predicted_taken = 1, de bi hieu nham thanh xuyen nhiem.
    drive_branch(32'h0000_0B00, 1'b1, 32'h40);
    chk(bd.read_btb_valid(704) === 1'b1, "chuan bi: btb_valid[704] (pc=0xB00) phai = 1");
    h.idle(4);
    h.push_branch(.pc(32'h0000_0100), .taken(1'b1), .offset(32'h40),
                  .ovr_nxpc2(1'b1), .nxpc2(32'h0000_0100));   // F  : f_valid = 1
    h.push_branch(.pc(32'h0000_0B00), .taken(1'b0), .offset(32'h40),
                  .flush_in(2'd2),                            // F+1: chan ca f va d cua W
                  .ovr_nxpc2(1'b1), .nxpc2(32'h0000_0FF8));
    h.drain();
    oC = h.obs_of(h.last_id);                                 // W tai F+3
    show("C: nhanh ke tiep W", oC);
    chk(oC.predicted_taken === 1'b0,
        "C: W thay predicted_taken=1 -- XUYEN NHIEM: quyet dinh cua lenh truoc dinh lai");

    //---- KET LUAN DIEU TRA R2 ---------------------------------------------
    `uvm_info(test_label, $sformatf({
      "\n=== DIEU TRA DesignNotes R2: carry-down khi co flush ===\n",
      "  Quan sat 1: flush_in KHONG xoa duong ong. Pha A cho predicted_taken=%0d,\n",
      "              pred_was_hit=%0d tai F+2 du flush_in=2 tai F+1 -- dung nhu doc\n",
      "              tu RTL (bpu_ctrl.v chi co rst_n xoa, halt dong bang).\n",
      "  Quan sat 2: voi lenh DA BI XOA (is_branch=0 tai execute), bpu_flush=%0d va\n",
      "              KHONG co hieu chinh -- bpu_ctrl.v ep ca hai ve 0 khi\n",
      "              is_branch=0. Quyet dinh con sot lai la VO HAI.\n",
      "  Quan sat 3: nhanh ke tiep W thay predicted_taken=%0d, dung bang quyet dinh\n",
      "              fetch cua CHINH NO. Duong ong mang tinh VI TRI: quyet dinh cua\n",
      "              moi lenh toi execute dung 2 chu ky sau khi no o fetch, roi roi di.\n",
      "  KET LUAN  : o muc module KHONG tai hien duoc du doan sai / hieu chinh gia\n",
      "              cho lenh da bi xoa. Rui ro con lai thuoc muc TICH HOP: neu lo\n",
      "              cho mot lenh DA BI XOA van toi execute voi is_branch=1 thi BPU\n",
      "              se so no voi quyet dinh cua chinh no -- BPU khong the biet lenh\n",
      "              do da bi xoa. Can doi chieu voi RTL loi de dong R2.\n",
      "======================================================="},
      oA.predicted_taken, oA.pred_was_hit, oB.bpu_flush, oC.predicted_taken), UVM_NONE)

    phase.drop_objection(this, "14_3");
  endtask
endclass : carry_across_flush_test


//==============================================================================
// 14.4 carry_back_to_back
//
// Sheet -- Flow: phat chuoi nhanh o cac chu ky lien tiep, moi nhanh co quyet
//   dinh fetch khac nhau (xen ke f_valid=1 va f_valid=0).
// Sheet -- Pass: moi nhanh toi tang execute kem DUNG quyet dinh cua chinh no;
//   khong co xuyen nhieu giua hai tang cua duong ong.
// RTL Ref: bpu_ctrl.v
//
// Helper luon lai nhip 1 chu ky (deassert_after = 0)
// nen cac lan push_branch lien tiep nam o cac chu ky KE NHAU.
//==============================================================================
class carry_back_to_back_test extends hyb_carry_base_test;
  `uvm_component_utils(carry_back_to_back_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  localparam int N = 8;

  function void build_phase(uvm_phase phase);
    test_label = "TEST_14_4 (carry_back_to_back)";
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor   bd;
    bpu_pipe_obs_t o;
    int  ids[N];
    int  i, n_wrong;
    bit  exp_pt;
    bit [31:0] pc_i;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "14_4");
    #100ns;

    //---- Chuan bi ----------------------------------------------------------
    // A = 0x100: huan luyen thanh BTB hit + du doan RE  -> dung lam nguon f_valid=1
    // P_i = 0x200 + i*0x100: huan luyen NHE de btb_valid = 1, nhu vay o chu ky
    //   F+1 cua chinh no thi d_valid = 0 (vi btb_valid_nxpc = 1). Nho do
    //   predicted_taken cua P_i CHI phu thuoc f_valid cua chinh no.
    phase_of("prep_train");
    train_predict_taken(32'h0000_0100, 24);
    for (i = 0; i < N; i++) begin
      pc_i = 32'h0000_0200 + (i * 32'h0000_0100);
      drive_branch(pc_i, 1'b1, 32'h40);          // 1 nhanh la du de btb_valid = 1
      chk(bd.read_btb_valid(pc_i[11:2]) === 1'b1,
          $sformatf("chuan bi: btb_valid cho pc=0x%08h phai = 1", pc_i));
    end

    //---- PHA A: N nhanh o cac chu ky KE NHAU, f_valid xen ke --------------
    // i chan -> nxpc2 = 0x100 (da huan luyen, du doan RE) -> f_valid = 1
    // i le   -> nxpc2 = 0xFF8 (chua bao gio ghi)          -> f_valid = 0
    phase_of("A_alternating_f_valid_back_to_back");
    h.idle(4);
    for (i = 0; i < N; i++) begin
      pc_i = 32'h0000_0200 + (i * 32'h0000_0100);
      h.push_branch(.pc(pc_i), .taken(1'b1), .offset(32'h40),
                    .ovr_nxpc2(1'b1),
                    .nxpc2((i % 2 == 0) ? 32'h0000_0100 : 32'h0000_0FF8));
      ids[i] = h.last_id;
    end
    h.drain();

    n_wrong = 0;
    for (i = 0; i < N; i++) begin
      o      = h.obs_of(ids[i]);
      exp_pt = (i % 2 == 0);
      show($sformatf("nhanh #%0d (ky vong predT=%0d)", i, exp_pt), o);
      if (o.predicted_taken !== exp_pt) begin
        n_wrong++;
        chk(1'b0, $sformatf(
          "nhanh #%0d (pc=0x%08h): predicted_taken=%0d, ky vong %0d -- XUYEN NHIEM giua cac tang",
          i, o.pc, o.predicted_taken, exp_pt));
      end
      // pred_was_hit di theo cung nguon: BTB trung tai nxpc2 chi voi i chan
      if (o.pred_was_hit !== exp_pt)
        chk(1'b0, $sformatf(
          "nhanh #%0d: pred_was_hit=%0d, ky vong %0d (duong BTB cung phai theo dung nhanh)",
          i, o.pred_was_hit, exp_pt));
    end

    //---- PHA B: cac nhanh THAT SU o chu ky ke nhau ------------------------
    // Neu giao thuc driver van la 2 chu ky (truoc viec 0.5) thi cac chu ky
    // execute se cach nhau 2 thay vi 1 -> phep kiem nay bat duoc ngay.
    phase_of("B_cycles_are_adjacent");
    for (i = 1; i < N; i++) begin
      int d;
      d = h.obs_of(ids[i]).cycle - h.obs_of(ids[i-1]).cycle;
      chk(d === 1, $sformatf(
        "nhanh #%0d va #%0d cach nhau %0d chu ky, ky vong 1 (back_to_back khong hoat dong)",
        i-1, i, d));
    end

    `uvm_info(test_label, $sformatf(
      "back-to-back: %0d nhanh o %0d chu ky lien tiep, sai quyet dinh = %0d",
      N, h.obs_of(ids[N-1]).cycle - h.obs_of(ids[0]).cycle + 1, n_wrong), UVM_NONE)

    phase.drop_objection(this, "14_4");
  endtask
endclass : carry_back_to_back_test
