`timescale 1ns/1ps
`ifndef TB_HARMONY_TUNED_ENGINE_SV
`define TB_HARMONY_TUNED_ENGINE_SV
// 验证原始录音、音源选择、真实 I2S 及控制的集成行为。
// 此测试不替代独立的 DSP 数值参考验证。
module tb_harmony_tuned_engine #(
    parameter integer TEST_RAM_BITS=8,
    parameter integer TEST_GRAIN_LOG2=6,
    parameter integer TEST_DUAL_ENABLE=1
);
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,key_mode_n=1,key_gain_n=1;
    reg [3:0] button_n=4'b1111;
    reg enc_gain_sw_n=1,enc_gain_clk=1,enc_gain_dt=1;
    reg enc_pitch_sw_n=1,enc_pitch_clk=1,enc_pitch_dt=1;
    wire soft_reset_request;
    reg [3:0] mic_sd=0;
    wire mic_bclk,mic_ws,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812,uart_tx,led_ck,led_da;
    reg ddr_ready=1,ddr_error=0;
    wire req_valid,req_write,req_ready;
    wire [28:0] req_addr;wire[255:0]req_wdata;
    reg rsp_valid=0;reg[255:0]rsp_rdata=0;
    wire[3:0]rec_state;wire[31:0]record_samples,record_progress,play_samples;
    wire ring_tuning;wire signed[12:0]ring_calibration_margin;wire[15:0]ring_noise_floor,ring_mean_level;
    wire record_valid,record_full,storage_fault,active_source;
    wire[1:0]active_algorithm_mode;wire signed[4:0]active_pitch_semitones;wire[4:0]gain_index;
    wire signed[4:0]active_pitch_second;wire display_pitch_voice;
    audio_harmony_engine_tuned #(.DEBOUNCE_CYCLES(3),.LONG_PRESS_CYCLES(24),
        .POR_CYCLES(8),.STARTUP_FRAMES(3),.UART_REPORT_CYCLES(10000000),
        .EXTERNAL_CONTROLS(1),.ENHANCED_PLAYBACK(1),.DUAL_VOICE_ENABLE(TEST_DUAL_ENABLE),
        .LONG_RESET_CYCLES(100),.ENCODER_FILTER_CYCLES(3),
        .RING_TUNE_ENABLE(1),.LONG_RING_TUNE_CYCLES(100),.LONG_DIAG_CYCLES(100),.LONG_PITCH_CYCLES(100),.RING_FAST_CYCLES(10),
        .MAX_SAMPLES(4096),.RAM_ADDR_BITS(TEST_RAM_BITS),.GRAIN_LOG2(TEST_GRAIN_LOG2)) dut(
        .clk(clk),.rst_n(rst_n),.key_mode_n(key_mode_n),.key_gain_n(key_gain_n),.mic_sd(mic_sd),
        .button_n(button_n),.enc_gain_sw_n(enc_gain_sw_n),.enc_gain_clk(enc_gain_clk),.enc_gain_dt(enc_gain_dt),
        .enc_pitch_sw_n(enc_pitch_sw_n),.enc_pitch_clk(enc_pitch_clk),.enc_pitch_dt(enc_pitch_dt),.soft_reset_request(soft_reset_request),
        .mic_bclk(mic_bclk),.mic_ws(mic_ws),.HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN),
        .PA_EN(PA_EN),.WS2812(WS2812),.uart_tx(uart_tx),.led_ck(led_ck),.led_da(led_da),
        .ddr_ready(ddr_ready),.ddr_error(ddr_error),.ddr_diag(16'h040F),.ddr_failure(545'd0),.req_valid(req_valid),.req_write(req_write),
        .req_addr(req_addr),.req_wdata(req_wdata),.req_ready(req_ready),.rsp_valid(rsp_valid),.rsp_rdata(rsp_rdata),
        .rec_state(rec_state),.record_samples(record_samples),.record_progress(record_progress),.play_samples(play_samples),
        .record_valid(record_valid),.record_full(record_full),.storage_fault(storage_fault),.active_source(active_source),
        .active_algorithm_mode(active_algorithm_mode),.active_pitch_semitones(active_pitch_semitones),.gain_index(gain_index),
        .active_pitch_second(active_pitch_second),.display_pitch_voice(display_pitch_voice),
        .ring_tuning(ring_tuning),.ring_calibration_margin(ring_calibration_margin),.ring_noise_floor(ring_noise_floor),.ring_mean_level(ring_mean_level));
    wire [TEST_RAM_BITS-1:0] second_write_address;
    generate if(TEST_DUAL_ENABLE!=0)begin: check_dual_core
        assign second_write_address=dut.core.second_algorithm.write_address;
        always @(posedge clk)if(dut.pipeline_rst_n)begin
            if(dut.core.first_valid!==dut.core.second_valid)$fatal(1,"dual valid alignment");
            if(dut.core.algorithm.write_address!==second_write_address)$fatal(1,"dual histories sample count mismatch");
            if(dut.core.second_algorithm.fault)$fatal(1,"second pitch busy fault");
        end
    end else begin: no_second_core
        assign second_write_address=0;
    end endgenerate
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
    task panel_key(input integer index,input bit long_press);
        begin @(negedge clk);button_n[index]=0;
            repeat(long_press?40:12)@(negedge clk);button_n[index]=1;repeat(12)@(negedge clk);end
    endtask
    task gain_hold;begin @(negedge clk);enc_gain_sw_n=0;repeat(140)@(negedge clk);enc_gain_sw_n=1;repeat(12)@(negedge clk);end endtask
    task gain_press;begin @(negedge clk);enc_gain_sw_n=0;repeat(12)@(negedge clk);enc_gain_sw_n=1;repeat(12)@(negedge clk);end endtask
    task pitch_press;begin @(negedge clk);enc_pitch_sw_n=0;repeat(12)@(negedge clk);enc_pitch_sw_n=1;repeat(12)@(negedge clk);end endtask
    task pitch_hold;begin @(negedge clk);enc_pitch_sw_n=0;repeat(140)@(negedge clk);enc_pitch_sw_n=1;repeat(12)@(negedge clk);end endtask
    task phase(input bit pitch_encoder,input [1:0] value);
        begin @(negedge clk);if(pitch_encoder){enc_pitch_clk,enc_pitch_dt}=value;
            else {enc_gain_clk,enc_gain_dt}=value;repeat(12)@(negedge clk);end
    endtask
    task turn(input bit pitch_encoder,input bit up);
        begin phase(pitch_encoder,up?2'b01:2'b10);phase(pitch_encoder,0);
            phase(pitch_encoder,up?2'b10:2'b01);phase(pitch_encoder,3);repeat(8)@(negedge clk);end
    endtask
    // 按序、可变延时的 DDR 应用端口事务模型，包含不完整的 BL8 块。
    reg memory_busy=0,job_write;reg[28:0]job_addr;reg[255:0]job_data;
    reg[7:0]latency=0;reg[255:0]memory[0:255];integer requests=0;
    assign req_ready=!memory_busy;
    always @(posedge clk)begin
        rsp_valid<=0;
        if(!rst_n)begin memory_busy<=0;latency<=0;end
        else if(req_valid&&req_ready)begin
            check(req_addr[2:0]==0&&req_addr<2048,"DDR request address/alignment");
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

    reg signed[15:0]saved_pcm[0:4095];integer saved_count=0,next_play_index=0;
    reg[3:0]prior_state=0;
    reg frame_before,fade_before,amp_before,pa_before,run_before;
    reg[1:0]mode_before,alg_before;reg signed[4:0]pitch_before,second_before;reg source_before;
    reg expected_pa=1;
    reg[23:0]expected_word;
    integer cycle=0,last_rx_cycle=0;
    always @(posedge clk)begin
        cycle=cycle+1;
        frame_before=dut.frame_ce;fade_before=dut.fade_zero;amp_before=dut.amplifier_frame_ready;
        pa_before=PA_EN;run_before=dut.run_n;mode_before=dut.active_mode;
        alg_before=active_algorithm_mode;pitch_before=active_pitch_semitones;second_before=active_pitch_second;source_before=active_source;
        // 复位后的首个串行帧早于首次 frame_ce。
        // 其功放期望状态由复位静音的串行器及功放状态决定，
        // 而非由上一个复位周期最后一个实时帧决定。
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
            if(dut.core.pcm_in_valid&&active_source)begin
                if(rec_state==7)begin
                    check(play_samples==next_play_index,"play sample progression no skip/duplicate");
                    check(dut.recorder.playback_tick,"core/controller sample enable aligned");
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
            if(active_source!=source_before||active_algorithm_mode!=alg_before||active_pitch_semitones!=pitch_before||
               ((TEST_DUAL_ENABLE!=0)&&(active_pitch_second!=second_before)))begin
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


    integer clip_length=0,bookmark=0,prior_inputs=0,prior_outputs=0,prior_write_address=0,n;
    task await_config(input integer algorithm,input integer pitch_value);
        integer timeout;
        begin timeout=0;
            while(active_algorithm_mode!=algorithm || $signed(active_pitch_semitones)!=pitch_value || dut.display_switching)begin
                wait_frames(1);timeout=timeout+1;if(timeout>650)$fatal(1,"config timeout");end
            wait_frames(5);
        end
    endtask
    task assert_paused(input integer expected_position);
        integer saved_in,saved_out,saved_phase,saved_phase2;
        begin
            wait_frames(3);saved_in=play_input_checks;saved_out=dut.played;saved_phase=dut.core.algorithm.write_address;saved_phase2=second_write_address;
            wait_frames(80);
            check(rec_state==11 && play_samples==expected_position,"paused cursor stable");
            check(play_input_checks==saved_in && dut.played==saved_out,"paused producer and FIFO consumer frozen");
            check(dut.core.algorithm.write_address==saved_phase,"paused pitch history preserved");
            check(second_write_address==saved_phase2,"paused second pitch history preserved");
            check(PA_EN===1 && dut.pipeline_rst_n,"paused mute keeps processing state");
            check(record_valid && record_samples==clip_length,"pause retains clip");
        end
    endtask
    task await_second(input integer wanted);
        integer timeout;
        begin timeout=0;
            while($signed(active_pitch_second)!=wanted || dut.display_switching)begin
                wait_frames(1);timeout=timeout+1;if(timeout>650)$fatal(1,"second pitch config timeout");end
            wait_frames(5);
        end
    endtask
    integer selected_commits=0,dual_bookmark=0,tune_gain=0,tune_live=0,tune_commits=0,tune_position=0;
    initial begin
        repeat(8)@(negedge clk);rst_n=1;wait(dut.mic_ready);wait_frames(5);
        check(!active_source && gain_index==10 && active_algorithm_mode==0 && active_pitch_semitones==0,"unified harmony ordinary defaults");
        gain_press;wait_frames(350);check(dut.active_mode==1 && PA_EN===0,"external rotary press enables live microphone");
        panel_key(0,0);wait_frames(350);check(active_source && dut.active_mode==0,"external mode key selects clip");
        panel_key(2,0);wait_state(2,10);
        while(dut.recorder.captured<2600)wait_frames(1);
        panel_key(2,0);wait_state(4,20);clip_length=record_samples;
        check(clip_length==saved_count && clip_length>=2600 && record_valid,"external key records exact raw clip");
        for(n=0;n<clip_length;n=n+1)check(memory[n/16][(n%16)*16+:16]===saved_pcm[n],"DDR samples exact");
        panel_key(3,0);wait_state(7,15000);
        while(play_samples<100)wait_frames(1);
        panel_key(3,0);wait_state(11,700);bookmark=play_samples;
        assert_paused(bookmark);
        panel_key(1,0);turn(1,1);await_config(1,1);assert_paused(bookmark);
        turn(0,1);wait_frames(5);check(gain_index==11,"fine gain selected while paused");assert_paused(bookmark);
        panel_key(3,0);wait_state(7,700);wait_frames(70);
        check(play_samples>bookmark && play_input_checks==play_samples,"resume advances exact original cursor");
        // 对外和声为第三个且最后一个音效，默认为 0/0。
        prior_write_address=dut.core.algorithm.write_address;bookmark=play_samples;
        panel_key(1,0);await_config(2,0);
        check(active_pitch_second==0 && !display_pitch_voice && rec_state==7 && play_samples>bookmark,"unified harmony enters two zero defaults and continues replay");
        check(dut.core.algorithm.fill_count>0 && !dut.core.algorithm.fault,"harmony switch retains initialized history");
        bookmark=play_samples;turn(1,1);await_config(2,1);
        check(active_pitch_second==0 && rec_state==7 && play_samples>bookmark,"first harmony semitone continues original cursor");
        selected_commits=safe_commits;pitch_press;wait_frames(5);
        check(display_pitch_voice && active_pitch_semitones==1 && active_pitch_second==0,"short press only selects second harmony voice");
        check(safe_commits==selected_commits && !dut.display_switching && dut.active_mode==1,"editor target has no fade or configuration commit");
        dual_bookmark=play_samples;turn(1,1);await_second(1);
        check(active_pitch_semitones==1 && rec_state==7 && play_samples>dual_bookmark,"independent second harmony semitone continues replay");

        // 进入或退出校准界面以及转动其旋钮，均不得改变
        // 音频增益、实时目标、待提交配置或原始样本游标。
        tune_gain=gain_index;tune_live=dut.active_live_mode;tune_commits=safe_commits;tune_position=play_samples;
        gain_hold;wait_frames(5);
        check(ring_tuning && gain_index==tune_gain && dut.active_live_mode==tune_live,"long rotary1 release enters tuning without gain/live changes");
        check(!dut.display_switching && safe_commits==tune_commits && dut.active_mode==1,"tuning entry does not request audio fade");
        turn(0,1);wait_frames(20);
        check(ring_calibration_margin==25 && gain_index==tune_gain && rec_state==7 && play_samples>tune_position,"calibration24to25 changes ring only while playback advances");
        check(!dut.display_switching && safe_commits==tune_commits,"calibration adjustment does not commit an audio configuration");
        gain_hold;wait_frames(5);
        check(!ring_tuning && gain_index==tune_gain && dut.active_live_mode==tune_live && safe_commits==tune_commits,"tuning exit has no accidental short press or fade");

        panel_key(3,0);wait_state(11,700);dual_bookmark=play_samples;assert_paused(dual_bookmark);
        pitch_hold;await_second(0);assert_paused(dual_bookmark);
        check(display_pitch_voice && active_pitch_semitones==1,"long press resets only selected second voice while paused");
        tune_commits=safe_commits;gain_hold;wait_frames(3);turn(0,0);wait_frames(5);
        check(ring_tuning && ring_calibration_margin==24 && gain_index==tune_gain && safe_commits==tune_commits && !dut.display_switching,"paused ring tuning remains outside audio configuration");
        assert_paused(dual_bookmark);
        gain_hold;wait_frames(3);check(!ring_tuning && gain_index==tune_gain && safe_commits==tune_commits,"paused tuning exit leaves playback paused and audio gain unchanged");
        assert_paused(dual_bookmark);
        panel_key(3,0);wait_state(7,700);wait_frames(30);
        check(play_samples>dual_bookmark && play_input_checks==play_samples,"unified harmony pause/resume preserves exact original cursor");
        pitch_press;wait_frames(3);check(!display_pitch_voice,"short press returns harmony editing to first voice");
        pitch_hold;await_config(2,0);check(active_pitch_second==0 && rec_state==7,"both harmony voices zero after independent resets");
        panel_key(1,0);await_config(0,1);check(rec_state==7,"three-mode wrap restores separately saved ordinary pitch1");
        // 增益调整不得触发淡出、重启或暂停游标。
        bookmark=play_samples;turn(0,1);wait_frames(40);
        check(gain_index==12 && rec_state==7 && play_samples>bookmark,"fine gain is continuous during replay");
        check(dut.underflow==0 && dut.overflow==0 && !dut.core.algorithm.fault,"enhanced stream no FIFO/core fault");
        wait_state(4,24000);wait_frames(350);
        check(play_samples==clip_length && play_input_checks==clip_length,"pause/config replay delivers every sample exactly once");
        check(PA_EN===1 && nonzero_frames>100,"finished enhanced replay drains and mutes");
        // 暂停后的继续与显式从头重播是不同命令。
        panel_key(3,0);wait_state(7,15000);while(play_samples<100)wait_frames(1);
        panel_key(3,0);wait_state(11,700);bookmark=play_samples;
        panel_key(3,1);wait_state(6,700);check(play_samples==0 && record_valid,"long replay starts again at zero");
        wait_state(7,15000);wait_frames(20);check(play_samples>=20 && play_samples<bookmark,"restart streams from beginning");
        panel_key(0,0);wait_frames(350);check(!active_source && record_valid,"source exit stops session and retains recording");
        gain_press;wait_frames(350);check(PA_EN===0,"live still works after pause/restart");
        @(negedge clk);ddr_error=1;wait_frames(10);check(storage_fault && PA_EN===0,"DDR failure isolated from live path");
        check(nonzero_frames>100 && safe_commits>=6 && isolated_samples>=clip_length,"meaningful enhanced physical-interface coverage");
        $display("PASS HARMONY_TUNED_ENGINE grain=%0d dual=%0d checks=%0d clip=%0d raw_inputs=%0d DAC=%0d nonzero=%0d safe_commits=%0d pause_resume no_skip config_continue fine_gain unified_harmony0_0 independent_voice_selection second_pitch_commit ring_tune_no_audio_change paused_ring_tune source_fault_isolation",TEST_GRAIN_LOG2,TEST_DUAL_ENABLE,checks,clip_length,play_input_checks,dac_frames,nonzero_frames,safe_commits);
        $finish;
    end
    initial begin #3000000000;$fatal(1,"harmony engine timeout");end
endmodule
`endif
