`timescale 1ns/1ps
// Deliberately small debounce/hold thresholds; DUT clocks retain full ordering.
module tb_record_keys;
    localparam integer DB=3, LP=12;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, mode_n=1, gain_n=1;
    wire record_source;
    wire [1:0] live_mode, algorithm_mode;
    wire [2:0] gain_index;
    wire signed [4:0] pitch_semitones;
    wire record_toggle,play_toggle,source_changed;
    integer rec_pulses=0,play_pulses=0,source_pulses=0,checks=0;
    reg prev_record=0,prev_play=0,prev_source=0;
    audio_record_keys #(.DEBOUNCE_CYCLES(DB),.LONG_PRESS_CYCLES(LP)) dut (
        .clk(clk),.rst_n(rst_n),.key_mode_n(mode_n),.key_gain_n(gain_n),
        .record_source(record_source),.live_mode(live_mode),.gain_index(gain_index),
        .algorithm_mode(algorithm_mode),.pitch_semitones(pitch_semitones),
        .record_toggle(record_toggle),.play_toggle(play_toggle),.source_changed(source_changed)
    );
    task check(input bit condition,input [511:0] message);
        begin checks=checks+1; if(!condition) begin $display("FAIL %0s",message);$fatal(1);end end
    endtask
    task clocks(input integer count);
        begin repeat(count) begin @(posedge clk); #1; end end
    endtask
    task keys(input bit m,input bit g);
        begin @(negedge clk);mode_n=m;gain_n=g;end
    endtask
    task settle; begin clocks(DB+7);end endtask
    task solo(input bit gain_key,input bit long_press);
        begin
            keys(gain_key, !gain_key);
            clocks(long_press ? (LP+DB+8) : (DB+5));
            keys(1,1);settle;
        end
    endtask
    task chord(input bit long_press,input bit mode_first_release);
        begin
            keys(0,0);clocks(long_press ? (LP+DB+8) : (DB+5));
            if(mode_first_release) keys(1,0);else keys(0,1);
            // First release must never dispatch a command.
            clocks(DB+7);
            check(!source_changed && !record_toggle && !play_toggle,"partial chord release dispatched");
            keys(1,1);settle;
        end
    endtask
    always @(posedge clk) begin
        #2;
        if (rst_n) begin
            if(record_toggle) rec_pulses=rec_pulses+1;
            if(play_toggle) play_pulses=play_pulses+1;
            if(source_changed) source_pulses=source_pulses+1;
            check(!(record_toggle&&prev_record),"record pulse wider than one cycle");
            check(!(play_toggle&&prev_play),"play pulse wider than one cycle");
            check(!(source_changed&&prev_source),"source pulse wider than one cycle");
            check(!(record_toggle||play_toggle||source_changed)||
                  (dut.mode_stable&&dut.gain_stable),"event before all debounced keys released");
        end
        prev_record=record_toggle;prev_play=play_toggle;prev_source=source_changed;
    end
    integer i,old_source,old_rec,old_play;
    reg [2:0] expected_gain[0:4];
    reg signed [4:0] expected_pitch[0:6];
    initial begin
        expected_gain[0]=2;expected_gain[1]=4;expected_gain[2]=5;expected_gain[3]=6;expected_gain[4]=0;
        expected_pitch[0]=4;expected_pitch[1]=8;expected_pitch[2]=12;expected_pitch[3]=-4;
        expected_pitch[4]=-8;expected_pitch[5]=-12;expected_pitch[6]=0;
        clocks(4);@(negedge clk);rst_n=1;settle;
        check(!record_source&&live_mode==0&&gain_index==0&&algorithm_mode==0&&pitch_semitones==0,"reset defaults");
        // Sub-debounce contact noise must have no effect, even after synchronization.
        keys(0,1);clocks(1);keys(1,1);clocks(2);keys(0,1);clocks(1);keys(1,1);settle;
        check(live_mode==0&&algorithm_mode==0,"press bounce generated command");
        solo(0,0);check(live_mode==1,"live short mode 1");
        solo(0,0);check(live_mode==2,"live short mode 2");
        solo(0,0);check(live_mode==0,"live short wraps");
        for(i=0;i<5;i=i+1) begin solo(1,0);check(gain_index==expected_gain[i],"five gain cycle");end
        for(i=0;i<7;i=i+1) begin solo(1,1);check(pitch_semitones==expected_pitch[i]&&gain_index==0,"pitch cycle without short gain");end
        for(i=1;i<=3;i=i+1) begin solo(0,1);check(algorithm_mode==(i%3)&&live_mode==0,"algorithm cycle without short mode");end
        old_play=play_pulses;chord(0,1);
        check(!record_source&&play_pulses==old_play&&live_mode==0&&gain_index==0,"live short chord must be inert");
        // Held gestures, including a first key long before second arrives,
        // cannot emit the solo long action before all keys have been released.
        keys(0,1);clocks(LP*3+DB+8);
        check(algorithm_mode==0&&live_mode==0,"single long dispatched before release");
        keys(0,0);clocks(DB+5);keys(1,0);settle;
        check(algorithm_mode==0&&gain_index==0&&source_pulses==0,"late chord emitted solo command");
        keys(1,1);settle;
        check(!record_source&&algorithm_mode==0&&gain_index==0,"short overlap incorrectly long chord");
        old_source=source_pulses;chord(1,0);
        check(record_source&&live_mode==0&&source_pulses==old_source+1,"long chord enters recording source");
        old_rec=rec_pulses;solo(0,0);check(rec_pulses==old_rec+1,"record short toggles recording");
        solo(0,0);check(rec_pulses==old_rec+2,"second record short stops recording");
        old_play=play_pulses;chord(0,0);check(play_pulses==old_play+1,"short chord plays");
        chord(0,1);check(play_pulses==old_play+2,"short chord stops with opposite release order");
        solo(0,1);check(algorithm_mode==1&&rec_pulses==old_rec+2,"record long only changes effect");
        solo(1,0);check(gain_index==2,"record short gain retained");
        solo(1,1);check(pitch_semitones==4,"record long pitch retained");
        // Exact classification boundaries using observed debounced low cycles.
        keys(1,0);wait(dut.gain_stable==0);clocks(LP-DB-3);keys(1,1);settle;
        check(gain_index==4&&pitch_semitones==4,"one below long threshold classified short");
        keys(1,0);wait(dut.gain_stable==0);clocks(LP-DB-2);keys(1,1);settle;
        check(gain_index==4&&pitch_semitones==8,"exact long threshold classified long");
        // Release bounce does not prematurely finish a gesture.
        old_rec=rec_pulses;
        keys(0,1);clocks(DB+3);keys(1,1);clocks(1);keys(0,1);clocks(2);
        check(rec_pulses==old_rec,"release bounce dispatched record");
        keys(1,1);settle;check(rec_pulses==old_rec+1,"release bounce lost short record");
        // Long holds only dispatch once on release, with no extra short action.
        old_source=source_pulses;old_play=play_pulses;old_rec=rec_pulses;
        keys(0,0);clocks(LP*20);
        check(source_pulses==old_source&&play_pulses==old_play&&rec_pulses==old_rec,"held chord repeated or dispatched early");
        keys(1,1);settle;clocks(LP*3);
        check(!record_source&&source_pulses==old_source+1&&play_pulses==old_play&&rec_pulses==old_rec,"long chord release dispatch count");
        check(live_mode==0&&algorithm_mode==1&&gain_index==4&&pitch_semitones==8,"source switch failed preserve effects/reset mute");
        // Reset while keys held cancels pending gestures and restores defaults.
        keys(0,0);settle;@(negedge clk);rst_n=0;clocks(3);keys(1,1);clocks(3);
        @(negedge clk);rst_n=1;settle;
        check(!record_source&&live_mode==0&&gain_index==0&&algorithm_mode==0&&pitch_semitones==0,"reset cancellation/defaults");
        $display("PASS tb_record_keys checks=%0d rec=%0d play=%0d source=%0d",checks,rec_pulses,play_pulses,source_pulses);
        $finish;
    end
    initial begin #2000000;$fatal(1,"timeout tb_record_keys");end
endmodule
