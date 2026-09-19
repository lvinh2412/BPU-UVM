//------------------------------------------------------------------------------
// FILE: tests/hyb_choice_tests.sv
//
//   6.1 choice_no_update             [C] viet lai choice_no_update_test
//   6.2 choice_update_and_saturation [C] gop choice_update_test + choice_saturation_test
//   6.3 choice_carry_source          [D] moi -- diem sua loi "bo chon bi ket"
//   6.4 choice_pc_independence       [C] viet lai choice_pc_independence_test
//
// Ke thua hyb_fetch_base_test (tests/hyb_predict_tests.sv) -> include SAU tep do.
//
//==============================================================================
// VI SAO MOI TEST CU CUA NHOM NAY DEU SAI TIEN DE
//
//   bpu_predictor.v so local_carry voi global_carry. Hai tin hieu do KHONG
//   phai gia tri PHT doc tai thoi diem execute: chung la bit du doan doc tai
//   nxpc2 o THOI DIEM FETCH, mang xuong qua bpu_ctrl.v (tang 1) roi
//   :74-75 (tang 2) va lo ra o :83-84. Nghia la:
//
//       local_carry(F+2)  = local_pht_data_nxpc2[1]  lay tai chu ky F
//       global_carry(F+2) = global_pht_data_nxpc2[1] lay tai chu ky F
//
//   Cac test cu deu ep PHT tai CHI MUC PHIA PC ngay truoc khi phat nhanh, roi
//   mong bo chon doc gia tri vua ep. Gia tri dung de cap nhat da duoc chot tu
//   HAI CHU KY TRUOC, nen cach dung canh do khong con tac dung -- do la ly do
//   choice_update_test va choice_saturation_test dang FAIL.
//
//==============================================================================
// CANH DUNG CHUNG -- dung HOAN TOAN bang duong cap nhat that, khong ep gi
//
//   build_scene() dua he thong toi mot trang thai co GHR = 0 va bon dia chi cho
//   dung bon to hop (local_carry, global_carry) khi doc tai nxpc2:
//
//       R_00 = 0x0800  -> local_pht[1024]=SNT , global_pht[512]=SNT   -> (0,0)
//       R_01 = 0x0900  -> local_pht[   5]=SNT , global_pht[576]=WT    -> (0,1)
//       R_10 = 0x0400  -> local_pht[   0]=WT  , global_pht[256]=SNT   -> (1,0)
//       R_11 = 0x0300  -> local_pht[   0]=WT  , global_pht[192]=WT    -> (1,1)
//
//   Ba ky thuat cua lo 1 va lo 2 duoc dung lai nguyen ven:
//     - vong "1 re + 10 khong re" tai dia chi la (w_cycle) dua GHR ve 0 va ghi
//       THANG WT vao local_pht[0] (nhanh dau tai dia chi la co btb_valid_pc=0
//       nen bpu_predictor.v bo qua bo dem) -> tach bit local khoi bit global;
//     - GHR = 0 lam chi muc global bang thang nxpc2_index, nen moi dia chi doc
//       dung o global cua rieng no;
//     - lich su local rieng cua tung chi muc (local_bht) chon o local_pht khac
//       nhau: bht[576]=5 tro toi mot o chua ai ghi, bht[768]=0xFFF tro toi o da
//       bao hoa.
//
//   ADDR_P = 0x0C00 (idx 768) la dia chi GHI: choice[768] la thu duoc do. No co
//   btb_valid=1 va bht=0xFFF, nen moi nhanh khong re tai do ghi vao local_pht o
//   vung chi muc cao (0xFFF, 0xFFE, ...) -- khong dung toi bon o ma bon dia chi
//   R dang doc. Nho vay canh dung KHONG bi chinh phep do lam hong.
//==============================================================================


//==============================================================================
// BASE cho nhom 6.
//==============================================================================
class hyb_choice_base_test extends hyb_fetch_base_test;

  // --- dia chi doc (nxpc2 tai chu ky F) : bon to hop carry ---
  localparam bit [31:0] R_00 = 32'h0000_0800;   // idx 512
  localparam bit [31:0] R_01 = 32'h0000_0900;   // idx 576
  localparam bit [31:0] R_10 = 32'h0000_0400;   // idx 256
  localparam bit [31:0] R_11 = 32'h0000_0300;   // idx 192

  // --- dia chi ghi (pc tai chu ky F+2) ---
  localparam bit [31:0] ADDR_P  = 32'h0000_0C00;   // idx 768 -- muc tieu chinh
  localparam bit [31:0] ADDR_P2 = 32'h0000_0500;   // idx 320 -- doc lap voi P
  localparam bit [31:0] ADDR_PA = 32'h0000_1C00;   // idx 768 -- TRUNG chi muc voi P
  localparam bit [31:0] ADDR_NB = 32'h0000_0700;   // idx 448 -- KHONG co btb_valid

  localparam int P_IDX  = 768;
  localparam int P2_IDX = 320;
  localparam int NB_IDX = 448;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  //--------------------------------------------------------------------------
  // w_cycle -- "1 re + 10 khong re" tai mot dia chi LA.
  //   Nhanh dau  : btb_valid_pc=0 -> local_pht[0] duoc ghi THANG bang WT (bit 1)
  //                va GHR nhan them mot bit 1.
  //   10 nhanh sau: GHR dich them 10 bit 0 -> ve 0 bat ke gia tri truoc do;
  //                local_bht cua dia chi do chay 1,2,4,...,512 nen cac lan ghi
  //                local_pht deu roi vao chi muc luy thua hai, KHONG dung
  //                local_pht[0] nua.
  //--------------------------------------------------------------------------
  protected task automatic w_cycle(bit [31:0] a);
    drive_branch(a, 1'b1, 32'h40);
    repeat (10) drive_branch(a, 1'b0, 32'h40);
  endtask

  //--------------------------------------------------------------------------
  // build_scene -- dung lai canh tu dau. Goi o DAU MOI PHA can canh sach.
  //
  //   BAT DAU BANG MOT LAN RESET. Chuoi huan luyen o duoi chi cho dung ket qua
  //   khi may o trang thai sach: nhanh DAU tai mot dia chi la co btb_valid_pc=0
  //   nen bpu_predictor.v ghi THANG WT thay vi di qua bo dem, va
  //   local_bht xuat phat tu 0 thi moi chay dung day 1,2,4,... Goi build_scene()
  //   lan thu hai tren mot may da co trang thai se ra canh KHAC han -- do la ly
  //   do ban dau cua muc nay FAIL o cac pha co dung lai canh.
  //   Thu tu quan trong: ADDR_P duoc huan luyen TRUOC khi dung R_01, vi qua
  //   trinh huan luyen ADDR_P lam local_bht chay qua 1,3,7,... va se ghi de o
  //   local_pht ma R_01 dinh doc neu lam nguoc lai.
  //--------------------------------------------------------------------------
  protected task automatic build_scene();
    bus_free();
    apply_idle(2);        // is_branch = 0 truoc khi assert reset -- xem ghi chu
    bus_free();           // o muc 1.1 pha A2 ve gioi han cua reference model
    reset_by_force(3);    // canh chi dung neu XUAT PHAT TU TRANG THAI SACH
    repeat (24) drive_branch(ADDR_TK, 1'b1, 32'h40);   // bht[64]=0xFFF
    repeat (6)  drive_branch(ADDR_NT, 1'b0, 32'h40);
    repeat (24) drive_branch(ADDR_P,  1'b1, 32'h40);   // bht[768]=0xFFF, btb_valid=1
    repeat (24) drive_branch(ADDR_P2, 1'b1, 32'h40);   // bht[320]=0xFFF, btb_valid=1
    //   Ca hai dia chi ghi deu phai co local_bht = 0xFFF. Neu de nguyen 0 thi
    //   moi nhanh KHONG RE tai do se ghi vao local_pht[0] -- dung o ma R_10 va
    //   R_11 doc -- va canh dung tu hong sau vai buoc do.
    w_cycle(32'h0000_0800);                            // GHR -> 0, local_pht[0] = WT
    drive_branch(R_01, 1'b1, 32'h40);                  // bht[576]: 0 -> 1
    drive_branch(R_01, 1'b0, 32'h40);                  // bht[576]: 1 -> 2
    drive_branch(R_01, 1'b1, 32'h40);                  // bht[576]: 2 -> 5 (o chua ai ghi)
    w_cycle(32'h0000_0A00);                            // GHR -> 0
  endtask

  //--------------------------------------------------------------------------
  // assert_carry -- kiem TIEN DE: dia chi R that su cho dung to hop mong doi.
  //   Doc thang hai cong doc tai nxpc2 (bpu_reg.v) truoc khi do bat cu
  //   dieu gi ve bo chon. Khong co buoc nay thi mot canh dung sai van co the
  //   "pass" nham -- rui ro cao nhat cua nhom 6.
  //--------------------------------------------------------------------------
  protected task automatic assert_carry(string lbl, bit [31:0] R, bit exp_l, bit exp_g);
    bpu_fetch_obs_t o;
    observe_at(R, 2'd0, o);
    chk(o.lp[1] === exp_l, $sformatf(
      "%s: nxpc2=0x%08h cho local_pht_data_nxpc2[1]=%0d (%02b), canh dung SAI (can %0d)",
      lbl, R, o.lp[1], o.lp, exp_l));
    chk(o.gp[1] === exp_g, $sformatf(
      "%s: nxpc2=0x%08h cho global_pht_data_nxpc2[1]=%0d (%02b), canh dung SAI (can %0d)",
      lbl, R, o.gp[1], o.gp, exp_g));
  endtask

  protected task automatic assert_scene(string lbl);
    bpu_backdoor bd = tb.module_env.backdoor;
    assert_carry({lbl, " R_00"}, R_00, 1'b0, 1'b0);
    assert_carry({lbl, " R_01"}, R_01, 1'b0, 1'b1);
    assert_carry({lbl, " R_10"}, R_10, 1'b1, 1'b0);
    assert_carry({lbl, " R_11"}, R_11, 1'b1, 1'b1);
    chk(bd.read_btb_valid(P_IDX) === 1'b1, $sformatf(
      "%s: btb_valid[%0d] phai = 1 thi choice_wr_en moi co the tich cuc", lbl, P_IDX));
    chk(bd.read_ghr() === 10'd0, $sformatf(
      "%s: ghr=0x%03h, canh dung can 0 de chi muc global bang nxpc2_index", lbl, bd.read_ghr()));
  endtask

  //--------------------------------------------------------------------------
  // choice_step -- MOT lan cap nhat bo chon, lai tay tung chu ky.
  //
  //     F   : nxpc2 = R      -> chot (local_carry, global_carry)
  //     F+1 : trung tinh, opcode = ADDI -> d_valid = 0, khong co gi xen vao
  //     F+2 : pc = P, is_branch = 1, branch_taken = taken
  //           doc local_carry/global_carry/choice_wr_en NGAY tai day: chung la
  //           gia tri cua chinh chu ky nay, truoc canh len ghi bo chon
  //     F+3 : mot chu ky nua de lenh ghi tai canh len F+2 on dinh roi moi doc
  //           (doc ngay sau F+2 se ra gia tri CU -- xem ghi chu ben duoi)
  //--------------------------------------------------------------------------
  protected task automatic choice_step(input  bit [31:0] R,
                                       input  bit [31:0] P,
                                       input  bit        taken,
                                       input  int        cidx,
                                       output bit        lc,
                                       output bit        gc,
                                       output bit        wren,
                                       output bit [1:0]  ch_b,
                                       output bit [1:0]  ch_a,
                                       input  bit        is_branch = 1'b1);
    bpu_backdoor bd = tb.module_env.backdoor;
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(R),         .opcode(OPC_NOP));
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP));
    ch_b = bd.read_choice(cidx);
    apply(.pc(P), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .btf(32'h0), .flush_in(2'd0), .halt(1'b0),
          .is_branch(is_branch), .taken(taken), .offset(32'h40));
    lc   = bd.read_local_carry();
    gc   = bd.read_global_carry();
    wren = bd.read_choice_wr_en();
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP));
    ch_a = bd.read_choice(cidx);
  endtask

  // Bo dem bao hoa 2 bit -- ban sao bpu_predictor.v dung de tinh ky vong
  // CHINH XAC (ke ca o hai dau day) thay vi chi doi hoi "tang" hay "giam".
  protected function bit [1:0] upd_ctr(bit [1:0] cur, bit taken);
    case (cur)
      `ST     : upd_ctr = taken ? `ST  : `WT ;
      `WT     : upd_ctr = taken ? `ST  : `WNT;
      `WNT    : upd_ctr = taken ? `WT  : `SNT;
      default : upd_ctr = taken ? `WNT : `SNT;   // SNT
    endcase
  endfunction

  // Ky vong cho MOT lan cap nhat bo chon (bpu_predictor.v).
  protected function bit [1:0] exp_choice(bit [1:0] cur, bit l, bit g, bit taken, bit wr_ok);
    if (!wr_ok || (l === g)) exp_choice = cur;              // choice_wr_en = 0
    else                     exp_choice = upd_ctr(cur, (g === taken) ? 1'b1 : 1'b0);
  endfunction

  protected function string cn(bit [1:0] v);
    case (v)
      2'b00: cn = "SNT"; 2'b01: cn = "WNT"; 2'b10: cn = "WT "; default: cn = "ST ";
    endcase
  endfunction

endclass : hyb_choice_base_test


//==============================================================================
// 6.1 choice_no_update
//
// Sheet -- Flow: ba truong hop rieng biet; moi truong hop phai day nhanh qua du
//   ba tang de carry-down co gia tri xac dinh truoc khi danh gia.
// Sheet -- Pass: choice_wr_en = 0 va gia tri choice giu nguyen trong ca ba.
// RTL Ref: bpu_predictor.v
//==============================================================================
class choice_no_update_test extends hyb_choice_base_test;
  `uvm_component_utils(choice_no_update_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_6_1 (choice_no_update)"; super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor bd;
    bit       lc, gc, wren;
    bit [1:0] b, a;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "6_1");
    #100ns;

    phase_of("A_build_scene");
    build_scene();
    assert_scene("A");

    //---- PHA B: KHONG PHAI lenh re nhanh (is_branch = 0) -------------------
    // Canh van BAT DONG (R_10) va btb_valid_pc van = 1: dieu kien duy nhat
    // thieu la is_branch. Neu khong dung canh bat dong thi phep kiem vacuous.
    phase_of("B_not_a_branch");
    choice_step(.R(R_10), .P(ADDR_P), .taken(1'b0), .cidx(P_IDX),
                .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a), .is_branch(1'b0));
    chk(lc !== gc, $sformatf(
      "B: carry=(%0d,%0d) -- can BAT DONG thi phep kiem moi co nghia", lc, gc));
    chk(wren === 1'b0, $sformatf("B: choice_wr_en=%0d voi is_branch=0, ky vong 0", wren));
    chk(a === b, $sformatf("B: choice[%0d] %s -> %s, ky vong giu nguyen", P_IDX, cn(b), cn(a)));
    `uvm_info(test_label, $sformatf(
      "B (is_branch=0) : carry=(%0d,%0d) bat dong, btb_valid_pc=1 -> choice_wr_en=%0d, choice[%0d] giu %s",
      lc, gc, wren, P_IDX, cn(a)), UVM_NONE)

    //---- PHA C: btb_valid_pc = 0 ------------------------------------------
    // ADDR_NB chua bao gio la pc nen btb_valid[448] = 0. Canh van bat dong.
    phase_of("C_btb_valid_pc_zero");
    chk(bd.read_btb_valid(NB_IDX) === 1'b0, $sformatf(
      "chuan bi C: btb_valid[%0d] phai = 0", NB_IDX));
    choice_step(.R(R_10), .P(ADDR_NB), .taken(1'b0), .cidx(NB_IDX),
                .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
    chk(lc !== gc, $sformatf("C: carry=(%0d,%0d) -- can BAT DONG", lc, gc));
    chk(wren === 1'b0, $sformatf("C: choice_wr_en=%0d voi btb_valid_pc=0, ky vong 0", wren));
    chk(a === b, $sformatf("C: choice[%0d] %s -> %s, ky vong giu nguyen", NB_IDX, cn(b), cn(a)));
    `uvm_info(test_label, $sformatf(
      "C (btb_valid_pc=0): carry=(%0d,%0d) bat dong, is_branch=1 -> choice_wr_en=%0d, choice[%0d] giu %s",
      lc, gc, wren, NB_IDX, cn(a)), UVM_NONE)

    //---- PHA D: local_carry == global_carry (DONG THUAN) -------------------
    // Hai truong hop dong thuan: ca hai cung 0 (R_00) va ca hai cung 1 (R_11).
    // Voi moi truong hop lai thu ca hai gia tri branch_taken, vi neu RTL lo
    // dung mot phep so khac thi mot trong hai se lo ra.
    phase_of("D_carry_agree");
    for (int k = 0; k < 4; k++) begin
      bit [31:0] R;  bit tk;
      R  = k[1] ? R_11 : R_00;
      tk = k[0];
      // Dung lai canh cho TUNG truong hop: buoc co branch_taken=1 lam GHR dich
      // mot bit, va chi muc global cua moi dia chi R la (nxpc2_index ^ ghr) nen
      // canh se lech ngay o truong hop ke tiep neu khong dung lai.
      build_scene();
      assert_scene($sformatf("D o %0d", k));
      choice_step(.R(R), .P(ADDR_P), .taken(tk), .cidx(P_IDX),
                  .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
      chk(lc === gc, $sformatf(
        "D: nxpc2=0x%08h cho carry=(%0d,%0d) -- canh dung SAI, can DONG THUAN", R, lc, gc));
      chk(wren === 1'b0, $sformatf(
        "D: carry=(%0d,%0d) taken=%0d -> choice_wr_en=%0d, ky vong 0 (dong thuan)", lc, gc, tk, wren));
      chk(a === b, $sformatf(
        "D: carry=(%0d,%0d) taken=%0d -> choice[%0d] %s -> %s, ky vong giu nguyen",
        lc, gc, tk, P_IDX, cn(b), cn(a)));
      `uvm_info(test_label, $sformatf(
        "D dong thuan (%0d,%0d) taken=%0d -> choice_wr_en=%0d, choice[%0d] giu %s",
        lc, gc, tk, wren, P_IDX, cn(a)), UVM_NONE)
    end

    //---- PHA E: doi chung -- cung khung do NHUNG du dieu kien -> PHAI ghi --
    // Neu thieu pha nay thi ca bon pha tren co the "pass" chi vi khung do khong
    // bao gio lam bo chon doi duoc.
    phase_of("E_positive_control");
    choice_step(.R(R_10), .P(ADDR_P), .taken(1'b0), .cidx(P_IDX),
                .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
    chk(lc !== gc, $sformatf("E: carry=(%0d,%0d) -- can BAT DONG", lc, gc));
    chk(wren === 1'b1, $sformatf(
      "E: choice_wr_en=%0d khi du ca ba dieu kien, ky vong 1", wren));
    chk(a === upd_ctr(b, 1'b1), $sformatf(
      "E: choice[%0d] %s -> %s, ky vong %s", P_IDX, cn(b), cn(a), cn(upd_ctr(b, 1'b1))));
    `uvm_info(test_label, $sformatf(
      "E doi chung: du ca ba dieu kien -> choice_wr_en=1, choice[%0d] %s -> %s",
      P_IDX, cn(b), cn(a)), UVM_NONE)

    bus_free();
    phase.drop_objection(this, "6_1");
  endtask
endclass : choice_no_update_test


//==============================================================================
// 6.2 choice_update_and_saturation
//
// Sheet -- Flow: tao bat dong local khac global tai thoi diem fetch; day nhanh
//   qua du ba tang roi cap branch_taken tai tang execute; lap muoi lan cho chieu
//   global dung, sau do muoi lan cho chieu local dung.
// Sheet -- Pass: bo dem tien ve phia global khi global_carry dung va ve phia
//   local khi local_carry dung; dung tai ST sau khi bao hoa roi giam dan ve SNT
//   va dung tai SNT.
// RTL Ref: bpu_predictor.v ; bpu_ctrl.v
//==============================================================================
class choice_update_and_saturation_test extends hyb_choice_base_test;
  `uvm_component_utils(choice_update_and_saturation_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_6_2 (choice_update_and_saturation)"; super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor bd;
    bit       lc, gc, wren;
    bit [1:0] b, a, e;
    int       k, n_sat_hi, n_sat_lo;
    string    s;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "6_2");
    #100ns;

    phase_of("A_build_scene");
    build_scene();
    assert_scene("A");
    `uvm_info(test_label, $sformatf(
      "A: choice[%0d] xuat phat tu %s, btb_valid=%0d, ghr=0x%03h",
      P_IDX, cn(bd.read_choice(P_IDX)), bd.read_btb_valid(P_IDX), bd.read_ghr()), UVM_NONE)

    //---- PHA B: 10 buoc chieu GLOBAL dung -> tien len roi bao hoa tai ST ---
    // carry = (1,0), branch_taken = 0  =>  global_carry == branch_taken
    //   => bpu_predictor.v chon nhanh (!local_correct && global_correct)
    //   => update_counter(choice, 1) : tien ve phia GLOBAL.
    // branch_taken = 0 con mot loi ich nua: GHR khong dich (bpu_predictor.v
    // chen bit 0 vao GHR dang bang 0), nen chi muc global cua R_10 dung yen suot
    // ca muoi buoc -- canh dung khong tu hong.
    phase_of("B_ten_steps_toward_global");
    s = "\n=== 6.2 QUY DAO BO DEM CHOICE ===\n";
    s = {s, "  Pha B: carry=(local=1, global=0), branch_taken=0 -> GLOBAL dung -> tien len\n"};
    s = {s, "   buoc | carry | wr_en | choice truoc -> sau | ky vong\n"};
    s = {s, "   -----+-------+-------+---------------------+--------\n"};
    n_sat_hi = 0;
    for (k = 0; k < 10; k++) begin
      choice_step(.R(R_10), .P(ADDR_P), .taken(1'b0), .cidx(P_IDX),
                  .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
      e = exp_choice(b, 1'b1, 1'b0, 1'b0, 1'b1);
      chk(lc === 1'b1 && gc === 1'b0, $sformatf(
        "B buoc %0d: carry=(%0d,%0d), canh dung SAI (can 1,0)", k+1, lc, gc));
      chk(wren === 1'b1, $sformatf("B buoc %0d: choice_wr_en=%0d, ky vong 1", k+1, wren));
      chk(a === e, $sformatf("B buoc %0d: choice[%0d] %s -> %s, ky vong %s",
                             k+1, P_IDX, cn(b), cn(a), cn(e)));
      if (b === `ST && a === `ST) n_sat_hi++;
      s = {s, $sformatf("    %2d  | (%0d,%0d) |   %0d   | %s -> %s          | %s\n",
                        k+1, lc, gc, wren, cn(b), cn(a), cn(e))};
    end
    chk(bd.read_choice(P_IDX) === `ST, $sformatf(
      "B: sau 10 buoc choice[%0d]=%s, ky vong ST", P_IDX, cn(bd.read_choice(P_IDX))));
    chk(n_sat_hi >= 6, $sformatf(
      "B: chi co %0d buoc o trang thai bao hoa ST -- chua chung minh duoc no KHONG tran", n_sat_hi));

    //---- PHA C: 10 buoc chieu LOCAL dung -> giam dan roi bao hoa tai SNT ---
    // carry = (0,1), branch_taken = 0  =>  local_carry == branch_taken
    //   => bpu_predictor.v chon nhanh (local_correct && !global_correct)
    //   => update_counter(choice, 0) : tien ve phia LOCAL.
    phase_of("C_ten_steps_toward_local");
    s = {s, "  Pha C: carry=(local=0, global=1), branch_taken=0 -> LOCAL dung -> giam dan\n"};
    s = {s, "   buoc | carry | wr_en | choice truoc -> sau | ky vong\n"};
    s = {s, "   -----+-------+-------+---------------------+--------\n"};
    n_sat_lo = 0;
    for (k = 0; k < 10; k++) begin
      choice_step(.R(R_01), .P(ADDR_P), .taken(1'b0), .cidx(P_IDX),
                  .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
      e = exp_choice(b, 1'b0, 1'b1, 1'b0, 1'b1);
      chk(lc === 1'b0 && gc === 1'b1, $sformatf(
        "C buoc %0d: carry=(%0d,%0d), canh dung SAI (can 0,1)", k+1, lc, gc));
      chk(wren === 1'b1, $sformatf("C buoc %0d: choice_wr_en=%0d, ky vong 1", k+1, wren));
      chk(a === e, $sformatf("C buoc %0d: choice[%0d] %s -> %s, ky vong %s",
                             k+1, P_IDX, cn(b), cn(a), cn(e)));
      if (b === `SNT && a === `SNT) n_sat_lo++;
      s = {s, $sformatf("    %2d  | (%0d,%0d) |   %0d   | %s -> %s          | %s\n",
                        k+1, lc, gc, wren, cn(b), cn(a), cn(e))};
    end
    chk(bd.read_choice(P_IDX) === `SNT, $sformatf(
      "C: sau 10 buoc choice[%0d]=%s, ky vong SNT", P_IDX, cn(bd.read_choice(P_IDX))));
    chk(n_sat_lo >= 6, $sformatf(
      "C: chi co %0d buoc o trang thai bao hoa SNT -- chua chung minh duoc no KHONG muon", n_sat_lo));
    s = {s, "   Bo dem dung han tai ST va tai SNT, khong tran vong.\n"};
    s = {s, "======================================="};
    `uvm_info(test_label, s, UVM_NONE)

    //---- PHA D: quet du TAM o cua cx_choice_update_table -------------------
    // Cross la carry_local x carry_global x branch_taken. Cac muc truoc chi lai
    // branch_taken=1 nen cross moi dat 37.5%. O day quet ca BON to hop carry
    // voi CA HAI gia tri branch_taken.
    //   Moi o dung lai canh tu dau roi nap bo dem ve WT: tu WT thi ca ba ket
    //   qua (tang / giam / giu) deu quan sat duoc, con neu de bo dem nam o dau
    //   day thi mot chieu se bi che mat.
    phase_of("D_sweep_eight_cells");
    s = "\n=== 6.2 TAM O CUA cx_choice_update_table ===\n";
    s = {s, "   local global taken | wr_en | choice truoc -> sau | ky vong | huong\n"};
    s = {s, "   -------------------+-------+---------------------+---------+--------\n"};
    for (k = 0; k < 8; k++) begin
      bit tk;  bit [31:0] R;  bit el, eg;  string dir;
      tk = k[2];
      case (k[1:0])
        2'd0: begin R = R_00; el = 1'b0; eg = 1'b0; end
        2'd1: begin R = R_01; el = 1'b0; eg = 1'b1; end
        2'd2: begin R = R_10; el = 1'b1; eg = 1'b0; end
        default: begin R = R_11; el = 1'b1; eg = 1'b1; end
      endcase
      build_scene();
      // nap bo dem ve WT bang chinh duong that: hai buoc "tien ve global"
      choice_step(.R(R_10), .P(ADDR_P), .taken(1'b0), .cidx(P_IDX),
                  .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
      choice_step(.R(R_10), .P(ADDR_P), .taken(1'b0), .cidx(P_IDX),
                  .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
      chk(a === `WT, $sformatf("D o %0d: nap bo dem ve WT that bai, dang o %s", k, cn(a)));
      // o can do
      choice_step(.R(R), .P(ADDR_P), .taken(tk), .cidx(P_IDX),
                  .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
      e = exp_choice(b, el, eg, tk, 1'b1);
      chk(lc === el && gc === eg, $sformatf(
        "D o %0d: carry=(%0d,%0d), canh dung SAI (can %0d,%0d)", k, lc, gc, el, eg));
      chk(wren === ((el !== eg) ? 1'b1 : 1'b0), $sformatf(
        "D o %0d: choice_wr_en=%0d, ky vong %0d", k, wren, (el !== eg)));
      chk(a === e, $sformatf("D o %0d (l=%0d g=%0d taken=%0d): choice %s -> %s, ky vong %s",
                             k, el, eg, tk, cn(b), cn(a), cn(e)));
      dir = (a === b) ? "giu"   :
            (a >   b) ? "tang"  : "giam";
      s = {s, $sformatf("     %0d     %0d      %0d    |   %0d   | %s -> %s          | %s     | %s\n",
                        el, eg, tk, wren, cn(b), cn(a), cn(e), dir)};
    end
    s = {s, "   -------------------+-------+---------------------+---------+--------\n"};
    s = {s, "   local == global -> choice_wr_en = 0, bo dem dung yen o ca hai gia tri taken.\n"};
    s = {s, "   local != global -> tien ve phia bo du doan trung voi branch_taken.\n"};
    s = {s, "======================================="};
    `uvm_info(test_label, s, UVM_NONE)

    bus_free();
    phase.drop_objection(this, "6_2");
  endtask
endclass : choice_update_and_saturation_test


//==============================================================================
// 6.3 choice_carry_source
//
// Sheet -- Flow: dung tinh huong ma gia tri local/global tai chu ky F khac voi
//   gia tri doc duoc tai F+2 (vi du GHR da dich, hoac PHT bi mot nhanh khac cap
//   nhat xen vao giua); quan sat huong cap nhat cua bo chon.
// Sheet -- Pass: bo chon cap nhat theo local_carry va global_carry (gia tri tai
//   F). Neu cap nhat theo gia tri tai F+2 thi test phai bao loi.
// RTL Ref: bpu_ctrl.v ; bpu_predictor.v
//
//==============================================================================
// CACH DUNG CHENH LECH F so voi F+2
//
//   Dung MOT dia chi duy nhat A cho ca hai vai tro -- nxpc2 tai F va pc tai F+2 --
//   dung nhu mot lenh that di qua duong ong. Chen mot nhanh KHAC tai F+1, va
//   nhanh do lam doi DONG THOI ca hai duong doc cua A:
//
//     (a) GHR dich  : GHR = 1 tai F, nhanh xen vao (khong re) day GHR len 2.
//                     Chi muc global cua A doi tu (A_idx ^ 1) sang (A_idx ^ 2),
//                     tuc tu o 257 sang o 258 -- hai o co gia tri NGUOC nhau.
//     (b) PHT bi ghi de: nhanh xen vao co local_bht = 0 giong A, nen lenh ghi
//                     cua no roi dung vao local_pht[0] -- chinh o ma A doc.
//                     WT (bit 1) -> WNT (bit 0).
//
//   Ket qua: tai F doc duoc (local=1, global=0), tai F+2 doc duoc (local=0,
//   global=1) -- NGUOC HAN nhau. Voi branch_taken = 0:
//
//     nguon carry-down (dung)  : global_carry == branch_taken -> TIEN LEN
//     nguon execute-time (sai) : local doc tai F+2 == branch_taken -> GIAM
//
//   Hai gia thuyet cho hai huong doi nguoc nhau, nen phep do phan biet duoc
//   chung -- khong chi la "choice co doi hay khong".
//==============================================================================
class choice_carry_source_test extends hyb_choice_base_test;
  `uvm_component_utils(choice_carry_source_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_6_3 (choice_carry_source)"; super.build_phase(phase);
  endfunction

  localparam bit [31:0] A_ADDR = 32'h0000_0400;   // idx 256 -- nxpc2 tai F VA pc tai F+2
  localparam int        A_IDX  = 256;
  localparam bit [31:0] X_ADDR = 32'h0000_0D00;   // idx 832 -- nhanh XEN VAO tai F+1
  localparam bit [31:0] Z_ADDR = 32'h0000_0E00;   // idx 896 -- dat GHR = 1
  localparam bit [31:0] G_ADDR = 32'h0000_0408;   // idx 258 -- nap global_pht[258] = WT

  //--------------------------------------------------------------------------
  // arm -- dung canh cho phep do. Sau khi goi: GHR = 1, A co btb_valid = 1 va
  //   local_bht = 0, local_pht[0] = WT, global_pht[257] = SNT, global_pht[258] = WT.
  //--------------------------------------------------------------------------
  protected task automatic arm();
    build_scene();                              // GHR = 0, local_pht[0] = WT
    drive_branch(A_ADDR, 1'b0, 32'h40);         // A: btb_valid = 1, local_bht van = 0
    drive_branch(G_ADDR, 1'b0, 32'h40);         // dia chi la, idx 258, GHR=0
                                                //   -> btb_valid_pc=0 nen global_pht[258]
                                                //      duoc ghi THANG bang WT (bit 1)
    drive_branch(X_ADDR, 1'b0, 32'h40);         // X: btb_valid = 1, local_bht van = 0
    drive_branch(Z_ADDR, 1'b1, 32'h40);         // GHR: 0 -> 1
  endtask

  task run_phase(uvm_phase phase);
    bpu_backdoor    bd;
    bpu_fetch_obs_t o;
    bit       lF, gF, lX, gX, lc, gc, wren;
    bit [9:0] ghr_x2;
    bit [1:0] b, a, e_carry, e_exec;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "6_3");
    #100ns;

    //---- PHA A: dung canh va kiem tien de ---------------------------------
    phase_of("A_arm_and_assert");
    arm();
    chk(bd.read_ghr() === 10'd1, $sformatf(
      "A: ghr=0x%03h, canh dung can 1 (de nhanh xen vao doi duoc chi muc global)", bd.read_ghr()));
    chk(bd.read_btb_valid(A_IDX) === 1'b1, "A: btb_valid[A] phai = 1 (dieu kien choice_wr_en)");
    chk(bd.read_local_bht(A_IDX) === 12'd0, $sformatf(
      "A: local_bht[A]=0x%03h, canh dung can 0 (de A doc local_pht[0])", bd.read_local_bht(A_IDX)));
    observe_at(A_ADDR, 2'd0, o);
    lF = o.lp[1]; gF = o.gp[1];
    chk(lF === 1'b1 && gF === 1'b0, $sformatf(
      "A: tai F doc duoc (local,global)=(%0d,%0d), canh dung can (1,0)", lF, gF));

    //---- PHA B: phep do -- ba chu ky lien tiep -----------------------------
    phase_of("B_measure");
    b = bd.read_choice(A_IDX);
    // F : nxpc2 = A -> chot carry
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(A_ADDR), .opcode(OPC_NOP));
    // F+1 : nhanh XEN VAO tai X, khong re -> GHR 1 -> 2 va ghi de local_pht[0]
    apply(.pc(X_ADDR), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .btf(32'h0), .flush_in(2'd0), .halt(1'b0),
          .is_branch(1'b1), .taken(1'b0), .offset(32'h40));
    // F+2 : nhanh cua CHINH A. Truoc canh len, doc CA HAI nguon de doi chieu.
    apply(.pc(A_ADDR), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .btf(32'h0), .flush_in(2'd0), .halt(1'b0),
          .is_branch(1'b1), .taken(1'b0), .offset(32'h40));
    lc   = bd.read_local_carry();               // nguon THAT: gia tri tai F
    gc   = bd.read_global_carry();
    lX   = bd.read_local_pht_data_pc()[1];      // nguon DOI CHUNG: gia tri tai F+2
    gX   = bd.read_global_pht_data_pc()[1];
    wren = bd.read_choice_wr_en();
    ghr_x2 = bd.read_ghr();                     // GHR DUNG TAI F+2, khong phai luc bao cao
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP));
    a = bd.read_choice(A_IDX);

    //---- PHA C: doi chieu hai gia thuyet ----------------------------------
    phase_of("C_discriminate");
    e_carry = exp_choice(b, lc, gc, 1'b0, 1'b1);   // neu dung carry-down (gia tri F)
    e_exec  = exp_choice(b, lX, gX, 1'b0, 1'b1);   // neu dung gia tri doc tai F+2

    chk(lc === 1'b1 && gc === 1'b0, $sformatf(
      "C: local_carry/global_carry = (%0d,%0d), canh dung can (1,0) -- gia tri tai F", lc, gc));
    chk(lX === 1'b0 && gX === 1'b1, $sformatf(
      "C: doc theo pc tai F+2 = (%0d,%0d), canh dung can (0,1) -- phai NGUOC voi tai F", lX, gX));
    chk(e_carry !== e_exec, $sformatf(
      "C: hai gia thuyet cho cung ket qua %s -- phep do KHONG phan biet duoc, canh dung hong",
      cn(e_carry)));
    chk(wren === 1'b1, $sformatf("C: choice_wr_en=%0d, ky vong 1", wren));
    chk(a === e_carry, $sformatf(
      "C: choice[%0d] %s -> %s. Nguon CARRY-DOWN cho %s, nguon EXECUTE-TIME cho %s -> RTL dang dung nguon SAI",
      A_IDX, cn(b), cn(a), cn(e_carry), cn(e_exec)));

    `uvm_info(test_label, $sformatf({
      "\n=== 6.3 NGUON GIA TRI CAP NHAT BO CHON ===\n",
      "  Mot dia chi 0x%08h di qua ca ba tang; mot nhanh khac xen vao tai F+1.\n",
      "    tai F   (nxpc2) : local=%0d global=%0d   <- gia tri duoc CHOT vao carry-down\n",
      "    tai F+2 (pc)    : local=%0d global=%0d   <- gia tri neu doc lai luc execute\n",
      "    GHR 0x001 -> 0x%03h tai F+2 (nhanh xen vao lam dich) => chi muc global doi 257 -> 258\n",
      "    local_pht[0] bi chinh nhanh xen vao ghi de   => bit local doi 1 -> 0\n",
      "  branch_taken = 0:\n",
      "    neu dung carry-down  (dung) -> choice %s -> %s\n",
      "    neu dung gia tri F+2 (sai)  -> choice %s -> %s\n",
      "  DO DUOC: choice[%0d] %s -> %s  ==> RTL dung CARRY-DOWN.\n",
      "  Day la diem sua loi 'bo chon bi ket': neu doc lai tai execute thi moi\n",
      "  lan GHR dich hoac PHT bi nhanh khac cap nhat, bo chon se hoc nham chieu.\n",
      "======================================="},
      A_ADDR, lc, gc, lX, gX, ghr_x2,
      cn(b), cn(e_carry), cn(b), cn(e_exec), A_IDX, cn(b), cn(a)), UVM_NONE)

    bus_free();
    phase.drop_objection(this, "6_3");
  endtask
endclass : choice_carry_source_test


//==============================================================================
// 6.4 choice_pc_independence
//
// Sheet -- Flow: phat mau cap nhat nguoc nhau tai cac PC khong trung chi muc va
//   tai cac PC trung chi muc.
// Sheet -- Pass: khong trung: hai bo dem doc lap. Trung chi muc: lan ghi sau thang.
// RTL Ref: bpu_reg.v
//==============================================================================
class choice_pc_independence_test extends hyb_choice_base_test;
  `uvm_component_utils(choice_pc_independence_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_6_4 (choice_pc_independence)"; super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor bd;
    bit       lc, gc, wren;
    bit [1:0] b, a, p_start, p2_start;
    int       k;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "6_4");
    #100ns;

    //---- PHA A: dung canh, them ADDR_P2 vao BTB ---------------------------
    phase_of("A_build_scene");
    build_scene();
    // ADDR_P2 phai co btb_valid = 1 thi choice_wr_en moi tich cuc duoc.
    // Mot nhanh khong re tai dia chi la: btb_valid -> 1, local_bht van = 0, GHR
    // khong dich (dang bang 0) -> canh dung khong bi xe dich.
    drive_branch(ADDR_P2, 1'b0, 32'h40);
    assert_scene("A");
    chk(bd.read_btb_valid(P2_IDX) === 1'b1, $sformatf(
      "A: btb_valid[%0d] phai = 1", P2_IDX));
    chk(ADDR_P[11:2] !== ADDR_P2[11:2], "chuan bi A: hai PC nay phai KHAC chi muc");
    chk(ADDR_P[11:2] === ADDR_PA[11:2], "chuan bi A: ADDR_PA phai TRUNG chi muc voi ADDR_P");

    //---- PHA B: hai PC KHONG trung chi muc -> hai bo dem doc lap ----------
    // Lai NGUOC chieu nhau: P di len (carry 1,0), P2 di xuong (carry 0,1).
    phase_of("B_distinct_indices");
    // Nap truoc choice[P2] len ST bang chinh duong that. Neu de no o SNT thi ba
    // buoc "di xuong" o duoi se khong lam no doi (da o day duoi), va phep kiem
    // doc lap tro thanh vacuous.
    for (k = 0; k < 3; k++)
      choice_step(.R(R_10), .P(ADDR_P2), .taken(1'b0), .cidx(P2_IDX),
                  .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
    chk(a === `ST, $sformatf("B: nap choice[%0d] len ST that bai, dang o %s", P2_IDX, cn(a)));
    p_start  = bd.read_choice(P_IDX);
    p2_start = bd.read_choice(P2_IDX);
    `uvm_info(test_label, $sformatf("B: xuat phat choice[%0d]=%s choice[%0d]=%s",
              P_IDX, cn(p_start), P2_IDX, cn(p2_start)), UVM_NONE)
    for (k = 0; k < 3; k++) begin
      // P: tien LEN
      choice_step(.R(R_10), .P(ADDR_P), .taken(1'b0), .cidx(P_IDX),
                  .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
      chk(lc === 1'b1 && gc === 1'b0, $sformatf("B buoc %0d (P): carry=(%0d,%0d), can (1,0)", k, lc, gc));
      chk(a === upd_ctr(b, 1'b1), $sformatf(
        "B buoc %0d: choice[%0d] %s -> %s, ky vong %s", k, P_IDX, cn(b), cn(a), cn(upd_ctr(b, 1'b1))));
      chk(bd.read_choice(P2_IDX) === p2_start, $sformatf(
        "B buoc %0d: cap nhat tai pc=0x%08h da lam doi choice[%0d] (%s -> %s) -- hai bo dem KHONG doc lap",
        k, ADDR_P, P2_IDX, cn(p2_start), cn(bd.read_choice(P2_IDX))));
      // P2: tien XUONG
      choice_step(.R(R_01), .P(ADDR_P2), .taken(1'b0), .cidx(P2_IDX),
                  .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
      chk(lc === 1'b0 && gc === 1'b1, $sformatf("B buoc %0d (P2): carry=(%0d,%0d), can (0,1)", k, lc, gc));
      chk(a === upd_ctr(b, 1'b0), $sformatf(
        "B buoc %0d: choice[%0d] %s -> %s, ky vong %s", k, P2_IDX, cn(b), cn(a), cn(upd_ctr(b, 1'b0))));
      p2_start = a;
    end
    `uvm_info(test_label, $sformatf(
      "B: sau 3 cap buoc nguoc chieu -- choice[%0d]=%s (di LEN), choice[%0d]=%s (di XUONG)",
      P_IDX, cn(bd.read_choice(P_IDX)), P2_IDX, cn(bd.read_choice(P2_IDX))), UVM_NONE)
    chk(bd.read_choice(P_IDX) !== bd.read_choice(P2_IDX),
        "B: hai bo dem ket thuc bang nhau -- phep kiem doc lap khong con y nghia");

    //---- PHA C: hai PC TRUNG chi muc -> dung chung mot o, lan sau thang ----
    phase_of("C_aliased_indices");
    build_scene();
    // Nap choice[768] ve WT bang duong that de con cho ca hai chieu.
    choice_step(.R(R_10), .P(ADDR_P), .taken(1'b0), .cidx(P_IDX),
                .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
    choice_step(.R(R_10), .P(ADDR_P), .taken(1'b0), .cidx(P_IDX),
                .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
    chk(a === `WT, $sformatf("C: nap bo dem ve WT that bai, dang o %s", cn(a)));

    // ADDR_PA = ADDR_P + 4 KB : cung chi muc 768, khong co truong tag.
    choice_step(.R(R_01), .P(ADDR_PA), .taken(1'b0), .cidx(P_IDX),
                .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
    chk(lc === 1'b0 && gc === 1'b1, $sformatf("C: carry=(%0d,%0d), can (0,1)", lc, gc));
    chk(wren === 1'b1, $sformatf(
      "C: choice_wr_en=%0d khi pc=0x%08h, ky vong 1 -- btb_valid doc theo chi muc nen dia chi la van trung",
      wren, ADDR_PA));
    chk(a === upd_ctr(b, 1'b0), $sformatf(
      "C: pc=0x%08h ghi vao choice[%0d]: %s -> %s, ky vong %s",
      ADDR_PA, P_IDX, cn(b), cn(a), cn(upd_ctr(b, 1'b0))));
    `uvm_info(test_label, $sformatf({
      "\n=== 6.4 PC TRUNG CHI MUC DUNG CHUNG MOT O ===\n",
      "  pc=0x%08h va pc=0x%08h cach nhau 4 KB, deu cho pc[11:2] = %0d.\n",
      "  Bo dem duoc pc=0x%08h nap len %s, roi pc=0x%08h ghi de xuong %s.\n",
      "  Lan ghi sau THANG: bpu_reg.v chi lay chi muc, khong luu tag.\n",
      "======================================="},
      ADDR_P, ADDR_PA, P_IDX, ADDR_P, cn(b), ADDR_PA, cn(a)), UVM_NONE)

    bus_free();
    phase.drop_objection(this, "6_4");
  endtask
endclass : choice_pc_independence_test
