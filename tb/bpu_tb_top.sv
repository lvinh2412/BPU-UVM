module bpu_tb_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import bpu_pkg::*;
  import clock_and_reset_pkg::*;
  import bpu_module_pkg::*;

  `include "bpu_drive_vseqs.sv"
  `include "bpu_pipe_helper.sv"
  `include "bpu_tb.sv"
  `include "bpu_test_lib.sv"

  initial begin
    bpu_vif_config::set(null, "*.tb.bpu.tx_agent.*", "vif",
                        bpu_hw_top.bpu_if);

    clock_and_reset_vif_config::set(null, "*.tb.clock_and_reset*", "vif",
                                    bpu_hw_top.clk_rst_if);

    uvm_config_db#(virtual clock_and_reset_if)::set(null,
                   "*.tb.module_env.reference", "rst_vif",
                   bpu_hw_top.clk_rst_if);

    run_test();
  end

endmodule
