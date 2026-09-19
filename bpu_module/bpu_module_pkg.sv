package bpu_module_pkg;
import uvm_pkg::*;
`include "uvm_macros.svh"

import bpu_pkg::*;

// Thu tu include quan trong -- moi tep dung cac tep phia tren no:
//   expected_item  chi cho du lieu, khong phu thuoc gi
//   reference      tu no `include state / predictor / ctrl
//   scoreboard     dung bpu_item + expected_item
//   coverage       dung expected_item + mot handle toi reference
//   backdoor       doc lap
//   module_env     boc tat ca nhung cai tren
`include "bpu_expected_item.sv"
`include "bpu_reference.sv"
`include "bpu_scoreboard.sv"
`include "bpu_coverage.sv"
`include "bpu_backdoor.sv"
`include "bpu_module_env.sv"

endpackage
