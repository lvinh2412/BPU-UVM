// gen clk
//
`ifdef IXCOM_1X
module clkgen(output logic clock=0, input run_clock, logic [31:0] clock_period);
  always begin
    #10;
    clock = ~clock;
  end
endmodule

`else
module clkgen(output logic clock=0, input run_clock, logic [31:0] clock_period);
  `ifdef IXCOM_UXE
  initial $ixc_ctrl("map_delays");
  `endif
  always begin
    #(clock_period/2);
    clock = (run_clock == 1) ? ~clock : 0;
  end
endmodule
`endif //IXCOM_1X
