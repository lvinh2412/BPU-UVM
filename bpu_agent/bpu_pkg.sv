package bpu_pkg;
import uvm_pkg::*;
`include "uvm_macros.svh"


typedef uvm_config_db#(virtual bpu_if) bpu_vif_config;
`include "bpu_item.sv"
`include "bpu_monitor.sv"
`include "bpu_sequencer.sv"
`include "bpu_seqs.sv"
`include "bpu_driver.sv"
`include "bpu_agent.sv"
`include "bpu_env.sv"
`include "bpu_drive_seqs.sv"

endpackage
