`timescale 1ns/1ps
module tb_lcd_timing;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0;
    wire test_pattern_en=1'b0;
    wire [9:0] x;wire [8:0] y;wire frame_start;
    wire [17:0] pixel_rgb={x[5:0],y[5:0],(x[5:0]^y[5:0])};
    wire LCD_CLK,LCD_HSYNC,LCD_VSYNC,LCD_DE,LCD_BL;
    wire [5:0] LCD_R,LCD_G,LCD_B;
    lcd_rgb_timing dut(.*);
    wire enabled_bl;
    integer light_cycles=0;
    lcd_rgb_timing #(.BACKLIGHT_ENABLE(1),.BACKLIGHT_DELAY(10)) backlight_test(
        .clk(clk),.rst_n(rst_n),.test_pattern_en(1'b0),.pixel_rgb(18'd0),.LCD_BL(enabled_bl));
    integer checks=0,pixels=0,active=0,frames=0,h,v,xx,yy;
    integer line_active=0,hs_active=0,vs_active=0;
    reg [17:0] expected_rgb;
    reg [20:0] last_bus=0;
    reg prior_clock=0;
    time last_change=0,last_rise=0,last_edge=0;
    task check(input bit ok,input [511:0] message);
        begin checks=checks+1;if(ok!==1'b1)begin
            $display("FAIL LCD_TIMING %0s pixel=%0d h=%0d v=%0d",message,pixels,h,v);$fatal(1);end end
    endtask
    always @(posedge clk)begin
        #1;
        if(rst_n)begin
            light_cycles=light_cycles+1;
            check(enabled_bl===(light_cycles>10),"enabled backlight waits configured power-up delay");
            if({LCD_HSYNC,LCD_VSYNC,LCD_DE,LCD_R,LCD_G,LCD_B}!==last_bus)begin
                if(pixels>0)check(!LCD_CLK&&prior_clock,"RGB/control only changes with falling pixel clock");
                last_change=$time;
            end
            check(LCD_BL===0,"default backlight disabled");
        end
        last_bus={LCD_HSYNC,LCD_VSYNC,LCD_DE,LCD_R,LCD_G,LCD_B};
        prior_clock=LCD_CLK;
    end
    always @(LCD_CLK)begin
        if(rst_n && pixels>0)begin
            check($time-last_edge==60,"pixel clock high and low widths both 60 ns");
        end
        last_edge=$time;
    end
    always @(posedge LCD_CLK)begin
        #2;
        if(rst_n)begin
            h=pixels%525;v=(pixels/525)%286;
            check($time-last_change>=60,"RGB/control setup at rising sample edge >=60 ns");
            if(pixels>0)check($time-last_rise==120,"8.333 MHz pixel cadence");
            last_rise=$time;
            check(LCD_HSYNC===(h>=41),"HSYNC 41 active-low pixels");
            check(LCD_VSYNC===(v>=10),"VSYNC 10 active-low lines");
            check(LCD_DE===(h>=43&&h<523&&v>=12&&v<284),"exact active-window DE");
            if(!LCD_HSYNC)hs_active=hs_active+1;
            if(!LCD_VSYNC)vs_active=vs_active+1;
            if(LCD_DE)begin
                active=active+1;line_active=line_active+1;
                xx=h-43;yy=v-12;
                expected_rgb={xx[5:0],yy[5:0],(xx[5:0]^yy[5:0])};
                check({LCD_R,LCD_G,LCD_B}===expected_rgb,"RGB matches coordinates without a one-pixel displacement");
            end else check({LCD_R,LCD_G,LCD_B}===18'd0,"blanking is black");
            if(h==524)begin
                check(line_active==((v>=12&&v<284)?480:0),"480 DE samples per visible line");
                line_active=0;
            end
            pixels=pixels+1;
            if(pixels%150150==0)begin
                frames=frames+1;
                check(active==130560,"480x272 active samples per frame");
                check(hs_active==41*286&&vs_active==10*525,"complete sync widths per frame");
                active=0;hs_active=0;vs_active=0;
                if(frames==2)begin
                    $display("PASS LCD_TIMING checks=%0d frames=%0d total_pixels_per_frame=150150 active_pixels_per_frame=130560 pixel_period_ns=120 setup_ns=60 default_backlight=OFF",checks,frames);
                    $finish;
                end
            end
        end
    end
    initial begin repeat(5)@(negedge clk);rst_n=1;end
    initial begin #40000000;$fatal(1,"LCD timing timeout");end
endmodule
