`timescale 1ns/1ps
// 仅复用此已有测试中确定性的物理 DDR 桩模块。
// -s tb_lcd_boot_diagnostics 会裁剪另一个独立测试顶层。
`include "sim/tb_record_top_startup.sv"
module tb_lcd_boot_diagnostics;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,key_gain_n=1;
    reg [3:0] button_n=4'b1111;
    reg enc_gain_sw_n=1,enc_gain_clk=1,enc_gain_dt=1;
    reg enc_pitch_sw_n=1,enc_pitch_clk=1,enc_pitch_dt=1;
    reg [3:0] mic_sd=0;
    wire mic_bclk,mic_ws,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812,uart_tx,led_ck,led_da;
    wire memory_clk,memory_clkn,memory_cke,memory_cs_n,memory_cas_n;
    wire memory_ras_n,memory_we_n,memory_reset_n,memory_odt;
    wire [14:0] memory_addr;wire [2:0] memory_bank;
    wire [31:0] memory_dq;wire [3:0] memory_dqs,memory_dqs_n,memory_dm;
    wire LCD_CLK,LCD_HSYNC,LCD_VSYNC,LCD_DE,LCD_BL;
    wire [5:0] LCD_R,LCD_G,LCD_B;
    audio_record_ddr_top dut(.*);
    // 保留实际的 65536 时钟板级上电复位，以及实际 LCD 扫描和背光。
    // 仅缩短麦克风启动时间，不强制修改被测模块寄存器。
    defparam dut.u_audio.POR_CYCLES=8;
    defparam dut.u_audio.STARTUP_FRAMES=3;
    defparam dut.u_audio.MAX_SAMPLES=128;
    defparam dut.u_audio.UART_REPORT_CYCLES=1000000;

    integer checks=0,boots=0,completed_frames=0;
    integer h=0,v=0,xx,yy,normal_nonzero=0,diagnostic_pixels=0;
    reg [7:0] colors_seen=0;
    reg white_border_seen=0,red_marker_seen=0;
    reg [17:0] expected_rgb;
    time last_edge=0;
    reg edge_seen=0;

    task check(input bit ok,input [639:0] message);
        begin checks=checks+1;if(ok!==1'b1)begin
            $display("FAIL LCD_BOOT_DIAGNOSTICS boot=%0d h=%0d v=%0d: %0s",boots,h,v,message);
            $fatal(1);
        end end
    endtask
    task clocks(input integer n);
        begin repeat(n)begin @(posedge clk);#2;end end
    endtask

    // 下面所有协议期望均来自外部时钟、控制和 RGB
    // 引脚和独立帧坐标，而非内部扫描计数器。
    always @(posedge clk)begin
        #2;
        if(!dut.board_run_n)begin
            h=0;v=0;completed_frames=0;edge_seen=0;
        end
    end
    always @(LCD_CLK)begin
        if(rst_n && dut.board_run_n)begin
            if(edge_seen)check($time-last_edge==60,"pixel clock half-period remains 60ns");
            edge_seen=1;last_edge=$time;
        end
    end
    always @(LCD_R or LCD_G or LCD_B or LCD_HSYNC or LCD_VSYNC or LCD_DE)begin
        if(rst_n && dut.board_run_n && LCD_CLK===1'b1)begin
            $display("FAIL LCD data/control changed while pixel clock high");$fatal(1);
        end
    end
    always @(posedge LCD_CLK)begin
        #1;
        if(rst_n && dut.board_run_n)begin
            check(LCD_HSYNC===(h<41?1'b0:1'b1),"horizontal synchronization width/polarity");
            check(LCD_VSYNC===(v<10?1'b0:1'b1),"vertical synchronization width/polarity");
            check(LCD_DE===((h>=43 && h<523 && v>=12 && v<284)?1'b1:1'b0),"480x272 visible window and unchanged blanking");
            if(LCD_DE)begin
                xx=h-43;yy=v-12;
                if(dut.lcd_test_mode)begin
                    case(xx/60)
                        0:expected_rgb=18'h3ffff;
                        1:expected_rgb={6'd63,6'd63,6'd0};
                        2:expected_rgb={6'd0,6'd63,6'd63};
                        3:expected_rgb={6'd0,6'd63,6'd0};
                        4:expected_rgb={6'd63,6'd0,6'd63};
                        5:expected_rgb={6'd63,6'd0,6'd0};
                        6:expected_rgb={6'd0,6'd0,6'd63};
                        default:expected_rgb=18'd0;
                    endcase
                    if(xx<2 || yy<2 || xx>=478 || yy>=270)begin
                        expected_rgb=18'h3ffff;white_border_seen=1;
                    end
                    if(xx>=8 && xx<32 && yy>=8 && yy<32)begin
                        expected_rgb={6'd63,6'd0,6'd0};red_marker_seen=1;
                    end
                    check({LCD_R,LCD_G,LCD_B}===expected_rgb,"runtime diagnostic selection emits exact bars/border/marker");
                    if(yy==40 && xx%60==30)colors_seen[xx/60]=1;
                    diagnostic_pixels=diagnostic_pixels+1;
                end else if({LCD_R,LCD_G,LCD_B}!==18'd0)
                    normal_nonzero=normal_nonzero+1;
            end else
                check({LCD_R,LCD_G,LCD_B}===18'd0,"blanking RGB remains black");
            if(h==524)begin
                h=0;
                if(v==285)begin v=0;completed_frames=completed_frames+1;end
                else v=v+1;
            end else h=h+1;
        end
    end

    task boot(input bit diagnostic);
        begin
            boots=boots+1;
            @(negedge clk);rst_n=0;key_gain_n=diagnostic?0:1;
            clocks(8);
            check(LCD_BL===0,"reset clears the backlight request");
            @(negedge clk);rst_n=1;
            wait(dut.board_run_n);clocks(6);
            check(dut.lcd_test_mode===diagnostic,"boot latch reflects synchronized KEY2 during POR");
            @(negedge clk);key_gain_n=1;
            clocks(12);
            check(dut.lcd_test_mode===diagnostic,"releasing KEY2 does not switch the latched display page");
            wait(dut.u_audio.mic_ready);clocks(8);
            check(!dut.audio_source && !dut.storage_started && !dut.storage_run_n,"display boot does not start DDR");
            check(!memory_reset_n && !dut.bridge_ready && !dut.u_audio.storage_fault,"DDR standby is fault-free and held reset");
            check(dut.u_audio.active_algorithm_mode==0 && dut.u_audio.active_mode==0 && dut.u_audio.gain_index==10 && dut.u_audio.active_pitch_semitones==0,"original muted 0-semitone unity boot remains intact");
            check(!dut.u_audio.record_valid && PA_EN===1,"boot recording validity and amplifier mute remain intact");
            check(dut.u_audio.ring_color_rgb===3'b011,"merged ring retains baseline original cyan selection");
        end
    endtask

    initial begin
        clocks(4);
        boot(0);
        // 实际板级上电复位完成后，麦克风约在 3 帧后就绪。
        // 这些检查点跨越保持不变的实际 50 毫秒背光延时。
        clocks(2490000);check(LCD_BL===0,"backlight stays low before its 50ms delay");
        clocks(10050);check(LCD_BL===1,"backlight is enabled after its 50ms delay");
        check(completed_frames>=2 && normal_nonzero>100000,"normal dashboard has nonzero visible content over complete frames");
        @(negedge clk);key_gain_n=0;clocks(30);@(negedge clk);key_gain_n=1;clocks(30);
        check(dut.lcd_test_mode===0,"KEY2 alone outside reset cannot enter diagnostics");

        boot(1);
        wait(completed_frames>=1);clocks(2);
        check(colors_seen===8'hff && diagnostic_pixels==480*272,"one exact full diagnostic frame covers all eight bars");
        check(white_border_seen && red_marker_seen,"diagnostic frame contains orientation landmarks");
        check(dut.lcd_test_mode===1 && !dut.storage_started,"diagnostics stay selected without DDR use");

        boot(0);
        wait(completed_frames>=1);clocks(2);
        check(dut.lcd_test_mode===0 && !dut.audio_source && !dut.storage_started,"ordinary KEY1 reset returns to dashboard/live standby");
        check(boots==3 && diagnostic_pixels==130560 && normal_nonzero>200000,"meaningful three-boot display coverage");
        $display("MEASURE LCD_BOOT_DIAGNOSTICS boots=%0d diagnostic_pixels=%0d normal_nonzero=%0d colors=%02x",boots,diagnostic_pixels,normal_nonzero,colors_seen);
        $display("PASS LCD_BOOT_DIAGNOSTICS checks=%0d legal_keys_only normal_bars_restore sync_controls backlight50ms no_DDR_start audio_defaults ring_cyan",checks);
        $finish;
    end
    initial begin #130000000;$fatal(1,"LCD_BOOT_DIAGNOSTICS timeout");end
endmodule
