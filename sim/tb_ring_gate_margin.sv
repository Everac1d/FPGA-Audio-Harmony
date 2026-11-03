`timescale 1ns/1ps
// 真实电平表比较：输入相同 PCM，默认与调参校准独立进行。
// 仅缩短窗口及校准长度；曲线、流水线和衰减
// 公式使用正式 RTL，并解码实际的 SK9822 串行帧。
module tb_ring_gate_margin;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,pcm_valid=0;
    reg signed [15:0] pcm=0;
    wire [7:0] old_level,new_level;
    wire [15:0] old_floor,new_floor,old_mean,new_mean;
    wire led_ck,led_da;
    integer checks=0,windows=0,serial_frames=0,swept=0;
    integer expected_old_level=0,expected_new_level=0;
    integer expected_old_floor=64,expected_new_floor=64;
    audio_level_meter #(.WINDOW_LOG2(2),.CALIBRATION_LOG2(2)) original(
        .clk(clk),.rst_n(rst_n),.pcm(pcm),.pcm_valid(pcm_valid),
        .level(old_level),.noise_floor(old_floor),.mean_level(old_mean));
    audio_level_meter #(.WINDOW_LOG2(2),.CALIBRATION_LOG2(2),.CALIBRATION_MARGIN(24)) tuned(
        .clk(clk),.rst_n(rst_n),.pcm(pcm),.pcm_valid(pcm_valid),
        .level(new_level),.noise_floor(new_floor),.mean_level(new_mean));
    sk9822_ring #(.HALF_PERIOD_CYCLES(1),.REFRESH_CYCLES(256),.LED_COUNT(1)) ring(
        .clk(clk),.rst_n(rst_n),.level(new_level),.color_mask_rgb(3'b011),
        .led_ck(led_ck),.led_da(led_da));
    task check(input bit ok,input [767:0] message);
        begin checks=checks+1;if(!ok)begin
            $display("FAIL RING_GATE_MARGIN window=%0d pcm=%0d old=%0d/%0d new=%0d/%0d: %0s",
                windows,pcm,old_level,old_floor,new_level,new_floor,message);$fatal(1);end end
    endtask
    task clocks(input integer count);
        begin repeat(count)begin @(posedge clk);#1;end end
    endtask
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
        begin
            @(negedge clk);pcm=sample;pcm_valid=1;
            clocks(4);@(negedge clk);pcm_valid=0;clocks(4);windows=windows+1;
        end
    endtask
    task checked_window(input integer sample);
        integer mag,old_target,new_target;
        begin
            mag=(sample<0)?-sample:sample;
            old_target=curve((mag>expected_old_floor)?mag-expected_old_floor:0);
            new_target=curve((mag>expected_new_floor)?mag-expected_new_floor:0);
            expected_old_level=release_level(expected_old_level,old_target);
            expected_new_level=release_level(expected_new_level,new_target);
            raw_window(sample);
            check(old_mean==mag && new_mean==mag,"exact absolute window mean");
            check(old_floor==expected_old_floor && new_floor==expected_new_floor,"calibration remains fixed");
            check(old_level==expected_old_level,"legacy default curve, pipeline and release");
            check(new_level==expected_new_level,"tuned curve, pipeline and release");
        end
    endtask
    task calibrate(input integer sample);
        integer mag,j;
        begin
            @(negedge clk);rst_n=0;pcm_valid=0;pcm=0;clocks(5);
            check(old_level==0 && new_level==0,"reset keeps display dark");
            @(negedge clk);rst_n=1;
            for(j=0;j<4;j=j+1)begin
                raw_window(sample);check(old_level==0 && new_level==0,"entire calibration stays dark");
            end
            mag=(sample<0)?-sample:sample;
            expected_old_floor=2*mag+32;expected_new_floor=2*mag+24;
            if(expected_old_floor<64)expected_old_floor=64;
            if(expected_new_floor<64)expected_new_floor=64;
            if(expected_old_floor>65535)expected_old_floor=65535;
            if(expected_new_floor>65535)expected_new_floor=65535;
            expected_old_level=0;expected_new_level=0;
            check(old_floor==expected_old_floor && new_floor==expected_new_floor,"measured gate and floor/saturation");
            checked_window(sample);
            check(old_level==0 && new_level==0,"calibrated baseline remains dark");
        end
    endtask
    task serial_frame(input integer intensity);
        integer word_number,bit_number;
        reg [31:0] word_value;
        begin
            // 等待新帧，使其锁存电平对应已经稳定的电平表输出。
            @(negedge clk);while(ring.busy)@(negedge clk);
            while(!ring.busy)@(negedge clk);
            for(word_number=0;word_number<3;word_number=word_number+1)begin
                word_value=0;
                for(bit_number=31;bit_number>=0;bit_number=bit_number-1)begin
                    @(posedge led_ck);#1;word_value[bit_number]=led_da;
                end
                case(word_number)
                    0:check(word_value==0,"actual serial start word");
                    1:begin
                        check(word_value[31:24]==8'he8,"global brightness remains 8/31");
                        check(word_value[23:16]==intensity && word_value[15:8]==intensity && word_value[7:0]==0,
                            "actual BGR pixel uses unchanged level/2 and cyan mask");
                    end
                    2:check(word_value==32'hffffffff,"actual serial end word");
                endcase
            end
            serial_frames=serial_frames+1;
        end
    endtask
    task boundary_case(input integer baseline);
        begin
            calibrate(baseline);
            check(expected_old_floor-expected_new_floor==8,"only eight PCM units of calibrated margin removed");
            checked_window(expected_new_floor+31);
            check((new_level>>1)==0 && (old_level>>1)==0,"below first actual RGB step stays dark");
            serial_frame(0);
            checked_window(expected_new_floor+32);
            check((new_level>>1)==1 && (old_level>>1)==0,"weak sound gains exactly first visible RGB step");
            serial_frame(1);
            checked_window(expected_old_floor+32);
            check((new_level>>1)==1 && (old_level>>1)==1,"legacy threshold still reaches same low brightness");
        end
    endtask
    integer amplitude,j;
    initial begin
        calibrate(0);check(old_floor==64 && new_floor==64,"quiet calibration preserves 64 hard minimum");
        checked_window(64);checked_window(95);serial_frame(0);
        checked_window(96);serial_frame(1);
        for(j=0;j<50;j=j+1)checked_window(0);
        check(old_level==0 && new_level==0,"silence releases fully dark");serial_frame(0);
        calibrate(16);check(old_floor==64 && new_floor==64,"low baseline cannot lower gate below 64");
        boundary_case(32);boundary_case(64);boundary_case(128);
        calibrate(64);
        // 遍历全部可达到的 PCM 幅度，与独立曲线
        // 以及独立衰减参考模型进行比较；余量是唯一的行为差异。
        for(amplitude=0;amplitude<=32768;amplitude=amplitude+1)begin
            checked_window((amplitude==32768)?-32768:amplitude);swept=swept+1;
        end
        check(old_level==255 && new_level==255,"positive/negative full magnitude saturates brightness");
        checked_window(-32768);serial_frame(127);
        for(j=0;j<40;j=j+1)checked_window(0);
        check(old_level==0 && new_level==0,"full scale decay and silence retain original release");
        calibrate(-32768);
        check(old_floor==65535 && new_floor==65535,"full negative calibration saturates gate without wrapping");
        checked_window(-32768);check(old_level==0 && new_level==0,"saturated gate stays dark");
        $display("PASS RING_GATE_MARGIN checks=%0d windows=%0d magnitudes=%0d serial_frames=%0d margin=32_to_24 floor=64 curve_release_unchanged=1",
            checks,windows,swept,serial_frames);$finish;
    end
    initial begin #200000000;$fatal(1,"RING_GATE_MARGIN timeout");end
endmodule
