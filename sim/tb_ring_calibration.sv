`timescale 1ns/1ps
// Compare the fixed production setting cycle-for-cycle with the accepted
// meter, then exercise the new signed runtime margin independently.
module tb_ring_calibration;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,pcm_valid=0;reg signed [15:0] pcm=0;
    reg signed [12:0] calibration_margin=24;
    wire [7:0] legacy_level,fixed_level,live_level;
    wire [15:0] legacy_floor,fixed_floor,live_floor,legacy_mean,fixed_mean,live_mean;
    wire led_ck,led_da;
    audio_level_meter #(.WINDOW_LOG2(2),.CALIBRATION_LOG2(2),.CALIBRATION_MARGIN(24)) legacy(
        .clk(clk),.rst_n(rst_n),.pcm(pcm),.pcm_valid(pcm_valid),.level(legacy_level),.noise_floor(legacy_floor),.mean_level(legacy_mean));
    audio_ring_cal_meter #(.WINDOW_LOG2(2),.CALIBRATION_LOG2(2),.CALIBRATION_MARGIN(24),.LIVE_CALIBRATION(0)) fixed_meter(
        .clk(clk),.rst_n(rst_n),.pcm(pcm),.pcm_valid(pcm_valid),.calibration_margin(calibration_margin),
        .level(fixed_level),.noise_floor(fixed_floor),.mean_level(fixed_mean));
    audio_ring_cal_meter #(.WINDOW_LOG2(2),.CALIBRATION_LOG2(2),.CALIBRATION_MARGIN(24),.LIVE_CALIBRATION(1)) live_meter(
        .clk(clk),.rst_n(rst_n),.pcm(pcm),.pcm_valid(pcm_valid),.calibration_margin(calibration_margin),
        .level(live_level),.noise_floor(live_floor),.mean_level(live_mean));
    sk9822_ring #(.HALF_PERIOD_CYCLES(1),.REFRESH_CYCLES(256),.LED_COUNT(1)) ring(
        .clk(clk),.rst_n(rst_n),.level(live_level),.color_mask_rgb(3'b011),.led_ck(led_ck),.led_da(led_da));
    reg prod_rst_n=0,prod_valid=0;reg signed [15:0] prod_pcm=0;
    wire [7:0] prod_old_level,prod_new_level;
    wire [15:0] prod_old_floor,prod_new_floor,prod_old_mean,prod_new_mean;
    audio_level_meter #(.CALIBRATION_MARGIN(24)) production_legacy(
        .clk(clk),.rst_n(prod_rst_n),.pcm(prod_pcm),.pcm_valid(prod_valid),
        .level(prod_old_level),.noise_floor(prod_old_floor),.mean_level(prod_old_mean));
    audio_ring_cal_meter #(.CALIBRATION_MARGIN(24),.LIVE_CALIBRATION(0)) production_fixed(
        .clk(clk),.rst_n(prod_rst_n),.pcm(prod_pcm),.pcm_valid(prod_valid),.calibration_margin(13'sd24),
        .level(prod_new_level),.noise_floor(prod_new_floor),.mean_level(prod_new_mean));
    integer checks=0,cycle_checks=0,production_checks=0,windows=0,serial_frames=0;
    integer swept_margins=0,swept_magnitudes=0,calibrations=0;
    integer expected_legacy_level=0,expected_live_level=0,expected_baseline=0;
    integer expected_legacy_floor=64;
    reg live_equivalent=1;
    task check(input bit ok,input string message);
        begin checks=checks+1;if(!ok)$fatal(1,"%s mean%0d base%0d margin%0d floors%0d/%0d/%0d levels%0d/%0d/%0d",message,live_mean,expected_baseline,$signed(calibration_margin),legacy_floor,fixed_floor,live_floor,legacy_level,fixed_level,live_level);end
    endtask
    always @(posedge clk)begin
        #1;
        if(rst_n)begin
            if(legacy_level!==fixed_level || legacy_floor!==fixed_floor || legacy_mean!==fixed_mean)$fatal(1,"LIVE0 differs from accepted meter at a clock edge");
            if(live_mean!==legacy_mean)$fatal(1,"runtime margin changed mean statistics/timing");
            if(live_equivalent && (live_level!==legacy_level || live_floor!==legacy_floor))$fatal(1,"LIVE1 at margin24 differs from accepted meter");
            cycle_checks=cycle_checks+1;
        end
        if(prod_rst_n)begin
            if(prod_old_level!==prod_new_level || prod_old_floor!==prod_new_floor || prod_old_mean!==prod_new_mean)$fatal(1,"default512sample/128window meter mismatch");
            production_checks=production_checks+1;
        end
    end
    task clocks(input integer count);begin repeat(count)begin @(posedge clk);#2;end end endtask
    function integer abs16(input integer value);begin abs16=value<0?-value:value;end endfunction
    function integer gate(input integer baseline,input integer margin);
        integer value;
        begin value=baseline*2+margin;if(value<64)gate=64;else if(value>65535)gate=65535;else gate=value;end
    endfunction
    function integer curve(input integer value);
        begin
            if(value<512)curve=value/16;
            else if(value<1024)curve=32+(value-512)*3/64;
            else if(value<2048)curve=56+(value-1024)*5/128;
            else if(value<4096)curve=96+(value-2048)*3/128;
            else if(value<8192)curve=144+(value-4096)*7/512;
            else if(value<16384)curve=200+(value-8192)*55/8192;
            else curve=255;
        end
    endfunction
    function integer release_level(input integer previous,input integer wanted);
        integer step;
        begin step=previous/8;if(step<8)step=8;
            if(wanted>=previous)release_level=wanted;
            else if(previous-wanted>step)release_level=previous-step;
            else release_level=wanted;
        end
    endfunction
    task raw_window(input integer sample);
        begin @(negedge clk);pcm=sample;pcm_valid=1;clocks(4);
            @(negedge clk);pcm_valid=0;clocks(4);windows=windows+1;end
    endtask
    task checked_window(input integer sample);
        integer mag,target_old,target_live,floor_live;
        begin
            mag=abs16(sample);floor_live=gate(expected_baseline,$signed(calibration_margin));
            target_old=curve(mag>expected_legacy_floor ? mag-expected_legacy_floor:0);
            target_live=curve(mag>floor_live ? mag-floor_live:0);
            expected_legacy_level=release_level(expected_legacy_level,target_old);
            expected_live_level=release_level(expected_live_level,target_live);
            raw_window(sample);
            check(legacy_mean==mag && fixed_mean==mag && live_mean==mag,"exact window magnitude");
            check(legacy_floor==expected_legacy_floor && live_floor==floor_live,"fixed and signed live floor oracle");
            check(legacy_level==expected_legacy_level && fixed_level==expected_legacy_level,"accepted curve/release unchanged");
            check(live_level==expected_live_level,"runtime curve/release oracle");
            check(live_meter.calibrated && live_meter.calibrated_baseline==expected_baseline,"baseline remains latched after speech");
        end
    endtask
    task calibrate(input integer sample);
        integer j;
        begin
            @(negedge clk);rst_n=0;pcm_valid=0;pcm=0;calibration_margin=24;live_equivalent=1;clocks(5);
            check(legacy_level==0 && fixed_level==0 && live_level==0,"reset flushes all display slots");
            @(negedge clk);rst_n=1;
            for(j=0;j<4;j=j+1)begin raw_window(sample);check(legacy_level==0&&live_level==0,"calibration is entirely dark");end
            expected_baseline=abs16(sample);expected_legacy_floor=gate(expected_baseline,24);
            expected_legacy_level=0;expected_live_level=0;calibrations=calibrations+1;
            check(live_meter.calibrated_baseline==expected_baseline,"stores completed calibration rather than a moving baseline wire");
            checked_window(sample);
        end
    endtask
    task set_margin(input integer value);
        integer old_mean,old_count,old_sum;
        begin
            live_equivalent=0;old_mean=live_mean;old_count=live_meter.sample_count;old_sum=live_meter.magnitude_sum;
            @(negedge clk);calibration_margin=value;#2;
            check(live_floor==gate(expected_baseline,value),"signed clamp gate updates with runtime setting");
            clocks(1);
            check(live_mean==old_mean && live_meter.sample_count==old_count && live_meter.magnitude_sum==old_sum,"turning margin alone never advances/reset statistics");
            check(live_meter.calibrated && live_meter.calibrated_baseline==expected_baseline,"margin edit never re-enters calibration");
        end
    endtask
    task serial_frame(input integer intensity);
        integer word_number,bit_number;reg [31:0] word_value;
        begin
            @(negedge clk);while(ring.busy)@(negedge clk);while(!ring.busy)@(negedge clk);
            for(word_number=0;word_number<3;word_number=word_number+1)begin
                word_value=0;
                for(bit_number=31;bit_number>=0;bit_number=bit_number-1)begin @(posedge led_ck);#2;word_value[bit_number]=led_da;end
                case(word_number)
                0:check(word_value==0,"SK9822 real start word");
                1:begin check(word_value[31:24]==8'he8,"globalbrightness8/31 retained");
                    check(word_value[23:16]==intensity && word_value[15:8]==intensity && word_value[7:0]==0,"actual BGR serial bytes retain level/2");end
                2:check(word_value==32'hffffffff,"SK9822 real end word");endcase
            end
            serial_frames=serial_frames+1;
        end
    endtask
    integer b,m,i,j,mag,held_mean;integer baselines[0:5];integer margins[0:8];
    initial begin
        // Accepted production parameters, including valid gaps and real 512x128 calibration.
        clocks(5);@(negedge clk);prod_rst_n=1;prod_pcm=128;
        for(i=0;i<65536;i=i+1)begin
            @(negedge clk);prod_valid=1;clocks(1);
            if((i%7)==3)begin @(negedge clk);prod_valid=0;prod_pcm=-19000;clocks(2);@(negedge clk);prod_pcm=128;end
        end
        @(negedge clk);prod_valid=0;clocks(6);
        check(prod_old_floor==280 && prod_new_floor==280,"default geometry128 baseline yields280 floor");
        for(i=0;i<4096;i=i+1)begin @(negedge clk);prod_valid=1;prod_pcm=(i<1024)?-32768:(i<2048?0:((i*173)&32767));clocks(1);end
        @(negedge clk);prod_valid=0;clocks(8);prod_rst_n=0;
        baselines[0]=0;baselines[1]=32;baselines[2]=64;baselines[3]=128;baselines[4]=512;baselines[5]=32768;
        margins[0]=-4096;margins[1]=-512;margins[2]=-64;margins[3]=-1;margins[4]=0;margins[5]=1;margins[6]=24;margins[7]=255;margins[8]=4095;
        for(b=0;b<6;b=b+1)begin
            calibrate(baselines[b]==32768 ? -32768 : baselines[b]);
            // Every representable signed margin; no audio sample is inserted by a setting change.
            for(m=-4096;m<=4095;m=m+1)begin set_margin(m);swept_margins=swept_margins+1;end
            for(j=0;j<9;j=j+1)begin
                set_margin(margins[j]);
                checked_window(0);checked_window(32);checked_window(-64);checked_window(128);
                checked_window(4096);checked_window(-32768);
                for(i=0;i<40;i=i+1)checked_window(0);
            end
        end
        calibrate(64);
        for(mag=0;mag<=32768;mag=mag+1)begin checked_window(mag==32768?-32768:mag);swept_magnitudes=swept_magnitudes+1;end
        check(legacy_level==255 && live_level==255,"all PCM magnitudes reach correct full-scale saturation");
        serial_frame(127);
        for(i=0;i<40;i=i+1)checked_window(0);
        check(live_level==0,"full-scale release ends dark");serial_frame(0);
        // Gate+31 yields level1 but RGB0; gate+32 yields the first RGB1.
        checked_window(183);check(live_level==1 && (live_level>>1)==0,"expected RGB quantization below visible boundary");serial_frame(0);
        checked_window(184);check(live_level==2 && (live_level>>1)==1,"first visible step at captured gate+32");serial_frame(1);
        set_margin(-64);checked_window(96);check(live_floor==64 && live_level==2,"negative margin does not unsigned-wrap");serial_frame(1);
        for(i=0;i<16;i=i+1)checked_window(-32768);
        check(live_floor==64&&live_meter.calibrated_baseline==64,"loud speech never moves stored noise baseline");
        held_mean=live_mean;
        @(negedge clk);pcm_valid=0;
        for(i=0;i<37;i=i+1)begin pcm=i*911;clocks(1);check(live_mean==held_mean,"invalid PCM changes do not enter mean");end
        // Back-to-back windows and irregular gaps retain the accepted timing.
        calibrate(128);
        @(negedge clk);pcm_valid=1;
        for(i=0;i<512;i=i+1)begin pcm=(i[0]?-1:1)*(i*61);clocks(1);@(negedge clk);end
        pcm_valid=0;clocks(6);
        check(live_meter.calibrated_baseline==128&&live_floor==280,"continuous samples cannot recalibrate floor");
        $display("PASS RING_CALIBRATION checks=%0d cycle_exact_checks=%0d production_geometry_checks=%0d windows=%0d signed_margin_values=%0d magnitudes=%0d calibrations=%0d serial_frames=%0d static24_matches_28 stored_baseline no_audio_or_mean_reset clamp64_65535 rgb_quantization_retained",checks,cycle_checks,production_checks,windows,swept_margins,swept_magnitudes,calibrations,serial_frames);
        $finish;
    end
    initial begin #100000000;$fatal(1,"RING_CALIBRATION watchdog");end
endmodule
