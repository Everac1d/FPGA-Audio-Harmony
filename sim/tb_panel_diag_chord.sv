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
        // Short overlap owns both releases and leaves live/pitch unchanged.
        old_entries=tone_entries;gain_sw=0;pitch_sw=0;tick(16);
        gain_sw=1;tick(12);check(live==1 && pitch==2,"short chord first release swallowed");
        pitch_sw=1;tick(12);check(live==1 && pitch==2 && tone_entries==old_entries,"short chord no action");
        // The order in which the two shafts are pressed is unrestricted; only
        // the common continuously held interval contributes to the 2s count.
        gain_sw=0;tick(DIAG+20);pitch_sw=0;tick(16);
        check(live==1,"first shaft alone cannot qualify chord");
        pitch_sw=1;tick(12);gain_sw=1;tick(12);
        check(live==1 && pitch==2 && tone_entries==old_entries,"long first hold plus short overlap rejected");
        // Qualify while live, release gain first, and leave pitch held longer.
        gain_sw=0;tick(14);pitch_sw=0;tick(DIAG+20);
        check(live==1 && pitch==2 && dut.diag_qualified,"qualified chord waits for every release");
        gain_sw=1;tick(DIAG+15);check(live==1 && pitch==2,"first release never starts tone");
        pitch_sw=1;tick(12);
        check(live==2 && pitch==2 && tone_entries==old_entries+1,"last release starts exactly one tone entry");
        tick(100);check(tone_entries==old_entries+1,"no repeat once fully released");
        gain_press();check(live==0,"tone exit uses gain press to safe mute");
        gain_press();check(live==1,"next ordinary press enables microphone");
        // Qualify with opposite press/release order.
        old_entries=tone_entries;pitch_sw=0;tick(20);gain_sw=0;tick(DIAG+20);
        pitch_sw=1;tick(12);check(live==1 && pitch==2,"opposite first release swallowed");
        gain_sw=1;tick(12);check(live==2 && pitch==2 && tone_entries==old_entries+1,"opposite last release works");
        gain_press();
        // A cancelled early release cannot accumulate time after repressing.
        gain_sw=0;pitch_sw=0;tick(16);gain_sw=1;tick(12);
        gain_sw=0;tick(DIAG+50);pitch_sw=1;tick(12);gain_sw=1;tick(12);
        check(live==0 && pitch==2,"short broken overlap stays cancelled until both up");
        // Contact chatter below debounce cannot create either a chord or a press.
        repeat(6)begin gain_sw=0;pitch_sw=0;tick(1);gain_sw=1;pitch_sw=1;tick(1);end
        tick(12);check(live==0 && pitch==2,"sub-debounce simultaneous chatter ignored");
        // A source switch cancels an already qualified chord and consumes its
        // trailing releases, including when the source is switched back first.
        old_entries=tone_entries;gain_sw=0;pitch_sw=0;tick(DIAG+20);
        key(0,12);check(source==1 && live==0,"source switch cancels qualified chord");
        key(0,12);check(source==0 && live==0,"return live does not revive held chord");
        gain_sw=1;tick(12);pitch_sw=1;tick(12);
        check(live==0 && pitch==2 && tone_entries==old_entries,"cancelled chord releases cannot unmute or reset pitch");
        // A chord begun in record mode remains invalid even if live is selected
        // before the shafts are released.
        key(0,12);gain_sw=0;pitch_sw=0;tick(DIAG+30);
        key(0,12);pitch_sw=1;tick(12);gain_sw=1;tick(12);
        check(source==0 && live==0 && pitch==2 && tone_entries==old_entries,"record-origin chord never enters tone");
        // Source switch on the same edge as final release has explicit priority.
        gain_sw=0;pitch_sw=0;tick(DIAG+20);
        button_n[0]=0;tick(12);button_n[0]=1;gain_sw=1;pitch_sw=1;tick(12);
        check(source==1 && live==0 && tone_entries==old_entries,"simultaneous source/final release prioritizes source");
        // Reset interrupts a pending qualified gesture; no deferred entry survives.
        key(0,12);gain_sw=0;pitch_sw=0;tick(DIAG+20);
        rst_n=0;tick(6);gain_sw=1;pitch_sw=1;rst_n=1;tick(12);
        check(source==0 && live==0 && pitch==0 && tone_entries==old_entries,"reset flushes chord state");
        // Holding both through reset requires a fresh full debounced overlap.
        gain_sw=0;pitch_sw=0;rst_n=0;tick(6);rst_n=1;tick(20);
        check(!dut.diag_qualified && live==0,"held startup cannot qualify early");
        tick(DIAG+10);check(live==0 && dut.diag_qualified,"held startup still requires final release");
        gain_sw=1;pitch_sw=1;tick(12);check(live==2,"fresh full startup overlap may enter diagnostic");
        // Physical diagnostic duration remains 2 seconds in the production default.
        check(dut.LONG_DIAG_CYCLES==DIAG,"test explicitly scales diagnostic duration only");
        $display("PASS PANEL_DIAG_CHORD checks=%0d tone_entries=%0d source_events=%0d reset_events=%0d",checks,tone_entries,source_events,reset_events);
        $finish;
    end
    initial begin #10000000;$fatal(1,"panel chord timeout");end
endmodule
