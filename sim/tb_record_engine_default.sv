// 使用正式参数：重点验证真实 8192 窗口下完整的和声加 4 半音回放。
// 小参数测试组另行覆盖全部三种音效及控制。
`timescale 1ns/1ps
`ifndef TB_RECORD_ENGINE_DEFAULT_SV
`define TB_RECORD_ENGINE_DEFAULT_SV
// 验证原始录音、音源选择、真实 I2S 及控制的集成行为。
// 此测试不替代独立的 DSP 数值参考验证。
module tb_record_engine_default #(
    parameter integer TEST_RAM_BITS=14,
    parameter integer TEST_GRAIN_LOG2=13
);
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,key_mode_n=1,key_gain_n=1;
    reg [3:0] mic_sd=0;
    wire mic_bclk,mic_ws,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812,uart_tx,led_ck,led_da;
    reg ddr_ready=1,ddr_error=0;
    wire req_valid,req_write,req_ready;
    wire [28:0] req_addr;wire[255:0]req_wdata;
    reg rsp_valid=0;reg[255:0]rsp_rdata=0;
    wire[3:0]rec_state;wire[20:0]record_samples,record_progress,play_samples;
    wire record_valid,record_full,storage_fault,active_source;
    wire[1:0]active_algorithm_mode;wire signed[4:0]active_pitch_semitones;wire[2:0]gain_index;
    audio_record_engine #(.DEBOUNCE_CYCLES(3),.LONG_PRESS_CYCLES(24),
        .POR_CYCLES(8),.STARTUP_FRAMES(3),.UART_REPORT_CYCLES(10000000),
        .MAX_SAMPLES(512),.RAM_ADDR_BITS(TEST_RAM_BITS),.GRAIN_LOG2(TEST_GRAIN_LOG2)) dut(
        .clk(clk),.rst_n(rst_n),.key_mode_n(key_mode_n),.key_gain_n(key_gain_n),.mic_sd(mic_sd),
        .mic_bclk(mic_bclk),.mic_ws(mic_ws),.HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN),
        .PA_EN(PA_EN),.WS2812(WS2812),.uart_tx(uart_tx),.led_ck(led_ck),.led_da(led_da),
        .ddr_ready(ddr_ready),.ddr_error(ddr_error),.ddr_diag(16'h040F),.ddr_failure(545'd0),.req_valid(req_valid),.req_write(req_write),
        .req_addr(req_addr),.req_wdata(req_wdata),.req_ready(req_ready),.rsp_valid(rsp_valid),.rsp_rdata(rsp_rdata),
        .rec_state(rec_state),.record_samples(record_samples),.record_progress(record_progress),.play_samples(play_samples),
        .record_valid(record_valid),.record_full(record_full),.storage_fault(storage_fault),.active_source(active_source),
        .active_algorithm_mode(active_algorithm_mode),.active_pitch_semitones(active_pitch_semitones),.gain_index(gain_index));
    integer checks=0,record_input_checks=0,play_input_checks=0,zero_input_checks=0;
    integer isolated_samples=0,core_outputs=0,dac_frames=0,nonzero_frames=0,safe_commits=0;
    task check(input bit condition,input[511:0]message);
        begin checks=checks+1;if(!condition)begin $display("FAIL %0s state=%0d",message,rec_state);$fatal(1);end end
    endtask
    task step;begin @(posedge clk);#2;end endtask
    task wait_frames(input integer count);
        integer k;
        begin k=0;while(k<count)begin @(posedge clk);if(dut.frame_ce)k=k+1;end @(negedge clk);end
    endtask
    task wait_state(input integer wanted,input integer limit);
        integer n;
        begin n=0;while(rec_state!=wanted)begin wait_frames(1);n=n+1;if(n>limit)$fatal(1,"state timeout want=%0d actual=%0d",wanted,rec_state);end end
    endtask
    task solo(input bit gain_key,input bit long_press);
        begin @(negedge clk);key_mode_n=gain_key;key_gain_n=!gain_key;
            repeat(long_press?36:9)@(negedge clk);key_mode_n=1;key_gain_n=1;
            repeat(12)@(negedge clk);end
    endtask
    task chord(input bit long_press);
        begin @(negedge clk);key_mode_n=0;key_gain_n=0;
            repeat(long_press?36:9)@(negedge clk);key_mode_n=1;key_gain_n=1;
            repeat(12)@(negedge clk);end
    endtask

    // 按序、可变延时的 DDR 应用端口事务模型，包含不完整的 BL8 块。
    reg memory_busy=0,job_write;reg[28:0]job_addr;reg[255:0]job_data;
    reg[7:0]latency=0;reg[255:0]memory[0:31];integer requests=0;
    assign req_ready=!memory_busy;
    always @(posedge clk)begin
        rsp_valid<=0;
        if(!rst_n)begin memory_busy<=0;latency<=0;end
        else if(req_valid&&req_ready)begin
            check(req_addr[2:0]==0&&req_addr<256,"DDR request address/alignment");
            memory_busy<=1;job_write<=req_write;job_addr<=req_addr;job_data<=req_wdata;
            latency<=3+(requests%11);requests=requests+1;
        end else if(memory_busy)begin
            if(latency==0)begin
                if(job_write)memory[job_addr>>3]<=job_data;else rsp_rdata<=memory[job_addr>>3];
                memory_busy<=0;rsp_valid<=1;
            end else latency<=latency-1'b1;
        end
    end

    // 物理麦克风 I2S 字：中央通道为第 3 路的右声道时隙。
    wire board_run=rst_n&&dut.run_n;
    reg[5:0]mic_position=0;integer mic_frame=0,mic_epoch=0,lane;
    reg[23:0]word_value;
    function[23:0] source_word(input integer frame,input integer channel,input integer epoch);
        integer pcm;
        begin
            pcm=((frame%64)-32)*128+300+epoch*5000;
            if(channel!=7)pcm=(frame*31+channel*1777)^16'h65a1;
            source_word={pcm[15:0],8'h53};
        end
    endfunction
    always @(negedge mic_bclk or negedge board_run)begin
        if(!board_run)begin mic_position=0;mic_frame=0;mic_sd=0;end
        else begin
            if(mic_position==63)mic_frame=mic_frame+1;
            mic_position=mic_position+1'b1;#2;
            check(mic_ws===mic_position[5],"physical microphone WS phase");
            for(lane=0;lane<4;lane=lane+1)begin
                word_value=source_word(mic_frame,lane*2+mic_position[5],mic_epoch);
                mic_sd[lane]=(mic_position[4:0]>=1&&mic_position[4:0]<=24)?word_value[24-mic_position[4:0]]:0;
            end
        end
    end

    reg signed[15:0]saved_pcm[0:511];integer saved_count=0,next_play_index=0;
    reg[3:0]prior_state=0;
    reg frame_before,fade_before,amp_before,pa_before,run_before;
    reg[1:0]mode_before,alg_before;reg signed[4:0]pitch_before;reg source_before;
    reg expected_pa=1;
    reg[23:0]expected_word;
    integer cycle=0,last_rx_cycle=0;
    always @(posedge clk)begin
        cycle=cycle+1;
        frame_before=dut.frame_ce;fade_before=dut.fade_zero;amp_before=dut.amplifier_frame_ready;
        pa_before=PA_EN;run_before=dut.run_n;mode_before=dut.active_mode;
        alg_before=active_algorithm_mode;pitch_before=active_pitch_semitones;source_before=active_source;
        // 复位同时开启新的帧检查周期：首个全零发送
        // 帧在首次 frame_ce 之前出现，此时功放处于复位静音状态。
        if(!board_run)begin saved_count=0;next_play_index=0;last_rx_cycle=0;expected_pa=1;end
        else begin
            if(dut.clip_record&&(rec_state==1||rec_state==4))saved_count=0;
            if(rec_state==5&&prior_state!=5)next_play_index=0;
            if(dut.rx_valid)begin
                if(last_rx_cycle!=0)check(cycle-last_rx_cycle==1024,"unchanged sample cadence 1024 clocks");
                last_rx_cycle=cycle;
            end
            if(dut.recorder.capture)begin
                expected_word=source_word(mic_frame,7,mic_epoch);
                check(dut.central_pcm===expected_word[23:8],"recorded central word matches external I2S");
                saved_pcm[saved_count]=dut.central_pcm;saved_count=saved_count+1;record_input_checks=record_input_checks+1;
                check(PA_EN===1,"amplifier muted while recording");
            end
            if(dut.pipeline_rst_n&&dut.rx_valid&&active_source)begin
                if(rec_state==7)begin
                    check(play_samples==next_play_index,"play sample progression no skip/duplicate");
                    check(dut.core.pcm_in===saved_pcm[next_play_index],"actual algorithm input equals stored raw PCM");
                    if(dut.central_pcm!==saved_pcm[next_play_index])isolated_samples=isolated_samples+1;
                    next_play_index=next_play_index+1;play_input_checks=play_input_checks+1;
                end else begin
                    check(dut.core.pcm_in===16'sd0,"preroll/tail/idle input is zero, not live mic");zero_input_checks=zero_input_checks+1;
                end
            end
            if(dut.pipeline_rst_n)check(dut.underflow==0&&dut.overflow==0,"nominal FIFO underflow/overflow");
            if(frame_before)expected_pa=!dut.playback_ready;
        end
        prior_state=rec_state;
        #1;
        if(run_before&&dut.run_n&&dut.mic_ready)begin
            if(frame_before)check(PA_EN===expected_pa,"PA complete-frame decision");
            else check(PA_EN===pa_before,"PA cannot truncate stereo frame");
            if(active_source!=source_before||active_algorithm_mode!=alg_before||active_pitch_semitones!=pitch_before)begin
                check(frame_before&&fade_before&&mode_before==0&&!amp_before,"source/effect commit after final muted frame");
                safe_commits=safe_commits+1;
            end
        end
        if(dut.pipeline_rst_n&&dut.core_valid)begin
            check((^dut.core_out)!==1'bx,"algorithm output known");core_outputs=core_outputs+1;
        end
        check((^{HP_WS,HP_DIN,PA_EN})!==1'bx,"audio output pins known");
    end

    // 检查串行 DAC 帧格式及双时隙复制；DSP 数值由其他测试检查。
    reg[5:0]dac_position=0;reg[15:0]shift=0,right_word=0;
    always @(posedge HP_BCK or negedge board_run)begin
        if(!board_run)begin dac_position=0;shift=0;right_word=0;end
        else begin
            check(HP_WS===dac_position[5],"physical DAC WS phase");
            if(dac_position[4:0]<16)begin check(HP_DIN===0,"DAC leading padding");shift=0;end
            else begin
                shift={shift[14:0],HP_DIN};
                if(dac_position==31)right_word=shift;
                if(dac_position==63)begin
                    check(shift===right_word,"DAC stereo slots identical");
                    check(PA_EN===expected_pa,"final DAC frame PA held");
                    dac_frames=dac_frames+1;if(shift!=0)nonzero_frames=nonzero_frames+1;
                end
            end
            dac_position=dac_position+1'b1;
        end
    end

    integer clip_length=0,replays=0,starting_play_checks=0,i,n;
    reg[2:0]expected_gain[0:4];reg signed[4:0]expected_pitch[0:5];
    task replay(input bit vary_gain);
        integer k;
        begin
            starting_play_checks=play_input_checks;mic_epoch=mic_epoch+1;
            chord(0);wait_state(6,30);
            if(vary_gain)for(k=0;k<5;k=k+1)begin solo(1,0);wait_frames(3);check(gain_index==expected_gain[k],"integrated five-gain selection");end
            wait_state(4,25000);wait_frames(300);
            check(play_input_checks-starting_play_checks==clip_length,"each recorded sample delivered once including last");
            check(record_samples==clip_length&&record_valid&&play_samples==clip_length,"complete replay retains original clip");
            check(PA_EN===1&&dut.active_mode==0,"replay tail drains and fades fully to mute");replays=replays+1;
        end
    endtask
    initial begin
        repeat(8)@(negedge clk);rst_n=1;wait(dut.mic_ready);wait_frames(6);
        check(!active_source&&dut.active_mode==0&&gain_index==0&&!record_valid,"production reset defaults");
        chord(1);wait_frames(8);solo(0,0);wait_state(2,10);
        while(dut.recorder.captured<350)wait_frames(1);
        solo(0,0);wait_state(4,20);wait_frames(3);clip_length=record_samples;
        check(clip_length==saved_count&&clip_length>=350&&record_valid,"production raw clip committed");
        for(i=0;i<clip_length;i=i+1)check(memory[i/16][(i%16)*16+:16]===saved_pcm[i],"production DDR raw sample");
        solo(0,1);wait_frames(8);solo(0,1);wait_frames(8);solo(1,1);wait_frames(8);
        check(active_algorithm_mode==2&&active_pitch_semitones==4,"production harmony+4 selected");
        replay(0);
        check(replays==1&&play_input_checks==clip_length&&isolated_samples==clip_length&&nonzero_frames>20,"production 8192-window complete wet and dry replay");
        check(!dut.core.algorithm.fault&&dut.underflow==0&&dut.overflow==0,"production DSP/queue no fault");
        @(negedge clk);ddr_error=1;step();check(PA_EN===1,"production DDR error mute");
        @(negedge clk);rst_n=0;repeat(8)@(negedge clk);ddr_error=0;rst_n=1;
        wait(dut.mic_ready);wait_frames(6);
        check(!record_valid&&record_samples==0&&record_progress==0&&PA_EN===1,"production reset invalidates clip");
        $display("PASS RECORD_ENGINE_DEFAULT RAM_BITS=%0d GRAIN_LOG2=%0d checks=%0d raw_captured=%0d replay_input_samples=%0d zero_input_samples=%0d isolated_from_mic=%0d full_harmony_replays=%0d core_outputs=%0d DAC_frames=%0d nonzero_frames=%0d safe_commits=%0d",TEST_RAM_BITS,TEST_GRAIN_LOG2,checks,record_input_checks,play_input_checks,zero_input_checks,isolated_samples,replays,core_outputs,dac_frames,nonzero_frames,safe_commits);
        $finish;
    end
    initial begin #3000000000;$fatal(1,"engine integration timeout");end
endmodule
`endif
