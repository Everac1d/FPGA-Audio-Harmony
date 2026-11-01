`timescale 1ns/1ps
module tb_clip_controller;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,tick=0,rec=0,play=0,abort_play=0,ready=1,storage_error=0;
 reg signed[15:0] mic=0;
 wire valid,wr,req_ready,rsp,committed,full,active,fault;
 wire[28:0] addr;wire[255:0] wd;reg[255:0] rd=0;
 wire signed[15:0] pcm;wire[3:0] state;wire[20:0] len,pos;
 reg busy=0;reg[7:0] latency=0;reg rsp_reg=0;reg blocked=0;
 reg[255:0] memory[0:15];reg job_wr;reg[28:0] job_addr;reg[255:0] job_data;
 assign req_ready=!busy&&!blocked;assign rsp=rsp_reg;
 pcm_clip_controller #(.MAX_SAMPLES(67),.PREROLL_SAMPLES(5),.TAIL_SAMPLES(7),.DRAIN_SAMPLES(3)) dut(
 .clk(clk),.rst_n(rst_n),.sample_tick(tick),.mic_pcm(mic),.record_toggle(rec),.play_toggle(play),
 .abort_play(abort_play),.storage_ready(ready),.storage_error(storage_error),.req_valid(valid),
 .req_write(wr),.req_addr(addr),.req_wdata(wd),.req_ready(req_ready),.rsp_valid(rsp),.rsp_rdata(rd),
 .play_pcm(pcm),.rec_state(state),.record_samples(len),.play_samples(pos),.record_valid(committed),
 .record_full(full),.play_active(active),.fault(fault));
 integer requests=0,responses=0;
 always @(posedge clk)begin
   rsp_reg<=0;
   if(!rst_n) begin busy<=0;latency<=0;end
   else if(valid&&req_ready)begin
     if(addr[2:0]!=0||addr>=128)$fatal(1,"bad aligned address");
     busy<=1;job_wr<=wr;job_addr<=addr;job_data<=wd;
     latency<=3+(requests%13);requests<=requests+1;
   end else if(busy)begin
     if(latency==0)begin
       if(job_wr)memory[job_addr>>3]<=job_data;else rd<=memory[job_addr>>3];
       rsp_reg<=1;busy<=0;responses<=responses+1;
     end else latency<=latency-1;
   end
 end
 task step;begin @(posedge clk);#1;end endtask
 task reset;begin @(negedge clk);rst_n=0;rec=0;play=0;abort_play=0;tick=0;blocked=0;
 repeat(4)step();@(negedge clk);rst_n=1;repeat(5)step();end endtask
 task command(input integer n);begin @(negedge clk);rec=(n==0);play=(n==1);abort_play=(n==2);
 step();@(negedge clk);rec=0;play=0;abort_play=0;end endtask
 task sample(input integer value);begin repeat(35)step();@(negedge clk);mic=value;tick=1;
 step();@(negedge clk);tick=0;end endtask
 task wait_ready;integer timeout;begin timeout=0;
 while(state!=4&&state!=1)begin step();timeout=timeout+1;if(timeout>5000)$fatal(1,"ready timeout %d",state);end end endtask
 integer i,pre,tail,checks=0;
 task replay(input integer n,input integer base);begin
 command(1);pre=0;tail=0;i=0;
 while(state!=4)begin
   repeat(35)step();@(negedge clk);tick=1;
   if(state==7)begin if(pcm!==$signed(16'(base+i)))$fatal(1,"PCM mismatch at %d got %d",i,pcm);i=i+1;checks=checks+1;end
   else if(state==6)begin if(pcm!==0)$fatal;pre=pre+1;end
   else if(state==8)begin if(pcm!==0)$fatal;tail=tail+1;end
   step();@(negedge clk);tick=0;
   if(fault)$fatal(1,"unexpected storage fault");
 end
 if(i!=n||pre!=5||tail!=7||pos!=n)$fatal(1,"length/roll mismatch n=%d pre=%d tail=%d",i,pre,tail);
 end endtask
 initial begin
 reset();command(1);repeat(30)step();if(state!=1||active||committed)$fatal(1,"empty playback");
 command(0);for(i=0;i<35;i=i+1)sample(100+i);command(0);
 if(committed)$fatal(1,"committed before final write drained");wait_ready();
 if(len!=35||!committed||full)$fatal(1,"partial length");
 if(memory[2][255:48]!==0)$fatal(1,"last burst padding not zero");
 replay(35,100);replay(35,100);
 command(0);for(i=0;i<67;i=i+1)sample(-300+i);wait_ready();
 if(!full||len!=67)$fatal(1,"automatic full");replay(67,-300);
 command(1);while(state!=7)sample(0);sample(0);command(2);wait_ready();
 if(!committed||len!=67)$fatal(1,"stop deleted clip");
 command(0);for(i=0;i<3;i=i+1)sample(900+i);command(0);wait_ready();
 if(len!=3)$fatal(1,"overwrite short length");replay(3,900);
 reset();if(committed||len!=0)$fatal(1,"reset validity");
 command(0);command(0);wait_ready();if(committed||len!=0)$fatal(1,"zero capture");
 command(0);for(i=0;i<9;i=i+1)sample(i);command(2);wait_ready();if(len!=9)$fatal(1,"abort recording lost data");
 // Never hide an unbounded DDR stall by dropping/duplicating PCM.
 command(0);blocked=1;for(i=0;i<50;i=i+1)sample(i);repeat(5)step();
 if(!fault||committed||state!=10)$fatal(1,"write stall not faulted");
 reset();storage_error=1;repeat(3)step();if(!fault||state!=10)$fatal(1,"storage error");
 $display("PASS CLIP_CONTROLLER bit_exact_samples=%0d repeated_playback partial_padding full_stop overwrite reset fault",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"watchdog");end
endmodule
