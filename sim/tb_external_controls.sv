`timescale 1ns/1ps
module tb_external_controls;
    reg clk=0,rst_n=0;
    always #10 clk=~clk;
    reg [3:0] button_n=4'b1111;
    reg gain_sw=1,gain_clk=1,gain_dt=1,pitch_sw=1,pitch_clk=1,pitch_dt=1;
    wire source,rec,play,restart,changed,reset_request;
    wire [1:0] live,algorithm;
    wire [4:0] gain;
    wire signed [4:0] pitch;
    audio_external_controls #(.DEBOUNCE_CYCLES(4),.LONG_RESET_CYCLES(32),
        .LONG_REPLAY_CYCLES(20),.ENCODER_FILTER_CYCLES(3)) dut(
        .clk(clk),.rst_n(rst_n),.button_n(button_n),
        .enc_gain_sw_n(gain_sw),.enc_gain_clk(gain_clk),.enc_gain_dt(gain_dt),
        .enc_pitch_sw_n(pitch_sw),.enc_pitch_clk(pitch_clk),.enc_pitch_dt(pitch_dt),
        .record_source(source),.live_mode(live),.gain_index(gain),
        .algorithm_mode(algorithm),.pitch_semitones(pitch),
        .record_toggle(rec),.play_toggle(play),.play_restart(restart),
        .source_changed(changed),.reset_request(reset_request));
    reg reverse_clk=1,reverse_dt=1;
    wire reverse_up,reverse_down;
    audio_panel_encoder #(.FILTER_CYCLES(1),.REVERSE(1)) reverse_dut(
        .clk(clk),.rst_n(rst_n),.contact_clk(reverse_clk),.contact_dt(reverse_dt),
        .step_up(reverse_up),.step_down(reverse_down));
    integer checks=0,rec_count=0,play_count=0,restart_count=0,source_count=0,reset_count=0;
    integer reverse_up_count=0,reverse_down_count=0;
    reg [4:0] previous_pulses=0;
    always @(negedge clk)begin
        if(rst_n)begin
            if(({rec,play,restart,changed,reset_request} & previous_pulses)!=0)
                $fatal(1,"Command pulse exceeded one clock");
            if(rec)rec_count=rec_count+1;
            if(play)play_count=play_count+1;
            if(restart)restart_count=restart_count+1;
            if(changed)source_count=source_count+1;
            if(reset_request)reset_count=reset_count+1;
            if(reverse_up)reverse_up_count=reverse_up_count+1;
            if(reverse_down)reverse_down_count=reverse_down_count+1;
            if(play && restart)$fatal(1,"Replay long/short commands overlapped");
            previous_pulses={rec,play,restart,changed,reset_request};
        end else previous_pulses=0;
    end
    task tick(input integer count);begin repeat(count)@(negedge clk);#1;end endtask
    task check(input logic ok,input string message);begin
        checks=checks+1;
        if(ok!==1'b1)$fatal(1,"check %0d: %s",checks,message);
    end endtask
    task key(input integer index,input integer held);begin
        @(negedge clk);button_n[index]=0;tick(held);
        button_n[index]=1;tick(12);
    end endtask
    task gain_press;begin gain_sw=0;tick(12);gain_sw=1;tick(12);end endtask
    task pitch_press;begin pitch_sw=0;tick(12);pitch_sw=1;tick(12);end endtask
    task phase(input integer encoder,input [1:0] value,input integer clocks);begin
        @(negedge clk);
        case(encoder)
            0:{gain_clk,gain_dt}=value;
            1:{pitch_clk,pitch_dt}=value;
            2:{reverse_clk,reverse_dt}=value;
        endcase
        tick(clocks);
    end endtask
    task turn(input integer encoder,input integer direction,input integer clocks);begin
        if(direction>0)begin phase(encoder,2'b01,clocks);phase(encoder,2'b00,clocks);
            phase(encoder,2'b10,clocks);phase(encoder,2'b11,clocks);end
        else begin phase(encoder,2'b10,clocks);phase(encoder,2'b00,clocks);
            phase(encoder,2'b01,clocks);phase(encoder,2'b11,clocks);end
        tick(5);
    end endtask
    integer n;
    initial begin
        tick(5);rst_n=1;tick(12);
        check(source==0 && live==0 && gain==10 && algorithm==0 && pitch==0,"safe defaults");
        key(2,12);key(3,12);key(3,45);
        check(rec_count==0 && play_count==0 && restart_count==0,"record/replay ignored in live");
        gain_press();check(live==1,"live microphone");
        gain_press();check(live==0,"live mute without test tone");
        key(1,12);check(algorithm==1,"pitch effect");
        key(1,70);check(algorithm==2,"held effect dispatched only once on release");
        key(1,12);check(algorithm==0,"effect wrap");
        // Raw 1-clock contact chatter is shorter than the button filter.
        repeat(5)begin button_n[0]=0;tick(1);button_n[0]=1;tick(1);end
        tick(15);check(source_count==0 && source==0,"short button chatter ignored");
        button_n[0]=0;tick(12);
        check(source_count==0,"button waits for release");
        button_n[0]=1;tick(12);
        check(source_count==1 && source==1 && reset_count==0,"short mode switch");
        gain_press();check(live==0,"live sound contact ignored in record source");
        key(2,12);check(rec_count==1,"record command");
        key(2,90);check(rec_count==2,"held record command occurs once");
        key(3,12);check(play_count==1 && restart_count==0,"short replay command");
        key(3,45);check(play_count==1 && restart_count==1,"long replay suppresses short");
        // Full detents in both directions, including all numeric gain endpoints.
        for(n=11;n<=30;n=n+1)begin turn(0,1,10);check(gain==n,"gain up 0.1 detent");end
        repeat(5)begin turn(0,1,10);check(gain==30,"gain upper saturation");end
        for(n=29;n>=10;n=n-1)begin turn(0,-1,10);check(gain==n,"gain down 0.1 detent");end
        repeat(5)begin turn(0,-1,10);check(gain==10,"gain lower saturation");end
        for(n=1;n<=12;n=n+1)begin turn(1,1,10);check($signed(pitch)==n,"pitch up 1 semitone detent");end
        repeat(4)begin turn(1,1,10);check(pitch==12,"pitch upper saturation");end
        for(n=11;n>=-12;n=n-1)begin turn(1,-1,10);check($signed(pitch)==n,"pitch down 1 semitone detent");end
        repeat(4)begin turn(1,-1,10);check(pitch== -12,"pitch lower saturation");end
        pitch_press();check(pitch==0,"pitch press returns zero");
        // A partially turned contact bouncing backwards is not a detent.
        phase(0,2'b01,10);phase(0,2'b11,10);phase(0,2'b01,10);phase(0,2'b11,10);
        check(gain==10,"partial travel cancels");
        // Diagonal jumps cannot contribute part of a later complete detent.
        phase(0,2'b00,10);phase(0,2'b10,10);phase(0,2'b11,10);
        check(gain==10,"illegal jump discarded until anchor");
        turn(0,1,10);check(gain==11,"decoder recovers after illegal jump");
        // Contact bounce on valid edges produces one completed cycle only.
        phase(0,2'b01,10);phase(0,2'b11,10);phase(0,2'b01,10);
        phase(0,2'b00,10);phase(0,2'b01,10);phase(0,2'b00,10);
        phase(0,2'b10,10);phase(0,2'b00,10);phase(0,2'b10,10);
        phase(0,2'b11,10);tick(5);check(gain==12,"quadrature edge bounce cancels");
        // Brief impulses are rejected before the quadrature state machine.
        phase(0,2'b01,1);phase(0,2'b11,10);
        check(gain==12,"sub-filter phase glitch ignored");
        // Rapid but valid turns, still longer than synchronization/filter budget.
        for(n=0;n<20;n=n+1)begin
            turn(1,1,6);check(pitch==1,"rapid positive turn");
            turn(1,-1,6);check(pitch==0,"rapid negative turn");
        end
        turn(2,1,6);check(reverse_down_count==1 && reverse_up_count==0,"direction reversal parameter");
        turn(2,-1,6);check(reverse_down_count==1 && reverse_up_count==1,"reverse decoder return");
        // Source changes preserve the selected effect, pitch and gain.
        key(1,12);turn(1,1,10);key(0,12);
        check(source==0 && live==0 && gain==12 && pitch==1 && algorithm==1,"source change retains parameters");
        // Long reset does nothing while held, then emits only reset on release.
        button_n[0]=0;tick(80);
        check(reset_count==0 && source_count==2,"long reset waits for release");
        button_n[0]=1;tick(12);
        check(reset_count==1 && source_count==2 && source==0,"long reset suppresses mode toggle");
        rst_n=0;tick(5);rst_n=1;tick(12);
        check(source==0 && live==0 && gain==10 && pitch==0 && algorithm==0,"reset returns defaults");
        // Reset in the middle of a turn discards partial mechanical movement.
        phase(0,2'b01,10);rst_n=0;tick(5);rst_n=1;tick(12);
        phase(0,2'b00,10);phase(0,2'b10,10);phase(0,2'b11,10);
        check(gain==10,"reset cancels partial turn");
        turn(0,1,10);check(gain==11,"full turn after reset");
        $display("PASS EXTERNAL_CONTROLS checks=%0d rec=%0d play=%0d restart=%0d source=%0d reset=%0d",checks,rec_count,play_count,restart_count,source_count,reset_count);
        $finish;
    end
    initial begin #10000000;$fatal(1,"external controls timeout");end
endmodule
