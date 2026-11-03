`timescale 1ns/1ps
module tb_lcd_dashboard;
    `include "src/lcd_ui_text.vh"
    `include "src/lcd_footer_text.vh"
    reg clk=0;always #10 clk=~clk;
    reg [9:0] x=1023;
    reg [8:0] y=511;
    reg source=0;
    reg [1:0] active_mode=0,algorithm_mode=0;
    reg signed [4:0] pitch=0;
    reg [4:0] gain_index=10;
    reg [4:0] legacy_gain_index=0;
    reg [3:0] rec_state=0;
    reg record_valid=0,record_full=0,storage_fault=0,ddr_ready=0;
    reg [15:0] ddr_diag=0;
    reg [11:0] rec_centis=0,total_centis=0,play_centis=0;
    reg [8:0] progress_pixels=0;
    wire [17:0] rgb;
    lcd_dashboard #(.FINE_GAIN(1)) dut(.*);
    wire [17:0] legacy_rgb;
    lcd_dashboard #(.FINE_GAIN(0)) legacy(.gain_index(legacy_gain_index),.rgb(legacy_rgb),.*);
    integer checks=0,state_index,gain_value,pitch_value,magnitude,fd,px,py;
    task check(input bit condition,input string label);
        begin checks=checks+1;if(!condition)$fatal(1,"%s",label);end
    endtask
    task expect_text(input integer line_number,input integer start,input [332:0] message,input integer cells);
        integer i;reg [8:0] wanted,actual;
        begin
            for(i=0;i<cells;i=i+1)begin
                wanted=message >> ((36-i)*9);
                actual=dut.line_token(line_number,start+i);
                if(actual!==wanted)$fatal(1,"line=%0d halfcell=%0d expected token=%h actual=%h",line_number,start+i,wanted,actual);
                checks=checks+1;
            end
        end
    endtask
    task expect_footer(input integer line_number,input [503:0] message);
        integer i;reg [8:0] wanted;
        begin for(i=0;i<56;i=i+1)begin
            wanted=message >> ((55-i)*9);
            check(dut.footer_token(line_number,i)===wanted,"complete fixed footer token");
        end end
    endtask
    task expect_page;
        begin
            expect_footer(0,source ? TF_CLIP_0:TF_LIVE_0);
            expect_footer(1,source ? TF_CLIP_1:TF_LIVE_1);
            expect_footer(2,source ? TF_CLIP_2:TF_LIVE_2);
            expect_footer(3,source ? TF_CLIP_3:TF_LIVE_3);
        end
    endtask
    task expect_digit(input integer line_number,input integer column,input integer number);
        begin check(dut.line_token(line_number,column)==G_U0030+number,"decimal digit decode");end
    endtask
    task snapshot(input [511:0] filename);
        begin
            fd=$fopen(filename,"w");if(!fd)$fatal(1,"Cannot write actual RTL preview");
            $fwrite(fd,"P3\n480 272\n255\n");
            for(py=0;py<272;py=py+1)begin
                for(px=0;px<480;px=px+1)begin
                    @(negedge clk);x=px;y=py;
                    repeat(5)@(posedge clk);#1;
                    if(^rgb===1'bx)$fatal(1,"Unknown actual RTL pixel %0d,%0d",px,py);
                    $fwrite(fd,"%0d %0d %0d ",rgb[17:12]*255/63,rgb[11:6]*255/63,rgb[5:0]*255/63);
                end
                $fwrite(fd,"\n");
            end
            $fclose(fd);
        end
    endtask
    initial begin
        #1;
        expect_text(0,0,T_LIVE,N_LIVE);expect_text(0,6,T_MUTED,N_MUTED);
        expect_text(1,5,T_ORIGINAL,N_ORIGINAL);expect_text(2,5,T_LIVE_IDLE,N_LIVE_IDLE);
        expect_text(2,26,T_DDR_STANDBY,N_DDR_STANDBY);
        check(dut.line_token(1,16)==G_U002B,"zero pitch plus sign");
        expect_digit(1,17,0);expect_digit(1,18,0);
        expect_digit(1,26,1);expect_digit(1,28,0);
        check(dut.line_token(3,19)==G_U002D,"invalid clip total unavailable");
        expect_page;
        snapshot("sim/results/lcd_cn_live_muted.ppm");
        active_mode=1;#1;expect_text(0,6,T_MIC,N_MIC);expect_text(2,5,T_LIVE_RUNNING,N_LIVE_RUNNING);
        active_mode=2;#1;expect_text(0,6,T_TONE,N_TONE);
        algorithm_mode=1;#1;expect_text(1,5,T_PITCH,N_PITCH);
        algorithm_mode=2;#1;expect_text(1,5,T_HARMONY,N_HARMONY);
        for(gain_value=10;gain_value<=30;gain_value=gain_value+1)begin
            gain_index=gain_value;
            for(pitch_value=-12;pitch_value<=12;pitch_value=pitch_value+1)begin
                pitch=pitch_value;magnitude=pitch_value<0 ? -pitch_value:pitch_value;#1;
                check(dut.line_token(1,16)==(pitch_value<0 ? G_U002D : G_U002B),"signed pitch sign all25");
                expect_digit(1,17,magnitude/10);expect_digit(1,18,magnitude%10);
                expect_digit(1,26,gain_value/10);expect_digit(1,28,gain_value%10);
                check(dut.line_token(1,27)==G_U002E,"fine gain always has decimal point");
            end
        end
        // 无效精细增益应与监听模块一致，保守回退到 1 倍增益。
        gain_index=31;#1;expect_digit(1,26,1);expect_digit(1,28,0);
        // 旧版渲染仍可按需启用，并兼容原来的五种编码。
        for(state_index=0;state_index<5;state_index=state_index+1)begin
            case(state_index)0:legacy_gain_index=0;1:legacy_gain_index=2;
            2:legacy_gain_index=4;3:legacy_gain_index=5;4:legacy_gain_index=6;endcase
            #1;
            check(legacy.line_token(1,26)==G_U0030+(state_index<2 ? 1 : state_index<4 ? 2 : 3),"legacy gain integer unchanged");
            check(legacy.line_token(1,28)==G_U0030+(state_index==1 || state_index==3 ? 5 : 0),"legacy gain decimal unchanged");
        end
        source=1;active_mode=0;ddr_ready=0;rec_state=0;#1;
        expect_text(0,0,T_CLIP,N_CLIP);expect_text(2,5,T_DDR_INIT,N_DDR_INIT);
        expect_page;
        snapshot("sim/results/lcd_cn_initializing.ppm");
        ddr_ready=1;
        for(state_index=1;state_index<=11;state_index=state_index+1)begin
            rec_state=state_index;#1;expect_page;
            case(state_index)
            1:expect_text(2,5,T_EMPTY,N_EMPTY);2:expect_text(2,5,T_RECORDING,N_RECORDING);
            3:expect_text(2,5,T_SAVING,N_SAVING);4:expect_text(2,5,T_READY,N_READY);
            5:expect_text(2,5,T_PREPARE,N_PREPARE);6:expect_text(2,5,T_WARMUP,N_WARMUP);
            7:expect_text(2,5,T_PLAYING,N_PLAYING);8:expect_text(2,5,T_TAIL,N_TAIL);
            9:expect_text(2,5,T_DRAIN,N_DRAIN);10:expect_text(2,5,T_FAULT,N_FAULT);
            11:expect_text(2,5,T_PAUSED,N_PAUSED);
            endcase
        end
        rec_state=2;pitch=-11;gain_index=11;rec_centis=1234;progress_pixels=177;#1;
        expect_digit(3,5,1);expect_digit(3,6,2);expect_digit(3,8,3);expect_digit(3,9,4);
        expect_page;
        snapshot("sim/results/lcd_cn_recording.ppm");
        rec_state=3;#1;expect_page;
        rec_state=4;record_valid=1;record_full=1;total_centis=3000;rec_centis=3000;progress_pixels=432;#1;
        expect_text(2,26,T_FULL,N_FULL);expect_page;
        snapshot("sim/results/lcd_cn_ready_full.ppm");
        rec_state=7;active_mode=1;pitch=9;gain_index=19;play_centis=1420;progress_pixels=204;#1;
        expect_digit(4,5,1);expect_digit(4,6,4);expect_digit(4,8,2);expect_digit(4,9,0);
        expect_page;
        snapshot("sim/results/lcd_cn_playback.ppm");
        rec_state=11;active_mode=0;#1;
        expect_text(2,5,T_PAUSED,N_PAUSED);expect_page;
        snapshot("sim/results/lcd_ext_paused.ppm");
        rec_state=0;storage_fault=1;ddr_diag=16'hA50F;source=0;#1;
        expect_text(2,5,T_FAULT,N_FAULT);expect_page;
        expect_text(4,13,T_RESET,N_RESET);
        check(dut.line_token(4,7)==G_U0041 && dut.line_token(4,8)==G_U0035 && dut.line_token(4,9)==G_U0030 && dut.line_token(4,10)==G_U0046,"fault hexadecimal decode");
        snapshot("sim/results/lcd_cn_fault.ppm");
        storage_fault=0;rec_state=7;source=1;progress_pixels=204;
        @(negedge clk);x=24;y=182;
        repeat(5)@(posedge clk);#1;check(rgb==={6'd15,6'd61,6'd61},"progress start");
        @(negedge clk);x=228;
        repeat(5)@(posedge clk);#1;check(rgb==={6'd10,6'd17,6'd24},"progress end exclusive");
        @(negedge clk);x=0;y=0;
        repeat(5)@(posedge clk);#1;check(rgb==={6'd3,6'd9,6'd16},"header background");
        @(negedge clk);x=479;y=271;
        repeat(4)begin @(posedge clk);#1;check(rgb==={6'd3,6'd9,6'd16},"previous pixel remains until fifth stage");end
        @(posedge clk);#1;check(rgb==={6'd1,6'd2,6'd4},"five-clock pipeline latency");
        $display("PASS LCD dashboard external: %0d assertions, 7 full actual RTL previews, signed_pitch25 gain21 combinations525 legacy_gain5 state12 paused_resume fixed2pages_4rows all_states_footer_invariant font24px footer16px no_timer five_clock_pipeline",checks);
        $finish;
    end
endmodule
