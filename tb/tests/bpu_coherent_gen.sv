//------------------------------------------------------------------------------
// FILE: tests/bpu_coherent_gen.sv
//
// BO SINH KICH THICH NHAT QUAN DUONG ONG, quy mo lon.
//
//------------------------------------------------------------------------------

class bpu_coherent_gen extends bpu_pipe_helper;

  `uvm_object_utils(bpu_coherent_gen)

  //--------------------------------------------------------------------------
  // Bo dem theo chu ky (cong don qua ca lan chay)
  //--------------------------------------------------------------------------
  int n_cycles_sampled;    // so chu ky da lay mau
  int n_fetch_wins;        // f_valid && !d_valid && !corr_valid  <-- tu kiem 16.1
  int n_decode_wins;       // d_valid && !corr_valid
  int n_corr_wins;         // corr_valid
  int n_no_redirect;       // khong tang nao thang
  int n_f_valid;           // f_valid bat ke uu tien
  int n_btb_valid_nxpc2;   // BTB trung o PHIA DU DOAN  <-- diem do cua 16.2
  int n_flush3_cycles;     // so chu ky da lai voi flush_in = 3
  int n_halt_cycles;       // so chu ky da lai voi halt = 1
  int n_x_seen;            // so lan thay gia tri X tren ngo ra

  //--------------------------------------------------------------------------
  // BAT BIEN NHAT QUAN DUONG ONG  (Pass Condition chinh cua 16.1)
  //
  int n_coherence_checked; // so bo ba da doi chieu duoc
  int n_coherence_bad;     // so bo ba VI PHAM bat bien
  protected bit [31:0] m_hist_nxpc2[$];   // nxpc2 da lai, theo chu ky
  protected bit [31:0] m_hist_nxpc[$];
  protected bit [31:0] m_hist_pc[$];
  protected bit        m_hist_live[$];    // chu ky nay co nhanh o khe FETCH?

  //--------------------------------------------------------------------------
  // Nguon bit tat dinh, giong het nhau tren moi trinh mo phong.
  // Xem ghi chu day du o dau bpu_det_rng (tests/pattern_tests.sv).
  //--------------------------------------------------------------------------
  protected bpu_det_rng m_rng;

  function new(string name = "bpu_coherent_gen");
    super.new(name);
    m_rng = new(32'd2);
    clear_stats();
  endfunction

  virtual function void set_seed(bit [31:0] seed);
    m_rng = new(seed);
  endfunction

  virtual function void clear_stats();
    n_cycles_sampled  = 0; n_fetch_wins      = 0; n_decode_wins = 0;
    n_corr_wins       = 0; n_no_redirect     = 0; n_f_valid     = 0;
    n_btb_valid_nxpc2 = 0; n_flush3_cycles   = 0; n_halt_cycles = 0;
    n_x_seen          = 0;
    n_coherence_checked = 0; n_coherence_bad = 0;
    m_hist_nxpc2.delete(); m_hist_nxpc.delete();
    m_hist_pc.delete();    m_hist_live.delete();
  endfunction

  //--------------------------------------------------------------------------
  // So nguyen gia tri 0..n-1, tat dinh. Ghep 16 bit tu hai lan rut de tranh
  // lay lien tiep cung mot bit cua LCG.
  //--------------------------------------------------------------------------
  virtual function int unsigned rnd(int unsigned n);
    bit [15:0] r;
    int i;
    for (i = 0; i < 16; i++) r[i] = m_rng.next_bit();
    return (n == 0) ? 0 : (r % n);
  endfunction

  virtual function bit rnd_bit();
    return m_rng.next_bit();
  endfunction

  //--------------------------------------------------------------------------
  // Dia chi ngau nhien cho muc 16.1.
  //
  //--------------------------------------------------------------------------
  virtual function bit [31:0] rnd_pc();
    bit [31:0] hi = m_rng.next_bits(20);   // pc[31:12]
    return (hi << 12) | (rnd(1024) << 2);
  endfunction

  //--------------------------------------------------------------------------
  // sample_tier -- chup them cac quan sat helper khong co. Goi NGAY sau moi
  // chu ky helper vua lai.
  //--------------------------------------------------------------------------
  protected virtual function void sample_tier();
    bit f, d, c;
    f = m_bd.read_f_valid();
    d = m_bd.read_d_valid();
    c = m_bd.read_corr_valid();

    n_cycles_sampled++;
    if (f) n_f_valid++;
    if (m_bd.read_btb_valid_nxpc2()) n_btb_valid_nxpc2++;

    // Thu tu uu tien MUX: corr > decode > fetch  (bpu_ctrl.v)
    if      (c)        n_corr_wins++;
    else if (d)        n_decode_wins++;
    else if (f)        n_fetch_wins++;
    else               n_no_redirect++;

    if ($isunknown(m_bd.read_bpu_nxpc2())       ||
        $isunknown(m_bd.read_bpu_nxpc2_valid()) ||
        $isunknown(m_bd.read_bpu_flush()))
      n_x_seen++;

    sample_coherence();
  endfunction

  //--------------------------------------------------------------------------
  // sample_coherence -- doi chieu bat bien nxpc2(T) == nxpc(T+1) == pc(T+2)
  // tren dia chi DOC LAI TU NET INTERFACE.
  //--------------------------------------------------------------------------
  protected virtual function void sample_coherence();
    int n;
    m_hist_nxpc2.push_back(m_bd.read_if_nxpc2());
    m_hist_nxpc .push_back(m_bd.read_if_nxpc());
    m_hist_pc   .push_back(m_bd.read_if_pc());
    // Chi kiem khi khe FETCH co nhanh VA khong bi ghi de dia chi doc: khi
    // ovr_nxpc2 = 1 thi test CO Y dat nxpc2 khac pc, nen bat bien khong ap dung.
    m_hist_live .push_back(m_slot[0].valid && !m_slot[0].ovr_nxpc2);

    n = m_hist_pc.size();
    if (n >= 3) begin
      // Chu ky T = n-3 : nhanh o khe FETCH   -> dia chi ra nxpc2
      // Chu ky T+1     : nhanh o khe DECODE  -> dia chi ra nxpc
      // Chu ky T+2 = n-1: nhanh o khe EXECUTE -> dia chi ra pc
      if (m_hist_live[n-3]) begin
        n_coherence_checked++;
        if (m_hist_nxpc2[n-3] !== m_hist_nxpc[n-2] ||
            m_hist_nxpc2[n-3] !== m_hist_pc[n-1]) begin
          n_coherence_bad++;
          if (n_coherence_bad <= 5)
            `uvm_error("BPU_COH_GEN", $sformatf(
              {"vi pham nhat quan duong ong tai chu ky T=%0d: ",
               "nxpc2(T)=0x%08h nxpc(T+1)=0x%08h pc(T+2)=0x%08h -- ba gia tri phai bang nhau"},
              n-3, m_hist_nxpc2[n-3], m_hist_nxpc[n-2], m_hist_pc[n-1]))
        end
      end
      // Chi giu 3 khe gan nhat: chuoi 10k nhanh khong duoc phinh bo nho.
      void'(m_hist_nxpc2.pop_front()); void'(m_hist_nxpc.pop_front());
      void'(m_hist_pc.pop_front());    void'(m_hist_live.pop_front());
    end
  endfunction

  //--------------------------------------------------------------------------
  // Bao ngoai hai nguyen thuy cua helper. Chu ky cua chung phai TRUNG KHOP
  // voi lop cha, neu khong thi loi goi ham se im lang chon nham ban.
  //--------------------------------------------------------------------------
  virtual task push_branch(input bit [31:0] pc,
                           input bit        taken     = 1'b1,
                           input bit [31:0] offset    = 32'h0000_0040,
                           input bit [6:0]  opcode    = 7'b1100011,
                           input bit [1:0]  flush_in  = 2'b00,
                           input bit        halt      = 1'b0,
                           input bit [31:0] btf       = 32'h0000_0040,
                           input bit        is_branch = 1'b1,
                           input bit        ovr_nxpc2 = 1'b0,
                           input bit [31:0] nxpc2     = 32'h0);
    super.push_branch(pc, taken, offset, opcode, flush_in, halt, btf,
                      is_branch, ovr_nxpc2, nxpc2);
    if (flush_in == 2'd3) n_flush3_cycles++;
    if (halt)             n_halt_cycles++;
    sample_tier();
  endtask

  // Phai lay mau TUNG chu ky nghi, nen goi super.idle(1) trong vong lap thay
  // vi super.idle(n) mot lan (se bo qua n-1 chu ky).
  virtual task idle(input int n = 1,
                    input bit [1:0] flush_in = 2'b00,
                    input bit       halt     = 1'b0);
    repeat (n) begin
      super.idle(1, flush_in, halt);
      if (flush_in == 2'd3) n_flush3_cycles++;
      if (halt)             n_halt_cycles++;
      sample_tier();
    end
  endtask

  //==========================================================================
  // KICH BAN DUNG CHUNG
  //==========================================================================

  //--------------------------------------------------------------------------
  // run_random_branches -- n nhanh ngau nhien lien tiep, moi nhanh mot chu ky
  //   (back-to-back). PC / taken / offset deu ngau nhien tat dinh.
  //   b2b = 0 thi chen 0..2 chu ky nghi giua cac nhanh de trai ra khoang cach.
  //--------------------------------------------------------------------------
  virtual task run_random_branches(int n, bit b2b = 1'b1);
    int k;
    for (k = 0; k < n; k++) begin
      push_branch(.pc(rnd_pc()),
                  .taken(rnd_bit()),
                  .offset({rnd(512), 1'b0}),
                  .btf({rnd(512), 1'b0}));
      if (!b2b) idle(rnd(3));
    end
    drain();
  endtask

  //--------------------------------------------------------------------------
  // run_random_ctrl -- n chu ky voi halt ngau nhien ~30% va flush_in ngau
  //   nhien GOM CA gia tri 3 (bpu_ctrl.v chi coi 0/1 la fetch_ready, nen 2
  //   va 3 deu la not-ready; gia tri 3 truoc day khong bo sinh nao lai toi).
  //   Xen ke nhanh va chu ky nghi de ca hai duong deu bi ep.
  //--------------------------------------------------------------------------
  virtual task run_random_ctrl(int n_cyc);
    int k;
    bit [1:0] fv;
    bit       hv;
    for (k = 0; k < n_cyc; k++) begin
      fv = rnd(4);                 // 0,1,2,3 -- gom ca 3
      hv = (rnd(100) < 30);        // ~30% halt
      if (rnd_bit())
        push_branch(.pc(rnd_pc()), .taken(rnd_bit()),
                    .offset({rnd(512), 1'b0}), .btf({rnd(512), 1'b0}),
                    .flush_in(fv), .halt(hv));
      else
        idle(1, fv, hv);
    end
    drain();
  endtask

  //--------------------------------------------------------------------------
  // inject_reset -- ep reset giua chung roi nha, va xoa cua so duong ong.
  //   reference model tu dong xoa shadow state khi thay negedge rst_n
  //   (bpu_reference.sv reset_handler), nen scoreboard VAN SONG qua lan reset.
  //--------------------------------------------------------------------------
  virtual task inject_reset(int n_cyc_held = 3);
    m_bd.force_tb_reset(1'b1);
    idle(n_cyc_held);
    m_bd.release_tb_reset();
    idle(2);
    reset_pipe();
    // Xoa cua so bat bien: mot bo ba vat qua diem reset khong con y nghia
    // (reset_pipe da don ba khe, nen dia chi truoc va sau khong lien quan).
    m_hist_nxpc2.delete(); m_hist_nxpc.delete();
    m_hist_pc.delete();    m_hist_live.delete();
  endtask

  //--------------------------------------------------------------------------
  // stats -- mot dong tom tat, dung cho ca log lan bao cao
  //--------------------------------------------------------------------------
  virtual function string stats();
    return $sformatf(
      {"cycles=%0d | MUX thang: fetch=%0d decode=%0d corr=%0d none=%0d | ",
       "f_valid=%0d btb_valid_nxpc2=%0d | flush3_cyc=%0d halt_cyc=%0d | X=%0d | ",
       "coherence: %0d/%0d dat"},
      n_cycles_sampled, n_fetch_wins, n_decode_wins, n_corr_wins, n_no_redirect,
      n_f_valid, n_btb_valid_nxpc2, n_flush3_cycles, n_halt_cycles, n_x_seen,
      n_coherence_checked - n_coherence_bad, n_coherence_checked);
  endfunction

endclass : bpu_coherent_gen
