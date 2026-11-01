`timescale 1ns/1ps
module tb_dual_voice_core;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,valid=0;reg signed[15:0] pcm=0;
 reg[1:0] mode=0;reg signed[4:0] pitch=0,pitch2=7;
 wire signed[15:0] out;wire out_valid;
 audio_effect_core #(.RAM_ADDR_BITS(8),.GRAIN_LOG2(6),.GUARD_SAMPLES(4),
   .DYNAMIC_CONFIG(1),.DUAL_VOICE_ENABLE(1)) dut(
   .clk(clk),.rst_n(rst_n),.pcm_in(pcm),.pcm_in_valid(valid),.mode(mode),
   .pitch_semitones(pitch),.pitch_second(pitch2),.pcm_out(out),.pcm_out_valid(out_valid));
 integer history[0:1][0:255];integer expected[0:15999],due[0:15999];
 integer head=0,tail=0,cycle=0,index=0,fill=0,startup=0;
 integer n,k,x,m,p,q,gap,want,y1,y2,v,holds=0,changed=0;
 reg[624:0] pairs_seen=0;reg[3:0] modes_seen=0;
 reg[31:0] random_state=32'h3288ab4f;
 longint phase[0:1];
 function integer round_shift(input longint value,input integer shift);
   longint r;begin
     if(value<0)r=-(((-value)+(64'sd1<<(shift-1)))>>>shift);
     else r=(value+(64'sd1<<(shift-1)))>>>shift;
     if(r>32767)round_shift=32767;else if(r< -32768)round_shift=-32768;
     else round_shift=r;
   end
 endfunction
 task voice_model(input integer voice,input integer xx,input integer mm,input integer pp,output integer yy);
 integer wr,filled,gain,ratio,a0,a1,b0,b1,aligned,a,b,t,w,mixed;
 longint other,position_a,position_b,frac_a,frac_b,value,square,curve,total;
 begin
   if(pp>12)pp=12;if(pp< -12)pp=-12;
   ratio=$rtoi((2.0**(pp/12.0))*1048576.0+0.5);
   wr=index%256;filled=(fill>=70);gain=filled ? ((startup<32768)?startup+256:32768) : 0;
   other=phase[voice]^33554432;
   position_a=wr*64'sd1048576-4*64'sd1048576-phase[voice];
   position_b=wr*64'sd1048576-4*64'sd1048576-other;
   frac_a=position_a&1048575;frac_b=position_b&1048575;
   if(filled)begin
     a0=history[voice][(position_a>>>20)&255];a1=history[voice][((position_a>>>20)+1)&255];
     b0=history[voice][(position_b>>>20)&255];b1=history[voice][((position_b>>>20)+1)&255];
     aligned=history[voice][(wr-36)&255];
   end else begin a0=0;a1=0;b0=0;b1=0;aligned=0;end
   a=round_shift(a0*64'sd1048576+(a1-a0)*frac_a,20);
   b=round_shift(b0*64'sd1048576+(b1-b0)*frac_b,20);
   t=((phase[voice]>=33554432)?67108864-phase[voice]:phase[voice])>>>10;
   square=(t*64'sd1*t)>>>15;curve=(square*(98304-2*t))>>>15;w=curve;
   value=a*64'sd1*w+b*64'sd1*(32768-w);total=round_shift(value,15);
   case(mm)0:begin mixed=xx;gain=32768;end 1:mixed=total;
     2:mixed=(aligned+total)/2;default:mixed=0;endcase
   yy=round_shift(mixed*64'sd1*gain,15);
   history[voice][wr]=xx;
   phase[voice]=(phase[voice]+1048576-ratio)&67108863;
 end endtask
 always @(posedge clk)begin
   cycle=cycle+1;#1;
   if(rst_n)begin
     if(head<tail&&cycle==due[head])begin
       if(out_valid!==1||$signed(out)!==expected[head])
         $fatal(1,"dual sample%0d cycle%0d got%0d want%0d valid%b",head,cycle,$signed(out),expected[head],out_valid);
       head=head+1;
     end else if(out_valid)$fatal(1,"extra output during hold cycle%0d",cycle);
     if(dut.first_valid!==dut.dual_voice.second_valid)$fatal(1,"voice valid disagreement");
   end
 end
 initial begin
   phase[0]=0;phase[1]=0;
   for(v=0;v<2;v=v+1)for(n=0;n<256;n=n+1)history[v][n]=0;
   repeat(4)@(negedge clk);rst_n=1;
   for(n=0;n<12000;n=n+1)begin
     random_state=random_state^(random_state<<13);random_state=random_state^(random_state>>17);random_state=random_state^(random_state<<5);
     case(n%31)0:x=-32768;1:x=32767;2:x=-1;3:x=0;default:x=$signed(random_state[15:0]);endcase
     m=(n<2500)?3:((n/19)%4);
     p=((n%625)/25)-12;q=(n%25)-12;
     if(m==3)pairs_seen[(p+12)*25+q+12]=1;
     modes_seen[m]=1;
     voice_model(0,x,(m==3)?1:m,p,y1);voice_model(1,x,1,q,y2);
     want=(m==3)?(y1+y2)/2:y1;
     index=index+1;
     startup=(fill>=70)?((startup<32768)?startup+256:32768):0;
     if(fill<70)fill=fill+1;
     @(negedge clk);pcm=x;mode=m;pitch=p;pitch2=q;valid=1;
     expected[tail]=want;due[tail]=cycle+18;tail=tail+1;
     @(negedge clk);valid=0;
     gap=32+(random_state[4:0]);
     if((n%101)==0)begin gap=gap+2048;holds=holds+1;end
     // Busy public controls must not change an already accepted output job.
     mode=3-m;pitch=-p;pitch2=-q;changed=changed+1;
     repeat(gap-2)@(negedge clk);
   end
   repeat(40)@(negedge clk);
   if(head!=tail||dut.algorithm.fault||dut.dual_voice.second_algorithm.fault)$fatal(1,"pending/busy fault");
   if(dut.algorithm.fill_count!=70||dut.algorithm.write_address!=(12000%256))$fatal(1,"first history reset");
   if(dut.dual_voice.second_algorithm.fill_count!=70||dut.dual_voice.second_algorithm.write_address!=(12000%256))$fatal(1,"second history reset");
   if(pairs_seen!={625{1'b1}}||modes_seen!=4'hf)$fatal(1,"missing pair/mode coverage");
   $display("PASS DUAL_VOICE_CORE independent_fixedpoint_samples=%0d all625pitch_pairs modes012_bit_exact mode3_two_independent_ratios rails symmetric_average job_latching holds=%0d history_continuity",head,holds);
   $finish;
 end
 initial begin #100000000;$fatal(1,"watchdog");end
endmodule
