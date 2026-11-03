`timescale 1ns/1ps
module tb_clip_pause;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,tick=0,rec=0,play=0,abort_play=0,hold_play=0,restart=0;
 reg ready=1,storage_error=0,blocked=0;
 reg signed[15:0] mic=0;
 wire valid,wr,req_ready,rsp,committed,full,active,paused,fault;
 wire[28:0] addr;wire[255:0] wd;reg[255:0] rd=0;
 wire signed[15:0] pcm;wire[3:0] state;wire[20:0] len,pos;
 reg busy=0;integer latency=0,extra_read_latency=0;reg rsp_reg=0;
 reg[255:0] memory[0:127];reg job_wr;reg[28:0] job_addr;reg[255:0] job_data;
 integer requests=0,responses=0,checks=0,consumed=0,saved_pos,saved_lane,saved_count;
 integer i,j,n,pre,tail,drain,guard_count;
 assign req_ready=!busy&&!blocked;assign rsp=rsp_reg;
 pcm_clip_controller #(.MAX_SAMPLES(257),.PREROLL_SAMPLES(5),.TAIL_SAMPLES(7),
   .DRAIN_SAMPLES(3),.ENHANCED_PLAYBACK(1)) dut(
 .clk(clk),.rst_n(rst_n),.sample_tick(tick),.mic_pcm(mic),.record_toggle(rec),.play_toggle(play),
 .abort_play(abort_play),.play_hold(hold_play),.play_restart(restart),.storage_ready(ready),
 .storage_error(storage_error),.req_valid(valid),.req_write(wr),.req_addr(addr),.req_wdata(wd),
 .req_ready(req_ready),.rsp_valid(rsp),.rsp_rdata(rd),.play_pcm(pcm),.rec_state(state),
 .record_samples(len),.play_samples(pos),.record_valid(committed),.record_full(full),
 .play_active(active),.play_paused(paused),.fault(fault));
 always @(posedge clk)begin
   rsp_reg<=0;
   if(!rst_n)begin busy<=0;latency<=0;end
   else if(valid&&req_ready)begin
     if(addr[2:0]!=0||addr>=1024)$fatal(1,"unaligned/out of range DDR request");
     busy<=1;job_wr<=wr;job_addr<=addr;job_data<=wd;
     latency<=3+(requests%29)+(wr ? 0 : extra_read_latency);requests<=requests+1;
   end else if(busy)begin
     if(latency==0)begin
       if(job_wr)memory[job_addr>>3]<=job_data;else rd<=memory[job_addr>>3];
       rsp_reg<=1;busy<=0;responses<=responses+1;
     end else latency<=latency-1;
   end
 end
 task step;begin @(posedge clk);#1;end endtask
 task reset;begin
   @(negedge clk);rst_n=0;rec=0;play=0;abort_play=0;tick=0;hold_play=0;restart=0;blocked=0;
   repeat(4)step();@(negedge clk);rst_n=1;repeat(5)step();
 end endtask
 task command(input integer c);begin
   @(negedge clk);rec=(c==0);play=(c==1);abort_play=(c==2);restart=(c==3);
   step();@(negedge clk);rec=0;play=0;abort_play=0;restart=0;
 end endtask
 task sample(input integer value);begin
   repeat(39)step();@(negedge clk);mic=value;tick=1;
   step();@(negedge clk);tick=0;
   if(fault)$fatal(1,"unexpected clip fault state%0d",state);
 end endtask
 task wait_ready;integer t;begin t=0;
   while(state!=4&&state!=1)begin step();t=t+1;if(t>5000)$fatal(1,"ready timeout state%0d",state);end
 end endtask
 task record_clip(input integer count,input integer base);integer a;begin
   command(0);for(a=0;a<count;a=a+1)sample(base+a);
   if(state==2)command(0);wait_ready();
   if(!committed||len!=count)$fatal(1,"record length/valid count=%0d len=%0d state=%0d committed=%b captured=%0d pending=%b transaction=%b",count,len,state,committed,dut.captured,dut.pending_write,dut.transaction_active);
 end endtask
 task pause_and_resume;integer a,s;begin
   s=state;saved_pos=pos;saved_lane=dut.lane;saved_count=dut.silence_count;
   command(1);
   if(state!=11||!paused||!active)$fatal(1,"pause missing from state%0d",s);
   for(a=0;a<11;a=a+1)begin
     sample(0);checks=checks+1;
     if(pos!=saved_pos||dut.lane!=saved_lane||dut.silence_count!=saved_count)
       $fatal(1,"paused cursor moved from state%0d",s);
   end
   command(1);
   if(state!=s||paused||pos!=saved_pos)$fatal(1,"resume changed cursor/state");
   checks=checks+1;
 end endtask
 task check_sample(input integer base);begin
   repeat(39)step();@(negedge clk);tick=1;
   if(state==7)begin
     if($signed(pcm)!==base+consumed)$fatal(1,"skip/repeat at%0d got%0d",consumed,$signed(pcm));
     consumed=consumed+1;checks=checks+1;
   end
   step();@(negedge clk);tick=0;
   if(fault)$fatal(1,"fault during checked play");
 end endtask
 task stop_with_read_inflight;integer a,t;begin
   extra_read_latency=400;
   command(1);t=0;
   while(state!=7)begin sample(0);t=t+1;if(t>100)$fatal(1,"prefetch timeout before pending-command test");end
   consumed=0;for(a=0;a<16;a=a+1)check_sample(2000);
   t=0;while(!dut.transaction_active)begin step();t=t+1;if(t>100)$fatal(1,"no in-flight read to test");end
   command(2);
   if(state!=4 || !dut.transaction_active)$fatal(1,"stop did not retain old in-flight transaction");
 end endtask
 initial begin
   reset();command(1);command(3);repeat(20)step();
   if(state!=1||committed||active||paused)$fatal(1,"empty session started");
   record_clip(257,-1000);if(!full)$fatal(1,"full flag missing");
   command(1);
   // 即使首次读响应尚未到达也可暂停，不得丢失任何旧事务。
   if(state!=5)$fatal(1,"expected prefetch");pause_and_resume();
   while(state==5)step();
   if(state!=6)$fatal(1,"expected preroll");sample(0);pause_and_resume();
   while(state!=7)sample(0);
   consumed=0;
   while(state==7)begin
     if((consumed%13)==0)pause_and_resume();
     // 参数切换使用此保持信号：它必须冻结准确的原始通道，
     // 包括第 15 通道及末样本边界；预取可以继续完成。
     if((consumed%7)==0)begin
       @(negedge clk);hold_play=1;saved_pos=pos;saved_lane=dut.lane;
       for(j=0;j<5;j=j+1)begin
         sample(0);checks=checks+1;
         if(pos!=saved_pos||dut.lane!=saved_lane||state!=7)$fatal(1,"hold advanced raw cursor");
       end
       @(negedge clk);hold_play=0;
     end
     check_sample(-1000);
   end
   if(consumed!=257||pos!=257||state!=8)$fatal(1,"complete raw play length");
   sample(0);pause_and_resume();while(state==8)sample(0);
   if(state!=9)$fatal(1,"expected drain");pause_and_resume();wait_ready_with_ticks();
   if(!committed||pos!=257)$fatal(1,"natural end metadata");
   // 继续与强制重新开始是不同命令；重新开始须等待
   // 旧读响应返回，再从准确的第 0 个样本开始，并保留一个末尾不完整块。
   command(1);while(state!=7)sample(0);consumed=0;
   repeat(33)check_sample(-1000);
   pause_and_resume();
   while(!dut.transaction_active && dut.read_requested<17)check_sample(-1000);
   command(3);guard_count=0;
   while(state!=7)begin sample(0);guard_count=guard_count+1;if(guard_count>30)$fatal(1,"restart timeout");end
   consumed=0;while(state==7)check_sample(-1000);
   if(consumed!=257)$fatal(1,"restart omitted raw data");wait_ready_with_ticks();
   // 暂停命令与 sample_tick 位于同一边沿时不得消耗样本通道。
   command(1);while(state!=7)sample(0);consumed=0;
   repeat(15)check_sample(-1000);saved_pos=pos;saved_lane=dut.lane;
   @(negedge clk);tick=1;play=1;step();@(negedge clk);tick=0;play=0;
   if(!paused||pos!=saved_pos||dut.lane!=saved_lane)$fatal(1,"pause/sample collision advanced");
   command(1);check_sample(-1000);
   command(2);wait_ready();if(!committed||len!=257)$fatal(1,"abort erased clip");
   record_clip(19,700);command(1);while(state!=7)sample(0);command(1);
   if(!paused)$fatal(1,"short clip pause missing");command(0);wait_ready();
   if(!committed||len!=19)$fatal(1,"record button stop erased clip");
   // 即使旧响应延迟很长，待处理命令仍须保留；而音源中止
   // 必须取消这些命令；之后进入实时音源时不得执行排队动作。
   record_clip(65,2000);
   stop_with_read_inflight();command(0);
   if(!dut.record_pending || state!=4)$fatal(1,"record command dropped while read in flight");
   command(2);while(dut.transaction_active)step();repeat(8)step();
   if(dut.record_pending || dut.restart_pending || state!=4 || len!=65)
     $fatal(1,"abort failed to cancel queued record");checks=checks+1;
   stop_with_read_inflight();command(1);
   if(!dut.restart_pending || state!=4)$fatal(1,"play command dropped while read in flight");
   command(2);while(dut.transaction_active)step();repeat(8)step();
   if(dut.restart_pending || state!=4 || len!=65)$fatal(1,"abort failed to cancel queued play");checks=checks+1;
   stop_with_read_inflight();command(1);
   if(!dut.restart_pending || state!=4)$fatal(1,"queued play not retained");
   guard_count=0;while(state!=7)begin sample(0);guard_count=guard_count+1;if(guard_count>100)$fatal(1,"queued replay timeout");end
   if(pos!=0)$fatal(1,"queued replay did not start from zero");
   consumed=0;while(state==7)check_sample(2000);wait_ready_with_ticks();
   if(consumed!=65)$fatal(1,"queued replay missing samples");checks=checks+1;
   stop_with_read_inflight();command(0);
   if(!dut.record_pending || state!=4)$fatal(1,"queued overwrite not retained");
   guard_count=0;while(state!=2)begin step();guard_count=guard_count+1;if(guard_count>1000)$fatal(1,"queued record timeout");end
   sample(901);sample(902);command(0);wait_ready();
   if(len!=2 || !committed || dut.record_pending || dut.restart_pending)$fatal(1,"queued overwrite metadata");checks=checks+1;
   extra_read_latency=0;
   record_clip(1,-12345);command(1);while(state!=7)sample(0);pause_and_resume();
   consumed=0;check_sample(-12345);wait_ready_with_ticks();
   if(pos!=1||len!=1)$fatal(1,"single lane replay");
   command(1);while(state!=7)sample(0);command(1);storage_error=1;
   repeat(3)step();if(!fault||committed||state!=10||paused)$fatal(1,"paused storage fault");
   storage_error=0;reset();if(committed||len!=0||pos!=0||paused)$fatal(1,"reset retained volatile clip");
   $display("PASS CLIP_PAUSE checks=%0d exact257samples all_prefetch_preroll_play_tail_drain_pause holds lane15 final_lane restart_ddr_inflight pending_record_play_cancel overwrite one_sample reset fault",checks);
   $finish;
 end
 task wait_ready_with_ticks;integer t;begin
   t=0;while(state!=4&&state!=1)begin sample(0);t=t+1;if(t>100)$fatal(1,"end timeout");end
 end endtask
 initial begin #100000000;$fatal(1,"watchdog");end
endmodule
