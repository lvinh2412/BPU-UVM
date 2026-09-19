//------------------------------------------------------------------------------
//
// CLASS: bpu_backdoor
//
// Vai tro: truy cap trang thai noi bo DUT bang uvm_hdl_*, cho nhung phep kiem
//   khong the lam qua cong -- doc cac bang du doan va thanh ghi carry-down, nap
//   san trang thai de bat dau tu giua mot chuoi lich su, va nhin rieng cac day noi
//   ben trong nhu f_valid / d_valid.
//
//
//------------------------------------------------------------------------------

class bpu_backdoor extends uvm_object;

   `uvm_object_utils(bpu_backdoor)

   // Duong dan goc toi register file trong DUT
   string path_root = "bpu_hw_top.dut.u_bpu_reg";

   function new (string name = "bpu_backdoor");
      super.new(name);
   endfunction : new

   // Cho phep env/test doi hierarchy ma khong phai sua tep nay
   function void set_path_root(string root);
      path_root = root;
   endfunction

   // Ghep duong dan mot phan tu mang: "<root>.<array>[<idx>]"
   local function string elem_path(string arr, int idx);
      return $sformatf("%s.%s[%0d]", path_root, arr, idx);
   endfunction

   // Ghep duong dan mot tin hieu vo huong: "<root>.<signal>"
   local function string scalar_path(string sig);
      return $sformatf("%s.%s", path_root, sig);
   endfunction

   // Duong dan muc DUT: chi dung de doc cac ngo ra to hop (bpu_nxpc2, ...)
   string dut_path = "bpu_hw_top.dut";
   function void set_dut_path(string root);
      dut_path = root;
   endfunction
   local function string dut_sig(string sig);
      return $sformatf("%s.%s", dut_path, sig);
   endfunction

   // Duong dan bpu_ctrl: thanh ghi carry-down va dieu kien cac tang nam o day,
   // khong nam trong register file.
   string ctrl_path = "bpu_hw_top.dut.u_bpu_ctrl";
   function void set_ctrl_path(string root);
      ctrl_path = root;
   endfunction
   local function string ctrl_sig(string sig);
      return $sformatf("%s.%s", ctrl_path, sig);
   endfunction

   // Duong dan interface. Ep tren day noi cua interface (thay vi cong DUT) thi
   // monitor va DUT cung thay mot gia tri, nen mo hinh tham chieu VAN dong bo ngay
   // ca khi dang ep ngo vao.
   // Sau khi gop hai UVC thanh mot agent, ca 13 tin hieu nam tren CUNG mot
   // interface, nen hai bien duoi day tro vao cung mot cho. Co Y giu hai bien
   // rieng: muc tieu cua lan chuyen doi nay la chung minh hanh vi khong doi, nen
   // diff cang nho cang de chung minh. Viec hop nhat chung la don dep, lam sau.
   string predict_if_path = "bpu_hw_top.bpu_if";
   string update_if_path  = "bpu_hw_top.bpu_if";
   local function string predict_if_sig(string sig);
      return $sformatf("%s.%s", predict_if_path, sig);
   endfunction
   local function string update_if_sig(string sig);
      return $sformatf("%s.%s", update_if_path, sig);
   endfunction

   //==========================================================================
   // Cac ham boc uvm_hdl_* -- NOI DUY NHAT ma ma tra ve duoc kiem tra.
   //
   //   Moi truy cap trong class nay deu di qua mot trong bon ham nay, nen khong cho
   //   goi nao co the bo qua ma tra ve.
   //
   //   Bi tu choi thi bao `uvm_fatal chu khong phai `uvm_error: cac lenh nay DUNG
   //   NEN kich ban. Neu mot lenh nap bi tu choi, bang van o gia tri reset, va moi
   //   phep kiem sau do bao cao ve mot kich ban chua tung duoc dung -- thuong la
   //   bao PASS. Dung ngay tai cho bi tu choi moi lam lo ra dieu do.
   //==========================================================================
   local function void hdl_read(string path, output uvm_hdl_data_t v);
      if (!uvm_hdl_read(path, v))
         `uvm_fatal("BPU_BACKDOOR",
            $sformatf("uvm_hdl_read refused by the simulator on path '%s'", path))
   endfunction

   local function void hdl_force(string path, uvm_hdl_data_t v);
      if (!uvm_hdl_force(path, v))
         `uvm_fatal("BPU_BACKDOOR",
            $sformatf("uvm_hdl_force refused by the simulator on path '%s'", path))
   endfunction

   local function void hdl_release(string path);
      if (!uvm_hdl_release(path))
         `uvm_fatal("BPU_BACKDOOR",
            $sformatf("uvm_hdl_release refused by the simulator on path '%s'", path))
   endfunction

   local function void hdl_deposit(string path, uvm_hdl_data_t v);
      if (!uvm_hdl_deposit(path, v))
         `uvm_fatal("BPU_BACKDOOR",
            $sformatf("uvm_hdl_deposit refused by the simulator on path '%s'", path))
   endfunction

   //==========================================================================
   // Cac ham DOC
   //==========================================================================
   function bit read_btb_valid(int idx);
      uvm_hdl_data_t v;
      hdl_read(elem_path("btb_valid", idx), v);
      read_btb_valid = v[0];
   endfunction

   function bit [31:0] read_btb_target(int idx);
      uvm_hdl_data_t v;
      hdl_read(elem_path("btb_target", idx), v);
      read_btb_target = v[31:0];
   endfunction

   function bit [11:0] read_local_bht(int idx);
      uvm_hdl_data_t v;
      hdl_read(elem_path("local_bht", idx), v);
      read_local_bht = v[11:0];
   endfunction

   function bit [1:0] read_local_pht(int idx);
      uvm_hdl_data_t v;
      hdl_read(elem_path("local_pht", idx), v);
      read_local_pht = v[1:0];
   endfunction

   function bit [1:0] read_global_pht(int idx);
      uvm_hdl_data_t v;
      hdl_read(elem_path("global_pht", idx), v);
      read_global_pht = v[1:0];
   endfunction

   function bit [1:0] read_choice(int idx);
      uvm_hdl_data_t v;
      hdl_read(elem_path("choice", idx), v);
      read_choice = v[1:0];
   endfunction

   function bit [9:0] read_ghr();
      uvm_hdl_data_t v;
      hdl_read(scalar_path("ghr"), v);
      read_ghr = v[9:0];
   endfunction

   //==========================================================================
   // Doc CARRY-DOWN -- tam thanh ghi duong ong trong bpu_ctrl.
   //
   //   *_delay_1  o decode:  nap tu cac phep doc phia fetch cua chu ky nay
   //   *_delay_2  o execute: cai ma tang execute dem ra so
   //
   //   RTL viet la "predic_taken_delay_*" (thieu chu t); ten duoi day giu nguyen
   //   cach viet do de grep mot phat ra ca hai noi.
   //
   //   Chi doc -- khong co ham force cho nhom nay.
   //==========================================================================
   local function bit read_ctrl_bit(string sig);
      uvm_hdl_data_t v;
      hdl_read(ctrl_sig(sig), v);
      read_ctrl_bit = v[0];
   endfunction

   function bit read_predic_taken_delay_1();
      read_predic_taken_delay_1 = read_ctrl_bit("predic_taken_delay_1");
   endfunction

   function bit read_predic_taken_delay_2();
      read_predic_taken_delay_2 = read_ctrl_bit("predic_taken_delay_2");
   endfunction

   function bit read_btb_hit_delay_1();
      read_btb_hit_delay_1 = read_ctrl_bit("btb_hit_delay_1");
   endfunction

   function bit read_btb_hit_delay_2();
      read_btb_hit_delay_2 = read_ctrl_bit("btb_hit_delay_2");
   endfunction

   function bit read_local_delay_1();
      read_local_delay_1 = read_ctrl_bit("local_delay_1");
   endfunction

   function bit read_local_delay_2();
      read_local_delay_2 = read_ctrl_bit("local_delay_2");
   endfunction

   function bit read_global_delay_1();
      read_global_delay_1 = read_ctrl_bit("global_delay_1");
   endfunction

   function bit read_global_delay_2();
      read_global_delay_2 = read_ctrl_bit("global_delay_2");
   endfunction

   // Gia tri tang 2, dat theo dung ten ma phan RTL con lai goi chung
   function bit read_predicted_taken(); read_predicted_taken = read_predic_taken_delay_2(); endfunction
   function bit read_pred_was_hit();    read_pred_was_hit    = read_btb_hit_delay_2();      endfunction
   function bit read_local_carry();     read_local_carry     = read_local_delay_2();        endfunction
   function bit read_global_carry();    read_global_carry    = read_global_delay_2();       endfunction

   // Ca hai tang tren mot dong, tien khi phai go loi ve thoi diem
   function void print_carry_down();
      `uvm_info("BPU_BACKDOOR", $sformatf(
         {"carry-down: stage1[steer=%0b hit=%0b local=%0b global=%0b] ",
          "stage2[predicted_taken=%0b pred_was_hit=%0b local_carry=%0b global_carry=%0b]"},
         read_predic_taken_delay_1(), read_btb_hit_delay_1(),
         read_local_delay_1(),        read_global_delay_1(),
         read_predic_taken_delay_2(), read_btb_hit_delay_2(),
         read_local_delay_2(),        read_global_delay_2()), UVM_LOW)
   endfunction

   //==========================================================================
   // Cac ham DEPOSIT -- ghi mot lan roi tha cho DUT chay tiep.
   //
   //   Day la cach MAC DINH de nap san trang thai: gia tri vao ngay bay gio va RTL
   //   duoc quyen ghi de o canh sau, y het nhu no den bang mot lenh ghi binh
   //   thuong. Chi dung force_* khi phai chan mot lenh ghi cua DUT.
   //==========================================================================
   task deposit_btb(int idx, bit valid, bit [31:0] target);
      hdl_deposit(elem_path("btb_valid",  idx), valid);
      hdl_deposit(elem_path("btb_target", idx), target);
   endtask

   task deposit_local_bht(int idx, bit [11:0] data);
      hdl_deposit(elem_path("local_bht", idx), data);
   endtask

   task deposit_local_pht(int idx, bit [1:0] data);
      hdl_deposit(elem_path("local_pht", idx), data);
   endtask

   task deposit_global_pht(int idx, bit [1:0] data);
      hdl_deposit(elem_path("global_pht", idx), data);
   endtask

   task deposit_choice(int idx, bit [1:0] data);
      hdl_deposit(elem_path("choice", idx), data);
   endtask

   task deposit_ghr(bit [9:0] data);
      hdl_deposit(scalar_path("ghr"), data);
   endtask

   //==========================================================================
   // Cac ham FORCE / RELEASE -- ep dinh, giu cho toi khi release_*.
   //
   //   Chi dung khi kich ban phai CHAN mot lenh ghi cua DUT: vi du giu ghr dung yen
   //   de chi muc gshare khong doi trong luc lai nhieu nhanh. Neu chi muon "bat dau
   //   tu trang thai X" thi dung deposit_*.
   //
   //   TINH KHA CHUYEN, do thuc te tren ca hai trinh mo phong:
   //
   //     dang duong dan             read  force  release  deposit
   //     -------------------------  ----  -----  -------  -------
   //     vo huong (ghr)              1      1       1        1     ca hai
   //     phan tu mang unpacked       1      1       1        1     Xcelium
   //     phan tu mang unpacked       1      0       0        1     QuestaSim
   //     day noi interface           1      1       1        1     ca hai
   //
   //   QuestaSim bao vsim-16133 "Unable to locate path" khi force/release mot phan
   //   tu mang va tra ve 0, ma ham boc bien do thanh fatal. Vi vay SAU ham
   //   force_*/release_* o muc phan tu duoi day chi chay duoc tren Xcelium;
   //   force_ghr (vo huong) va cac lenh ep tren day noi interface thi chay ca hai.
   //==========================================================================
   task force_btb(int idx, bit valid, bit [31:0] target);
      hdl_force(elem_path("btb_valid",  idx), valid);
      hdl_force(elem_path("btb_target", idx), target);
   endtask

   task release_btb(int idx);
      hdl_release(elem_path("btb_valid",  idx));
      hdl_release(elem_path("btb_target", idx));
   endtask

   task force_local_bht(int idx, bit [11:0] data);
      hdl_force(elem_path("local_bht", idx), data);
   endtask

   task release_local_bht(int idx);
      hdl_release(elem_path("local_bht", idx));
   endtask

   task force_local_pht(int idx, bit [1:0] data);
      hdl_force(elem_path("local_pht", idx), data);
   endtask

   task release_local_pht(int idx);
      hdl_release(elem_path("local_pht", idx));
   endtask

   task force_global_pht(int idx, bit [1:0] data);
      hdl_force(elem_path("global_pht", idx), data);
   endtask

   task release_global_pht(int idx);
      hdl_release(elem_path("global_pht", idx));
   endtask

   task force_choice(int idx, bit [1:0] data);
      hdl_force(elem_path("choice", idx), data);
   endtask

   task release_choice(int idx);
      hdl_release(elem_path("choice", idx));
   endtask

   task force_ghr(bit [9:0] data);
      hdl_force(scalar_path("ghr"), data);
   endtask

   task release_ghr();
      hdl_release(scalar_path("ghr"));
   endtask

   //==========================================================================
   // Cac ham kiem theo LO -- quet ca bang va dem so o lech
   //==========================================================================

   // choice reset ve WNT chu khong phai 0, nen phai co ham kiem rieng
   function int check_choice_reset_default();
      int mismatches = 0;
      bit [1:0] val;
      for (int i = 0; i < 1024; i++) begin
         val = read_choice(i);
         if (val !== 2'b01) begin
            mismatches++;
            `uvm_error("BPU_BACKDOOR",
               $sformatf("choice[%0d] = %0d after reset, expected WNT(01)", i, val))
         end
      end
      return mismatches;
   endfunction

   // table_sel: 0=btb_valid, 1=local_bht, 2=local_pht, 3=global_pht
   function int check_table_zero(int table_sel);
      int mismatches = 0;
      int size;
      bit ok;
      case (table_sel)
         0: size = 1024;  // btb_valid
         1: size = 1024;  // local_bht
         2: size = 4096;  // local_pht lay chi muc tu BHT 12 bit, nen 4096
         3: size = 1024;  // global_pht
         default: begin
            `uvm_error("BPU_BACKDOOR",
               $sformatf("check_table_zero: invalid table_sel=%0d", table_sel))
            return -1;
         end
      endcase
      for (int i = 0; i < size; i++) begin
         case (table_sel)
            0: ok = (read_btb_valid(i)  === 1'b0);
            1: ok = (read_local_bht(i)  === 12'b0);
            2: ok = (read_local_pht(i)  === 2'b0);
            3: ok = (read_global_pht(i) === 2'b0);
         endcase
         if (!ok) mismatches++;
      end
      return mismatches;
   endfunction

   // Chup ca bang, cho cac test so sanh bang truoc va sau
   function void dump_local_pht(ref bit [1:0] q[$]);
      q = {};
      for (int i = 0; i < 4096; i++)
         q.push_back(read_local_pht(i));
   endfunction

   function void dump_global_pht(ref bit [1:0] q[$]);
      q = {};
      for (int i = 0; i < 1024; i++)
         q.push_back(read_global_pht(i));
   endfunction

   //==========================================================================
   // In go loi -- max_entries dong dau cua moi bang, dat canh nhau
   //==========================================================================
   function void print_snapshot(int max_entries = 8);
      string s;
      s = "\n===== BPU Backdoor Snapshot =====\n";
      s = {s, $sformatf("  GHR = 0x%03h\n", read_ghr())};
      s = {s, "  idx : btb_v btb_target  bht    lpht gpht choice\n"};
      for (int i = 0; i < max_entries; i++) begin
         s = {s, $sformatf("  %3d :   %0d   0x%08h  0x%03h   %0d    %0d     %0d\n",
                  i, read_btb_valid(i), read_btb_target(i), read_local_bht(i),
                  read_local_pht(i),
                  read_global_pht(i), read_choice(i))};
      end
      s = {s, "=================================="};
      `uvm_info("BPU_BACKDOOR", s, UVM_LOW)
   endfunction

   //==========================================================================
   // Doc NGO RA -- doc thang ngo ra cua DUT.
   //   Danh cho test da ep trang thai noi bo nen khong dung duoc scoreboard.
   //   Day la tin hieu to hop: chi doc SAU khi ngo vao va trang thai bi ep da on.
   //==========================================================================
   function bit [31:0] read_bpu_nxpc2();
      uvm_hdl_data_t v;
      hdl_read(dut_sig("bpu_nxpc2"), v);
      read_bpu_nxpc2 = v[31:0];
   endfunction

   function bit read_bpu_nxpc2_valid();
      uvm_hdl_data_t v;
      hdl_read(dut_sig("bpu_nxpc2_valid"), v);
      read_bpu_nxpc2_valid = v[0];
   endfunction

   function bit [1:0] read_bpu_flush();
      uvm_hdl_data_t v;
      hdl_read(dut_sig("bpu_flush"), v);
      read_bpu_flush = v[1:0];
   endfunction

   //==========================================================================
   // Quan sat TANG FETCH -- cac cong doc phia nxpc2 va ngo ra tournament.
   //
   //   Day la day noi noi bo cua bpu_top, tren register file mot cap. Can chung vi
   //   predict_taken_nxpc2 khong duoc dua ra cong nao, va vi btb_valid_nxpc2 chinh
   //   la cai cho thay tang fetch VAN hoat dong trong khi tang decode bi chan.
   //
   //   Chi doc, nen mo hinh tham chieu khong bi anh huong.
   //==========================================================================
   local function bit [31:0] read_dut_word(string sig);
      uvm_hdl_data_t v;
      hdl_read(dut_sig(sig), v);
      read_dut_word = v[31:0];
   endfunction

   //==========================================================================
   // Quan sat NGO VAO INTERFACE -- ba dia chi DUNG NHU da duoc dua vao.
   //
   //   Dung de kiem bat bien nhat quan duong ong
   //
   //       nxpc2(T) == nxpc(T+1) == pc(T+2)
   //
   //   tren kich thich that. Neu bo sinh tu doi chieu y dinh cua no voi mo hinh cua
   //   chinh no thi khong chung minh duoc gi; cac ham nay doc dung nhung day noi ma
   //   monitor lay mau, nen cai duoc kiem la cai DUT thuc su nhan.
   //==========================================================================
   local function bit [31:0] read_predict_if_word(string sig);
      uvm_hdl_data_t v;
      hdl_read(predict_if_sig(sig), v);
      read_predict_if_word = v[31:0];
   endfunction

   function bit [31:0] read_if_pc();    return read_predict_if_word("pc");    endfunction
   function bit [31:0] read_if_nxpc();  return read_predict_if_word("nxpc");  endfunction
   function bit [31:0] read_if_nxpc2(); return read_predict_if_word("nxpc2"); endfunction

   function bit       read_predict_taken_nxpc2();  return read_dut_word("predict_taken_nxpc2"); endfunction
   function bit       read_btb_valid_nxpc2();      return read_dut_word("btb_valid_nxpc2");     endfunction
   function bit       read_btb_valid_nxpc();       return read_dut_word("btb_valid_nxpc");      endfunction
   function bit       read_btb_valid_pc_port();    return read_dut_word("btb_valid_pc");        endfunction
   function bit [31:0] read_btb_target_nxpc2();    return read_dut_word("btb_target_nxpc2");    endfunction
   function bit [31:0] read_btb_target_pc_port();  return read_dut_word("btb_target_pc");       endfunction
   function bit [1:0] read_local_pht_data_nxpc2(); return read_dut_word("local_pht_data_nxpc2");  endfunction
   function bit [1:0] read_global_pht_data_nxpc2();return read_dut_word("global_pht_data_nxpc2"); endfunction
   function bit [1:0] read_choice_data_nxpc2();    return read_dut_word("choice_data_nxpc2");     endfunction

   //==========================================================================
   // Quan sat viec CAP NHAT CHOICE.
   //
   //   Can choice_wr_en vi neu chi doc gia tri choice thi khong tach duoc "khong doi
   //   vi lenh ghi bi cam" voi "khong doi vi bo dem da bao hoa".
   //
   //   local_pht_data_pc / global_pht_data_pc la gia tri PHT doc tai PC phia execute.
   //   Phep cap nhat choice KHONG dung chung -- no dung cac bit carry-down -- nen hai
   //   gia tri nay dong vai tro doi chung: neu cap nhat theo chung thi choice se di
   //   ve huong khac.
   //==========================================================================
   local function bit [31:0] read_pred_word(string sig);
      uvm_hdl_data_t v;
      hdl_read($sformatf("%s.u_bpu_predictor.%s", dut_path, sig), v);
      read_pred_word = v[31:0];
   endfunction

   function bit       read_choice_wr_en();   return read_pred_word("choice_wr_en");   endfunction
   function bit [1:0] read_choice_wr_data(); return read_pred_word("choice_wr_data"); endfunction
   function bit       read_disagree();       return read_pred_word("disagree");       endfunction

   function bit [1:0] read_local_pht_data_pc();  return read_dut_word("local_pht_data_pc");  endfunction
   function bit [1:0] read_global_pht_data_pc(); return read_dut_word("global_pht_data_pc"); endfunction
   function bit [1:0] read_choice_data_pc();     return read_dut_word("choice_data_pc");     endfunction

   //==========================================================================
   // Quan sat DIEU KIEN CHAN -- dieu kien rieng cua tung tang.
   //   bpu_nxpc2_valid la phep OR cua ca ba tang, nen nhin cong do khong biet tang
   //   nao da kich hoat. Cac ham nay lam moi dieu kien chan quan sat duoc rieng le.
   //==========================================================================
   function bit read_fetch_is_branch(); return read_ctrl_bit("fetch_is_branch"); endfunction
   function bit read_fetch_ready();     return read_ctrl_bit("fetch_ready");     endfunction
   function bit read_f_valid();         return read_ctrl_bit("f_valid");         endfunction
   function bit read_d_valid();         return read_ctrl_bit("d_valid");         endfunction
   function bit read_corr_valid();      return read_ctrl_bit("corr_valid");      endfunction

   //==========================================================================
   // Hai bang ma check_table_zero khong phu duoc: btb_target rong 32 bit, con
   // choice reset ve WNT chu khong phai 0. Ca hai chi DEM im lang, de ben goi tu
   // bao loi kem nhan pha cua no.
   //==========================================================================
   function int count_btb_target_nonzero();
      count_btb_target_nonzero = 0;
      for (int i = 0; i < 1024; i++)
         if (read_btb_target(i) !== 32'h0) count_btb_target_nonzero++;
   endfunction

   function int count_choice_not_wnt();
      count_choice_not_wnt = 0;
      for (int i = 0; i < 1024; i++)
         if (read_choice(i) !== 2'b01) count_choice_not_wnt++;
   endfunction

   //==========================================================================
   // Lai RESET KHONG DONG BO.
   //
   //   clock_and_reset_if lai `reset` tu mot khoi always @(posedge clock), nen mot
   //   sequence chi co the danh thuc no DUNG TAI canh clock. Muon chung minh reset
   //   cua DUT la khong dong bo thi phai danh thuc GIUA hai canh, tuc phai ep dinh
   //   de len chinh bo lai theo clock cua interface -- vi vay dung force chu khong
   //   phai deposit.
   //
   //   Duong dan tro toi bien `reset` cua interface chu khong phai mot cong DUT:
   //   interface suy ra rst_n tu no bang assign lien tuc, nen ep o day moi thuc su
   //   lam doi rst_n cua DUT. Day la day noi interface nen ca hai trinh deu chay.
   //==========================================================================
   string rst_path = "bpu_hw_top.clk_rst_if.reset";

   function void force_tb_reset(bit v);
      hdl_force(rst_path, v);
   endfunction

   function void release_tb_reset();
      hdl_release(rst_path);
   endfunction

   function bit read_tb_rst_n();
      uvm_hdl_data_t v;
      hdl_read("bpu_hw_top.clk_rst_if.rst_n", v);
      read_tb_rst_n = v[0];
   endfunction

   //==========================================================================
   // Lai NGO VAO -- lai thang day noi interface, bo qua cac agent.
   //
   //   Cho nhung kich ban ma sequence khong dien ta duoc, vi du giu mot ngo vao dung
   //   yen qua nhieu chu ky. Vi day la day noi interface nen monitor thay dung gia
   //   tri DUT thay, khac voi nhom ep trang thai o tren, nhom nay GIU mo hinh tham
   //   chieu dong bo.
   //
   //   Luon phai goi kem release_predict_inputs(), neu khong cac agent bi khoa ngoai
   //   trong suot phan con lai cua lan chay.
   //
   //   Gia tri mac dinh mo ta mot chu ky nghi: khong tra BTB tai nxpc2 va khong co
   //   nhanh nao giai quyet o execute.
   //==========================================================================
   task force_predict_inputs(bit [31:0] pc,
                             bit [31:0] nxpc,
                             bit [6:0]  fetch_opcode,
                             bit [31:0] branch_target_fetch,
                             bit [1:0]  flush_in,
                             bit        halt,
                             bit [31:0] nxpc2         = 32'h0,
                             bit        is_branch     = 1'b0,
                             bit        branch_taken  = 1'b0,
                             bit [31:0] branch_offset = 32'h0);
      hdl_force(predict_if_sig("pc"),                  pc);
      hdl_force(predict_if_sig("nxpc"),                nxpc);
      hdl_force(predict_if_sig("nxpc2"),               nxpc2);
      hdl_force(predict_if_sig("fetch_opcode"),        fetch_opcode);
      hdl_force(predict_if_sig("branch_target_fetch"), branch_target_fetch);
      hdl_force(predict_if_sig("flush_in"),            flush_in);
      hdl_force(predict_if_sig("halt"),                halt);
      hdl_force(update_if_sig("is_branch"),            is_branch);
      hdl_force(update_if_sig("branch_taken"),         branch_taken);
      hdl_force(update_if_sig("branch_offset"),        branch_offset);
   endtask

   task release_predict_inputs();
      hdl_release(predict_if_sig("pc"));
      hdl_release(predict_if_sig("nxpc"));
      hdl_release(predict_if_sig("nxpc2"));
      hdl_release(predict_if_sig("fetch_opcode"));
      hdl_release(predict_if_sig("branch_target_fetch"));
      hdl_release(predict_if_sig("flush_in"));
      hdl_release(predict_if_sig("halt"));
      hdl_release(update_if_sig("is_branch"));
      hdl_release(update_if_sig("branch_taken"));
      hdl_release(update_if_sig("branch_offset"));
   endtask

endclass : bpu_backdoor
