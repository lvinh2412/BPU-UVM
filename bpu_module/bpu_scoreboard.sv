//------------------------------------------------------------------------------
//
// CLASS: bpu_scoreboard
//
// Vai tro: doi chieu ba ngo ra cua DUT (bpu_nxpc2, bpu_nxpc2_valid, bpu_flush) voi
//   mo hinh tham chieu, moi chu ky mot lan so sanh.
//
//------------------------------------------------------------------------------

// Chon kieu so sanh: uvm_comparer bao het moi truong lech, con comp_equal chi bao
// truong lech DAU TIEN nhung thong bao de doc hon.
typedef enum bit {EQUALITY, UVM} comp_t;

class bpu_scoreboard extends uvm_scoreboard;

   uvm_tlm_analysis_fifo #(bpu_item)          item_fifo;       // quan sat duoc
   uvm_tlm_analysis_fifo #(bpu_expected_item) expected_fifo;   // ky vong

   comp_t compare_policy = UVM;

   // Thong ke, in o report_phase
   int total_compares    = 0;
   int match_count       = 0;
   int miscompare_count  = 0;
   int miscompare_nxpc2  = 0;
   int miscompare_valid  = 0;
   int miscompare_flush  = 0;


   function new(string name="", uvm_component parent=null);
     super.new(name, parent);
     item_fifo     = new("item_fifo",     this);
     expected_fifo = new("expected_fifo", this);
   endfunction

   `uvm_component_utils_begin(bpu_scoreboard)
     `uvm_field_enum(comp_t, compare_policy, UVM_ALL_ON)
   `uvm_component_utils_end

   // So sanh thu cong, chi bao truong lech dau tien
   function bit comp_equal (input bpu_item p, input bpu_expected_item e);
      if (p.bpu_nxpc2 != e.expected_bpu_nxpc2) begin
        `uvm_error("BPU_SB_COMPARE",
                   $sformatf("bpu_nxpc2 mismatch @ pc=0x%08h: actual=0x%08h expected=0x%08h",
                             e.pc, p.bpu_nxpc2, e.expected_bpu_nxpc2))
        return(0);
      end
      if (p.bpu_nxpc2_valid != e.expected_bpu_nxpc2_valid) begin
        `uvm_error("BPU_SB_COMPARE",
                   $sformatf("bpu_nxpc2_valid mismatch @ pc=0x%08h: actual=%0d expected=%0d",
                             e.pc, p.bpu_nxpc2_valid, e.expected_bpu_nxpc2_valid))
        return(0);
      end
      if (p.bpu_flush != e.expected_bpu_flush) begin
        `uvm_error("BPU_SB_COMPARE",
                   $sformatf("bpu_flush mismatch @ pc=0x%08h: actual=%0d expected=%0d",
                             e.pc, p.bpu_flush, e.expected_bpu_flush))
        return(0);
      end
      return(1);
   endfunction

   // So sanh qua uvm_comparer, bao moi truong lech
   function bit comp_uvm(input bpu_item          p,
                         input bpu_expected_item e,
                         uvm_comparer comparer = null);
      if (comparer == null)
         comparer = new();
      comp_uvm  = comparer.compare_field("bpu_nxpc2",
                                         p.bpu_nxpc2, e.expected_bpu_nxpc2, 32);
      comp_uvm &= comparer.compare_field("bpu_nxpc2_valid",
                                         p.bpu_nxpc2_valid, e.expected_bpu_nxpc2_valid, 1);
      comp_uvm &= comparer.compare_field("bpu_flush",
                                         p.bpu_flush, e.expected_bpu_flush, 2);
   endfunction


   task run_phase(uvm_phase phase);

     fork
       check_outputs();
     join
   endtask

   task check_outputs();
     bpu_item          p;
     bpu_expected_item e;
     bit pktcompare;
     forever begin
       // Ngo ra quan sat duoc, do bpu_monitor lay mau
       item_fifo.get_peek_export.get(p);
       `uvm_info(get_type_name(),
                 $sformatf("Scoreboard: Got bpu_item from monitor:\n%s",
                           p.sprint()),
                 UVM_HIGH)

       // Ngo ra ky vong cua CUNG chu ky do, tu mo hinh tham chieu
       expected_fifo.get_peek_export.get(e);
       `uvm_info(get_type_name(),
                 $sformatf("Scoreboard: Got expected_item from reference:\n%s",
                           e.sprint()),
                 UVM_HIGH)

       total_compares++;

       if (compare_policy == UVM)
         pktcompare = comp_uvm(p, e);
       else
         pktcompare = comp_equal(p, e);

       if (pktcompare) begin
          match_count++;
          `uvm_info(get_type_name(),
                    $sformatf("Scoreboard Compare Match @ pc=0x%08h: nxpc2=0x%08h valid=%0d flush=%0d",
                              e.pc, e.expected_bpu_nxpc2, e.expected_bpu_nxpc2_valid, e.expected_bpu_flush),
                    UVM_HIGH)
       end
       else begin
          miscompare_count++;
          // Tach theo tung truong, chi dem duoc o che do UVM: comp_equal dung lai
          // o truong lech dau tien nen khong quy trach nhiem cho cac truong sau.
          if (compare_policy == UVM) begin
             if (p.bpu_nxpc2       != e.expected_bpu_nxpc2)       miscompare_nxpc2++;
             if (p.bpu_nxpc2_valid != e.expected_bpu_nxpc2_valid) miscompare_valid++;
             if (p.bpu_flush       != e.expected_bpu_flush)       miscompare_flush++;
          end
          `uvm_warning(get_type_name(),
                       $sformatf("Scoreboard Error [MISCOMPARE] @ pc=0x%08h:\n  ACTUAL  : nxpc2=0x%08h valid=%0d flush=%0d\n  EXPECTED: nxpc2=0x%08h valid=%0d flush=%0d",
                                 e.pc,
                                 p.bpu_nxpc2, p.bpu_nxpc2_valid, p.bpu_flush,
                                 e.expected_bpu_nxpc2, e.expected_bpu_nxpc2_valid, e.expected_bpu_flush))
       end
     end
   endtask : check_outputs

// Con sot trong fifo nao nghia la hai luong da lech nhip
function void check_phase(uvm_phase phase);
  `uvm_info(get_type_name(), "Scoreboard: Checking BPU Scoreboard", UVM_LOW)
  if (item_fifo.is_empty() && expected_fifo.is_empty())
   `uvm_info(get_type_name(), "Check:\n\n   BPU Scoreboard Empty!\n", UVM_LOW)
  else
  `uvm_error(get_type_name(), $sformatf( { "Check:\n\nWARNING: BPU Scoreboard FIFO's NOT Empty:\n",
    "     item_fifo : %0d     expected_fifo : %0d" } ,
    item_fifo.size(), expected_fifo.size()))
endfunction : check_phase

function void report_phase(uvm_phase phase);
  `uvm_info(get_type_name(), $sformatf( { "Report:\n\n   Scoreboard: BPU Output Compare Statistics \n     " ,
    "     Total compares:\t%0d\n" ,
    "     Matches:\t%0d\n" ,
    "     Miscompares (total):\t%0d\n" ,
    "       - bpu_nxpc2:\t%0d\n" ,
    "       - bpu_nxpc2_valid:\t%0d\n" ,
    "       - bpu_flush:\t%0d\n\n" },
    total_compares, match_count, miscompare_count,
    miscompare_nxpc2, miscompare_valid, miscompare_flush), UVM_LOW)
  if (miscompare_count > 0)
    `uvm_error(get_type_name(),"Status:\n\nSimulation FAILED\n")
  else if (total_compares == 0)
    `uvm_warning(get_type_name(),"Status:\n\nNo compares performed - test may not have run\n")
  else
    `uvm_info(get_type_name(),"Status:\n\nSimulation PASSED\n", UVM_NONE)
endfunction : report_phase

endclass : bpu_scoreboard
