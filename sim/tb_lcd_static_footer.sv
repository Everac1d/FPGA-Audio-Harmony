`timescale 1ns/1ps
`include "sim/fixtures/lcd_dashboard_33002_reference.v"
module tb_lcd_static_footer;
    `include "src/lcd_footer_text.vh"
    reg clk=0;always #10 clk=~clk;
    reg [9:0] x=1023;reg [8:0] y=511;
    reg source=0;
    reg [1:0] active_mode=1,algorithm_mode=2;
    reg signed [4:0] pitch=-1;
    reg [4:0] gain_index=19;
    reg [3:0] rec_state=4;
    reg record_valid=1,record_full=0,storage_fault=0,ddr_ready=1;
    reg [15:0] ddr_diag=16'h040F;
    reg [11:0] rec_centis=3000,total_centis=3000,play_centis=1500;
    reg [8:0] progress_pixels=216;
    wire [17:0] rgb,old_rgb;
    lcd_dashboard #(.FINE_GAIN(1)) dut(.*);
    lcd_dashboard_33002_reference #(.FINE_GAIN(1)) previous(.rgb(old_rgb),.*);
    reg [15:0] font_rows[0:2047];
    integer checks=0,main_pixels=0,footer_pixels=0,pages=0,fd,px,py,mode,state,i,j;
    reg [503:0] word;
    reg [8:0] token;
    reg [17:0] wanted;
    integer row_number,row_start,column,halfcell;
    function [503:0] expected_line;
        input bit clip;input integer line;
        begin case(line)
        0:expected_line=clip ? TF_CLIP_0:TF_LIVE_0;
        1:expected_line=clip ? TF_CLIP_1:TF_LIVE_1;
        2:expected_line=clip ? TF_CLIP_2:TF_LIVE_2;
        default:expected_line=clip ? TF_CLIP_3:TF_LIVE_3;
        endcase end
    endfunction
    task check(input bit ok,input string message);
        begin checks=checks+1;if(ok!==1'b1)$fatal(1,"%s x=%0d y=%0d source=%0d",message,x,y,source);end
    endtask
    task snapshot(input string filename);
        begin
            fd=$fopen(filename,"w");check(fd!=0,"preview file opened");
            $fwrite(fd,"P3\n480 272\n255\n");
            for(py=0;py<272;py=py+1)begin
                for(px=0;px<480;px=px+1)begin
                    @(negedge clk);x=px;y=py;
                    repeat(5)@(posedge clk);#1;
                    if(py<202)begin
                        check(rgb===old_rgb,"main region pixel identical to frozen 33002 renderer");
                        main_pixels=main_pixels+1;
                    end else begin
                        wanted={6'd1,6'd2,6'd4};row_number=-1;row_start=0;
                        if(py>=204 && py<220)begin row_number=0;row_start=204;end
                        else if(py>=221 && py<237)begin row_number=1;row_start=221;end
                        else if(py>=238 && py<254)begin row_number=2;row_start=238;end
                        else if(py>=255 && py<271)begin row_number=3;row_start=255;end
                        if(row_number>=0 && px>=16 && px<464)begin
                            word=expected_line(source,row_number);halfcell=(px-16)/8;
                            token=word>>((55-halfcell)*9);
                            column=((px-16)%8)+(token[8]?8:0);
                            if(font_rows[token[6:0]*16+(py-row_start)][15-column])wanted={6'd61,6'd62,6'd63};
                        end
                        check(rgb===wanted,"footer geometry/token/ROM pixel matches independent coordinate oracle");
                        footer_pixels=footer_pixels+1;
                    end
                    check((^rgb)!==1'bx,"known raster output");
                    $fwrite(fd,"%0d %0d %0d ",rgb[17:12]*255/63,rgb[11:6]*255/63,rgb[5:0]*255/63);
                end
                $fwrite(fd,"\n");
            end
            $fclose(fd);pages=pages+1;
        end
    endtask
    initial begin
        $readmemh("src/lcd_cjk16.mem",font_rows);
        #1;
        // Every recorder condition and fault leaves the complete source page
        // unchanged. Main fields remain free to show the actual status.
        for(mode=0;mode<2;mode=mode+1)begin
            source=mode;
            for(state=0;state<12;state=state+1)begin
                rec_state=state;storage_fault=(state%3)==0;ddr_ready=(state%2)!=0;
                gain_index=10+state;pitch=state-6;#1;
                for(i=0;i<4;i=i+1)begin
                    word=expected_line(source,i);
                    for(j=0;j<56;j=j+1)check(dut.footer_token(i,j)===(word>>((55-j)*9)&9'h1ff),"source-only complete page for all states/faults");
                end
                repeat(17)@(posedge clk);
                for(i=0;i<4;i=i+1)begin
                    word=expected_line(source,i);
                    for(j=0;j<56;j=j+1)check(dut.footer_token(i,j)===(word>>((55-j)*9)&9'h1ff),"fixed page remains invariant across clocks");
                end
            end
        end
        source=0;active_mode=1;algorithm_mode=2;pitch=-1;gain_index=19;
        storage_fault=0;ddr_ready=1;rec_state=4;
        snapshot("sim/results/lcd_static_live.ppm");
        source=1;active_mode=0;rec_state=11;record_full=1;
        snapshot("sim/results/lcd_static_clip.ppm");
        check(pages==2 && main_pixels==193920 && footer_pixels==67200,"two complete 480x272 fixed pages");
        $display("PASS LCD_STATIC_FOOTER checks=%0d main_identical_pixels=%0d footer_oracle_pixels=%0d fixed_pages=2 rows_per_page=4 font16 native480x272 no_rotation all12states both_sources five_clock_pipeline",checks,main_pixels,footer_pixels);
        $finish;
    end
    initial begin #50000000;$fatal(1,"static footer test timeout");end
endmodule
