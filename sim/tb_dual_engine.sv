`timescale 1ns/1ps
`include "sim/tb_external_engine.sv"
module tb_dual_engine;
    tb_external_engine #(.TEST_DUAL_ENABLE(1)) dual_panel();
endmodule
