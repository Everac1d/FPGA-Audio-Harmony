`timescale 1ns/1ps
// 在存储端口注入故障，同时使用真实麦克风 I2S 和 PT8211 解码。
// DSP、调理器、界面及串行音频均使用真实实现，不强制 PCM 输出。
module tb_record_fault_isolation;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,key_mode_n=1,key_gain_n=1;
    reg [3:0] mic_sd=0;
    reg ddr_ready=0,ddr_error=0;
    wire mic_bclk,mic_ws,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812,uart_tx,led_ck,led_da;
    wire req_valid,req_write,req_ready;
    wire [28:0] req_addr;wire [255:0] req_wdata;
    reg rsp_valid=0;reg [255:0] rsp_rdata=0;
    wire [3:0] rec_state;
    wire [20:0] record_samples,record_progress,play_samples;
    wire record_valid,record_full,storage_fault,active_source;
    wire [1:0] active_algorithm_mode;
    wire signed [4:0] active_pitch_semitones;
    wire [2:0] gain_index;
    audio_record_engine #(.DEBOUNCE_CYCLES(3),.LONG_PRESS_CYCLES(24),
        .POR_CYCLES(8),.STARTUP_FRAMES(3),.UART_REPORT_CYCLES(10000000),
        .MAX_SAMPLES(128),.RAM_ADDR_BITS(8),.GRAIN_LOG2(6)) dut(
        .clk(clk),.rst_n(rst_n),.key_mode_n(key_mode_n),.key_gain_n(key_gain_n),.mic_sd(mic_sd),
        .mic_bclk(mic_bclk),.mic_ws(mic_ws),.HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN),
        .PA_EN(PA_EN),.WS2812(WS2812),.uart_tx(uart_tx),.led_ck(led_ck),.led_da(led_da),
        .ddr_ready(ddr_ready),.ddr_error(ddr_error),.ddr_diag(16'h1234),.ddr_failure(545'd0),
        .req_valid(req_valid),.req_write(req_write),.req_addr(req_addr),.req_wdata(req_wdata),
        .req_ready(req_ready),.rsp_valid(rsp_valid),.rsp_rdata(rsp_rdata),.rec_state(rec_state),
        .record_samples(record_samples),.record_progress(record_progress),.play_samples(play_samples),
        .record_valid(record_valid),.record_full(record_full),.storage_fault(storage_fault),
        .active_source(active_source),.active_algorithm_mode(active_algorithm_mode),
        .active_pitch_semitones(active_pitch_semitones),.gain_index(gain_index));

    integer checks=0,frames=0,nonzero_frames=0,muted_frames=0,live_inputs=0,requests=0;
    integer case_id=0,phase_frames[0:7],phase_nonzero[0:7],k;
    task check(input bit condition,input [511:0] message);
        begin checks=checks+1;if(!condition)begin
            $display("FAIL FAULT_ISOLATION %0s case=%0d rec=%0d mode=%0d",message,case_id,rec_state,dut.active_mode);
            $fatal(1);end end
    endtask
    task wait_frames(input integer count);
        integer n;begin n=0;while(n<count)begin @(posedge clk);if(dut.frame_ce)n=n+1;end @(negedge clk);end
    endtask
    task wait_state(input integer wanted,input integer limit);
        integer n;begin n=0;while(rec_state!=wanted)begin wait_frames(1);n=n+1;
            if(n>limit)$fatal(1,"fault-isolation state timeout want=%0d got=%0d",wanted,rec_state);end end
    endtask
    task wait_source(input bit wanted,input integer limit);
        integer n;begin n=0;while(active_source!=wanted)begin wait_frames(1);n=n+1;
            if(n>limit)$fatal(1,"fault-isolation source timeout want=%0d got=%0d mode=%0d fade=%0d",wanted,active_source,dut.active_mode,dut.fade_level);end end
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
    task reset_board;
        begin @(negedge clk);rst_n=0;key_mode_n=1;key_gain_n=1;
            repeat(8)@(negedge clk);rst_n=1;wait(dut.mic_ready);wait_frames(6);end
    endtask
    task expect_live_audio(input integer phase);
        begin case_id=phase;wait_frames(360);
            check(!active_source&&dut.active_mode==1&&!PA_EN,"live speaker enabled despite storage state");
            check(phase_nonzero[phase]>80,"real microphone produces nonzero physical DAC frames");
            check(dut.color==24'h200000,"live status green unaffected by recorder fault");end
    endtask

    // 小容量可变延时存储模型，独立于被测音频路径。
    reg memory_busy=0,job_write;reg [28:0] job_addr;reg [255:0] job_data;
    reg [3:0] latency=0;reg [255:0] memory[0:7];
    assign req_ready=ddr_ready&&!ddr_error&&!memory_busy;
    always @(posedge clk)begin
        rsp_valid<=0;
        if(!rst_n)begin memory_busy<=0;latency<=0;end
        else if(req_valid&&req_ready)begin
            check(req_addr[2:0]==0&&req_addr<64,"DDR address alignment/range");
            memory_busy<=1;job_write<=req_write;job_addr<=req_addr;job_data<=req_wdata;
            latency<=3+(requests%7);requests=requests+1;
        end else if(memory_busy)begin
            if(latency==0)begin
                if(job_write)memory[job_addr>>3]<=job_data;else rsp_rdata<=memory[job_addr>>3];
                memory_busy<=0;rsp_valid<=1;
            end else latency<=latency-1'b1;
        end
    end

    wire board_run=rst_n&&dut.run_n;
    reg [5:0] mic_position=0;integer mic_frame=0,lane;
    reg [23:0] word_value;
    function [23:0] source_word(input integer frame,input integer channel);
        integer pcm;begin
            pcm=((frame%64)-32)*128+300;
            if(channel!=7)pcm=(frame*31+channel*1777)^16'h65a1;
            source_word={pcm[15:0],8'h53};end
    endfunction
    always @(negedge mic_bclk or negedge board_run)begin
        if(!board_run)begin mic_position=0;mic_frame=0;mic_sd=0;end
        else begin
            if(mic_position==63)mic_frame=mic_frame+1;
            mic_position=mic_position+1'b1;#2;
            check(mic_ws===mic_position[5],"microphone physical WS phase");
            for(lane=0;lane<4;lane=lane+1)begin
                word_value=source_word(mic_frame,lane*2+mic_position[5]);
                mic_sd[lane]=(mic_position[4:0]>=1&&mic_position[4:0]<=24)?word_value[24-mic_position[4:0]]:0;
            end
        end
    end

    reg frame_before,pa_before,run_before,playback_before;
    reg [15:0] expected_dac=0;
    reg expected_pa=1;
    always @(posedge clk)begin
        frame_before=dut.frame_ce;pa_before=PA_EN;run_before=dut.run_n;
        playback_before=dut.playback_ready;
        if(!board_run)begin expected_dac=0;expected_pa=1;end
        else begin
            if(frame_before)begin
                expected_dac=playback_before?dut.output_pcm:16'd0;
                expected_pa=!playback_before;
            end
            if(dut.pipeline_rst_n&&dut.rx_valid&&!active_source)begin
                check(dut.core.pcm_in===dut.central_pcm,"live algorithm input unaffected by DDR fault");
                live_inputs=live_inputs+1;
            end
            if(active_source&&(ddr_error||!ddr_ready))begin
                check(!dut.playback_ready&&!dut.pipeline_rst_n,"unreliable clip output blocked");
                check(!dut.clip_record&&!dut.clip_play,"failed storage rejects new commands");
            end
        end
        #1;
        if(run_before&&board_run&&dut.mic_ready)begin
            if(frame_before)check(PA_EN===expected_pa,"PA follows complete TX-frame decision");
            else check(PA_EN===pa_before,"fault cannot truncate an already active stereo frame");
        end
        check((^{HP_WS,HP_DIN,PA_EN})!==1'bx,"audio pins stay known");
    end

    reg [5:0] dac_position=0;reg [15:0] shift=0,right_word=0;
    always @(posedge HP_BCK or negedge board_run)begin
        if(!board_run)begin dac_position=0;shift=0;right_word=0;end
        else begin
            check(HP_WS===dac_position[5],"DAC physical WS phase");
            if(dac_position[4:0]<16)begin check(HP_DIN===0,"DAC leading padding");shift=0;end
            else begin
                shift={shift[14:0],HP_DIN};
                if(dac_position==31)right_word=shift;
                if(dac_position==63)begin
                    check(shift===right_word,"stereo slots identical during fault/switching");
                    check(shift===expected_dac,"serialized DAC equals frame-latched protected PCM");
                    check(PA_EN===expected_pa,"PA held to final bit of frame");
                    frames=frames+1;phase_frames[case_id]=phase_frames[case_id]+1;
                    if(shift!=0)begin nonzero_frames=nonzero_frames+1;phase_nonzero[case_id]=phase_nonzero[case_id]+1;end
                    else muted_frames=muted_frames+1;
                end
            end
            dac_position=dac_position+1'b1;
        end
    end

    integer before_audio,before_requests;
    initial begin
        for(k=0;k<8;k=k+1)begin phase_frames[k]=0;phase_nonzero[k]=0;end
        reset_board();
        check(!ddr_ready&&!storage_fault&&rec_state==0,"DDR may initialize while UI is available");
        check(dut.color==24'h000010,"initial live mute is blue, not false red fault");
        solo(0,0);expect_live_audio(1);
        solo(0,0);case_id=2;wait_frames(600);
        check(dut.active_mode==2&&!PA_EN&&phase_nonzero[2]>100,"test tone works before DDR ready");
        // 在帧开始后注入故障；测试音不得淡出或复位。
        wait_frames(1);repeat(200)@(negedge clk);ddr_error=1;
        before_audio=phase_nonzero[2];wait_frames(80);
        check(storage_fault&&rec_state==10&&!PA_EN&&dut.active_mode==2,"tone unaffected by DDR error");
        check(phase_nonzero[2]-before_audio>60,"tone continues physically serialized through error");
        solo(1,0);solo(0,1);solo(1,1);wait_frames(330);
        check(gain_index==2&&active_algorithm_mode==1&&active_pitch_semitones==4,"gain/effect/pitch keys work after storage fault");

        // 上电时即存在故障也必须仍允许实时麦克风播放。
        reset_board();check(storage_fault&&rec_state==10,"boot fault reported");
        solo(0,0);expect_live_audio(3);
        before_audio=phase_nonzero[3];ddr_ready=1;wait_frames(80);
        check(phase_nonzero[3]-before_audio>60&&!PA_EN,"sticky recorder fault cannot interrupt live audio");

        chord(1);case_id=4;wait_frames(340);
        check(active_source&&dut.active_mode==0&&PA_EN,"faulted recorder source safely muted");
        check(dut.color==24'h002000||dut.color==0,"fault indication uses red/black flash");
        before_requests=requests;solo(0,0);chord(0);wait_frames(10);
        check(requests==before_requests&&!record_valid&&rec_state==10,"faulted recorder rejects record/play requests");
        chord(1);wait_frames(8);check(!active_source&&dut.active_mode==0,"source keys escape faulted recorder");
        solo(0,0);expect_live_audio(5);

        // 在帧中途通过存储失效打断真实录音或回放。
        ddr_error=0;ddr_ready=1;reset_board();case_id=6;
        chord(1);wait_frames(8);solo(0,0);wait_state(2,10);
        wait_frames(64);solo(0,0);wait_state(4,20);
        check(record_valid&&record_samples>=64,"real recording committed before playback fault");
        chord(0);wait_state(7,1000);wait_frames(16);
        check(dut.active_mode==1&&!PA_EN&&play_samples>0,"real clip playback active before fault");
        check(phase_nonzero[6]>0,"clip fault follows nonzero physical playback, not silent preroll");
        wait_frames(1);repeat(200)@(negedge clk);ddr_ready=0;ddr_error=1;
        #1;check(!PA_EN,"storage fault preserves PA through the already latched stereo frame");
        wait_frames(2);check(PA_EN&&storage_fault&&!record_valid,"next complete frame mutes failed clip and invalidates it");
        // 故障立即使新发送帧静音，但现有的 256 帧
        // 包络仍须先衰减完毕，音源或配置才可安全提交。
        wait_frames(8);chord(1);wait_source(0,300);wait_frames(2);
        check(!active_source&&dut.active_mode==0,"live source recoverable after playback fault");
        solo(0,0);expect_live_audio(7);
        check(live_inputs>1000&&nonzero_frames>600&&muted_frames>400,"meaningful physical-path coverage");
        $display("PASS RECORD_FAULT_ISOLATION checks=%0d DAC_frames=%0d nonzero_frames=%0d muted_frames=%0d live_input_samples=%0d DDR_requests=%0d boot_fault live_fault tone_fault clip_fault source_escape controls frame_safe_PA",checks,frames,nonzero_frames,muted_frames,live_inputs,requests);
        $finish;
    end
    initial begin #150000000;$fatal(1,"fault-isolation timeout");end
endmodule
