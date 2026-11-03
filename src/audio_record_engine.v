// 音频与界面集成，沿用50MHz / 1024采样时基。
// 以下所有控制端口及供LCD使用的状态端口均与clk同步。
module audio_record_engine #(
    parameter integer DEBOUNCE_CYCLES=1000000,LONG_PRESS_CYCLES=40000000,
    parameter integer POR_CYCLES=65535,STARTUP_FRAMES=4883,
    parameter integer UART_REPORT_CYCLES=25000000,
    parameter integer MAX_SAMPLES=1464844,
    parameter integer RAM_ADDR_BITS=14,GRAIN_LOG2=13,
    parameter integer EXTERNAL_CONTROLS=0,ENHANCED_PLAYBACK=0,
    parameter integer FINE_GAIN=EXTERNAL_CONTROLS,
    parameter integer DUAL_VOICE_ENABLE=0,
    parameter integer LONG_RESET_CYCLES=100000000,ENCODER_FILTER_CYCLES=50000,
    parameter integer LONG_DIAG_CYCLES=LONG_RESET_CYCLES,LONG_PITCH_CYCLES=LONG_RESET_CYCLES,
    parameter [31:0] STATUS_USER_CODE=32'h00032503
) (
    input wire clk,rst_n,key_mode_n,key_gain_n,
    input wire [3:0] button_n,
    input wire enc_gain_sw_n,enc_gain_clk,enc_gain_dt,
    input wire enc_pitch_sw_n,enc_pitch_clk,enc_pitch_dt,
    output wire soft_reset_request,
    input wire [3:0] mic_sd,
    output wire mic_bclk,mic_ws,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812,uart_tx,led_ck,led_da,
    input wire ddr_ready,ddr_error,
    input wire [15:0] ddr_diag,
    input wire [544:0] ddr_failure,
    output wire req_valid,req_write,
    output wire [28:0] req_addr,
    output wire [255:0] req_wdata,
    input wire req_ready,rsp_valid,
    input wire [255:0] rsp_rdata,
    output wire [3:0] rec_state,
    output wire [20:0] record_samples,record_progress,play_samples,
    output wire record_valid,record_full,storage_fault,
    output reg active_source,
    output reg [1:0] active_algorithm_mode,
    output reg signed [4:0] active_pitch_semitones,
    output wire [4:0] gain_index,
    output wire [1:0] display_active_mode,
    output wire display_switching,
    output reg signed [4:0] active_pitch_second,
    output wire display_pitch_voice
);
    (* ASYNC_REG="TRUE" *) reg reset_meta=0,reset_sync=0;
    reg [31:0] por_count=0;reg run_n=0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin reset_meta<=0;reset_sync<=0;end
        else begin reset_meta<=1;reset_sync<=reset_meta;end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin por_count<=0;run_n<=0;end
        else if(!reset_sync)begin por_count<=0;run_n<=0;end
        else if(!run_n)begin
            if(por_count==POR_CYCLES-1)run_n<=1;
            else por_count<=por_count+1'b1;
        end
    end
    wire fall_ce,sample_ce,frame_ce;wire[5:0] bit_pos;
    audio_test_clock clock_gen(.clk(clk),.rst_n(run_n),.bclk(mic_bclk),.mic_ws(mic_ws),
        .fall_ce(fall_ce),.rx_sample_ce(sample_ce),.bit_pos(bit_pos));
    assign HP_BCK=mic_bclk;
    reg[31:0] startup=0;reg mic_ready=0;
    always @(posedge clk)begin
        if(!run_n)begin startup<=0;mic_ready<=0;end
        else if(frame_ce&&!mic_ready)begin
            if(startup==STARTUP_FRAMES-1)mic_ready<=1;
            else startup<=startup+1'b1;
        end
    end
    wire signed[15:0] central_pcm,average_pcm;wire[111:0] channels_pcm;wire rx_valid;
    mic_array_pcm microphones(.clk(clk),.rst_n(run_n),.mic_sd(mic_sd),.sample_ce(sample_ce),
        .bit_pos(bit_pos),.mic_ready(mic_ready),.central_pcm(central_pcm),
        .average_pcm(average_pcm),.channels_pcm(channels_pcm),.frame_valid(rx_valid));
    wire ui_source,key_record,key_play,key_restart,key_source_changed;
    wire[1:0] ui_live,ui_algorithm;wire signed[4:0] ui_pitch;
    wire signed[4:0] ui_pitch_second;
    wire ui_pitch_voice;
    assign display_pitch_voice=ui_pitch_voice;
    generate if(EXTERNAL_CONTROLS!=0)begin: external_ui
    audio_external_controls #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
        .LONG_RESET_CYCLES(LONG_RESET_CYCLES),.LONG_REPLAY_CYCLES(LONG_PRESS_CYCLES),
        .ENCODER_FILTER_CYCLES(ENCODER_FILTER_CYCLES),.DUAL_VOICE_ENABLE(DUAL_VOICE_ENABLE),
        .LONG_DIAG_CYCLES(LONG_DIAG_CYCLES),.LONG_PITCH_CYCLES(LONG_PITCH_CYCLES)) keys(
        .clk(clk),.rst_n(run_n),.button_n(button_n),
        .enc_gain_sw_n(enc_gain_sw_n),.enc_gain_clk(enc_gain_clk),.enc_gain_dt(enc_gain_dt),
        .enc_pitch_sw_n(enc_pitch_sw_n),.enc_pitch_clk(enc_pitch_clk),.enc_pitch_dt(enc_pitch_dt),
        .record_source(ui_source),.live_mode(ui_live),.gain_index(gain_index),
        .algorithm_mode(ui_algorithm),.pitch_semitones(ui_pitch),.record_toggle(key_record),
        .play_toggle(key_play),.play_restart(key_restart),.source_changed(key_source_changed),
        .reset_request(soft_reset_request),.pitch_second(ui_pitch_second),.pitch_voice(ui_pitch_voice));
    end else begin: legacy_ui
    assign key_restart=1'b0;
    assign soft_reset_request=1'b0;
    assign ui_pitch_second=5'sd0;
    assign ui_pitch_voice=1'b0;
    wire [2:0] legacy_gain;
    assign gain_index={2'd0,legacy_gain};
    audio_record_keys #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),.LONG_PRESS_CYCLES(LONG_PRESS_CYCLES)) keys(
        .clk(clk),.rst_n(run_n),.key_mode_n(key_mode_n),.key_gain_n(key_gain_n),
        .record_source(ui_source),.live_mode(ui_live),.gain_index(legacy_gain),
        .algorithm_mode(ui_algorithm),.pitch_semitones(ui_pitch),.record_toggle(key_record),
        .play_toggle(key_play),.source_changed(key_source_changed));
    end endgenerate
    reg[1:0] active_live_mode,active_mode;
    assign display_active_mode=active_mode;
    reg pending_record,pending_play,pending_restart,clip_record,clip_play,clip_abort,clip_restart;
    wire play_active,play_paused,clip_fault;
    wire config_change=(active_source!=ui_source)||(active_live_mode!=ui_live)||
        (active_algorithm_mode!=ui_algorithm)||(active_pitch_semitones!=ui_pitch)||
        ((DUAL_VOICE_ENABLE!=0)&&(ui_algorithm==2'd3)&&(active_pitch_second!=ui_pitch_second));
    wire switching=config_change||pending_record||pending_play||pending_restart;
    assign display_switching=switching;
    // 只有录音片段回放依赖存储；故障或尚未就绪的
    // DDR控制器不得禁用独立的实时麦克风与测试音界面。
    wire clip_unavailable=active_source && (!ddr_ready || storage_fault);
    wire[1:0] sound_request=(switching||clip_unavailable) ? 2'd0 :
        (active_source ? ((play_active&&!play_paused) ? 2'd1:2'd0) : active_live_mode);
    // 静音时保留完整回放数据流：DDR游标、变调
    // 历史、调理器状态及输出FIFO均停在同一采样
    // 边界；已经开始的运算与DDR响应可正常完成。
    wire stream_hold=(ENHANCED_PLAYBACK!=0) && active_source &&
        (active_mode!=1 || play_paused || clip_play || clip_record || clip_abort || clip_restart);
    wire fade_zero;reg amplifier_frame_ready;
    always @(posedge clk)begin
        if(!run_n)begin
            active_source<=0;active_live_mode<=0;active_algorithm_mode<=0;
            active_pitch_semitones<=0;active_pitch_second<=5'sd7;active_mode<=0;pending_record<=0;pending_play<=0;pending_restart<=0;
            clip_record<=0;clip_play<=0;clip_abort<=0;clip_restart<=0;
        end else begin
            clip_record<=0;clip_play<=0;clip_abort<=0;clip_restart<=0;
            if(key_record)pending_record<=1;
            if(key_play)pending_play<=1;
            if(key_restart)pending_restart<=1;
            if(frame_ce && fade_zero)active_mode<=sound_request;
            // 等待TX完成最后一个已使能的帧，再执行复位、
            // 音源切换或配置变更；录音片段有效性独立于内核复位。
            if(frame_ce && fade_zero && active_mode==0 && !amplifier_frame_ready)begin
                if(config_change)begin
                    active_source<=ui_source;active_live_mode<=ui_live;
                    active_algorithm_mode<=ui_algorithm;active_pitch_semitones<=ui_pitch;
                    active_pitch_second<=ui_pitch_second;
                    clip_abort<=(active_source!=ui_source)||
                        ((ENHANCED_PLAYBACK==0)&&(rec_state>=5&&rec_state<=9));
                    if(active_source!=ui_source)begin
                        pending_record<=0;pending_play<=0;pending_restart<=0;
                    end
                end else if(pending_record)begin
                    if(active_source && mic_ready && ddr_ready && !storage_fault)clip_record<=1;
                    pending_record<=0;pending_play<=0;pending_restart<=0;
                end else if(pending_restart)begin
                    if(active_source && mic_ready && ddr_ready && !storage_fault)clip_restart<=1;
                    pending_restart<=0;pending_play<=0;
                end else if(pending_play)begin
                    if(active_source && mic_ready && ddr_ready && !storage_fault)clip_play<=1;
                    pending_play<=0;
                end
            end
        end
    end
    wire signed[15:0] clip_pcm;
    pcm_clip_controller #(.MAX_SAMPLES(MAX_SAMPLES),
        .ENHANCED_PLAYBACK(ENHANCED_PLAYBACK),
        .PREROLL_SAMPLES((1<<GRAIN_LOG2)+34+640),
        .TAIL_SAMPLES((1<<GRAIN_LOG2)+34+768)) recorder(
        .clk(clk),.rst_n(run_n),.sample_tick(rx_valid),.mic_pcm(central_pcm),
        .record_toggle(clip_record),.play_toggle(clip_play),.abort_play(clip_abort),
        .play_hold(stream_hold),.play_restart(clip_restart),.play_paused(play_paused),
        .storage_ready(ddr_ready),.storage_error(ddr_error),.req_valid(req_valid),
        .req_write(req_write),.req_addr(req_addr),.req_wdata(req_wdata),.req_ready(req_ready),
        .rsp_valid(rsp_valid),.rsp_rdata(rsp_rdata),.play_pcm(clip_pcm),.rec_state(rec_state),
        .record_samples(record_samples),.record_progress(record_progress),.play_samples(play_samples),
        .record_valid(record_valid),.record_full(record_full),.play_active(play_active),.fault(clip_fault));
    assign storage_fault=ddr_error||clip_fault;
    wire pipeline_rst_n=run_n && mic_ready && !clip_unavailable &&
        (((ENHANCED_PLAYBACK!=0)&&active_source) ? play_active : active_mode==1);
    wire signed[15:0] source_pcm=active_source ? clip_pcm : central_pcm;
    wire signed[15:0] core_out,path_pcm;wire core_valid,path_valid;
    audio_effect_core #(.RAM_ADDR_BITS(RAM_ADDR_BITS),.GRAIN_LOG2(GRAIN_LOG2),
        .DYNAMIC_CONFIG(ENHANCED_PLAYBACK),.DUAL_VOICE_ENABLE(DUAL_VOICE_ENABLE)) core(
        .clk(clk),.rst_n(pipeline_rst_n),.pcm_in(source_pcm),.pcm_in_valid(rx_valid&&pipeline_rst_n&&!stream_hold),
        .mode(active_algorithm_mode),.pitch_semitones(active_pitch_semitones),.pitch_second(active_pitch_second),
        .pcm_out(core_out),.pcm_out_valid(core_valid));
    pcm_voice_conditioner conditioner(.clk(clk),.rst_n(pipeline_rst_n),.pcm_in(core_out),
        .in_valid(core_valid),.pcm_out(path_pcm),.out_valid(path_valid));
    wire signed[15:0] queue_head;wire head_valid,queue_started;
    wire[4:0] queue_level;wire[31:0] accepted,played,underflow,overflow;
    pcm_output_queue #(.ADDR_WIDTH(4),.PREFILL_SAMPLES(2),.HEAD_SETUP_CYCLES(4)) queue(
        .clk(clk),.rst_n(pipeline_rst_n),.flush(1'b0),.pcm_in(path_pcm),.in_valid(path_valid),
        .frame_ce(frame_ce&&!stream_hold),.pcm_head(queue_head),.head_valid(head_valid),.started(queue_started),
        .level(queue_level),.accepted_count(accepted),.played_count(played),
        .underflow_count(underflow),.overflow_count(overflow));
    reg[23:0] phase=0;
    always @(posedge clk)if(!run_n)phase<=0;else if(frame_ce)phase<=phase+24'd343597;
    // 沿用约1kHz的低幅度诊断音，与录音片段无关。
    function signed[15:0] tone_lut;
        input[5:0] a;reg[4:0] i;reg[15:0] m;
        begin i=a[4]?(5'd16-{1'b0,a[3:0]}):{1'b0,a[3:0]};
            case(i)
            0:m=0;1:m=201;2:m=400;3:m=595;4:m=784;5:m=965;6:m=1138;7:m=1299;
            8:m=1448;9:m=1583;10:m=1703;11:m=1806;12:m=1892;13:m=1960;
            14:m=2009;15:m=2038;default:m=2048;endcase
            tone_lut=a[5]?-$signed(m):$signed(m);
        end
    endfunction
    wire raw_ready=queue_level!=0;
    wire source_ready=mic_ready && ((active_mode==1&&raw_ready)||active_mode==2) && !clip_unavailable;
    wire playback_ready=mic_ready && ((active_mode==1&&head_valid)||active_mode==2) && !clip_unavailable;
    wire signed[15:0] monitor_in=active_mode==2 ? tone_lut(phase[23:18]) : queue_head;
    // 与22402基线一致：先在帧边界锁存目标值，
    // 再由监听模块自身的逐帧增益渐变逻辑读取。
    reg [4:0] monitor_gain_index=0;
    always @(posedge clk)begin
        if(!run_n)monitor_gain_index<=0;
        else if(frame_ce)monitor_gain_index<=gain_index;
    end
    wire signed[15:0] output_pcm;wire would_clip,limiting;wire[8:0] fade_level;
    pcm_monitor_guard #(.PROTECTION_ENABLE(1),.SMOOTH_ENABLE(1),.PIPELINE_ENABLE(1),.FINE_GAIN(FINE_GAIN)) monitor(
        .clk(clk),.rst_n(run_n),.frame_ce(frame_ce),.active_mode(active_mode),.requested_mode(sound_request),
        .source_ready(source_ready),.gain_index(monitor_gain_index),.pcm_in(monitor_in),.pcm_out(output_pcm),
        .switch_ready(fade_zero),.would_clip(would_clip),.limiting(limiting),.fade_level(fade_level));
    pt8211_stereo_tx speaker(.clk(clk),.rst_n(run_n),.fall_ce(fall_ce),.bit_pos(bit_pos),
        .pcm_left(playback_ready?output_pcm:16'sd0),.pcm_right(playback_ready?output_pcm:16'sd0),
        .HP_WS(HP_WS),.HP_DIN(HP_DIN),.frame_ce(frame_ce));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)amplifier_frame_ready<=0;
        else if(!run_n)amplifier_frame_ready<=0;
        else if(frame_ce)amplifier_frame_ready<=playback_ready;
    end
    // 故障抑制下一个完整TX帧；不得通过组合逻辑功放静音
    // 截断PT8211串行发送器已经锁存的帧。
    assign PA_EN=!rst_n||!run_n||!mic_ready||!amplifier_frame_ready;
    wire[7:0] meter_level;wire[15:0] display_mean,display_floor;
    audio_level_meter #(.CALIBRATION_MARGIN(24)) meter(.clk(clk),.rst_n(run_n),.pcm(central_pcm),.pcm_valid(rx_valid),
        .level(meter_level),.mean_level(display_mean),.noise_floor(display_floor));
    wire [2:0] ring_color_rgb;
    audio_ring_palette ring_palette(.active_source(active_source),
        .active_algorithm_mode(active_algorithm_mode),.active_mode(active_mode),
        .rec_state(rec_state),.ddr_ready(ddr_ready),.storage_fault(storage_fault),
        .color_mask_rgb(ring_color_rgb));
    sk9822_ring ring(.clk(clk),.rst_n(run_n),.level(meter_level),
        .color_mask_rgb(ring_color_rgb),.led_ck(led_ck),.led_da(led_da));
    reg [24:0] fault_blink_count=0;
    always @(posedge clk)begin
        if(!run_n)fault_blink_count<=0;
        else fault_blink_count<=fault_blink_count+1'b1;
    end
    reg[23:0] color;
    always @* begin
        // 录音时红灯常亮；存储故障仅在录放模式下闪红灯。
        // 即使录音模块不可用，仍显示实时模式状态。
        if(active_source && storage_fault)color=fault_blink_count[24]?24'h000000:24'h002000;
        else if(active_source && !ddr_ready)color=24'h101000;
        else if(rec_state==2 || rec_state==3)color=24'h002000;
        else if(active_source && play_active)color=24'h200000;
        else if(active_source && record_valid)color=24'h101000;
        else if(active_source)color=24'h001010;
        else if(active_mode==1)color=24'h200000;
        else if(active_mode==2)color=24'h001010;
        else color=24'h000010;
    end
    status_ws2812 status_led(.clk(clk),.rst_n(run_n),.color_grb(color),.WS2812(WS2812));
    record_status_uart #(.REPORT_CYCLES(UART_REPORT_CYCLES),.USER_CODE(STATUS_USER_CODE),.FINE_GAIN(FINE_GAIN),
        .DUAL_VOICE_ENABLE(DUAL_VOICE_ENABLE)) reporter(
        .clk(clk),.rst_n(run_n),.source(active_source),.live_mode(active_mode),
        .algorithm_mode(active_algorithm_mode),.pitch_semitones(active_pitch_semitones),.gain_index(gain_index),
        .pitch_second(active_pitch_second),.pitch_voice(display_pitch_voice),
        .rec_state(rec_state),.record_samples(record_progress),.play_samples(play_samples),
        .ddr_ready(ddr_ready),.storage_error(storage_fault),.ddr_diag(ddr_diag),.ddr_failure(ddr_failure),.record_full(record_full),.mic_ready(mic_ready),
        .queue_underflow_count(underflow),.queue_overflow_count(overflow),.uart_tx(uart_tx));
endmodule
