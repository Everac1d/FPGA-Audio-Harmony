`timescale 1ns/1ps
module tb_ring_softlow;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0; reg [7:0] level=0; reg [2:0] mask=0;
    wire ck,da,old_ck,old_da;
    sk9822_ring_softlow #(.HALF_PERIOD_CYCLES(1),.REFRESH_CYCLES(1024)) dut(
        .clk(clk),.rst_n(rst_n),.level(level),.color_mask_rgb(mask),.led_ck(ck),.led_da(da));
    sk9822_ring #(.HALF_PERIOD_CYCLES(1),.REFRESH_CYCLES(1024)) old(
        .clk(clk),.rst_n(rst_n),.level(level),.color_mask_rgb(mask),.led_ck(old_ck),.led_da(old_da));
    reg meter_rst=0,valid=0; reg signed [15:0] pcm=0;
    reg signed [12:0] live_margin=-2000;
    wire [7:0] fixed_level,live_level; wire [15:0] fixed_gate,live_gate,fixed_mean,live_mean;
    audio_ring_cal_meter #(.WINDOW_LOG2(2),.CALIBRATION_LOG2(2),.CALIBRATION_MARGIN(-2000),.LIVE_CALIBRATION(0)) fixed_meter(
        .clk(clk),.rst_n(meter_rst),.pcm(pcm),.pcm_valid(valid),.calibration_margin(13'sd4095),
        .level(fixed_level),.noise_floor(fixed_gate),.mean_level(fixed_mean));
    audio_ring_cal_meter #(.WINDOW_LOG2(2),.CALIBRATION_LOG2(2),.CALIBRATION_MARGIN(24),.LIVE_CALIBRATION(1)) live_meter(
        .clk(clk),.rst_n(meter_rst),.pcm(pcm),.pcm_valid(valid),.calibration_margin(live_margin),
        .level(live_level),.noise_floor(live_gate),.mean_level(live_mean));
    integer checks=0,frames=0,bits=0,legacy_bits=0,meter_cycles=0,calibrations=0;
    integer v,m,b,w; integer previous=-1,current,header;
    reg [31:0] word_value,old_word,expected_pixel;
    reg [7:0] rgb;
    task check(input bit ok,input string why);
        begin checks=checks+1;if(!ok)$fatal(1,"%s L=%0d mask=%0d frame%0d bit%0d",why,level,mask,frames,bits);end
    endtask
    function integer expected_global(input integer x);
        begin
            if(x<16)expected_global=4;
            else if(x<32)expected_global=5;
            else if(x<48)expected_global=6;
            else if(x<64)expected_global=7;
            else expected_global=8;
        end
    endfunction
    task frame(input integer lev,input integer col,input bit disturb);
        begin
            @(negedge clk);rst_n=0;level=lev;mask=col;
            repeat(2)@(negedge clk);
            rst_n=1;rgb=lev/2;header=224+expected_global(lev);
            expected_pixel={header[7:0],(col&1)?rgb:8'd0,(col&2)?rgb:8'd0,(col&4)?rgb:8'd0};
            word_value=0;old_word=0;
            for(b=0;b<448;b=b+1)begin
                @(posedge ck);#1;
                check(old_ck===1'b1,"clock equivalence");
                word_value={word_value[30:0],da};old_word={old_word[30:0],old_da};
                bits=bits+1;
                if(lev>=64)begin check(da===old_da,"high-level legacy bit equivalence");legacy_bits=legacy_bits+1;end
                if(b==100 && disturb)begin level=255-lev;mask=col^7;end
                if((b%32)==31)begin
                    w=b/32;
                    if(w==0)check(word_value===32'd0,"zero start");
                    else if(w==13)check(word_value===32'hffffffff,"one end");
                    else begin
                        check(word_value===expected_pixel,"all twelve atomic pixels");
                        check(old_word[23:0]===expected_pixel[23:0],"unchanged RGB and color mask");
                        check(old_word[31:24]===8'he8,"legacy global8 reference");
                    end
                    if(lev>=64)check(word_value===old_word,"complete high-level legacy word");
                end
            end
            frames=frames+1;
        end
    endtask
    always @(negedge clk)begin
        if(rst_n)check(ck===old_ck,"entire clock waveform equivalence");
    end
    always @(posedge clk)begin
        #1;
        if(meter_rst)begin
            check({fixed_level,fixed_gate,fixed_mean}==={live_level,live_gate,live_mean},"fixed negative margin cycle-exact live match");
            meter_cycles=meter_cycles+1;
        end
    end
    task sample(input integer x);
        begin @(negedge clk);pcm=x;valid=1;@(negedge clk);valid=0;repeat(3)@(negedge clk);end
    endtask
    task calibrate(input integer base,input integer gate);
        integer k;
        begin
            @(negedge clk);meter_rst=0;valid=0;pcm=0;live_margin=-2000;
            repeat(3)@(negedge clk);meter_rst=1;
            for(k=0;k<16;k=k+1)sample((k%2)?-base:base);
            repeat(5)@(negedge clk);
            check(fixed_gate==gate,"negative static gate and saturation");
            // Speech after calibration changes mean and brightness, not the stored baseline.
            for(k=0;k<48;k=k+1)sample((k%2)?-32768:32767);
            repeat(5)@(negedge clk);check(fixed_gate==gate,"speech does not change stored gate");
            for(k=0;k<192;k=k+1)sample(0);
            repeat(40)@(negedge clk);check(fixed_level==0,"silence releases to darkness");
            calibrations=calibrations+1;
        end
    endtask
    initial begin
        // All 256 levels and all eight masks are decoded from actual 12-LED serial frames.
        for(v=0;v<256;v=v+1)begin
            current=expected_global(v)*(v/2);
            check(current>=previous,"effective light monotonic");
            check(current<=8*(v/2),"never brighter than accepted original");
            if(v>=64)check(current==8*(v/2),"large levels unchanged");
            if(v==2)check(current*2==8,"first nonzero brightness halved");
            previous=current;
            for(m=0;m<8;m=m+1)frame(v,m,1);
        end
        // Asynchronous reset in a partially transmitted pixel clears both pins and state.
        @(negedge clk);rst_n=0;level=2;mask=7;repeat(2)@(negedge clk);rst_n=1;
        repeat(85)@(posedge ck);
        #2;rst_n=0;#1;
        check(ck===0 && da===0 && dut.busy===0 && dut.frame_pixel===0,"asynchronous midframe reset");
        frame(2,7,0);frame(64,7,0);frame(255,7,0);
        rst_n=0;
        calibrate(1305,610);
        calibrate(0,64);calibrate(1000,64);calibrate(1032,64);calibrate(1033,66);
        calibrate(32768,63536);
        $display("PASS RING_SOFTLOW checks=%0d frames=%0d decoded_bits=%0d legacy_high_bits=%0d meter_cycles=%0d calibrations=%0d all256x8_masks atomic_midframe reset min_half monotonic fixed_minus2000_gate610",checks,frames,bits,legacy_bits,meter_cycles,calibrations);
        $finish;
    end
    initial begin #100000000;$fatal(1,"timeout");end
endmodule
