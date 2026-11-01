`timescale 1ns/1ps
module tb_dual_voice_spectrum;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,valid=0;reg signed[15:0] pcm=0;
 wire signed[15:0] out;wire out_valid;
 audio_effect_core #(.DYNAMIC_CONFIG(1),.DUAL_VOICE_ENABLE(1)) dut(
   .clk(clk),.rst_n(rst_n),.pcm_in(pcm),.pcm_in_valid(valid),.mode(2'd3),
   .pitch_semitones(5'sd4),.pitch_second(5'sd7),.pcm_out(out),.pcm_out_valid(out_valid));
 integer n,received=0,captured=0,fd,combined;
 always @(posedge clk)begin #1;if(rst_n&&out_valid)begin
   if(dut.first_valid!==dut.dual_voice.second_valid)$fatal(1,"spectral core valid mismatch");
   combined=($signed(dut.first_out)+$signed(dut.dual_voice.second_out))/2;
   if($signed(out)!==combined)$fatal(1,"spectral mixer differs from two actual shifted voices");
   if(received>=12000)begin
     $fwrite(fd,"%0d %0d %0d\n",$signed(dut.first_out),$signed(dut.dual_voice.second_out),$signed(out));captured=captured+1;
   end
   received=received+1;
 end end
 initial begin
   fd=$fopen("sim/results/dual_voice_spectrum.txt","w");if(!fd)$fatal(1,"spectrum output open");
   repeat(4)@(negedge clk);rst_n=1;
   for(n=0;n<44768;n=n+1)begin
     @(negedge clk);pcm=$rtoi(12000.0*$sin(6.283185307179586*440.0*n/48828.125));valid=1;
     @(negedge clk);valid=0;repeat(30)@(negedge clk);
   end
   repeat(40)@(negedge clk);$fclose(fd);
   if(received!=44768||captured!=32768||dut.algorithm.fault||dut.dual_voice.second_algorithm.fault)$fatal(1,"spectrum count/fault");
   $display("PASS DUAL_VOICE_SPECTRUM production_grain8192 sample_rate48828_125 input440Hz pitches4_7 actual_RTL_samples=%0d captured=%0d two_voice_mix_exact",received,captured);
   $finish;
 end
 initial begin #50000000;$fatal(1,"spectrum watchdog");end
endmodule
