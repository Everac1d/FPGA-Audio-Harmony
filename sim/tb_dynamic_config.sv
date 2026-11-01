`timescale 1ns/1ps
module tb_dynamic_config;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,valid=0;reg signed[15:0] pcm=0;
 reg[1:0] mode=0;reg signed[4:0] pitch=0;
 wire signed[15:0] out;wire out_valid;
 audio_effect_core #(.RAM_ADDR_BITS(8),.GRAIN_LOG2(6),.GUARD_SAMPLES(4),.DYNAMIC_CONFIG(1)) dut(
   .clk(clk),.rst_n(rst_n),.pcm_in(pcm),.pcm_in_valid(valid),.mode(mode),
   .pitch_semitones(pitch),.pcm_out(out),.pcm_out_valid(out_valid));
 integer history[0:255];integer expected[0:9999],due[0:9999];
 integer head=0,tail=0,cycle=0,index=0,fill=0,startup=0;
 integer n,x,m,p,gap,wr,filled,gain,ratio,a0,a1,b0,b1,aligned,a,b,t,w,mixed,want;
 integer changes=0,holds=0;reg [31:0] random_state=32'h9e3779b9;
 reg [24:0] pitches_seen=0;reg [3:0] modes_seen=0;
 longint phase=0,other,position_a,position_b,frac_a,frac_b,value,square,curve,total;
 function integer round_shift(input longint v,input integer shift);
   longint r;begin
     if(v<0)r=-(((-v)+(64'sd1<<(shift-1)))>>>shift);
     else r=(v+(64'sd1<<(shift-1)))>>>shift;
     if(r>32767)round_shift=32767;else if(r< -32768)round_shift=-32768;
     else round_shift=r;
   end
 endfunction
 task model(input integer xx,input integer mm,input integer pp,output integer yy);
 begin
   if(pp>12)pp=12;if(pp< -12)pp=-12;
   ratio=$rtoi((2.0**(pp/12.0))*1048576.0+0.5);
   wr=index%256;filled=(fill>=70);gain=filled ? ((startup<32768)?startup+256:32768) : 0;
   other=phase^33554432;
   position_a=wr*64'sd1048576-4*64'sd1048576-phase;
   position_b=wr*64'sd1048576-4*64'sd1048576-other;
   frac_a=position_a&1048575;frac_b=position_b&1048575;
   if(filled)begin
     a0=history[(position_a>>>20)&255];a1=history[((position_a>>>20)+1)&255];
     b0=history[(position_b>>>20)&255];b1=history[((position_b>>>20)+1)&255];
     aligned=history[(wr-36)&255];
   end else begin a0=0;a1=0;b0=0;b1=0;aligned=0;end
   a=round_shift(a0*64'sd1048576+(a1-a0)*frac_a,20);
   b=round_shift(b0*64'sd1048576+(b1-b0)*frac_b,20);
   t=((phase>=33554432)?67108864-phase:phase)>>>10;
   square=(t*64'sd1*t)>>>15;curve=(square*(98304-2*t))>>>15;w=curve;
   value=a*64'sd1*w+b*64'sd1*(32768-w);total=round_shift(value,15);
   case(mm)0:begin mixed=xx;gain=32768;end 1:mixed=total;
     2:mixed=(aligned+total)/2;default:mixed=0;endcase
   yy=round_shift(mixed*64'sd1*gain,15);
   history[wr]=xx;index=index+1;
   if(fill<70)fill=fill+1;
   startup=filled?((startup<32768)?startup+256:32768):0;
   phase=(phase+1048576-ratio)&67108863;
 end endtask
 always @(posedge clk)begin
   cycle=cycle+1;#1;
   if(rst_n)begin
     if(head<tail&&cycle==due[head])begin
       if(out_valid!==1||$signed(out)!==expected[head])
         $fatal(1,"dynamic sample%0d cycle%0d got%0d want%0d valid%b",head,cycle,$signed(out),expected[head],out_valid);
       head=head+1;
     end else if(out_valid)$fatal(1,"extra output during hold/idle cycle%0d",cycle);
   end
 end
 initial begin
   for(n=0;n<256;n=n+1)history[n]=0;
   repeat(4)@(negedge clk);rst_n=1;
   for(n=0;n<6000;n=n+1)begin
     random_state=random_state^(random_state<<13);random_state=random_state^(random_state>>17);random_state=random_state^(random_state<<5);
     x=$signed(random_state[15:0]);m=(n/19)%4;
     // Every integral semitone is exercised after fill and repeatedly across
     // every effect. Also retain out-of-range clamp checks at both ends.
     p=(n%29)-14;
     if(p>=-12 && p<=12)pitches_seen[p+12]=1;
     modes_seen[m]=1;
     if((n%19)==0)changes=changes+1;
     model(x,m,p,want);
     @(negedge clk);pcm=x;mode=m;pitch=p;valid=1;
     expected[tail]=want;due[tail]=cycle+18;tail=tail+1;
     @(negedge clk);valid=0;
     gap=32+(random_state[4:0]);
     if((n%101)==0)begin gap=gap+2048;holds=holds+1;end
     // A busy job must remain coherent even if its public controls change in
     // an idle input slot; only accepted sample parameters may affect it.
     mode=3-m;pitch=-p;
     repeat(gap-2)@(negedge clk);
   end
   repeat(40)@(negedge clk);
   if(head!=tail||dut.algorithm.fault)$fatal(1,"pending/missing sample or busy fault");
   if(dut.algorithm.fill_count!=70||dut.algorithm.write_address!=(6000%256))$fatal(1,"history reset on change");
   if(pitches_seen!=25'h1ffffff || modes_seen!=4'hf)$fatal(1,"missing semitone or mode coverage");
   $display("PASS DYNAMIC_CONFIG independent_fixedpoint_samples=%0d mode_changes=%0d long_idle_holds=%0d all25semitones clamp invalidmode rails history_continuity no_skip no_reset",head,changes,holds);
   $finish;
 end
 initial begin #100000000;$fatal(1,"watchdog");end
endmodule
