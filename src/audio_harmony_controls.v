// 外接面板A：四个低电平有效按键与两个正交编码器。
// 所有异步触点均在50MHz时钟域内同步并滤波。
// 触点不作为时钟；按键释放时才发出命令。
module audio_harmony_controls #(
    parameter integer DEBOUNCE_CYCLES=1000000,
    parameter integer LONG_RESET_CYCLES=100000000,
    parameter integer LONG_REPLAY_CYCLES=40000000,
    parameter integer LONG_DIAG_CYCLES=100000000,
    parameter integer LONG_PITCH_CYCLES=100000000,
    parameter integer DUAL_VOICE_ENABLE=0,
    parameter integer UNIFIED_HARMONY=0,RING_TUNE_ENABLE=0,
    parameter integer LONG_RING_TUNE_CYCLES=100000000,RING_FAST_CYCLES=6000000,
    parameter integer ENCODER_FILTER_CYCLES=50000,
    parameter integer GAIN_REVERSE=0,
    parameter integer PITCH_REVERSE=0
) (
    input wire clk,rst_n,
    input wire [3:0] button_n,
    input wire enc_gain_sw_n,enc_gain_clk,enc_gain_dt,
    input wire enc_pitch_sw_n,enc_pitch_clk,enc_pitch_dt,
    output reg record_source,
    output reg [1:0] live_mode,
    // 增益以0.1倍为单位：10=1.0倍，30=3.0倍。
    output reg [4:0] gain_index,
    output reg [1:0] algorithm_mode,
    output wire signed [4:0] pitch_semitones,
    output reg signed [4:0] pitch_second,
    output reg pitch_voice,
    output reg ring_tuning,
    output reg signed [12:0] ring_calibration_margin,
    output reg record_toggle,play_toggle,play_restart,source_changed,reset_request
);
    wire [5:0] contacts={enc_pitch_sw_n,enc_gain_sw_n,button_n};
    // 普通音效独立保留其音调；进入或退出双声部模式时，
    // 不会覆盖三组音调设置，也不会改变选中的双声部。
    reg signed [4:0] normal_pitch,dual_first;
    wire dual_selected=(DUAL_VOICE_ENABLE!=0) &&
        ((UNIFIED_HARMONY!=0) ? algorithm_mode==2'd2 : algorithm_mode==2'd3);
    assign pitch_semitones=dual_selected ? dual_first : normal_pitch;
    (* syn_preserve=1, ASYNC_REG="TRUE" *) reg [5:0] contact_meta,contact_sync;
    reg [5:0] contact_stable,contact_previous;
    reg [31:0] debounce_count[0:5];
    integer i;
    always @(posedge clk) begin
        if(!rst_n) begin
            contact_meta<=6'b111111;contact_sync<=6'b111111;
            contact_stable<=6'b111111;contact_previous<=6'b111111;
            for(i=0;i<6;i=i+1)debounce_count[i]<=0;
        end else begin
            contact_meta<=contacts;contact_sync<=contact_meta;
            contact_previous<=contact_stable;
            for(i=0;i<6;i=i+1) begin
                if(contact_sync[i]==contact_stable[i])debounce_count[i]<=0;
                else if(debounce_count[i]>=DEBOUNCE_CYCLES-1)begin
                    contact_stable[i]<=contact_sync[i];debounce_count[i]<=0;
                end else debounce_count[i]<=debounce_count[i]+1'b1;
            end
        end
    end
    wire [5:0] released=contact_stable & ~contact_previous;
    // 诊断组合操作会接管两个SW开关的释放事件，即使按压时间过短
    // 或操作已取消也如此；要求消抖后持续同时按住，再等待两个
    // 旋钮均释放；切换音源后取消操作，直至两个旋钮均松开。
    wire diag_both_down=!contact_stable[4] && !contact_stable[5];
    wire diag_both_up=contact_stable[4] && contact_stable[5];
    reg diag_session,diag_qualified,diag_cancelled;
    reg [31:0] diag_held;
    wire diag_block=diag_session || diag_both_down;
    wire diag_enter=diag_session && diag_qualified && !diag_cancelled &&
        diag_both_up && !record_source && !released[0];
    always @(posedge clk)begin
        if(!rst_n)begin
            diag_session<=0;diag_qualified<=0;diag_cancelled<=0;diag_held<=0;
        end else if(diag_session)begin
            if(record_source || released[0])diag_cancelled<=1;
            if(diag_both_up)begin
                diag_session<=0;diag_qualified<=0;diag_cancelled<=0;diag_held<=0;
            end else if(!diag_both_down)begin
                diag_held<=0;
                if(!diag_qualified)diag_cancelled<=1;
            end else if(!diag_qualified && !diag_cancelled && !record_source && !released[0])begin
                if(diag_held>=LONG_DIAG_CYCLES-1)diag_qualified<=1;
                else diag_held<=diag_held+1'b1;
            end
        end else if(diag_both_down)begin
            diag_session<=1;diag_held<=1;
            diag_qualified<=(LONG_DIAG_CYCLES<=1);
            diag_cancelled<=record_source || released[0];
        end
    end
    reg [31:0] reset_held,replay_held,pitch_held,gain_held;
    reg reset_long,replay_long,pitch_long,gain_long;
    reg gain_cancelled;
    always @(posedge clk)begin
        if(!rst_n)begin
            reset_held<=0;replay_held<=0;reset_long<=0;replay_long<=0;
            pitch_held<=0;pitch_long<=0;gain_held<=0;gain_long<=0;gain_cancelled<=0;
        end else begin
            // 音源切换会接管当前正在进行的增益旋钮按压。
            // 随后释放旋钮时不得重新进入调参，也不得将新音源
            // 静音；下一次完整按压可正常使用。
            if(RING_TUNE_ENABLE!=0 && released[0] && !contact_stable[4])gain_cancelled<=1;
            else if(contact_stable[4])gain_cancelled<=0;
            if(contact_stable[0])begin reset_held<=0;reset_long<=0;end
            else if(!reset_long)begin
                if(reset_held>=LONG_RESET_CYCLES-1)reset_long<=1;
                else reset_held<=reset_held+1'b1;
            end
            if(contact_stable[3])begin replay_held<=0;replay_long<=0;end
            else if(!replay_long)begin
                if(replay_held>=LONG_REPLAY_CYCLES-1)replay_long<=1;
                else replay_held<=replay_held+1'b1;
            end
            if(contact_stable[4] || diag_block || gain_cancelled || released[0])begin gain_held<=0;gain_long<=0;end
            else if(!gain_long)begin
                if(gain_held>=LONG_RING_TUNE_CYCLES-1)gain_long<=1;
                else gain_held<=gain_held+1'b1;
            end
            if(contact_stable[5] || diag_block)begin pitch_held<=0;pitch_long<=0;end
            else if(!pitch_long)begin
                if(pitch_held>=LONG_PITCH_CYCLES-1)pitch_long<=1;
                else pitch_held<=pitch_held+1'b1;
            end
        end
    end
    wire gain_up,gain_down,pitch_up,pitch_down;
    audio_panel_encoder #(.FILTER_CYCLES(ENCODER_FILTER_CYCLES),.REVERSE(GAIN_REVERSE)) gain_encoder(
        .clk(clk),.rst_n(rst_n),.contact_clk(enc_gain_clk),.contact_dt(enc_gain_dt),
        .step_up(gain_up),.step_down(gain_down));
    audio_panel_encoder #(.FILTER_CYCLES(ENCODER_FILTER_CYCLES),.REVERSE(PITCH_REVERSE)) pitch_encoder(
        .clk(clk),.rst_n(rst_n),.contact_clk(enc_pitch_clk),.contact_dt(enc_pitch_dt),
        .step_up(pitch_up),.step_down(pitch_down));
    // 只有显示校准支持加速；增益与音调控制
    // 仍保留原来的固定步进；前两次快速事件
    // 仍使用细步进，第三次同方向事件可使用16单位步进。
    reg [31:0] ring_event_age;
    reg [1:0] ring_fast_chain;
    reg ring_last_up;
    wire ring_fast=ring_event_age<RING_FAST_CYCLES && ring_last_up==gain_up;
    wire [4:0] ring_step=(ring_fast && ring_fast_chain>=1) ? 5'd16:5'd1;
    wire signed [13:0] ring_up_value=$signed({ring_calibration_margin[12],ring_calibration_margin})+$signed({9'd0,ring_step});
    wire signed [13:0] ring_down_value=$signed({ring_calibration_margin[12],ring_calibration_margin})-$signed({9'd0,ring_step});
    always @(posedge clk)begin
        if(!rst_n || !ring_tuning || diag_block)begin
            ring_event_age<=RING_FAST_CYCLES;ring_fast_chain<=0;ring_last_up<=0;
        end else if(gain_up || gain_down)begin
            ring_event_age<=0;ring_last_up<=gain_up;
            if(ring_fast)begin if(ring_fast_chain<2)ring_fast_chain<=ring_fast_chain+1'b1;end
            else ring_fast_chain<=0;
        end else if(ring_event_age<RING_FAST_CYCLES)ring_event_age<=ring_event_age+1'b1;
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            record_source<=0;live_mode<=0;gain_index<=5'd10;
            algorithm_mode<=0;normal_pitch<=0;dual_first<=(UNIFIED_HARMONY!=0) ? 5'sd0:5'sd4;
            pitch_second<=(UNIFIED_HARMONY!=0) ? 5'sd0:5'sd7;pitch_voice<=0;
            ring_tuning<=0;ring_calibration_margin<=13'sd24;
            record_toggle<=0;play_toggle<=0;play_restart<=0;
            source_changed<=0;reset_request<=0;
        end else begin
            record_toggle<=0;play_toggle<=0;play_restart<=0;
            source_changed<=0;reset_request<=0;
            if(released[0] && reset_long)reset_request<=1;
            else begin
                if(released[0])begin
                    record_source<=!record_source;live_mode<=0;source_changed<=1;ring_tuning<=0;
                end else if(diag_enter)begin live_mode<=2;ring_tuning<=0;end
                else if(released[4] && !diag_block && !(RING_TUNE_ENABLE!=0 && gain_cancelled))begin
                    if(RING_TUNE_ENABLE!=0 && gain_long)ring_tuning<=!ring_tuning;
                    else if(!record_source)live_mode<=(live_mode==0) ? 1 : 0;
                end
                if(released[1])begin
                    if(UNIFIED_HARMONY!=0)algorithm_mode<=(algorithm_mode==2) ? 0:algorithm_mode+1'b1;
                    else if(DUAL_VOICE_ENABLE!=0)algorithm_mode<=algorithm_mode+1'b1;
                    else algorithm_mode<=(algorithm_mode==2) ? 0 : algorithm_mode+1'b1;
                end
                if(released[2] && record_source)record_toggle<=1;
                if(released[3] && record_source)begin
                    if(replay_long)play_restart<=1;
                    else play_toggle<=1;
                end
                if(RING_TUNE_ENABLE!=0 && ring_tuning)begin
                    if(!diag_block && gain_up)ring_calibration_margin<=ring_up_value>14'sd4095 ? 13'sd4095:ring_up_value[12:0];
                    else if(!diag_block && gain_down)ring_calibration_margin<=ring_down_value < -14'sd4096 ? -13'sd4096:ring_down_value[12:0];
                end else begin
                    if(gain_up && gain_index<5'd30)gain_index<=gain_index+5'd1;
                    else if(gain_down && gain_index>5'd10)gain_index<=gain_index-5'd1;
                end
                if(released[5] && !diag_block)begin
                    if(dual_selected)begin
                        if(pitch_long)begin
                            if(pitch_voice)pitch_second<=0;
                            else dual_first<=0;
                        end else pitch_voice<=!pitch_voice;
                    end else normal_pitch<=0;
                end else if(dual_selected)begin
                    if(pitch_voice)begin
                        if(pitch_up && pitch_second<5'sd12)pitch_second<=pitch_second+5'sd1;
                        else if(pitch_down && pitch_second> -5'sd12)pitch_second<=pitch_second-5'sd1;
                    end else begin
                        if(pitch_up && dual_first<5'sd12)dual_first<=dual_first+5'sd1;
                        else if(pitch_down && dual_first> -5'sd12)dual_first<=dual_first-5'sd1;
                    end
                end else begin
                    if(pitch_up && normal_pitch<5'sd12)normal_pitch<=normal_pitch+5'sd1;
                    else if(pitch_down && normal_pitch> -5'sd12)normal_pitch<=normal_pitch-5'sd1;
                end
            end
        end
    end
endmodule

