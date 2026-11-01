`timescale 1ns/1ps
module tb_dual_panel;
    reg clk=0,rst_n=0;
    always #10 clk=~clk;
    reg [3:0] button_n=15;
    reg gain_sw=1,pitch_sw=1,gain_clk=1,gain_dt=1,pitch_clk=1,pitch_dt=1;
    wire source,rec,play,restart,changed,reset_request,voice;
    wire [1:0] live,algorithm;
    wire [4:0] gain;
    wire signed [4:0] pitch,pitch_second;
    audio_external_controls #(.DEBOUNCE_CYCLES(3),.LONG_RESET_CYCLES(64),
        .LONG_REPLAY_CYCLES(30),.LONG_DIAG_CYCLES(40),.LONG_PITCH_CYCLES(40),
        .DUAL_VOICE_ENABLE(1),.ENCODER_FILTER_CYCLES(2)) dut(
        .clk(clk),.rst_n(rst_n),.button_n(button_n),
        .enc_gain_sw_n(gain_sw),.enc_gain_clk(gain_clk),.enc_gain_dt(gain_dt),
        .enc_pitch_sw_n(pitch_sw),.enc_pitch_clk(pitch_clk),.enc_pitch_dt(pitch_dt),
        .record_source(source),.live_mode(live),.gain_index(gain),
        .algorithm_mode(algorithm),.pitch_semitones(pitch),.pitch_second(pitch_second),.pitch_voice(voice),
        .record_toggle(rec),.play_toggle(play),.play_restart(restart),.source_changed(changed),.reset_request(reset_request));
    integer checks=0,tone_entries=0;
    reg [1:0] previous_live=0;
    always @(negedge clk)begin
        if(rst_n)begin
            if(live==2 && previous_live!=2)tone_entries=tone_entries+1;
            previous_live=live;
            if(source && live==2)$fatal(1,"tone cannot be enabled in record source");
        end else previous_live=0;
    end
    task tick(input integer n);begin repeat(n)@(negedge clk);#1;end endtask
    task check(input logic okay,input string why);begin
        checks=checks+1;if(okay!==1'b1)$fatal(1,"check %0d %s",checks,why);
    end endtask
    task gain_press;begin gain_sw=0;tick(12);gain_sw=1;tick(12);end endtask
    task pitch_press(input integer held);begin pitch_sw=0;tick(held);pitch_sw=1;tick(12);end endtask
    task key(input integer k,input integer n);begin button_n[k]=0;tick(n);button_n[k]=1;tick(12);end endtask
    task phase(input integer encoder,input [1:0] value);begin
        if(encoder==0){gain_clk,gain_dt}=value;else {pitch_clk,pitch_dt}=value;
        tick(10);
    end endtask
    task turn(input integer encoder,input integer direction);begin
        if(direction>0)begin phase(encoder,2'b01);phase(encoder,2'b00);phase(encoder,2'b10);phase(encoder,2'b11);end
        else begin phase(encoder,2'b10);phase(encoder,2'b00);phase(encoder,2'b01);phase(encoder,2'b11);end
    end endtask
    integer n,previous_entries;
    initial begin
        tick(6);rst_n=1;tick(12);
        check(source==0 && live==0 && algorithm==0 && pitch==0 && pitch_second==7 && voice==0 && gain==10,"normal/dual defaults");
        repeat(3)turn(1,1);check(pitch==3,"normal pitch independent before dual");
        key(1,12);check(algorithm==1 && pitch==3,"pitch effect retains normal pitch");
        key(1,12);check(algorithm==2 && pitch==3,"original plus shifted effect retains normal pitch");
        key(1,12);check(algorithm==3 && pitch==4 && pitch_second==7 && voice==0,"fourth effect enters independent +4/+7 defaults");
        turn(1,1);check(pitch==5 && pitch_second==7 && voice==0,"turn adjusts voice one only");
        pitch_press(12);check(pitch==5 && pitch_second==7 && voice==1,"short press changes selection without changing audio parameters");
        turn(1,-1);check(pitch==5 && pitch_second==6 && voice==1,"turn adjusts voice two only");
        pitch_sw=0;tick(60);check(pitch==5 && pitch_second==6 && voice==1,"long pitch press waits for release");
        pitch_sw=1;tick(12);check(pitch==5 && pitch_second==0 && voice==1,"long pitch resets selected second voice without toggling");
        pitch_press(12);check(voice==0 && pitch==5 && pitch_second==0,"short press returns selection to first voice");
        pitch_press(60);check(voice==0 && pitch==0 && pitch_second==0,"long pitch resets selected first voice without toggling");
        // All 25 semitones and both saturating endpoints work independently.
        for(n=1;n<=12;n=n+1)begin turn(1,1);check($signed(pitch)==n && pitch_second==0,"voice one increments by one");end
        turn(1,1);check(pitch==12,"voice one upper endpoint");
        for(n=11;n>=-12;n=n-1)begin turn(1,-1);check($signed(pitch)==n && pitch_second==0,"voice one decrements by one");end
        turn(1,-1);check(pitch== -12,"voice one lower endpoint");
        pitch_press(12);
        for(n=1;n<=12;n=n+1)begin turn(1,1);check($signed(pitch_second)==n && pitch== -12,"voice two increments by one");end
        turn(1,1);check(pitch_second==12,"voice two upper endpoint");
        for(n=11;n>=-12;n=n-1)begin turn(1,-1);check($signed(pitch_second)==n && pitch== -12,"voice two decrements by one");end
        turn(1,-1);check(pitch_second== -12,"voice two lower endpoint");
        key(1,12);check(algorithm==0 && pitch==3 && pitch_second== -12 && voice==1,"effect wrap restores separate normal pitch");
        pitch_press(12);check(pitch==0 && voice==1,"normal short press returns normal pitch to zero");
        turn(1,-1);pitch_press(60);check(pitch==0 && voice==1,"normal long press also zeros without switching voice");
        repeat(3)key(1,12);check(algorithm==3 && pitch== -12 && pitch_second== -12 && voice==1,"dual settings and editor selection survive effect cycle");
        key(0,12);check(source==1 && live==0 && algorithm==3 && pitch== -12 && pitch_second== -12 && voice==1,"source change preserves dual state");
        pitch_press(12);check(source==1 && voice==0 && pitch== -12 && pitch_second== -12,"voice selection also works in record source");
        turn(1,1);check(pitch== -11 && pitch_second== -12,"record source edits selected voice independently");
        pitch_press(60);check(pitch==0 && pitch_second== -12 && voice==0,"record source long press resets selected voice");
        // A record-source chord cannot become a voice short/long command.
        previous_entries=tone_entries;
        gain_sw=0;pitch_sw=0;tick(70);gain_sw=1;tick(12);pitch_sw=1;tick(12);
        check(source==1 && live==0 && voice==0 && pitch==0 && pitch_second== -12 && tone_entries==previous_entries,"record chord swallows pitch long and both releases");
        key(0,12);gain_press();turn(1,1);pitch_press(12);
        check(source==0 && live==1 && voice==1 && pitch==1 && pitch_second== -12,"prepare live dual diagnostic collision");
        // Even if the pitch shaft was held past its long threshold first, a
        // later common diagnostic chord has priority over the old long press.
        pitch_sw=0;tick(65);gain_sw=0;tick(65);
        gain_sw=1;tick(12);check(live==1 && voice==1 && pitch_second== -12,"diagnostic first release cannot reset selected pitch");
        pitch_sw=1;tick(12);check(live==2 && voice==1 && pitch==1 && pitch_second== -12 && tone_entries==previous_entries+1,"diagnostic chord takes priority over pitch long press");
        gain_press();check(live==0 && voice==1 && pitch_second== -12,"diagnostic exit returns safe mute and preserves dual state");
        // A short common chord never changes the selected voice or its pitch.
        gain_sw=0;pitch_sw=0;tick(15);pitch_sw=1;tick(12);gain_sw=1;tick(12);
        check(live==0 && voice==1 && pitch==1 && pitch_second== -12,"short diagnostic chord cannot switch voice");
        turn(0,1);check(gain==11 && pitch==1 && pitch_second== -12,"gain knob remains independent in dual effect");
        rst_n=0;tick(6);rst_n=1;tick(12);
        check(algorithm==0 && pitch==0 && pitch_second==7 && voice==0 && gain==10 && live==0,"full reset restores normal and both dual pitches");
        repeat(3)key(1,12);check(algorithm==3 && pitch==4 && pitch_second==7,"reset restores first dual pitch +4");
        $display("PASS DUAL_PANEL checks=%0d tone_entries=%0d",checks,tone_entries);
        $finish;
    end
    initial begin #20000000;$fatal(1,"dual panel timeout");end
endmodule
