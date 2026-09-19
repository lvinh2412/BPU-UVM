// 64 bit option required for AWS labs
-64

-uvmhome $UVMHOME

// options
+UVM_VERBOSITY=UVM_MEDIUM

// default timescale
-timescale 1ns/100ps

// PLI/VPI read-write-connectivity access — required by the backdoor
// (uvm_hdl_read / uvm_hdl_force / uvm_hdl_deposit / uvm_hdl_release)
-access +rwc

// include directories
-incdir ../bpu_agent
-incdir ../clock_and_reset
-incdir ../bpu_module
-incdir .
-incdir ./tests

// =====================================================================
// compile files  (order matters: packages/interfaces -> DUT -> tops)
// =====================================================================

// BPU UVC package and interface
../bpu_agent/bpu_pkg.sv
../bpu_agent/bpu_if.sv

// clock and reset UVC package and interface
../clock_and_reset/clock_and_reset_pkg.sv
../clock_and_reset/clock_and_reset_if.sv

// DUT-level module env package (reference + scoreboard + coverage + backdoor)
// NOTE: depends on the UVC packages above, so it must compile after them.
../bpu_module/bpu_module_pkg.sv

// BPU DUT RTL (submodules before top)
../rtl/bpu_reg.v
../rtl/bpu_predictor.v
../rtl/bpu_ctrl.v
../rtl/bpu_top.v

// clock generator module
clkgen.sv

// top module for UVM test environment
bpu_tb_top.sv

// accelerated top module for interface instances + DUT
bpu_hw_top.sv
