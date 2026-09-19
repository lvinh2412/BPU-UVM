
//------------------------------------------------------------------------------
//
// CLASS: bpu_base_test
//
// Vai tro: tao testbench, khong lam gi khac. Moi test trong tests/ deu ke thua tu
// day, truc tiep hoac qua mot base class cua nhom.
//
//------------------------------------------------------------------------------

class bpu_base_test extends uvm_test;

  `uvm_component_utils(bpu_base_test)

  bpu_tb tb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  function void build_phase(uvm_phase phase);
    uvm_config_int::set(this, "*", "recording_detail", 1);
    super.build_phase(phase);
    tb = bpu_tb::type_id::create("tb", this);
  endfunction : build_phase

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction : end_of_elaboration_phase

  function void start_of_simulation_phase(uvm_phase phase);
    `uvm_info(get_type_name(), {"start of simulation for ", get_full_name()}, UVM_HIGH);
  endfunction : start_of_simulation_phase

  task run_phase(uvm_phase phase);
    // Drain time de duong ong chuyen huong va mo hinh tham chieu chay het nhung chu
    // ky con dang do sau khi sequence cuoi cung ha objection
    uvm_objection obj = phase.get_objection();
    obj.set_drain_time(this, 2000ns);
  endtask : run_phase

  function void check_phase(uvm_phase phase);
    // Bao cac muc config_db khong ai doc -- thuong la go sai chuoi scope
    check_config_usage();
  endfunction

endclass : bpu_base_test

//==============================================================================
`ifndef BPU_PHT_STATES
`define BPU_PHT_STATES
`define SNT 2'b00
`define WNT 2'b01
`define WT  2'b10
`define ST  2'b11
`endif


//==============================================================================
// INCLUDE TEST -- ca 44 muc testplan trong mot lan bien dich.
//==============================================================================

// Ha tang dung chung, cac nhom 15.x va 16.x deu dung:
//   bpu_det_rng      nguon bit tat dinh, giong nhau tren xrun va Questa
//   bpu_coherent_gen bo sinh kich thich nhat quan duong ong
`include "tests/bpu_det_rng.sv"
`include "tests/bpu_coherent_gen.sv"

`include "tests/hyb_btb_tests.sv"          // 3.1 - 3.3    BTB
`include "tests/hyb_pht_ghr_tests.sv"      // 4.1 - 4.4, 5.1, 5.2, 7.1
`include "tests/hyb_carry_tests.sv"        // 14.1 - 14.4  duong ong carry-down
`include "tests/hyb_redirect_tests.sv"     // 10.x, 11.x, 12.x, 13.1
`include "tests/hyb_predict_tests.sv"      // 8.1, 8.2, 9.1
`include "tests/hyb_rst_halt_tests.sv"     // 1.1, 1.2, 2.1, 2.2
`include "tests/hyb_choice_tests.sv"       // 6.1 - 6.4    bo chon tournament
`include "tests/global_pht_tests.sv"       // 5.3          trung chi muc gshare
`include "tests/global_pht_extra_tests.sv" // 5.4          doc/ghi global PHT
`include "tests/stress_tests.sv"           // 16.3         BTB day
`include "tests/hyb_stress_tests.sv"       // 16.1, 16.2
`include "tests/hyb_pattern_tests.sv"      // 15.1 - 15.6  cac mau re nhanh
