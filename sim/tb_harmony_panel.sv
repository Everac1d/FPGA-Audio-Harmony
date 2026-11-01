`timescale 1ns/1ps
module tb_harmony_panel;
    reg clk=0,rst_n=0;always #10 clk=~clk;
    reg [3:0] button_n=15;
    reg gain_sw=1,pitch_sw=1,gain_clk=1,gain_dt=1,pitch_clk=1,pitch_dt=1;
    wire source,rec,play,restart,changed,reset_request,voice,ring_tuning;
    wire [1:0] live,algorithm;wire [4:0] gain;
    wire signed [4:0] pitch,pitch_second;wire signed [12:0] ring_calibration_margin;
    audio_harmony_controls #(.DEBOUNCE_CYCLES(3),.LONG_RESET_CYCLES(64),
        .LONG_REPLAY_CYCLES(30),.LONG_DIAG_CYCLES(40),.LONG_PITCH_CYCLES(40),
        .LONG_RING_TUNE_CYCLES(40),.RING_FAST_CYCLES(120),.UNIFIED_HARMONY(1),
        .RING_TUNE_ENABLE(1),.DUAL_VOICE_ENABLE(1),.ENCODER_FILTER_CYCLES(2)) dut(
        .clk(clk),.rst_n(rst_n),.button_n(button_n),
        .enc_gain_sw_n(gain_sw),.enc_gain_clk(gain_clk),.enc_gain_dt(gain_dt),
        .enc_pitch_sw_n(pitch_sw),.enc_pitch_clk(pitch_clk),.enc_pitch_dt(pitch_dt),
        .record_source(source),.live_mode(live),.gain_index(gain),
        .algorithm_mode(algorithm),.pitch_semitones(pitch),.pitch_second(pitch_second),.pitch_voice(voice),
        .ring_tuning(ring_tuning),.ring_calibration_margin(ring_calibration_margin),
        .record_toggle(rec),.play_toggle(play),.play_restart(restart),.source_changed(changed),.reset_request(reset_request));
    wire formal_tuning;wire signed [12:0] formal_margin;
    audio_harmony_controls #(.DEBOUNCE_CYCLES(3),.LONG_RESET_CYCLES(64),
        .LONG_REPLAY_CYCLES(30),.LONG_DIAG_CYCLES(40),.LONG_PITCH_CYCLES(40),
        .LONG_RING_TUNE_CYCLES(40),.RING_FAST_CYCLES(120),.UNIFIED_HARMONY(1),
        .RING_TUNE_ENABLE(0),.DUAL_VOICE_ENABLE(1),.ENCODER_FILTER_CYCLES(2)) formal(
        .clk(clk),.rst_n(rst_n),.button_n(button_n),
        .enc_gain_sw_n(gain_sw),.enc_gain_clk(gain_clk),.enc_gain_dt(gain_dt),
        .enc_pitch_sw_n(pitch_sw),.enc_pitch_clk(pitch_clk),.enc_pitch_dt(pitch_dt),
        .ring_tuning(formal_tuning),.ring_calibration_margin(formal_margin));
    integer checks=0,n,old_gain,old_live,old_margin,rec_events=0,play_events=0,resets=0;
    always @(posedge clk)if(rst_n)begin
        if(formal_tuning!==0 || formal_margin!==24)$fatal(1,"formal build never enters calibration UI");
        if(algorithm>2)$fatal(1,"public fourth effect must not exist");
        if(rec)rec_events=rec_events+1;if(play)play_events=play_events+1;if(reset_request)resets=resets+1;
    end
    task tick(input integer count);begin repeat(count)@(negedge clk);#1;end endtask
    task check(input logic okay,input string why);begin checks=checks+1;if(okay!==1'b1)$fatal(1,"HARMONY_PANEL %s margin=%0d gain=%0d tune=%0d",why,ring_calibration_margin,gain,ring_tuning);end endtask
    task key(input integer k,input integer held);begin button_n[k]=0;tick(held);button_n[k]=1;tick(12);end endtask
    task gain_press(input integer held);begin gain_sw=0;tick(held);gain_sw=1;tick(12);end endtask
    task pitch_press(input integer held);begin pitch_sw=0;tick(held);pitch_sw=1;tick(12);end endtask
    task phase(input bit which,input [1:0] value);begin
        if(which){pitch_clk,pitch_dt}=value;else {gain_clk,gain_dt}=value;tick(10);
    end endtask
    task turn(input bit which,input integer direction);begin
        phase(which,direction>0 ? 2'b01:2'b10);phase(which,0);
        phase(which,direction>0 ? 2'b10:2'b01);phase(which,3);
    end endtask
    initial begin
        tick(6);rst_n=1;tick(12);
        check(algorithm==0 && pitch==0 && pitch_second==0 && gain==10 && !ring_tuning && ring_calibration_margin==24,"merged defaults are0/0, ordinary pitch0 and margin24");
        repeat(3)turn(1,1);key(1,12);check(algorithm==1 && pitch==3,"ordinary pitch preserved");
        key(1,12);check(algorithm==2 && pitch==0 && pitch_second==0 && !voice,"single harmony page owns independent zero defaults");
        turn(1,1);pitch_press(12);turn(1,-1);check(pitch==1 && pitch_second== -1 && voice,"two harmony voices independent");
        pitch_press(60);check(pitch==1 && pitch_second==0 && voice,"long press resets selected voice");
        key(1,12);check(algorithm==0 && pitch==3,"three-mode wrap restores ordinary pitch");
        repeat(2)key(1,12);check(algorithm==2 && pitch==1 && pitch_second==0,"harmony settings survive wrap");
        gain_press(12);check(live==1,"daily short press enables microphone");old_live=live;old_gain=gain;
        gain_sw=0;tick(60);check(!ring_tuning && live==old_live,"long gain gesture waits for release");
        gain_sw=1;tick(12);check(ring_tuning && live==old_live && gain==old_gain,"long gain gesture enters calibration without muting");
        turn(0,1);check(ring_calibration_margin==25 && gain==old_gain,"first calibration step1 and no gain change");
        tick(160);turn(0,-1);check(ring_calibration_margin==24,"slow reversal step1");
        tick(160);turn(0,1);check(ring_calibration_margin==25,"first new direction is fine");
        turn(0,1);check(ring_calibration_margin==26,"second event still fine");
        turn(0,1);check(ring_calibration_margin==42,"third continuous event accelerates16");
        tick(160);turn(0,1);check(ring_calibration_margin==43,"slow movement returns to step1");
        repeat(300)turn(0,1);check(ring_calibration_margin==4095 && gain==old_gain,"positive margin saturates without affecting gain");
        repeat(600)turn(0,-1);check(ring_calibration_margin== -4096 && gain==old_gain,"negative margin saturates safely");
        turn(1,1);check(pitch_second==1 && pitch==1 && voice,"pitch encoder remains a voice control during calibration");
        old_margin=ring_calibration_margin;gain_press(12);check(live==0 && ring_tuning,"short press remains microphone mute while tuning");
        gain_press(60);check(!ring_tuning && live==0 && ring_calibration_margin==old_margin,"long release exits without extra short press");
        turn(0,1);check(gain==old_gain+1 && ring_calibration_margin==old_margin,"normal gain operation restored after exit");
        gain_press(60);gain_sw=0;tick(60);key(0,12);
        check(source && !ring_tuning && ring_calibration_margin==old_margin,"source switch exits tuning but retains value");
        gain_sw=1;tick(12);check(source && !ring_tuning && live==0,"old long shaft release cannot re-enter tuning after source change");
        gain_press(60);check(ring_tuning && source,"calibration UI also accessible in recorder source");
        key(2,12);key(3,12);check(rec_events==1 && play_events==1,"record/play buttons remain available");
        gain_sw=0;pitch_sw=0;tick(65);gain_sw=1;tick(12);pitch_sw=1;tick(12);
        check(live==0 && source && ring_tuning && ring_calibration_margin==old_margin,"record chord cannot enter tone or toggle tuning");
        gain_sw=0;tick(12);key(0,12);gain_sw=1;tick(12);
        check(!source && !ring_tuning && live==0,"old short shaft release cannot unmute new live source");
        gain_press(60);check(!source && ring_tuning,"new complete gain press works after cancelled gesture");
        gain_sw=0;pitch_sw=0;tick(65);gain_sw=1;tick(12);check(live==0 && ring_tuning,"one release of diagnostic chord has no action");
        pitch_sw=1;tick(12);check(live==2 && !ring_tuning && ring_calibration_margin==old_margin && pitch_second==1,"diagnostic chord has priority over both long presses");
        gain_press(12);check(live==0,"tone exits safely to mute");
        key(0,80);check(resets==1,"global reset command remains distinct");
        rst_n=0;tick(6);rst_n=1;tick(12);check(ring_calibration_margin==24 && !ring_tuning && pitch==0 && pitch_second==0,"global reset restores calibration and harmony defaults");
        $display("PASS HARMONY_PANEL checks=%0d modes3 harmony_default0_0 ordinary_pitch_independent tune_release long_chord_priority signed_margin4096 slow1_fast16 gain_unchanged endpoints reset",checks);$finish;
    end
    initial begin #20000000;$fatal(1,"harmony panel timeout");end
endmodule
