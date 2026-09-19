//------------------------------------------------------------------------------
// FILE: tests/hyb_stress_tests.sv
//
//   16.1 random_pipeline_coherent  [C] VIET LAI (gop random_branch +
//                                      random_ctrl + stress_random)
//   16.2 stress_long_run           [B] SUA (doi diem do BTB sang phia du doan)
//
// Ca hai deu chay tren bpu_coherent_gen (tests/bpu_coherent_gen.sv), bo sinh
// nhat quan duong ong mo rong tu helper 1.1.
//
// Ke thua bpu_base_test truc tiep -- khong phu thuoc tep test nao khac.
//------------------------------------------------------------------------------


class hyb_stress_base_test extends bpu_base_test;

  string           test_label = "HYB_STRESS";
  int              err        = 0;
  bpu_coherent_gen gen;
  string           m_phase    = "";

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  protected function void select_clock();
    uvm_config_wrapper::set(this,
        "tb.clock_and_reset.agent.sequencer.run_phase",
        "default_sequence", clk10_rst5_seq::get_type());
  endfunction

  // Nhan pha -- moi uvm_error deu mang tien to ten pha (ky thuat da chung minh
  // doc log la biet ngay hong o doan nao).
  protected function void phase_of(string p);
    m_phase = p;
    `uvm_info(test_label, $sformatf(">>> PHA: %s", p), UVM_LOW)
  endfunction

  protected function void chk(bit ok, string msg);
    if (!ok) begin
      err++;
      `uvm_error(test_label, $sformatf("[%s] %s", m_phase, msg))
    end
  endfunction

  // Tao va noi bo sinh. Goi o dau run_phase.
  protected function void make_gen(bit [31:0] seed = 32'd2);
    gen = bpu_coherent_gen::type_id::create("gen");
    gen.connect(tb.bpu.tx_agent.sequencer, tb.module_env.backdoor);
    gen.set_seed(seed);
    gen.clear_stats();
  endfunction

  //--------------------------------------------------------------------------
  // Phep kiem manh nhat cua nhom nay: DUT khop reference suot ca lan chay.
  // Giu scoreboard SONG -- khong mot muc nao trong tep nay ep trang thai noi bo
  // bang backdoor, nen reference model theo kip va scoreboard la checker hop le.
  //--------------------------------------------------------------------------
  protected function void chk_no_miscompare(int min_compares);
    bpu_scoreboard sb = tb.module_env.scoreboard;
    `uvm_info(test_label, $sformatf("scoreboard: compares=%0d match=%0d miscompare=%0d",
              sb.total_compares, sb.match_count, sb.miscompare_count), UVM_NONE)
    chk(sb.miscompare_count == 0,
        $sformatf("%0d miscompare -- DUT lech khoi reference duoi kich thich ngau nhien",
                  sb.miscompare_count));
    chk(sb.total_compares >= min_compares,
        $sformatf("chi %0d lan so sanh (< %0d) -- co the treo", sb.total_compares, min_compares));
  endfunction

  protected function void chk_no_x();
    chk(gen.n_x_seen == 0,
        $sformatf("%0d chu ky co gia tri X tren ngo ra BPU", gen.n_x_seen));
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (err == 0) `uvm_info(test_label, "PASSED", UVM_NONE)
    else          `uvm_error(test_label, $sformatf("FAILED: %0d loi", err));
  endfunction

endclass : hyb_stress_base_test


//==============================================================================
// 16.1 random_pipeline_coherent
//
// Sheet -- Flow: kich thich ngau nhien quy mo lon NHUNG NHAT QUAN DUONG ONG:
//   cung mot dia chi phai di nxpc2 tai T, nxpc tai T+1, pc tai T+2. Kem halt
//   ngau nhien ~30%, flush_in ngau nhien gom ca gia tri 3, chen reset giua
//   chung, va cac nhanh sat nhau (back-to-back).
// Sheet -- Pass: khong treo, khong co gia tri X, ket qua tat dinh, scoreboard 0
//   miscompare, va moi nhanh tai execute duoc so voi dung quyet dinh fetch cua
//   chinh no.
// Sheet -- DIEU KIEN TU KIEM: "neu kich thich khong lai nxpc2 thi tang fetch
//   khong bao gio hoat dong va test nay phai phat hien ra".
//
//==============================================================================
// VI SAO BA TEST CU KHONG DU
//
//   random_branch_test / random_ctrl_test / stress_random_test deu lai
//   bpu_drive_seq voi auto_nxpc = 1, tuc nxpc2 = pc + 8 TRONG CUNG MOT CHU
//   KY. Dia chi o nxpc2 vi vay KHONG BAO GIO la dia chi se toi pc hai chu ky
//   sau, tru khi chuong trinh chay tuan tu deu dan -- ma kich thich ngau nhien
//   thi khong. Ket qua: tang fetch tra BTB o mot chi muc chang lien quan gi den
//   nhanh sap duoc giai quyet, nen phep so "quyet dinh fetch cua chinh nhanh
//   do" khong co y nghia. Ba test cu chi con dong gop phan no_miscompare/no_x.
//
//   Muc nay khac o cho bo sinh giu mot cua so ba khe, nen dia chi A that su
//   xuat hien o ca ba tang dung thu tu -- va phep tu kiem duoi day chung minh
//   dieu do da xay ra thay vi tin loi.
//==============================================================================
class random_pipeline_coherent_test extends hyb_stress_base_test;
  `uvm_component_utils(random_pipeline_coherent_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    test_label = "TEST_16_1 (random_pipeline_coherent)";
    select_clock();                       // khong dat default_sequence: gen tu lai
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    int n_fetch_a, n_fetch_b, n_fetch_c;
    super.run_phase(phase);
    phase.raise_objection(this, "16_1");
    #100ns;
    make_gen(32'd2);                      // seed co dinh -> tai lap duoc

    //---- PHA A: 1000 nhanh ngau nhien, sat nhau -----------------------------
    phase_of("A_1000_random_branches");
    gen.run_random_branches(.n(1000), .b2b(1'b1));
    n_fetch_a = gen.n_fetch_wins;
    `uvm_info(test_label, {"sau pha A: ", gen.stats()}, UVM_LOW)

    //---- PHA B: 2000 chu ky halt ~30% + flush_in ngau nhien gom ca 3 --------
    phase_of("B_2000_random_ctrl_cycles");
    gen.run_random_ctrl(.n_cyc(2000));
    n_fetch_b = gen.n_fetch_wins;
    `uvm_info(test_label, {"sau pha B: ", gen.stats()}, UVM_LOW)
    chk(gen.n_flush3_cycles > 0,
        "khong chu ky nao lai flush_in=3 -- gia tri 3 phai duoc phu (khong bo sinh cu nao lai toi)");
    chk(gen.n_halt_cycles > 0, "khong chu ky nao lai halt=1");

    //---- PHA C: chen reset giua chung roi chay tiep -------------------------
    // reference model xoa shadow state khi thay negedge rst_n
    // (bpu_reference.sv reset_handler), nen scoreboard van la checker hop le.
    phase_of("C_reset_injection_and_recovery");
    gen.inject_reset(.n_cyc_held(3));
    gen.run_random_branches(.n(200), .b2b(1'b0));
    n_fetch_c = gen.n_fetch_wins;
    `uvm_info(test_label, {"sau pha C: ", gen.stats()}, UVM_LOW)
    chk(n_fetch_c > n_fetch_b,
        "sau reset khong con chu ky nao tang fetch thang -- BPU khong hoi phuc");

    phase.drop_objection(this, "16_1");
  endtask

  function void report_phase(uvm_phase phase);
    real f_share;
    //------------------------------------------------------------------------
    // TU KIEM (Pass Condition cua sheet) -- HAI TANG.
    //
    // (1) BAT BIEN NHAT QUAN DUONG ONG, doc lai tu NET INTERFACE:
    //         nxpc2(T) == nxpc(T+1) == pc(T+2)
    //     Day moi la phep kiem THAT cho cau "moi nhanh tai execute duoc so voi
    //     dung quyet dinh fetch cua chinh no": neu ba dia chi khong trung thi
    //     quyet dinh fetch thuoc ve mot dia chi KHAC, va phep so la vo nghia.
    //
    // (2) TANG FETCH CO HOAT DONG: dem so chu ky f_valid && !d_valid &&
    //     !corr_valid. bpu_nxpc2_valid = corr||d||f (bpu_ctrl.v) nen nhin
    //     ngo ra thi khong phan biet duoc tang nao thang; mot bo sinh hong van
    //     cho bpu_nxpc2_valid = 1 deu deu nho tang decode.
    //
    //   DA THU NGHIEM DOI CHUNG: ep ovr_nxpc2 ve mot dia chi co dinh (mo phong
    //   dung kieu hong cua ba test cu) thi (2) VAN > 0 -- vi dia chi co dinh do
    //   sau mot luc cung thanh mot o BTB hop le. Rieng (2) la KHONG DU. Voi
    //   cung phep sabotage do thi (1) bat duoc ngay tu bo ba dau tien. Vi vay
    //   phep kiem chinh la (1), con (2) chi la phep kiem song.
    //------------------------------------------------------------------------
    phase_of("SELFCHECK_pipeline_coherence");
    `uvm_info(test_label, {"tong ket: ", gen.stats()}, UVM_NONE)

    chk(gen.n_coherence_checked > 0,
        "khong bo ba (nxpc2,nxpc,pc) nao duoc doi chieu -- bo sinh khong day nhanh nao qua duong ong");
    chk(gen.n_coherence_bad == 0, $sformatf(
        {"%0d/%0d bo ba VI PHAM nhat quan duong ong. Dia chi o nxpc2 tai T khong ",
         "phai dia chi toi pc tai T+2, nen quyet dinh fetch duoc so voi mot nhanh KHAC."},
        gen.n_coherence_bad, gen.n_coherence_checked));

    phase_of("SELFCHECK_fetch_tier_exercised");
    chk(gen.n_fetch_wins > 0,
        {"tang FETCH chua bao gio thang MUX (f_valid && !d_valid && !corr_valid == 0) ",
         "-- kich thich khong kich hoat duoc duong du doan tai tang fetch."});
    chk(gen.n_btb_valid_nxpc2 > 0,
        "btb_valid_nxpc2 chua bao gio bang 1 -- duong doc BTB phia du doan khong duoc kich hoat");

    f_share = (gen.n_cycles_sampled > 0) ?
              100.0 * real'(gen.n_fetch_wins) / real'(gen.n_cycles_sampled) : 0.0;
    `uvm_info(test_label, $sformatf(
      "phan bo MUX: fetch=%.1f%% decode=%.1f%% corr=%.1f%% none=%.1f%% (tren %0d chu ky)",
      f_share,
      100.0 * real'(gen.n_decode_wins) / real'(gen.n_cycles_sampled),
      100.0 * real'(gen.n_corr_wins)   / real'(gen.n_cycles_sampled),
      100.0 * real'(gen.n_no_redirect) / real'(gen.n_cycles_sampled),
      gen.n_cycles_sampled), UVM_NONE)

    phase_of("FINAL_robustness");
    chk_no_x();
    chk_no_miscompare(2500);
    super.report_phase(phase);
  endfunction
endclass : random_pipeline_coherent_test


//==============================================================================
// 16.2 stress_long_run
//
// Sheet -- Flow: chuoi 10.000 nhanh tron mau (luon-re / xen ke / tuong quan /
//   cold-start), chay tren bo sinh nhat quan duong ong cua 16.1.
// Sheet Performance chi so E -- DIEM DO: ti le BTB trung phai do o
//   btb_valid_nxpc2 (PHIA DU DOAN) chu khong phai btb_valid_pc (phia cap nhat).
//
//==============================================================================
// VI SAO DOI DIEM DO
//
//   reference model dem btb_hits_at_branch bang exp.btb_valid_pc
//   (bpu_reference.sv), tuc tra BTB theo pc o TANG EXECUTE -- do la du lieu cho
//   duong CAP NHAT, tra loi cau hoi "luc giai quyet nhanh nay, BTB da co entry
//   chua". No khong noi gi ve viec BPU co DU DOAN duoc hay khong.
//
//   Cai quyet dinh hieu nang la btb_valid_nxpc2: tra BTB theo dia chi dang o
//   TANG FETCH (bpu_reg.v). Chi khi day bang 1 thi f_valid moi co the len
//   (bpu_ctrl.v) va BPU moi tiet kiem duoc bong bong. Hai con so nay khac
//   nhau han vi tra o hai chi muc khac nhau tai hai thoi diem khac nhau.
//
//   Reference model GIU NGUYEN; phep dem moi nam trong
//   bo sinh, doc thang btb_valid_nxpc2 tung chu ky.
//==============================================================================
class stress_long_run_hyb_test extends hyb_stress_base_test;
  `uvm_component_utils(stress_long_run_hyb_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  localparam int NUM = 10000;

  //--------------------------------------------------------------------------
  // NGUONG TINH LAI TU SO DO THUC.
  //
  //   SO DO (xrun va Questa, seed 2, 10.000 nhanh):
  //     btb_valid_nxpc2 = 9827/10002 chu ky = 98.3%   <-- chi so E, diem do moi
  //     btb_valid_pc    = 9833/10000 nhanh  = 98.3%   (reference, doi chieu)
  //
  //   Dat nguong 95.0% -- duoi so do 3.3 diem. Kich thich tat dinh nen so do
  //   lap lai chinh xac tung lan; bien 3.3 diem la de chiu duoc thay doi nho o
  //   ti le tron mau, con du chat de bat mot suy giam that (mat mot khoi 20
  //   nhanh luon-re la da tut khoang 2 diem).
  //
  //   KHONG dung lai 90% cua ban decode: 90% do la nguong cho btb_valid_pc,
  //   mot diem do khac han. Trung hop la o day hai so gan bang nhau -- va do
  //   chinh la HE QUA cua kich thich nhat quan duong ong: dia chi o nxpc2 tai T
  //   dung la dia chi toi pc tai T+2, nen hai diem do tra CUNG mot o BTB, chi
  //   lech nhau hai chu ky noi dung. Voi kich thich cu (nxpc2 = pc+8 khong lien
  //   quan) hai so nay lech han nhau.
  //--------------------------------------------------------------------------
  localparam real BTB_HIT_MIN = 95.0;

  function void build_phase(uvm_phase phase);
    test_label = "TEST_16_2 (stress_long_run)";
    select_clock();
    super.build_phase(phase);
  endfunction

  // Chuoi tron mau, giu nguyen y cua stress_mixed_mcseq cu nhung lai qua bo
  // sinh nhat quan duong ong.
  task run_phase(uvm_phase phase);
    int n = 0, i;
    bit a;
    super.run_phase(phase);
    phase.raise_objection(this, "16_2");
    #100ns;
    make_gen(32'd2);

    phase_of("A_mixed_10k");
    while (n < NUM) begin
      // khoi luon-re tai 0x100
      for (i = 0; i < 20 && n < NUM; i++) begin
        gen.push_branch(.pc(32'h0000_0100), .taken(1'b1)); n++; end
      // khoi xen ke tai 0x200
      for (i = 0; i < 20 && n < NUM; i++) begin
        gen.push_branch(.pc(32'h0000_0200), .taken(n % 2 == 0)); n++; end
      // khoi tuong quan: A(0x300) ngau nhien tat dinh, B(0x400) = A
      for (i = 0; i < 10 && n < NUM; i++) begin
        a = gen.rnd_bit();
        gen.push_branch(.pc(32'h0000_0300), .taken(a)); n++;
        if (n >= NUM) break;
        gen.push_branch(.pc(32'h0000_0400), .taken(a)); n++; end
      // mot nhanh cold-start o PC moi (thua thot -> ti le trung van cao)
      if (n < NUM) begin
        gen.push_branch(.pc(32'h0000_0800 + ((n % 256) << 2)), .taken(1'b1)); n++; end
    end
    gen.drain();

    phase.drop_objection(this, "16_2");
  endtask

  function void report_phase(uvm_phase phase);
    real hit_rate_nxpc2;
    bpu_reference r = tb.module_env.reference;
    real hit_rate_pc = (r.total_branches > 0) ?
                       100.0 * real'(r.btb_hits_at_branch) / real'(r.total_branches) : 0.0;

    phase_of("REPORT_btb_hit_rate_fetch_side");
    hit_rate_nxpc2 = (gen.n_cycles_sampled > 0) ?
                     100.0 * real'(gen.n_btb_valid_nxpc2) / real'(gen.n_cycles_sampled) : 0.0;

    `uvm_info(test_label, $sformatf(
      {"\n=== 16.2 TI LE BTB TRUNG, HAI DIEM DO ===\n",
       "  phia DU DOAN  btb_valid_nxpc2 : %0d/%0d chu ky = %.1f%%   <-- chi so E\n",
       "  phia CAP NHAT btb_valid_pc    : %0d/%0d nhanh  = %.1f%%   (reference, de doi chieu)\n",
       "  Hai so do o hai chi muc khac nhau tai hai thoi diem khac nhau nen KHONG\n",
       "  bang nhau; chi so E cua sheet la so thu nhat.\n",
       "========================================"},
      gen.n_btb_valid_nxpc2, gen.n_cycles_sampled, hit_rate_nxpc2,
      r.btb_hits_at_branch, r.total_branches, hit_rate_pc), UVM_NONE)

    `uvm_info(test_label, {"tong ket: ", gen.stats()}, UVM_NONE)

    // NGUONG: xem ghi chu dat nguong ngay tren dinh nghia BTB_HIT_MIN.
    chk(hit_rate_nxpc2 >= BTB_HIT_MIN, $sformatf(
        "ti le BTB trung phia du doan %.1f%% < %.1f%%", hit_rate_nxpc2, BTB_HIT_MIN));

    phase_of("FINAL_robustness");
    chk_no_x();
    chk_no_miscompare(9000);
    super.report_phase(phase);
  endfunction

endclass : stress_long_run_hyb_test
