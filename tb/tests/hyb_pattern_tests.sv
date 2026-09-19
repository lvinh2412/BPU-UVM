//------------------------------------------------------------------------------
// FILE: tests/hyb_pattern_tests.sv
//
//   15.1 pattern_saturating_and_cold  [B] gop pattern_saturating + pattern_cold
//   15.2 pattern_alternating          [B] gop pattern_alternating + gshare_corr
//   15.3 pattern_loop_12b             [B] gop loop_short + loop_long
//   15.4 pattern_correlated           [B]
//   15.5 pattern_btb_aliasing         [B] + ca moi: dia chi KHONG phai lenh re
//   15.6 pattern_nested_loop          [B]
//
// Tat ca chay tren bpu_coherent_gen: dia chi di nxpc2(T) -> nxpc(T+1) -> pc(T+2),
// nen quyet dinh tang fetch thuoc ve DUNG nhanh dang duoc giai quyet. Ban cu lai
// bpu_drive_seq voi auto_nxpc2, tuc nxpc2 = pc + 8 trong cung chu ky -- tang
// fetch tra BTB o mot chi muc khong lien quan, nen moi nguong do duoc o ban do
// deu khong con nghia. Do la ly do MOI nguong trong tep nay deu duoc TINH LAI TU
// SO DO THUC, khong mot con so nao mang tu ban decode sang.
//
// Ke thua hyb_stress_base_test (tests/hyb_stress_tests.sv) -> include SAU tep do.
//------------------------------------------------------------------------------


class hyb_pattern_base_test extends hyb_stress_base_test;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  //--------------------------------------------------------------------------
  // Dem ket qua theo tung nhanh, doc tu nhat ky cua helper.
  //
  //   MISPREDICT dinh nghia GIONG reference model: bpu_flush == 2'd2
  //   (bpu_ctrl.v -- doan sai huong). flush == 2'd1 la BTB truot + re
  //   thuc, cung ton bong bong nhung khong phai doan sai; dem rieng.
  //--------------------------------------------------------------------------
  typedef struct {
    int n;          // so nhanh da xet
    int n_flush0;   // doan dung, khong bong bong
    int n_flush1;   // BTB truot + re thuc
    int n_flush2;   // doan sai
  } flush_tally_t;

  protected function flush_tally_t tally(int ids[$]);
    flush_tally_t t;
    bpu_pipe_obs_t o;
    t = '{default:0};
    foreach (ids[i]) begin
      o = gen.obs_of(ids[i]);
      t.n++;
      case (o.bpu_flush)
        2'd0: t.n_flush0++;
        2'd1: t.n_flush1++;
        2'd2: t.n_flush2++;
      endcase
    end
    return t;
  endfunction

  protected function void show_tally(string tag, flush_tally_t t);
    `uvm_info(test_label, $sformatf(
      "%-28s nhanh=%0d  flush0=%0d (%.1f%%)  flush1=%0d  flush2=%0d (%.1f%%)",
      tag, t.n, t.n_flush0, pct(t.n_flush0, t.n), t.n_flush1,
      t.n_flush2, pct(t.n_flush2, t.n)), UVM_NONE)
  endfunction

  protected function real pct(int a, int b);
    return (b > 0) ? 100.0 * real'(a) / real'(b) : 0.0;
  endfunction

  //--------------------------------------------------------------------------
  // KHOANG CACH GIUA CAC NHANH -- vi sao nhom 15 KHONG lai sat nhau
  //
  //   Bang PHT / BHT / GHR chi duoc ghi o TANG EXECUTE (bpu_predictor.v
  //   deu lay is_branch lam wr_en), tuc HAI CHU KY sau khi nhanh do duoc tra o
  //   tang fetch. Neu lai cac nhanh o chu ky KE NHAU thi luc nhanh k duoc tra,
  //   ket qua cua k-1 va k-2 CHUA kip ghi vao bang -- bo du doan luon nhin mot
  //   trang thai cu hai nhanh.
  //
  //   DO DUOC: mau chu ky 5 lai sat nhau cho 40.0% doan sai (2 lan moi vong);
  //   cung mau do voi GAP = 2 cho 0.0%. Cap tuong quan A/B cua 15.4 con ro hon:
  //   sat nhau thi luc B duoc tra, ket qua cua A chua vao GHR, nen dung cai
  //   tuong quan ma muc nay muon do lai KHONG THE nhin thay.
  //
  //   Nhom 15 do CHAT LUONG DU DOAN, nen phai tach bien do ra khoi hieu ung
  //   duong ong: dat GAP = 2 chu ky nghi giua cac nhanh, vua du de lenh ghi o
  //   T+2 hien ra truoc lan tra ke tiep.
  //
  //   Nguoc lai muc 16.1 CO Y lai sat nhau: do la muc stress, va suc ep
  //   back-to-back chinh la thu no phai kiem.
  //--------------------------------------------------------------------------
  localparam int GAP = 2;

  // Lai mot chuoi mau tai mot PC, tra ve danh sach id de doi chieu ve sau.
  protected task automatic run_pattern(bit [31:0] pc, bit pat[], ref int ids[$]);
    foreach (pat[i]) begin
      gen.push_branch(.pc(pc), .taken(pat[i]));
      ids.push_back(gen.last_id);
      gen.idle(GAP);
    end
  endtask

endclass : hyb_pattern_base_test


//==============================================================================
// 15.1 pattern_saturating_and_cold
//
// Sheet -- Flow: 100 nhanh luon-re roi 100 nhanh luon-khong-re tai mot PC; sau
//   do mot nhanh CHUA TUNG GAP de quan sat cold start.
// Sheet -- Pass: bo dem bao hoa hoi tu (so lan doan sai co bien tren); nhanh
//   cold gay BTB truot va bpu_flush = 2.
//
//==============================================================================
// BANG CHUNG DINH LUONG CHINH CUA LOI ICH HYBRID
//
//   Ban decode chi biet mot nhanh la nhanh khi no toi tang DECODE, nen ngay ca
//   khi doan DUNG van mat mot chu ky bong bong: bpu_flush = 1 o MOI nhanh cua
//   mau luon-re. Ban hybrid tra BTB ngay o tang FETCH, nen sau khi hoi tu thi
//   chuyen huong xay ra truoc khi bong bong hinh thanh: bpu_flush = 0.
//
//   Pha B do dung con so do: ti le bpu_flush == 0 tren doan on dinh cua mau
//   luon-re. In rieng de trich thang vao bao cao.
//==============================================================================
class pattern_saturating_and_cold_test extends hyb_pattern_base_test;
  `uvm_component_utils(pattern_saturating_and_cold_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  //---- NGUONG: TINH LAI TU SO DO THUC (khong dung lai so cua ban decode) ----
  //   SO DO: pha luon-re 12 doan sai / 100 nhanh; pha luon-khong-re 2/100.
  //          Tong 14. Dat bien 25 (~1.8 lan so do) -- du cho dao dong nho o
  //          giai doan hoc, van bat duoc truong hop bo dem khong hoi tu (se
  //          cho hang chuc den 100 lan doan sai).
  //          Ban decode dat check_max(14) -- KHONG dung lai, vi con so do do
  //          duoc voi kich thich nxpc2 khong nhat quan.
  localparam int  MISPREDICT_MAX   = 25;
  //   SO DO: 60/60 = 100.0% bpu_flush = 0 o doan on dinh.
  //          Dat dung 100.0: day la mot khang dinh CAU TRUC, khong phai mot
  //          nguong thong ke. Sau khi bo dem bao hoa va BTB da co entry, mau
  //          luon-re KHONG duoc phep con bong bong nao. Mot bong bong duy nhat
  //          la mot suy giam that va phai bao.
  localparam real STEADY_FLUSH0_MIN = 100.0;

  localparam int WARM   = 100;   // so nhanh dau, coi la giai doan hoc
  localparam int STEADY = 60;    // doan on dinh cuoi pha luon-re

  function void build_phase(uvm_phase phase);
    test_label = "TEST_15_1 (pattern_saturating_and_cold)";
    select_clock();
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    int ids_t[$], ids_nt[$], ids_steady[$];
    bit pat_t[], pat_nt[];
    flush_tally_t tt, tnt, tst;
    bpu_reference r;
    bpu_backdoor  bd;
    int m0, miss0, i;
    bit [9:0] icold;
    bpu_pipe_obs_t o;

    super.run_phase(phase);
    r  = tb.module_env.reference;
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "15_1");
    #100ns;
    make_gen(32'd2);

    //---- PHA A: 100 luon-re roi 100 luon-khong-re ---------------------------
    phase_of("A_saturating_convergence");
    pat_t  = new[WARM]; foreach (pat_t[i])  pat_t[i]  = 1'b1;
    pat_nt = new[WARM]; foreach (pat_nt[i]) pat_nt[i] = 1'b0;
    run_pattern(32'h0000_0100, pat_t,  ids_t);
    run_pattern(32'h0000_0100, pat_nt, ids_nt);
    gen.drain();

    tt  = tally(ids_t);
    tnt = tally(ids_nt);
    show_tally("pha luon-re",        tt);
    show_tally("pha luon-khong-re",  tnt);

    //---- PHA B: BANG CHUNG HYBRID -- doan on dinh cua mau luon-re -----------
    phase_of("B_hybrid_flush0_evidence");
    for (i = ids_t.size() - STEADY; i < ids_t.size(); i++) ids_steady.push_back(ids_t[i]);
    tst = tally(ids_steady);
    `uvm_info(test_label, $sformatf(
      {"\n=== 15.1 BANG CHUNG DINH LUONG LOI ICH HYBRID ===\n",
       "  Mau LUON-RE, %0d nhanh cuoi (da hoi tu):\n",
       "    bpu_flush = 0 : %0d/%0d = %.1f%%   <-- ban hybrid: chuyen huong tai tang FETCH\n",
       "    bpu_flush = 1 : %0d/%0d = %.1f%%\n",
       "    bpu_flush = 2 : %0d/%0d = %.1f%%\n",
       "  Ban DECODE cho mau nay se ra bpu_flush = 1 o MOI nhanh (100%%), vi no chi\n",
       "  biet do la nhanh khi da toi tang decode -- mat mot chu ky bong bong ngay\n",
       "  ca khi doan dung. Chenh lech giua hai con so nay la loi ich do duoc.\n",
       "================================================="},
      tst.n,
      tst.n_flush0, tst.n, pct(tst.n_flush0, tst.n),
      tst.n_flush1, tst.n, pct(tst.n_flush1, tst.n),
      tst.n_flush2, tst.n, pct(tst.n_flush2, tst.n)), UVM_NONE)

    chk(pct(tst.n_flush0, tst.n) >= STEADY_FLUSH0_MIN, $sformatf(
        "doan on dinh chi dat %.1f%% bpu_flush=0 (< %.1f%%) -- khong chung minh duoc loi ich hybrid",
        pct(tst.n_flush0, tst.n), STEADY_FLUSH0_MIN));

    chk((tt.n_flush2 + tnt.n_flush2) <= MISPREDICT_MAX, $sformatf(
        "tong doan sai %0d vuot bien %0d -- bo dem khong hoi tu",
        tt.n_flush2 + tnt.n_flush2, MISPREDICT_MAX));

    //---- PHA C: cold start -- mot PC chua tung gap -------------------------
    phase_of("C_cold_start");
    icold = (32'h0000_0500 >> 2) & 32'h3FF;      // = 320
    chk(bd.read_btb_valid(icold) === 1'b0,
        $sformatf("btb_valid[%0d] da duoc dat truoc khi lai nhanh cold", icold));

    m0    = r.mispredicts;
    miss0 = r.btb_misses_at_branch;
    gen.push_branch(.pc(32'h0000_0500), .taken(1'b0));   // chua gap + khong re
    gen.drain();
    o = gen.obs_of(gen.last_id);

    `uvm_info(test_label, $sformatf(
      "nhanh cold: bpu_flush=%0d  d_mispredict=%0d  d_btb_miss=%0d (ky vong 2, 1, 1)",
      o.bpu_flush, r.mispredicts - m0, r.btb_misses_at_branch - miss0), UVM_NONE)

    chk(o.bpu_flush === 2'd2,
        $sformatf("nhanh cold cho bpu_flush=%0d, ky vong 2 (BTB truot + mac dinh doan re)", o.bpu_flush));
    chk(r.mispredicts - m0 == 1,
        $sformatf("delta doan sai = %0d, ky vong 1", r.mispredicts - m0));
    chk(r.btb_misses_at_branch - miss0 == 1,
        $sformatf("delta BTB truot = %0d, ky vong 1", r.btb_misses_at_branch - miss0));

    phase.drop_objection(this, "15_1");
  endtask

  function void report_phase(uvm_phase phase);
    phase_of("FINAL");
    `uvm_info(test_label, {"tong ket: ", gen.stats()}, UVM_NONE)
    chk(gen.n_coherence_bad == 0, $sformatf(
        "%0d bo ba vi pham nhat quan duong ong", gen.n_coherence_bad));
    chk_no_x();
    super.report_phase(phase);
  endfunction
endclass : pattern_saturating_and_cold_test


//==============================================================================
// 15.2 pattern_alternating
//
// Gop pattern_alternating_test (200 nhanh xen ke) va gshare_corr_pattern_test
// (20 nhanh xen ke + kiem hai o global_pht phan ky). Cung MOT mau, chi khac do
// dai, nen gop lam mot muc voi hai pha.
//
// Sheet -- Pass: mau xen ke duoc hoc (so doan sai co bien tren); hai lich su
//   nguoc nhau hoi tu ve hai o global_pht doi lap.
//
//   CHI MUC HAI O: mau xen ke tai pc=0x100 (pc_index = 64) lam GHR di vao hai
//   trang thai on dinh 0b1010101010 = 682 va 0b0101010101 = 341. Chi muc gshare
//   la pc_index ^ ghr (bpu_reg.v):
//        64 ^ 682 = 746   (lich su ket thuc bang RE      -> hoi tu ST)
//        64 ^ 341 = 277   (lich su ket thuc bang KHONG RE -> hoi tu SNT)
//   Hai chi muc nay KHONG phu thuoc do dai chuoi mien la chuoi du dai de GHR
//   bao hoa (>= 10 nhanh) -- da kiem lai bang so do, khong mang tu ban cu sang.
//==============================================================================
class pattern_alternating_test_hyb extends hyb_pattern_base_test;
  `uvm_component_utils(pattern_alternating_test_hyb)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  //   SO DO: 0 doan sai / 176 nhanh sau 24 nhanh hoc (toan chuoi: 7/200).
  //          Dat bien 4 -- gan sat so do vi mau xen ke la mau de nhat trong
  //          nhom, bat cu doan sai nao sau khi hoc deu dang ngo.
  //          Ban decode dat check_max(12) -- khong dung lai.
  localparam int MISPREDICT_MAX = 4;
  localparam int LEN            = 200;
  localparam int WARM           = 24;    // bo qua giai doan hoc khi tinh bien

  function void build_phase(uvm_phase phase);
    test_label = "TEST_15_2 (pattern_alternating)";
    select_clock();
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    int ids[$], ids_steady[$];
    bit pat[];
    flush_tally_t tall, tst;
    bpu_backdoor bd;
    bit [1:0] e746, e277;
    int i;

    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "15_2");
    #100ns;
    make_gen(32'd2);

    //---- PHA A: 200 nhanh xen ke -------------------------------------------
    phase_of("A_alternating_learned");
    pat = new[LEN];
    foreach (pat[i]) pat[i] = (i % 2 == 0);
    run_pattern(32'h0000_0100, pat, ids);
    gen.drain();

    tall = tally(ids);
    for (i = WARM; i < ids.size(); i++) ids_steady.push_back(ids[i]);
    tst = tally(ids_steady);
    show_tally("toan chuoi",              tall);
    show_tally($sformatf("sau %0d nhanh hoc", WARM), tst);

    chk(tst.n_flush2 <= MISPREDICT_MAX, $sformatf(
        "doan sai o doan on dinh = %0d, vuot bien %0d -- mau xen ke khong duoc hoc",
        tst.n_flush2, MISPREDICT_MAX));

    //---- PHA B: hai lich su nguoc nhau -> hai o global_pht doi lap ---------
    phase_of("B_gshare_entries_diverge");
    e746 = bd.read_global_pht(746);   // 64 ^ 682, lich su ket thuc bang RE
    e277 = bd.read_global_pht(277);   // 64 ^ 341, lich su ket thuc bang KHONG RE
    `uvm_info(test_label, $sformatf(
      "global_pht[746]=2'b%02b (ky vong ST 11)   global_pht[277]=2'b%02b (ky vong SNT 00)",
      e746, e277), UVM_NONE)
    chk(e746 === 2'b11, $sformatf(
        "global_pht[746]=2'b%02b, ky vong ST -- lich su ket thuc bang RE phai hoi tu luon-re", e746));
    chk(e277 === 2'b00, $sformatf(
        "global_pht[277]=2'b%02b, ky vong SNT -- lich su ket thuc bang KHONG RE phai hoi tu luon-khong-re", e277));
    chk(e746[1] !== e277[1],
        "hai o gshare KHONG phan ky -- khong chung minh duoc gshare tach duoc hai lich su");

    phase.drop_objection(this, "15_2");
  endtask

  function void report_phase(uvm_phase phase);
    phase_of("FINAL");
    `uvm_info(test_label, {"tong ket: ", gen.stats()}, UVM_NONE)
    chk(gen.n_coherence_bad == 0, $sformatf(
        "%0d bo ba vi pham nhat quan duong ong", gen.n_coherence_bad));
    chk_no_x();
    super.report_phase(phase);
  endfunction
endclass : pattern_alternating_test_hyb


//==============================================================================
// 15.3 pattern_loop_12b
//
// Gop loop_short (chu ky 5) va loop_long (chu ky 21) thanh mot muc hai pha, vi
// ket luan chi co nghia khi DOI CHIEU hai con so voi nhau.
//
// Sheet -- Pass: vong lap NGAN HON lich su thi hoc duoc (doan sai gan 0 sau khi
//   on dinh); vong lap DAI HON lich su thi khong hoc duoc het (doan sai cao han).
//
//==============================================================================
// BAI HOC GIAI DOAN 1 -- SO VONG KHOI DONG
//
//   BHT rong 12 bit (bpu_reg.v), khong phai 6. Voi mau luon-re, lich su bao
//   hoa ve 0xFFF sau 12 nhanh, ma o local_pht[0xFFF] chi BAT DAU duoc ghi tu
//   nhanh thu 13. Vi vay can khoang 24 vong huan luyen moi dat du doan on dinh
//   -- dat WARM_LOOPS = 24 chu khong phai vai vong nhu ban 6 bit.
//
//   Chu ky 5  : 5 < 12  -> moi vi tri trong vong co mot lich su 12 bit RIENG
//               -> hoc duoc.
//   Chu ky 21 : 21 > 12 -> nhieu vi tri chia nhau cung mot lich su 12 bit (12
//               lan RE lien tiep khong phan biet duoc vi tri 12..20) -> nhanh
//               KHONG RE o cuoi vong khong the doan truoc.
//==============================================================================
class pattern_loop_12b_test extends hyb_pattern_base_test;
  `uvm_component_utils(pattern_loop_12b_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  localparam int WARM_LOOPS   = 24;    // BHT 12 bit
  localparam int CYC5_LOOPS   = 40;    // do tren 40 vong sau khoi dong
  localparam int CYC21_LOOPS  = 12;
  //   SO DO: chu ky 5  -> 0 doan sai / 200 nhanh  (0.0%)
  //          chu ky 21 -> 12 doan sai / 252 nhanh (4.8%), dung 1 lan moi vong
  //   Dat SHORT_MAX = 6  (so do 0, bien tuyet doi nho vi day la "phai hoc duoc")
  //   Dat LONG_MIN  = 8  (so do 12, duoi so do 4 -- phai chung minh la KHONG
  //          hoc duoc het; neu tut xuong duoi 8 thi ket luan cua muc sai)
  //   Ban decode dat 18 cho CA HAI -- khong dung lai; ranh gioi da dich vi
  //   lich su rong 12 bit chu khong phai 6.
  localparam int SHORT_MAX    = 6;
  localparam int LONG_MIN     = 8;

  function void build_phase(uvm_phase phase);
    test_label = "TEST_15_3 (pattern_loop_12b)";
    select_clock();
    super.build_phase(phase);
  endfunction

  // Lai n vong cua mot chu ky do dai `period` (period-1 lan RE roi 1 lan KHONG
  // RE), tra ve id cua cac nhanh SAU giai doan khoi dong.
  task automatic run_loop(bit [31:0] pc, int period, int warm_loops, int meas_loops,
                          ref int ids[$]);
    int l, i;
    for (l = 0; l < warm_loops + meas_loops; l++)
      for (i = 0; i < period; i++) begin
        gen.push_branch(.pc(pc), .taken((i != period - 1)));
        if (l >= warm_loops) ids.push_back(gen.last_id);
        gen.idle(GAP);
      end
  endtask

  task run_phase(uvm_phase phase);
    int ids5[$], ids21[$];
    flush_tally_t t5, t21;
    real r5, r21;

    super.run_phase(phase);
    phase.raise_objection(this, "15_3");
    #100ns;
    make_gen(32'd2);

    //---- PHA A: chu ky 5 -- VUA trong lich su 12 bit ------------------------
    phase_of("A_cycle5_fits_12b");
    run_loop(32'h0000_0100, 5, WARM_LOOPS, CYC5_LOOPS, ids5);
    gen.drain();
    t5 = tally(ids5);
    show_tally("chu ky 5 (sau khoi dong)", t5);

    //---- PHA B: chu ky 21 -- VUOT lich su 12 bit ----------------------------
    // PC khac de hai mau khong dung chung o BHT/PHT.
    phase_of("B_cycle21_exceeds_12b");
    run_loop(32'h0000_0300, 21, WARM_LOOPS, CYC21_LOOPS, ids21);
    gen.drain();
    t21 = tally(ids21);
    show_tally("chu ky 21 (sau khoi dong)", t21);

    //---- PHA C: doi chieu -- day moi la ket luan cua muc --------------------
    phase_of("C_compare");
    r5  = pct(t5.n_flush2,  t5.n);
    r21 = pct(t21.n_flush2, t21.n);
    `uvm_info(test_label, $sformatf(
      {"\n=== 15.3 RANH GIOI LICH SU 12 BIT ===\n",
       "  chu ky 5  (5 < 12) : doan sai %0d/%0d = %.1f%%\n",
       "  chu ky 21 (21 > 12): doan sai %0d/%0d = %.1f%%\n",
       "  Ket luan: vong lap ngan hon lich su thi hoc duoc, dai hon thi khong.\n",
       "======================================"},
      t5.n_flush2, t5.n, r5, t21.n_flush2, t21.n, r21), UVM_NONE)

    chk(t5.n_flush2 <= SHORT_MAX, $sformatf(
        "chu ky 5: doan sai %0d vuot bien %0d -- le ra phai hoc duoc", t5.n_flush2, SHORT_MAX));
    chk(t21.n_flush2 >= LONG_MIN, $sformatf(
        "chu ky 21: doan sai %0d duoi %0d -- le ra phai KHONG hoc duoc het",
        t21.n_flush2, LONG_MIN));
    chk(r21 > r5, $sformatf(
        "ti le doan sai chu ky 21 (%.1f%%) khong cao hon chu ky 5 (%.1f%%) -- ranh gioi 12 bit khong hien ra",
        r21, r5));

    phase.drop_objection(this, "15_3");
  endtask

  function void report_phase(uvm_phase phase);
    phase_of("FINAL");
    `uvm_info(test_label, {"tong ket: ", gen.stats()}, UVM_NONE)
    chk(gen.n_coherence_bad == 0, $sformatf(
        "%0d bo ba vi pham nhat quan duong ong", gen.n_coherence_bad));
    chk_no_x();
    super.report_phase(phase);
  endfunction
endclass : pattern_loop_12b_test


//==============================================================================
// 15.4 pattern_correlated
//
// Sheet -- Flow: A tai 0x100 ngau nhien, B tai 0x200 bang A (tuong quan hoan
//   toan). Local o B that bai vi lich su rieng cua B la ngau nhien; gshare bat
//   duoc tuong quan qua GHR -> bo chon chuyen ve global.
// Sheet -- Pass: global chinh xac hon local; choice tai B hoi tu ve global
//   (MSB = 1); ti le doan sai tai B duoi 5%.
//
//   Nguon bit: bpu_det_rng seed 2 -- tat dinh, giong nhau tren xrun va Questa.
//   Xem ghi chu day du o tests/bpu_det_rng.sv. Phep kiem choice MSB NHAY VOI
//   SEED; doi seed thi phai do lai.
//==============================================================================
class pattern_correlated_test_hyb extends hyb_pattern_base_test;
  `uvm_component_utils(pattern_correlated_test_hyb)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  //---- SO CAP VA NGUONG: TINH LAI TU SO DO THUC ----
  //   Ti le doan sai tai B phu thuoc so cap da huan luyen, vi gshare phai lam
  //   day cac o global_pht theo tung gia tri GHR:
  //     200 cap  (WARM 24)  -> 23.9%
  //     400 cap  (WARM 200) ->  3.0%
  //     800 cap  (WARM 400) ->  1.0%   <-- chon
  //    1600 cap  (WARM 800) ->  0.8%   (da bao hoa, khong dang doi them thoi gian)
  //   Chon 800 cap: dat 1.0%, con nguong sheet la 5% -- bien 5 lan.
  //
  //   GHI CHU: ghi chu cu trong pattern_tests.sv ket luan "<5% khong dat duoc"
  //   va da bo phep kiem nay. Ket luan do dung VOI KICH THICH CU: khi cac nhanh
  //   lai sat nhau, luc B duoc tra thi ket qua cua A chua vao GHR, nen dung cai
  //   tuong quan can do lai khong nhin thay duoc. Voi kich thich nhat quan
  //   duong ong va khoang cach GAP = 2, nguong 5% cua sheet dat duoc de dang.
  localparam int  PAIRS       = 800;
  localparam int  WARM        = 400;
  localparam real B_RATE_MAX  = 5.0;

  function void build_phase(uvm_phase phase);
    test_label = "TEST_15_4 (pattern_correlated)";
    select_clock();
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    int ids_a[$], ids_b[$], ids_b_steady[$];
    flush_tally_t ta, tb_tally, tbs;
    bpu_reference r;
    bpu_backdoor  bd;
    bit [1:0] ch_b;
    bit a;
    int k;

    super.run_phase(phase);
    r  = tb.module_env.reference;
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "15_4");
    #100ns;
    make_gen(32'd2);

    phase_of("A_correlated_pairs");
    for (k = 0; k < PAIRS; k++) begin
      a = gen.rnd_bit();
      gen.push_branch(.pc(32'h0000_0100), .taken(a)); ids_a.push_back(gen.last_id);
      gen.idle(GAP);
      gen.push_branch(.pc(32'h0000_0200), .taken(a)); ids_b.push_back(gen.last_id);
      gen.idle(GAP);
    end
    gen.drain();

    ta = tally(ids_a);
    tb_tally = tally(ids_b);
    for (k = WARM; k < ids_b.size(); k++) ids_b_steady.push_back(ids_b[k]);
    tbs = tally(ids_b_steady);
    show_tally("A (0x100, ngau nhien)", ta);
    show_tally("B (0x200, = A)",        tb_tally);
    show_tally($sformatf("B sau %0d nhanh hoc", WARM), tbs);

    phase_of("B_global_beats_local");
    ch_b = bd.read_choice(10'd128);   // chi muc cua pc=0x200
    `uvm_info(test_label, $sformatf(
      "global_correct=%0d  local_correct=%0d  choice[128]=2'b%02b (MSB=%0b)",
      r.global_correct_count, r.local_correct_count, ch_b, ch_b[1]), UVM_NONE)

    // Phep kiem CHINH: dung o moi seed da thu.
    chk(r.global_correct_count > r.local_correct_count, $sformatf(
        "global_correct(%0d) khong lon hon local_correct(%0d) -- gshare khong thang",
        r.global_correct_count, r.local_correct_count));
    // Phep kiem NHAY SEED: xem ghi chu o dau lop.
    chk(ch_b[1] === 1'b1, $sformatf(
        "choice[128]=2'b%02b -- MSB chua bat, bo chon chua hoi tu ve global", ch_b));

    phase_of("C_B_mispredict_rate");
    `uvm_info(test_label, $sformatf(
      "ti le doan sai tai B (sau khoi dong) = %.1f%% (sheet: < 5%%)",
      pct(tbs.n_flush2, tbs.n)), UVM_NONE)
    chk(pct(tbs.n_flush2, tbs.n) < B_RATE_MAX, $sformatf(
        "ti le doan sai tai B = %.1f%%, vuot %.1f%%",
        pct(tbs.n_flush2, tbs.n), B_RATE_MAX));

    phase.drop_objection(this, "15_4");
  endtask

  function void report_phase(uvm_phase phase);
    phase_of("FINAL");
    `uvm_info(test_label, {"tong ket: ", gen.stats()}, UVM_NONE)
    chk(gen.n_coherence_bad == 0, $sformatf(
        "%0d bo ba vi pham nhat quan duong ong", gen.n_coherence_bad));
    chk_no_x();
    super.report_phase(phase);
  endfunction
endclass : pattern_correlated_test_hyb


//==============================================================================
// 15.5 pattern_btb_aliasing
//
// Sheet -- Flow: hai nhanh o hai PC KHAC NHAU nhung TRUNG chi muc BTB, chay xen
//   ke voi hai chu ky khac nhau -> suy giam co kiem soat.
//   THEM: mot dia chi KHONG PHAI LENH RE trung chi muc voi mot
//   nhanh da nam trong BTB.
//
//==============================================================================
// CA MOI -- DesignNotes R1 TRONG DIEU KIEN WORKLOAD THAT
//
//   Tang fetch tra BTB THUAN THEO CHI MUC nxpc2[11:2] (bpu_reg.v) -- khong
//   co tag, va cung khong biet lenh tai dia chi do co phai lenh re hay khong
//   (fetch_opcode chi den o tang DECODE). Vi vay mot dia chi tro toi mot o BTB
//   hop le cua NHANH KHAC se lam f_valid len va BPU chuyen huong NHAM.
//
//   Muc 8.2 va 9.1 da quan sat hien tuong nay trong dieu kien
//   directed. O day quan sat trong dieu kien workload that: nhanh o 0x100 duoc
//   huan luyen vao BTB[64], roi lai dia chi 0x1100 (cung chi muc 64) voi
//   fetch_opcode = ADDI va is_branch = 0 -- tuc mot lenh HOAN TOAN KHONG PHAI
//   nhanh. Neu tang fetch van chuyen huong thi day la R1, quan sat duoc bang so.
//==============================================================================
class pattern_btb_aliasing_test_hyb extends hyb_pattern_base_test;
  `uvm_component_utils(pattern_btb_aliasing_test_hyb)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  localparam int  ITER          = 100;
  //   SO DO: tron hai chu ky tren cung o BTB -> 81 doan sai / 200 = 40.5%.
  //          Dat bien duoi 25.0% (duoi so do 15 diem). Day la nguong "phai
  //          suy giam": neu tut xuong duoi thi nghia la hai mau khong con
  //          tranh nhau mot o nua va muc mat y nghia.
  //          Ban decode dat "> 20%" -- khong dung lai.
  localparam real ALIAS_MIN     = 25.0;
  localparam int  NONBR_PROBES  = 20;

  // 0x0100 -> idx 64 ; 0x1100 -> (0x1100>>2)&0x3FF = 0x440 & 0x3FF = 64  (trung)
  localparam bit [31:0] PC_A     = 32'h0000_0100;
  localparam bit [31:0] PC_B     = 32'h0000_1100;
  localparam bit [6:0]  OPC_ADDI = 7'b0010011;   // KHONG phai lenh re

  function void build_phase(uvm_phase phase);
    test_label = "TEST_15_5 (pattern_btb_aliasing)";
    select_clock();
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    int ids_a[$], ids_b[$], ids_all[$];
    flush_tally_t tall;
    bpu_backdoor bd;
    bpu_pipe_obs_t o;
    int k, n_spurious, n_fetch_before, n_pre_ok;

    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "15_5");
    #100ns;
    make_gen(32'd2);

    chk(((PC_A >> 2) & 32'h3FF) == ((PC_B >> 2) & 32'h3FF), $sformatf(
        "tien de sai: 0x%08h va 0x%08h KHONG trung chi muc (%0d vs %0d)",
        PC_A, PC_B, (PC_A >> 2) & 32'h3FF, (PC_B >> 2) & 32'h3FF));

    //---- PHA A: hai chu ky khac nhau tren cung mot o BTB --------------------
    phase_of("A_two_periods_same_index");
    for (k = 0; k < ITER; k++) begin
      gen.push_branch(.pc(PC_A), .taken((k % 7) != 6));
      ids_a.push_back(gen.last_id); ids_all.push_back(gen.last_id);
      gen.idle(GAP);
      gen.push_branch(.pc(PC_B), .taken((k % 5) != 4));
      ids_b.push_back(gen.last_id); ids_all.push_back(gen.last_id);
      gen.idle(GAP);
    end
    gen.drain();
    tall = tally(ids_all);
    show_tally("tron hai chu ky (trung chi muc)", tall);
    chk(tall.n == 2 * ITER, $sformatf(
        "chi %0d/%0d nhanh duoc xu ly -- co the treo", tall.n, 2 * ITER));
    chk(pct(tall.n_flush2, tall.n) > ALIAS_MIN, $sformatf(
        "ti le doan sai %.1f%% khong cao hon %.1f%% -- suy giam do trung chi muc khong hien ra",
        pct(tall.n_flush2, tall.n), ALIAS_MIN));

    //---- PHA B (CA MOI): dia chi KHONG phai lenh re, trung chi muc ----------
    //
    // Truoc het dua o BTB[64] ve trang thai DOAN RE MANH bang mot loat nhanh
    // luon-re tai PC_A. Pha A tron hai chu ky nen bo dem o day dang lung chung;
    // neu khong huan luyen lai thi predict_taken_nxpc2 = 0 va hien tuong can
    // quan sat khong the xuat hien -- khi do test se bao "canh chua dung dung"
    // chu khong phai "khong co R1".
    // 24 nhanh chu khong phai 12: BHT rong 12 bit, lich su chi bao hoa ve
    // 0xFFF sau 12 nhanh va local_pht[0xFFF] moi BAT DAU duoc ghi tu nhanh thu
    // 13 chu khong phai 12: voi 12 nhanh thi o duoc tra luc thu
    // van con o trang thai khoi tao va hien tuong khong the xuat hien.
    phase_of("B_non_branch_aliases_btb_entry");
    for (k = 0; k < 24; k++) begin
      gen.push_branch(.pc(PC_A), .taken(1'b1));
      gen.idle(GAP);
    end
    gen.drain();
    chk(bd.read_btb_valid(64) === 1'b1,
        "tien de sai: BTB[64] chua hop le -- pha A phai huan luyen no truoc");

    n_spurious = 0;
    n_pre_ok   = 0;
    for (k = 0; k < NONBR_PROBES; k++) begin
      // is_branch = 0 VA fetch_opcode = ADDI: khong phai lenh re o CA hai tang,
      // nen d_valid = 0 (bpu_ctrl.v can fetch_is_branch) va corr_valid = 0
      // (bpu_ctrl.v can is_branch). Neu MUX van phat chuyen huong thi nguon
      // duy nhat con lai la tang FETCH, tra o BTB[64] cua nhanh 0x100 -- dung
      // hien tuong R1.
      //
      // PHAI do o CHU KY dia chi nay nam o tang FETCH, khong phai luc no toi
      // EXECUTE: obs_of(id) tra ve anh chup tai T+2, luc do nxpc2 da la dia chi
      // nghi. Vi vay dem qua bo dem n_fetch_wins cua bo sinh, tang len dung o
      // chu ky tang fetch thang MUX.
      n_fetch_before = gen.n_fetch_wins;
      gen.push_branch(.pc(PC_B), .taken(1'b0), .opcode(OPC_ADDI), .is_branch(1'b0));
      // Tien de (ky thuat assert_cell): o BTB phai hop le VA bo du doan phai
      // dang doan RE tai chi muc do. Neu khong thi khong the ket luan gi ve R1,
      // va thong bao loi phai noi ro la CANH chua dat chu khong phai khong co
      // hien tuong.
      if (bd.read_btb_valid_nxpc2() && bd.read_predict_taken_nxpc2()) n_pre_ok++;
      if (gen.n_fetch_wins > n_fetch_before) n_spurious++;
      gen.drain();
    end

    chk(n_pre_ok > 0, $sformatf(
        {"tien de chua dat o ca %0d lan thu: btb_valid_nxpc2 && predict_taken_nxpc2 ",
         "khong bao gio cung bang 1, nen chua the ket luan gi ve R1"}, NONBR_PROBES));

    `uvm_info(test_label, $sformatf(
      {"\n=== 15.5 CA MOI -- DesignNotes R1 trong workload that ===\n",
       "  Dia chi 0x%08h KHONG phai lenh re (fetch_opcode=ADDI, is_branch=0)\n",
       "  nhung trung chi muc BTB (%0d) voi nhanh 0x%08h da duoc huan luyen.\n",
       "  Tien de dat (BTB hop le VA dang doan RE): %0d/%0d\n",
       "  So lan tang FETCH van thang MUX (chuyen huong nham): %0d/%0d\n",
       "  BTB tra thuan theo chi muc, khong tag va khong biet lenh do co phai\n",
       "  nhanh hay khong (fetch_opcode chi den o tang DECODE), nen chuyen huong\n",
       "  nham la HE QUA CAU TRUC -- ghi nhan, khong phai loi RTL.\n",
       "========================================================"},
      PC_B, (PC_B >> 2) & 32'h3FF, PC_A, n_pre_ok, NONBR_PROBES, n_spurious, NONBR_PROBES), UVM_NONE)

    // Ghi nhan hien tuong: phai quan sat duoc it nhat mot lan, neu khong thi
    // canh dung chua dat va ca moi nay khong chung minh duoc gi.
    chk(n_spurious > 0, $sformatf(
        "khong lan nao trong %0d lan quan sat duoc chuyen huong nham -- canh chua dung dung",
        NONBR_PROBES));

    phase.drop_objection(this, "15_5");
  endtask

  function void report_phase(uvm_phase phase);
    phase_of("FINAL");
    `uvm_info(test_label, {"tong ket: ", gen.stats()}, UVM_NONE)
    chk(gen.n_coherence_bad == 0, $sformatf(
        "%0d bo ba vi pham nhat quan duong ong", gen.n_coherence_bad));
    chk_no_x();
    super.report_phase(phase);
  endfunction
endclass : pattern_btb_aliasing_test_hyb


//==============================================================================
// 15.6 pattern_nested_loop
//
// Sheet -- Flow: vong ngoai N=30, vong trong N=4 (TTTN), kem mot nhanh dieu
//   kien -- mo phong mot doan chuong trinh that.
// Sheet -- Pass: ti le doan sai tong duoi mot bien.
//==============================================================================
class pattern_nested_loop_test_hyb extends hyb_pattern_base_test;
  `uvm_component_utils(pattern_nested_loop_test_hyb)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  localparam int  OUTER    = 30;
  localparam int  INNER    = 4;
  //   SO DO: 20 doan sai / 270 nhanh = 7.4%.
  //          Giu nguong 15.0% cua sheet -- so do cho bien hon 2 lan, va day la
  //          mot muc "giong chuong trinh that" nen khong nen bo qua sat.
  localparam real RATE_MAX = 15.0;

  function void build_phase(uvm_phase phase);
    test_label = "TEST_15_6 (pattern_nested_loop)";
    select_clock();
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    int ids[$];
    flush_tally_t t;
    int o, i;

    super.run_phase(phase);
    phase.raise_objection(this, "15_6");
    #100ns;
    make_gen(32'd2);

    phase_of("A_nested_loop");
    for (o = 0; o < OUTER; o++) begin
      for (i = 0; i < INNER; i++) begin
        gen.push_branch(.pc(32'h0000_0100), .taken(i < 3));   // vong trong TTTN
        ids.push_back(gen.last_id); gen.idle(GAP);
        gen.push_branch(.pc(32'h0000_0300), .taken(i < 2));   // nhanh dieu kien
        ids.push_back(gen.last_id); gen.idle(GAP);
      end
      gen.push_branch(.pc(32'h0000_0200), .taken(o < OUTER - 1));  // vong ngoai
      ids.push_back(gen.last_id); gen.idle(GAP);
    end
    gen.drain();

    t = tally(ids);
    show_tally("vong lap long nhau", t);
    chk(pct(t.n_flush2, t.n) < RATE_MAX, $sformatf(
        "ti le doan sai %.1f%% vuot %.1f%%", pct(t.n_flush2, t.n), RATE_MAX));

    phase.drop_objection(this, "15_6");
  endtask

  function void report_phase(uvm_phase phase);
    phase_of("FINAL");
    `uvm_info(test_label, {"tong ket: ", gen.stats()}, UVM_NONE)
    chk(gen.n_coherence_bad == 0, $sformatf(
        "%0d bo ba vi pham nhat quan duong ong", gen.n_coherence_bad));
    chk_no_x();
    super.report_phase(phase);
  endfunction
endclass : pattern_nested_loop_test_hyb
