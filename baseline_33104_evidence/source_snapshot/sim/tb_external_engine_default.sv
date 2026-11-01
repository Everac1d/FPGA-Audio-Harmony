`timescale 1ns/1ps
`include "sim/tb_external_engine.sv"
module tb_external_engine_default;
    tb_external_engine #(.TEST_RAM_BITS(14),.TEST_GRAIN_LOG2(13)) production();
endmodule
