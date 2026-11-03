`timescale 1ns/1ps
module tb_panel_diag_chord;
    reg clk=0,rst_n=0;
    always #10 clk=~clk;
    reg [3:0] button_n=15;
    reg gain_sw=1,pitch_sw=1,gain_clk=1,gain_dt=1,pitch_clk=1,pitch_dt=1;
    wire source,rec,play,restart,changed,reset_request;
    wire [1:0] live,algorithm;
    wire [4:0] gain;
    wire signed [4:0] pitch;
    localparam integer DIAG=40;
    audio_external_controls #(.DEBOUNCE_CYCLES(3),.LONG_RESET_CYCLES(64),
        .LONG_REPLAY_CYCLES(30),.LONG_DIAG_CYCLES(DIAG),.ENCODER_FILTER_CYCLES(2)) dut(
        .clk(clk),.rst_n(rst_n),.button_n(button_n),
        .enc_gain_sw_n(gain_sw),.enc_gain_clk(gain_clk),.enc_gain_dt(gain_dt),
        .enc_pitch_sw_n(pitch_sw),.enc_pitch_clk(pitch_clk),.enc_pitch_dt(pitch_dt),
        .record_source(source),.live_mode(live),.gain_index(gain),
        .algorithm_mode(algorithm),.pitch_semitones(pitch),.record_toggle(rec),
        .play_toggle(play),.play_restart(restart),.source_changed(changed),.reset_request(reset_request));
    integer checks=0,tone_entries=0,source_events=0,reset_events=0;
    reg [1:0] previous_live=0;
    always @(negedge clk)begin
        if(rst_n)begin
            if(live==2 && previous_live!=2)tone_entries=tone_entries+1;
            if(changed)source_events=source_events+1;
            if(reset_request)reset_events=reset_events+1;
            if(source && live==2)$fatal(1,"diagnostic tone entered record source");
            previous_live=live;
        end else previous_live=0;
    end
    task tick(input integer n);begin repeat(n)@(negedge clk);#1;end endtask
    task check(input logic okay,input string why);begin
        checks=checks+1;if(okay!==1'b1)$fatal(1,"check %0d %s",checks,why);
    end endtask
    task gain_press;begin gain_sw=0;tick(12);gain_sw=1;tick(12);end endtask
    task pitch_press;begin pitch_sw=0;tick(12);pitch_sw=1;tick(12);end endtask
    task key(input integer k,input integer n);begin button_n[k]=0;tick(n);button_n[k]=1;tick(12);end endtask
    task turn_pitch;begin
        {pitch_clk,pitch_dt}=2'b01;tick(10);
        {pitch_clk,pitch_dt}=2'b00;tick(10);
        {pitch_clk,pitch_dt}=2'b10;tick(10);
        {pitch_clk,pitch_dt}=2'b11;tick(10);
    end endtask
    task reset_dut;begin
        rst_n=0;button_n=15;gain_sw=1;pitch_sw=1;tick(6);rst_n=1;tick(12);
    end endtask
    integer old_entries,old_source;
    initial begin
        reset_dut();
        check(live==0 && source==0,"safe live mute startup");
        gain_press();check(live==1,"single gain press enables microphone");
        gain_press();check(live==0,"single gain press mutes without tone");
        gain_sw=0;tick(DIAG+50);check(live==0,"long single gain press waits for release");
        gain_sw=1;tick(12);check(live==1,"long single gain press remains normal mic/mute");
        turn_pitch();turn_pitch();check(pitch==2,"pitch changed for reset suppression oracle");
        pitch_press();check(pitch==0 && live==1,"single pitch press resets pitch only");
        turn_pitch();turn_pitch();
        // 短时重叠操作接管两次释放事件，并保持实时状态和音高不变。
        old_entries=tone_entries;gain_sw=0;pitch_sw=0;tick(16);
        gain_sw=1;tick(12);check(live==1 && pitch==2,"short chord first release swallowed");
        pitch_sw=1;tick(12);check(live==1 && pitch==2 && tone_entries==old_entries,"short chord no action");
        // 两个旋钮轴的按下顺序不受限制；
        // 只有两者共同持续按住的区间计入 2 秒时长。
        gain_sw=0;tick(DIAG+20);pitch_sw=0;tick(16);
        check(live==1,"first shaft alone cannot qualify chord");
        pitch_sw=1;tick(12);gain_sw=1;tick(12);
        check(live==1 && pitch==2 && tone_entries==old_entries,"long first hold plus short overlap rejected");
        // 在实时模式满足触发时长，先释放增益旋钮，再继续按住变调旋钮。
        gain_sw=0;tick(14);pitch_sw=0;tick(DIAG+20);
        check(live==1 && pitch==2 && dut.diag_qualified,"qualified chord waits for every release");
        gain_sw=1;tick(DIAG+15);check(live==1 && pitch==2,"first release never starts tone");
        pitch_sw=1;tick(12);
        check(live==2 && pitch==2 && tone_entries==old_entries+1,"last release starts exactly one tone entry");
        tick(100);check(tone_entries==old_entries+1,"no repeat once fully released");
        gain_press();check(live==0,"tone exit uses gain press to safe mute");
        gain_press();check(live==1,"next ordinary press enables microphone");
        // 反转按下和释放顺序，再次检查满足触发条件的情况。
        old_entries=tone_entries;pitch_sw=0;tick(20);gain_sw=0;tick(DIAG+20);
        pitch_sw=1;tick(12);check(live==1 && pitch==2,"opposite first release swallowed");
        gain_sw=1;tick(12);check(live==2 && pitch==2 && tone_entries==old_entries+1,"opposite last release works");
        gain_press();
        // 提前释放取消后，再次按下不得继续累计先前时间。
        gain_sw=0;pitch_sw=0;tick(16);gain_sw=1;tick(12);
        gain_sw=0;tick(DIAG+50);pitch_sw=1;tick(12);gain_sw=1;tick(12);
        check(live==0 && pitch==2,"short broken overlap stays cancelled until both up");
        // 短于消抖时长的触点抖动不得产生组合操作或单次按键。
        repeat(6)begin gain_sw=0;pitch_sw=0;tick(1);gain_sw=1;pitch_sw=1;tick(1);end
        tick(12);check(live==0 && pitch==2,"sub-debounce simultaneous chatter ignored");
        // 切换音源会取消已达到时长要求的组合操作，并消耗其
        // 后续释放事件，包括先切回原音源的情况。
        old_entries=tone_entries;gain_sw=0;pitch_sw=0;tick(DIAG+20);
        key(0,12);check(source==1 && live==0,"source switch cancels qualified chord");
        key(0,12);check(source==0 && live==0,"return live does not revive held chord");
        gain_sw=1;tick(12);pitch_sw=1;tick(12);
        check(live==0 && pitch==2 && tone_entries==old_entries,"cancelled chord releases cannot unmute or reset pitch");
        // 在录放模式开始的组合操作仍然无效，即使随后选择实时模式，
        // 只要旋钮轴尚未释放，此结论始终成立。
        key(0,12);gain_sw=0;pitch_sw=0;tick(DIAG+30);
        key(0,12);pitch_sw=1;tick(12);gain_sw=1;tick(12);
        check(source==0 && live==0 && pitch==2 && tone_entries==old_entries,"record-origin chord never enters tone");
        // 切换音源与最终释放位于同一边沿时，明确由音源切换优先。
        gain_sw=0;pitch_sw=0;tick(DIAG+20);
        button_n[0]=0;tick(12);button_n[0]=1;gain_sw=1;pitch_sw=1;tick(12);
        check(source==1 && live==0 && tone_entries==old_entries,"simultaneous source/final release prioritizes source");
        // 复位打断已达到时长但待释放的操作，不得残留延迟进入请求。
        key(0,12);gain_sw=0;pitch_sw=0;tick(DIAG+20);
        rst_n=0;tick(6);gain_sw=1;pitch_sw=1;rst_n=1;tick(12);
        check(source==0 && live==0 && pitch==0 && tone_entries==old_entries,"reset flushes chord state");
        // 复位期间持续按住两键时，必须重新满足完整的消抖后重叠时长。
        gain_sw=0;pitch_sw=0;rst_n=0;tick(6);rst_n=1;tick(20);
        check(!dut.diag_qualified && live==0,"held startup cannot qualify early");
        tick(DIAG+10);check(live==0 && dut.diag_qualified,"held startup still requires final release");
        gain_sw=1;pitch_sw=1;tick(12);check(live==2,"fresh full startup overlap may enter diagnostic");
        // 正式版默认的实际诊断时长保持为 2 秒。
        check(dut.LONG_DIAG_CYCLES==DIAG,"test explicitly scales diagnostic duration only");
        $display("PASS PANEL_DIAG_CHORD checks=%0d tone_entries=%0d source_events=%0d reset_events=%0d",checks,tone_entries,source_events,reset_events);
        $finish;
    end
    initial begin #10000000;$fatal(1,"panel chord timeout");end
endmodule
