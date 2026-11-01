`timescale 1ns/1ps
// Decode only the serial pins. The 32503 copy below is a read-only behavioral
// reference for legacy cyan brightness, clock, framing and refresh behavior.
`include "sim/fixtures/sk9822_ring_32503.v"
module tb_mode_ring;
    localparam integer HALF=2, REFRESH=2048, LEDS=12;
    reg clk=0; always #10 clk=~clk;
    reg rst_n=0;
    reg [7:0] level=0;
    reg [2:0] raw_color=3'b011;
    reg use_palette=0;
    reg active_source=0;
    reg [1:0] active_algorithm_mode=0,active_mode=0;
    reg [3:0] rec_state=0;
    reg ddr_ready=1,storage_fault=0;
    wire [2:0] selected_color;
    wire [2:0] ring_color=use_palette?selected_color:raw_color;
    wire led_ck,led_da,old_ck,old_da;
    integer checks=0,frames=0,palette_cases=0,legacy_wave_clocks=0;
    integer mask_order,mask_index,level_index,s,a,m,t,d,f;
    reg legacy_cyan_compare=1;
    reg [2:0] wanted;
    time last_frame_start=0;
    reg have_frame_start=0;
    time previous_bit_time;

    audio_ring_palette palette(
        .active_source(active_source),.active_algorithm_mode(active_algorithm_mode),
        .active_mode(active_mode),.rec_state(rec_state),.ddr_ready(ddr_ready),
        .storage_fault(storage_fault),.color_mask_rgb(selected_color));
    sk9822_ring #(.HALF_PERIOD_CYCLES(HALF),.REFRESH_CYCLES(REFRESH),.LED_COUNT(LEDS)) dut(
        .clk(clk),.rst_n(rst_n),.level(level),.color_mask_rgb(ring_color),
        .led_ck(led_ck),.led_da(led_da));
    sk9822_ring_baseline_32503 #(.HALF_PERIOD_CYCLES(HALF),.REFRESH_CYCLES(REFRESH),.LED_COUNT(LEDS)) legacy(
        .clk(clk),.rst_n(rst_n),.level(level),.array_source(1'b0),
        .led_ck(old_ck),.led_da(old_da));

    task check(input bit ok,input [639:0] message);
        begin
            checks=checks+1;
            if(!ok)begin
                $display("FAIL MODE_RING frame=%0d mask=%0d level=%0d: %0s",frames,mask_index,level_index,message);
                $fatal(1);
            end
        end
    endtask
    task clocks(input integer n);
        begin repeat(n)begin @(posedge clk);#1;end end
    endtask

    // The clock schedule must remain bit-for-bit identical to the old module
    // regardless of selected color. Cyan data is also compared every cycle,
    // including idle time and every one of the 256 level inputs.
    always @(posedge clk)begin
        #1;
        if(rst_n)begin
            if(led_ck!==old_ck)begin $display("FAIL legacy LED clock schedule changed");$fatal(1);end
            if(legacy_cyan_compare)begin
                legacy_wave_clocks=legacy_wave_clocks+1;
                if(led_da!==old_da)begin $display("FAIL legacy cyan serial data changed");$fatal(1);end
            end
        end
    end
    // Serial data changes are legal on falling clock edges only, including
    // start/end boundaries; while the LED clock is high it must stay stable.
    always @(led_da)begin
        if(rst_n && led_ck===1'b1)begin
            $display("FAIL LED data changed while clock high");$fatal(1);
        end
    end

    task receive_frame(input [2:0] expected_mask,input [7:0] expected_level,input bit change_midframe);
        integer word_number,bit_number;
        integer expected_intensity;
        reg [31:0] word_value;
        time frame_start;
        begin
            expected_intensity=expected_level/2;
            for(word_number=0;word_number<LEDS+2;word_number=word_number+1)begin
                word_value=0;
                for(bit_number=31;bit_number>=0;bit_number=bit_number-1)begin
                    @(posedge led_ck);#1;
                    if(word_number==0 && bit_number==31)begin
                        frame_start=$time;
                        if(have_frame_start)
                            check(frame_start-last_frame_start==REFRESH*20,"unchanged refresh period in idle and transfer");
                        last_frame_start=frame_start;have_frame_start=1;
                    end else
                        check($time-previous_bit_time==HALF*2*20,"exact serial bit period");
                    previous_bit_time=$time;
                    check(led_da===1'b0 || led_da===1'b1,"serial bit must be known");
                    word_value[bit_number]=led_da;
                end
                if(word_number==0)check(word_value===32'd0,"32 zero start bits");
                else if(word_number==LEDS+1)check(word_value===32'hffffffff,"32 one end bits");
                else begin
                    check(word_value[31:24]===8'he8,"fixed 111 prefix and global brightness 8/31");
                    check(word_value[23:16]===(expected_mask[0]?expected_intensity[7:0]:8'd0),"B channel and original level/2 response");
                    check(word_value[15:8]===(expected_mask[1]?expected_intensity[7:0]:8'd0),"G channel and original level/2 response");
                    check(word_value[7:0]===(expected_mask[2]?expected_intensity[7:0]:8'd0),"R channel and original level/2 response");
                end
                // Change both the actual functional palette and the meter
                // input after the first pixel, not an internal DUT register.
                // All 12 pixels of this frame must still use the old pair.
                if(change_midframe && word_number==1)begin
                    @(negedge clk);active_algorithm_mode=2;level=173;
                end
            end
            frames=frames+1;
        end
    endtask

    initial begin
        // Exhaust the externally documented functional combinations, including
        // all four algorithm codes and storage faults while still in live mode.
        // Expected values are the specified visible RGB colors, independent of
        // the LED driver's BGR serialization implementation.
        for(s=0;s<2;s=s+1)for(a=0;a<4;a=a+1)for(m=0;m<4;m=m+1)
        for(t=0;t<16;t=t+1)for(d=0;d<2;d=d+1)for(f=0;f<2;f=f+1)begin
            active_source=s;active_algorithm_mode=a;active_mode=m;rec_state=t;
            ddr_ready=d;storage_fault=f;#1;
            case(a)
                1:wanted=3'b101;
                2:wanted=3'b110;
                3:wanted=3'b010;
                default:wanted=3'b011;
            endcase
            if(s==0 && m==2)wanted=3'b001;
            if(t==2 || t==3)wanted=3'b100;
            if(s!=0 && d==0)wanted=3'b001;
            if(s!=0 && f!=0)wanted=3'b100;
            check(selected_color===wanted,"functional palette and precedence");
            palette_cases=palette_cases+1;
        end
        active_source=0;active_algorithm_mode=0;active_mode=1;rec_state=0;
        ddr_ready=1;storage_fault=0;raw_color=3'b011;level=0;
        clocks(4);check(led_ck===0 && led_da===0,"reset holds both pins low");
        @(negedge clk);rst_n=1;

        // Start with cyan so the full exhaustive cyan sweep also has an old
        // module comparison from the same initial reset. Then cover the other
        // seven RGB masks, all 256 input levels and every pixel in every frame.
        for(mask_order=0;mask_order<8;mask_order=mask_order+1)begin
            if(mask_order==0)mask_index=3;
            else if(mask_order<=3)mask_index=mask_order-1;
            else mask_index=mask_order;
            if(mask_order!=0)legacy_cyan_compare=0;
            for(level_index=0;level_index<256;level_index=level_index+1)begin
                @(negedge clk);raw_color=mask_index;level=level_index;
                receive_frame(mask_index[2:0],level_index[7:0],0);
            end
        end
        check(frames==2048,"all RGB masks by all 256 levels decoded");
        check(legacy_wave_clocks>500000,"legacy cyan compared across a full 256-level sweep");

        @(negedge clk);use_palette=1;active_source=0;active_algorithm_mode=0;
        active_mode=1;rec_state=0;ddr_ready=1;storage_fault=0;level=80;
        receive_frame(3'b011,8'd80,1);
        receive_frame(3'b110,8'd173,0);

        // Reset in the middle of serial transmission, asynchronously between
        // audio clock edges. No partial old frame may survive the reset.
        @(posedge led_ck);#1;
        @(posedge led_ck);#3;rst_n=0;#1;
        check(led_ck===0 && led_da===0,"asynchronous reset immediately idles both pins");
        have_frame_start=0;clocks(4);
        check(led_ck===0 && led_da===0,"held reset stays idle");
        @(negedge clk);level=0;active_algorithm_mode=1;rst_n=1;
        receive_frame(3'b101,8'd0,0);
        $display("MEASURE MODE_RING palette_cases=%0d frames=%0d legacy_cyan_clock_samples=%0d",palette_cases,frames,legacy_wave_clocks);
        $display("PASS MODE_RING checks=%0d all_levels=256 masks=8 leds=12 atomic_color_level=1 legacy_cyan_equivalent=1",checks);
        $finish;
    end
    initial begin #150000000;$fatal(1,"MODE_RING timeout");end
endmodule
