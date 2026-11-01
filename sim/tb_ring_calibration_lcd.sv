`timescale 1ns/1ps
`include "sim/tb_harmony_lcd.sv"
module tb_ring_calibration_lcd;tb_harmony_lcd #(.TEST_RING_TUNE(1)) tuning();endmodule
