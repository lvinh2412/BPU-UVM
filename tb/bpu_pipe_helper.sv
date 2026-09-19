//------------------------------------------------------------------------------
// FILE: bpu_pipe_helper.sv
//
// Day MOT nhanh qua dung trinh tu ba tang ma RTL mong doi:
//
//==============================================================================

// Mot khe trong cua so. Cac truong duoc dung o TANG KHAC NHAU: opcode/btf chi co
// tac dung khi khe xuong DECODE, con is_branch/taken/offset khi xuong EXECUTE.
typedef struct {
  bit        valid;          // khe co nhanh, hay dang trong
  int        id;             // so hieu nhanh
  bit [31:0] pc;
  bit        ovr_nxpc2;      // 1 => tang fetch doc o dia chi khac pc
  bit [31:0] nxpc2;          // dia chi ghi de do
  bit [6:0]  opcode;
  bit [31:0] btf;            // branch_target_fetch
  bit        is_branch;
  bit        taken;
  bit [31:0] offset;
} bpu_pipe_slot_t;

// Anh chup cua DUNG MOT chu ky
typedef struct {
  int        id;             // nhanh dang o EXECUTE (-1 neu khong co)
  int        cycle;          // so thu tu chu ky helper da lai
  bit [31:0] pc;
  // Ngo ra cua DUT
  bit [1:0]  bpu_flush;
  bit [31:0] bpu_nxpc2;
  bit        bpu_nxpc2_valid;
  // Bon gia tri carry-down tai EXECUTE
  bit        predicted_taken;   // front-end co bi chuyen huong khong?
  bit        pred_was_hit;      // co thong tin BTB luc fetch khong?
  bit        local_carry;       // local du doan gi luc fetch
  bit        global_carry;      // global du doan gi luc fetch
  // Dieu kien MOI TRUONG (khong phai quyet dinh cua DUT): chi de debug, cho biet
  // chu ky nay co CHO PHEP tang tuong ung kich hoat hay khong.
  bit        f_cond;
  bit        d_cond;
} bpu_pipe_obs_t;


class bpu_pipe_helper extends uvm_object;

  `uvm_object_utils(bpu_pipe_helper)

  // Test phai goi connect() truoc khi dung helper
  protected bpu_sequencer   m_seqr;
  protected bpu_backdoor    m_bd;

  //--------------------------------------------------------------------------
  // Dia chi dung cho khe TRONG. Phai khac moi PC dang kiem, ke ca sau khi lay
  // chi muc pc[11:2], neu khong chu ky nghi se vo tinh huan luyen o dung chi muc
  // dang do. Test co the doi neu can.
  //--------------------------------------------------------------------------
  bit [31:0] idle_pc     = 32'h0000_0FF0;   // idx 1020
  bit [31:0] idle_nxpc   = 32'h0000_0FF4;   // idx 1021
  bit [31:0] idle_nxpc2  = 32'h0000_0FF8;   // idx 1022
  bit [6:0]  idle_opcode = 7'b0010011;      // ADDI -- khong phai nhanh

  protected bpu_pipe_slot_t m_slot[3];   // [0]=FETCH  [1]=DECODE  [2]=EXECUTE
  protected int             m_next_id;
  protected int             m_cyc;

  // Nhat ky: moi chu ky da lai sinh ra dung mot phan tu trong cyc_obs
  bpu_pipe_obs_t            cyc_obs[$];
  protected int             m_obs_of_id[int];  // id nhanh -> chi so trong cyc_obs
  int                       last_id;           // id cua nhanh vua push

  function new(string name = "bpu_pipe_helper");
    super.new(name);
    reset_pipe();
  endfunction

  virtual function void connect(bpu_sequencer seqr, bpu_backdoor bd);
    m_seqr = seqr;
    m_bd   = bd;
    if (m_seqr == null) `uvm_fatal("BPU_PIPE", "connect(): sequencer la null")
    if (m_bd   == null) `uvm_fatal("BPU_PIPE", "connect(): backdoor la null")
  endfunction

  // Goi sau khi reset DUT giua chung, de cua so va nhat ky khong con mang du lieu
  // cua truoc reset
  virtual function void reset_pipe();
    foreach (m_slot[i]) m_slot[i] = '{default:0};
    m_next_id = 0;
    m_cyc     = 0;
    last_id   = -1;
    cyc_obs.delete();
    m_obs_of_id.delete();
  endfunction

  // Day mot khe moi vao FETCH, don hai khe kia xuong. Gan tang sau truoc, giong
  // thu tu trong bpu_ctrl.
  protected function void shift_in(bpu_pipe_slot_t s);
    m_slot[2] = m_slot[1];
    m_slot[1] = m_slot[0];
    m_slot[0] = s;
  endfunction

  //--------------------------------------------------------------------------
  // step_cycle -- nguyen thuy duy nhat cua helper: lai dung MOT chu ky theo cua
  // so hien tai, roi chup quan sat cua chu ky do.
  //
  // flush_in / halt la tin hieu THEO CHU KY, khong theo nhanh: ca ba tang dung
  // chung mot gia tri trong mot chu ky, dung nhu RTL.
  //--------------------------------------------------------------------------
  protected task step_cycle(bit [1:0] flush_in, bit halt);
    bpu_drive_seq     s;
    bpu_pipe_obs_t    o;
    bit               fetch_ready;

    s = bpu_drive_seq::type_id::create("pipe_s");

    // Khe FETCH -> nxpc2
    s.auto_nxpc2 = 1'b0;
    s.nxpc2_val  = !m_slot[0].valid   ? idle_nxpc2 :
                    m_slot[0].ovr_nxpc2 ? m_slot[0].nxpc2 : m_slot[0].pc;

    // Khe DECODE -> nxpc, fetch_opcode, branch_target_fetch
    s.auto_nxpc    = 1'b0;
    s.nxpc_val     = m_slot[1].valid ? m_slot[1].pc     : idle_nxpc;
    s.is_branch_op = 1'b0;                       // de opcode_val di nguyen, khong ep BCC
    s.opcode_val   = m_slot[1].valid ? m_slot[1].opcode : idle_opcode;
    s.btf_val      = m_slot[1].valid ? m_slot[1].btf    : 32'h0;

    // Khe EXECUTE -> pc va toan bo phia execute
    s.pc_val        = m_slot[2].valid ? m_slot[2].pc : idle_pc;
    s.flush_val     = flush_in;
    s.halt_val      = halt;

    s.is_branch_val = m_slot[2].valid ? m_slot[2].is_branch : 1'b0;
    s.taken_val     = m_slot[2].valid ? m_slot[2].taken     : 1'b0;
    s.offset_val    = m_slot[2].valid ? m_slot[2].offset    : 32'h0;

    // MOT item = MOT chu ky, khong ha bus. Helper tu quan ly nhip: moi lan goi
    // step_cycle() la mot chu ky, nen cac nhanh ke nhau duoc. Neu ha bus o day
    // thi moi chu ky se ton hai, va khong the tao duoc chuoi nhanh lien tiep.
    // bpu_pipe_helper la uvm_object chu khong phai sequence, nen khong co `this`
    // hop le de lam parent_sequence. Goi khong tham so thu hai -> sequence goc,
    // dung y het hai lenh start cua ban goc.
    s.start(m_seqr);
    //------------------------------------------------------------------------
    // Dang o canh len cua chu ky nay, vung active: thanh ghi carry-down van giu
    // gia tri chu ky nay va ngo ra to hop da on. Chup NGAY -- xem quy tac doc tin
    // hieu o dau tep.
    //------------------------------------------------------------------------
    fetch_ready       = (flush_in == 2'd0) || (flush_in == 2'd1);
    o.id              = m_slot[2].valid ? m_slot[2].id : -1;
    o.cycle           = m_cyc;
    o.pc              = s.pc_val;
    o.bpu_flush       = m_bd.read_bpu_flush();
    o.bpu_nxpc2       = m_bd.read_bpu_nxpc2();
    o.bpu_nxpc2_valid = m_bd.read_bpu_nxpc2_valid();
    o.predicted_taken = m_bd.read_predicted_taken();
    o.pred_was_hit    = m_bd.read_pred_was_hit();
    o.local_carry     = m_bd.read_local_carry();
    o.global_carry    = m_bd.read_global_carry();
    o.f_cond          = fetch_ready;
    o.d_cond          = fetch_ready && (s.opcode_val == 7'b1100011);

    cyc_obs.push_back(o);
    if (o.id >= 0) m_obs_of_id[o.id] = cyc_obs.size() - 1;
    m_cyc++;
  endtask : step_cycle

  //--------------------------------------------------------------------------
  // push_branch -- dua MOT nhanh vao duong ong va lai dung mot chu ky.
  //
  //   Nhanh chi toi EXECUTE sau hai chu ky nua, nen phai drain() (hoac push them
  //   hai khe) TRUOC khi doc obs_of(last_id).
  //
  //   flush_in / halt ap cho chu ky NAY, tuc chu ky nhanh nay o tang fetch.
  //--------------------------------------------------------------------------
  virtual task push_branch(input bit [31:0] pc,
                           input bit        taken     = 1'b1,
                           input bit [31:0] offset    = 32'h0000_0040,
                           input bit [6:0]  opcode    = 7'b1100011,  // BPU_OPCODE_BRANCH
                           input bit [1:0]  flush_in  = 2'b00,
                           input bit        halt      = 1'b0,
                           input bit [31:0] btf       = 32'h0000_0040,
                           input bit        is_branch = 1'b1,
                           input bit        ovr_nxpc2 = 1'b0,
                           input bit [31:0] nxpc2     = 32'h0);
    bpu_pipe_slot_t s;
    s           = '{default:0};
    s.valid     = 1'b1;
    s.id        = m_next_id++;
    s.pc        = pc;
    s.ovr_nxpc2 = ovr_nxpc2;
    s.nxpc2     = nxpc2;
    s.opcode    = opcode;
    s.btf       = btf;
    s.is_branch = is_branch;
    s.taken     = taken;
    s.offset    = offset;
    last_id     = s.id;
    shift_in(s);
    step_cycle(flush_in, halt);
  endtask : push_branch

  // Chen n chu ky nghi. flush_in / halt ap cho MOI chu ky trong lot nay.
  virtual task idle(input int n = 1,
                    input bit [1:0] flush_in = 2'b00,
                    input bit       halt     = 1'b0);
    bpu_pipe_slot_t empty;
    empty = '{default:0};
    repeat (n) begin
      shift_in(empty);
      step_cycle(flush_in, halt);
    end
  endtask : idle

  //--------------------------------------------------------------------------
  // drain -- lai hai chu ky nua de nhanh vua push toi EXECUTE va duoc chup.
  //   Hai cap tham so dat flush_in / halt RIENG cho tung chu ky, nho do test
  //   chan duoc dung mot tang ma khong anh huong tang kia.
  //--------------------------------------------------------------------------
  virtual task drain(input bit [1:0] flush_in_d = 2'b00, input bit halt_d = 1'b0,
                     input bit [1:0] flush_in_x = 2'b00, input bit halt_x = 1'b0);
    idle(1, flush_in_d, halt_d);   // nhanh: FETCH -> DECODE
    idle(1, flush_in_x, halt_x);   // nhanh: DECODE -> EXECUTE, duoc chup o day
  endtask : drain

  //--------------------------------------------------------------------------
  // run_branch -- push_branch + drain trong mot lan goi: mot nhanh don le, khong
  //   chong voi nhanh nao, tra ve luon quan sat tai F+2.
  //   Ba bo tham so _f/_d/_x ung voi ba chu ky fetch / decode / execute.
  //--------------------------------------------------------------------------
  virtual task run_branch(input  bit [31:0] pc,
                          input  bit        taken     = 1'b1,
                          input  bit [31:0] offset    = 32'h0000_0040,
                          input  bit [6:0]  opcode    = 7'b1100011,
                          input  bit [1:0]  flush_in_f = 2'b00,
                          input  bit [1:0]  flush_in_d = 2'b00,
                          input  bit [1:0]  flush_in_x = 2'b00,
                          input  bit        halt_f     = 1'b0,
                          input  bit        halt_d     = 1'b0,
                          input  bit        halt_x     = 1'b0,
                          input  bit [31:0] btf        = 32'h0000_0040,
                          input  bit        is_branch  = 1'b1,
                          input  bit        ovr_nxpc2  = 1'b0,
                          input  bit [31:0] nxpc2      = 32'h0,
                          output bpu_pipe_obs_t o);
    int id;
    push_branch(.pc(pc), .taken(taken), .offset(offset), .opcode(opcode),
                .flush_in(flush_in_f), .halt(halt_f), .btf(btf),
                .is_branch(is_branch), .ovr_nxpc2(ovr_nxpc2), .nxpc2(nxpc2));
    id = last_id;
    drain(flush_in_d, halt_d, flush_in_x, halt_x);
    o = obs_of(id);
  endtask : run_branch

  //--------------------------------------------------------------------------
  // Hai ham truy cap duy nhat danh cho test
  //--------------------------------------------------------------------------
  virtual function bpu_pipe_obs_t obs_of(int id);
    bpu_pipe_obs_t empty;
    empty = '{default:0};
    if (!m_obs_of_id.exists(id)) begin
      `uvm_error("BPU_PIPE", $sformatf(
        "obs_of(%0d): nhanh chua toi tang EXECUTE. Goi drain() (hoac push them 2 nhanh) truoc.", id))
      return empty;
    end
    return cyc_obs[m_obs_of_id[id]];
  endfunction

  // Theo SO THU TU CHU KY (0 = chu ky dau tien helper lai), cho cac muc phai
  // theo doi carry-down o tung chu ky chu khong chi tai F+2
  virtual function bpu_pipe_obs_t obs_at_cycle(int c);
    bpu_pipe_obs_t empty;
    empty = '{default:0};
    if (c < 0 || c >= cyc_obs.size()) begin
      `uvm_error("BPU_PIPE", $sformatf("obs_at_cycle(%0d): ngoai pham vi 0..%0d",
                                       c, cyc_obs.size()-1))
      return empty;
    end
    return cyc_obs[c];
  endfunction

  virtual function int num_cycles();
    return cyc_obs.size();
  endfunction

  // In nhat ky chu ky, de doi chieu voi song
  virtual function void dump(string tag = "");
    string s;
    s = $sformatf("\n===== BPU PIPE LOG %s =====\n", tag);
    s = {s, "  cyc  id       pc     flush nxpc2      vld | predT hit locC glbC\n"};
    foreach (cyc_obs[i]) begin
      s = {s, $sformatf("  %3d %3d 0x%08h   %0d  0x%08h  %0d  |   %0d    %0d   %0d    %0d\n",
             cyc_obs[i].cycle, cyc_obs[i].id, cyc_obs[i].pc,
             cyc_obs[i].bpu_flush, cyc_obs[i].bpu_nxpc2, cyc_obs[i].bpu_nxpc2_valid,
             cyc_obs[i].predicted_taken, cyc_obs[i].pred_was_hit,
             cyc_obs[i].local_carry, cyc_obs[i].global_carry)};
    end
    s = {s, "==================================="};
    `uvm_info("BPU_PIPE", s, UVM_LOW)
  endfunction

endclass : bpu_pipe_helper
