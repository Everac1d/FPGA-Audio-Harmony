`timescale 1ns/1ps
// 将完整精细增益前端与实际直接渲染器的
// 光栅进行比较，不强制音频状态、不使用 Python 重建或面板模型。
module tb_lcd_fine_scan;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0;
    wire source=1'b1,test_pattern_en=1'b0;
    wire [1:0] active_mode=0,algorithm_mode=2;
    wire signed [4:0] pitch=-5'sd1;
    wire [4:0] gain_index=5'd19;
    wire [3:0] rec_state=4'd11;
    wire record_valid=1'b1,record_full=1'b0,storage_fault=1'b0,ddr_ready=1'b1;
    wire [15:0] ddr_diag=16'h040f;
    wire [20:0] record_progress=1464844,record_samples=1464844,play_samples=732422;
    wire LCD_CLK,LCD_HSYNC,LCD_VSYNC,LCD_DE,LCD_BL;
    wire [5:0] LCD_R,LCD_G,LCD_B;
    audio_lcd_display #(.BACKLIGHT_ENABLE(1),.FINE_GAIN(1)) dut(.*);

    reg [9:0] x=1023;reg [8:0] y=511;
    wire [11:0] rec_centis=3000,total_centis=3000,play_centis=1500;
    wire [8:0] progress_pixels=216;
    wire [17:0] rgb;
    lcd_dashboard #(.FINE_GAIN(1)) reference(.*);
    reg [17:0] raster[0:130559];
    integer xx,yy,scan_pixels=0,compared=0,checks=0,h,v,fd;
    reg [17:0] actual,wanted;
    task check(input bit ok,input string message);begin
        checks=checks+1;if(ok!==1'b1)$fatal(1,"LCD_FINE_SCAN %s at h=%0d v=%0d",message,h,v);
    end endtask
    always @(posedge LCD_CLK)begin
        #1;
        if(rst_n)begin
            h=scan_pixels%525;v=(scan_pixels/525)%286;
            check(LCD_HSYNC===(h>=41),"HSYNC");
            check(LCD_VSYNC===(v>=10),"VSYNC");
            check(LCD_DE===(h>=43 && h<523 && v>=12 && v<284),"visible geometry");
            if(scan_pixels>=150150)begin
                actual={LCD_R,LCD_G,LCD_B};
                if(LCD_DE)begin
                    wanted=raster[(v-12)*480+(h-43)];
                    check(actual===wanted,"frontend is pixel-identical to five-stage actual RTL raster");
                    compared=compared+1;
                    if(scan_pixels<300300)
                        $fwrite(fd,"%0d %0d %0d\n",actual[17:12]*255/63,actual[11:6]*255/63,actual[5:0]*255/63);
                end else check(actual===0,"blanking black");
            end
            scan_pixels=scan_pixels+1;
            if(scan_pixels==450450)begin
                check(compared==261120,"two full fine-gain paused frames compared");
                check(dut.s_gain==19 && dut.s_pitch==-1 && dut.s_state==11,"5bit gain and signed semitone survive atomic snapshot");
                check(dut.progress_pixels==216 && dut.play_centis==1500,"paused half-clip progress remains visible");
                $fclose(fd);
                $display("PASS LCD_FINE_SCAN checks=%0d exact_pixels=%0d fine_gain=1.9 signed_pitch=-1 paused_progress=216/432 three_complete_frames",checks,compared);
                $finish;
            end
        end
    end
    initial begin
        for(yy=0;yy<272;yy=yy+1)begin
            for(xx=0;xx<480;xx=xx+1)begin
                @(negedge clk);x=xx;y=yy;
                repeat(5)@(posedge clk);#1;
                if((^rgb)===1'bx)$fatal(1,"Unknown actual reference raster pixel");
                raster[yy*480+xx]=rgb;
            end
        end
        fd=$fopen("sim/results/lcd_ext_fine_scan.ppm","w");
        if(!fd)$fatal(1,"Cannot write full frontend RTL preview");
        $fwrite(fd,"P3\n480 272\n255\n");
        @(negedge clk);rst_n=1;
    end
    initial begin #100000000;$fatal(1,"LCD fine full-scan timeout");end
endmodule
