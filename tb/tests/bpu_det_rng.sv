//------------------------------------------------------------------------------
// FILE: tests/bpu_det_rng.sv
//
// bit random
//------------------------------------------------------------------------------
`ifndef BPU_DET_RNG_SV
`define BPU_DET_RNG_SV

class bpu_det_rng;

  bit [31:0] s;

  function new(bit [31:0] seed = 32'd1);
    s = seed;
  endfunction

  function bit next_bit();
    s = s * 32'd1664525 + 32'd1013904223;
    return s[16];
  endfunction

  // n bit ghep thanh mot so nguyen khong dau.
  function bit [31:0] next_bits(int n);
    bit [31:0] r = 32'd0;
    for (int i = 0; i < n; i++) r[i] = next_bit();
    return r;
  endfunction

endclass : bpu_det_rng

`endif
