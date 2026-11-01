`timescale 1ns/1ps
module tb_dual_lcd;
    `include "src/lcd_ui_text.vh"
    `include "src/lcd_footer_text.vh"
    reg clk=0;always #10 clk=~clk;
    reg [9:0] x=1023;reg [8:0] y=511;
    reg source=0,test_pattern_en=0;
    reg [1:0] active_mode=1,algorithm_mode=3;
    reg signed [4:0] pitch=4,pitch_second=7;
    reg pitch_voice=0;
    reg [4:0] gain_index=19;
    reg [3:0] rec_state=4;
    reg record_valid=1,record_full=0,storage_fault=0,ddr_ready=1;
    reg [15:0] ddr_diag=16'h040f;
    reg [20:0] record_progress=1464844,record_samples=1464844,play_samples=732422;
    reg [11:0] rec_centis=3000,total_centis=3000,play_centis=1500;
    reg [8:0] progress_pixels=216;
    wire [17:0] rgb;
    lcd_dual_dashboard #(.FINE_GAIN(1)) dashboard(.*);

    reg rst_n=0;
    wire LCD_CLK,LCD_HSYNC,LCD_VSYNC,LCD_DE,LCD_BL;
    wire [5:0] LCD_R,LCD_G,LCD_B;
    audio_lcd_dual_display #(.BACKLIGHT_ENABLE(1),.FINE_GAIN(1)) frontend(.*);

    reg snap_rst_n=0,frame_start=0;
    wire source_o,pitch_voice_o,record_valid_o,record_full_o,storage_fault_o,ddr_ready_o;
    wire [1:0] active_mode_o,algorithm_mode_o;
    wire signed [4:0] pitch_o,pitch_second_o;
    wire [4:0] gain_index_o;wire [3:0] rec_state_o;wire [15:0] ddr_diag_o;
    wire [11:0] snap_rec,snap_total,snap_play;wire [8:0] snap_pixels;
    lcd_dual_status_snapshot snapshot(.clk(clk),.rst_n(snap_rst_n),.frame_start(frame_start),
        .source(source),.active_mode(active_mode),.algorithm_mode(algorithm_mode),
        .pitch(pitch),.pitch_second(pitch_second),.pitch_voice(pitch_voice),.gain_index(gain_index),
        .rec_state(rec_state),.record_valid(record_valid),.record_full(record_full),
        .storage_fault(storage_fault),.ddr_ready(ddr_ready),.ddr_diag(ddr_diag),
        .record_progress(record_progress),.record_samples(record_samples),.play_samples(play_samples),
        .source_o(source_o),.active_mode_o(active_mode_o),.algorithm_mode_o(algorithm_mode_o),
        .pitch_o(pitch_o),.pitch_second_o(pitch_second_o),.pitch_voice_o(pitch_voice_o),
        .gain_index_o(gain_index_o),.rec_state_o(rec_state_o),.record_valid_o(record_valid_o),
        .record_full_o(record_full_o),.storage_fault_o(storage_fault_o),.ddr_ready_o(ddr_ready_o),
        .ddr_diag_o(ddr_diag_o),.rec_centis(snap_rec),.total_centis(snap_total),
        .play_centis(snap_play),.progress_pixels(snap_pixels));
    integer checks=0,pair_cases=0,snapshot_cases=0,scan_pixels=0,exact_pixels=0,pages=0;
    integer p,q,selection,g,line,cell_number,state,src,k,px,py,h,v,fd;
    integer magnitude1,magnitude2;
    reg [503:0] expected_footer;
    reg [8:0] expected_token;
    reg tone_pattern;
    reg [17:0] raster[0:130559];
    reg [17:0] actual,wanted;
    reg [44:0] expected_status=0;
    reg [11:0] expected_rec=0,expected_total=0,expected_play=0;
    reg [8:0] expected_pixels=0;
    reg [89:0] old_front;
    reg [31:0] random_state=32'h425E07A1;
    time last_bus_change=0,last_rising=0,rising_time;
    longint unsigned safe_rec,safe_total,safe_play,ratio;
    function [8:0] text_token(input [332:0] text,input integer index);
        text_token=(text>>((36-index)*9))&9'h1ff;
    endfunction
    function [8:0] digit_token(input integer value);
        digit_token={1'b0,G_U0030}+value;
    endfunction
    function [503:0] footer_word(input bit clip,input integer row);
        case(row)
        0:footer_word=clip ? TF_CLIP_0:TF_LIVE_0;
        1:footer_word=clip ? TF_CLIP_1:TF_LIVE_1;
        2:footer_word=clip ? TF_CLIP_2:TF_LIVE_2;
        default:footer_word=clip ? TF_CLIP_3:TF_LIVE_3;
        endcase
    endfunction
    function [89:0] published;
        published={source_o,active_mode_o,algorithm_mode_o,pitch_o,pitch_second_o,pitch_voice_o,
            gain_index_o,rec_state_o,record_valid_o,record_full_o,storage_fault_o,ddr_ready_o,
            ddr_diag_o,snap_rec,snap_total,snap_play,snap_pixels};
    endfunction
    task check(input bit okay,input string message);begin
        checks=checks+1;if(okay!==1'b1)$fatal(1,"DUAL_LCD %s p=%0d q=%0d voice=%0d h=%0d v=%0d",message,pitch,pitch_second,pitch_voice,h,v);
    end endtask
    task check_dual_line;
        begin
            magnitude1=pitch<0 ? -pitch:pitch;magnitude2=pitch_second<0 ? -pitch_second:pitch_second;
            for(cell_number=0;cell_number<31;cell_number=cell_number+1)begin
                expected_token=0;
                if(cell_number<6)expected_token=text_token(T_DUAL,cell_number);
                else if(cell_number>=21 && cell_number<25)expected_token=text_token(T_GAIN,cell_number-21);
                else case(cell_number)
                7:expected_token=!pitch_voice ? {1'b0,G_U003E}:9'd0;
                8:expected_token=digit_token(1);
                9,16:expected_token={1'b0,G_U003A};
                10:expected_token=pitch<0 ? {1'b0,G_U002D}:{1'b0,G_U002B};
                11:expected_token=digit_token(magnitude1/10);
                12:expected_token=digit_token(magnitude1%10);
                14:expected_token=pitch_voice ? {1'b0,G_U003E}:9'd0;
                15:expected_token=digit_token(2);
                17:expected_token=pitch_second<0 ? {1'b0,G_U002D}:{1'b0,G_U002B};
                18:expected_token=digit_token(magnitude2/10);
                19:expected_token=digit_token(magnitude2%10);
                26:expected_token=digit_token(gain_index/10);
                27:expected_token={1'b0,G_U002E};
                28:expected_token=digit_token(gain_index%10);
                29,30:expected_token=text_token(T_TIMES,cell_number-29);
                default:expected_token=0;
                endcase
                check(dashboard.line_token(1,cell_number)===expected_token,"independent dual row formatter, signed two-digit pitch, editor marker and fine gain");
            end
        end
    endtask
    task pulse_snapshot;
        begin @(negedge clk);frame_start=1;@(posedge clk);#1;frame_start=0;end
    endtask
    task expect_snapshot;
        begin
            check({source_o,active_mode_o,algorithm_mode_o,pitch_o,pitch_second_o,pitch_voice_o,
                gain_index_o,rec_state_o,record_valid_o,record_full_o,storage_fault_o,ddr_ready_o,
                ddr_diag_o}===expected_status,"entire 45-bit status publishes atomically with pitch2/voice");
            check(snap_rec===expected_rec && snap_total===expected_total && snap_play===expected_play,"snapshot independent sample-to-centisecond calculation");
            check(snap_pixels===expected_pixels,"snapshot independent progress ratio");
        end
    endtask
    task snapshot_case(input integer index);
        begin
            @(negedge clk);
            source=index%2;active_mode=index%3;algorithm_mode=3;
            pitch=index-12;pitch_second=12-index;pitch_voice=index%2;
            gain_index=10+index%21;rec_state=index%12;record_valid=index%4!=0;
            record_full=index%5==0;storage_fault=index%7==0;ddr_ready=index%3!=0;
            ddr_diag=16'h040f+index;record_progress=index*72000;
            record_samples=index*68000;play_samples=index*39000;
            pulse_snapshot();expect_snapshot();old_front=published();
            expected_status={source,active_mode,algorithm_mode,pitch,pitch_second,pitch_voice,
                gain_index,rec_state,record_valid,record_full,storage_fault,ddr_ready,ddr_diag};
            safe_rec=record_progress>1464844 ? 1464844:record_progress;
            safe_total=record_samples>1464844 ? 1464844:record_samples;
            safe_play=play_samples>safe_total ? safe_total:play_samples;
            if(!record_valid)begin safe_total=0;safe_play=0;end
            expected_rec=safe_rec*1024/500000;
            expected_total=safe_total*1024/500000;
            expected_play=safe_play*1024/500000;
            if(rec_state==2 || rec_state==3)ratio=safe_rec*432/1464844;
            else if(((rec_state>=5 && rec_state<=9)||rec_state==11)&&safe_total!=0)ratio=safe_play*432/safe_total;
            else ratio=0;
            expected_pixels=ratio>432 ? 432:ratio;
            for(k=1;k<=132;k=k+1)begin
                @(negedge clk);
                random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
                {source,active_mode,algorithm_mode,pitch,pitch_second,pitch_voice,gain_index,
                    rec_state,record_valid,record_full,storage_fault,ddr_ready,ddr_diag}={random_state,random_state[12:0]};
                record_progress=random_state[20:0];record_samples=~random_state[20:0];play_samples=random_state[31:11];
                frame_start=(k==8);
                @(posedge clk);#1;
                check(published()===old_front,"live inputs and a busy frame pulse never change published fields mid-frame");
                if(k<132)check(snapshot.busy && !snapshot.ready,"snapshot stays busy for complete 132-clock conversion");
                else check(!snapshot.busy && snapshot.ready,"four divisions complete at exactly 132 clocks");
            end
            frame_start=0;snapshot_cases=snapshot_cases+1;
        end
    endtask
    always @({LCD_R,LCD_G,LCD_B,LCD_DE,LCD_HSYNC,LCD_VSYNC})last_bus_change=$time;
    task render_and_scan(input string filename);
        begin
            @(negedge clk);rst_n=0;
            for(py=0;py<272;py=py+1)for(px=0;px<480;px=px+1)begin
                @(negedge clk);x=px;y=py;
                repeat(5)@(posedge clk);#1;
                check((^rgb)!==1'bx,"five-clock direct RTL raster is known");
                raster[py*480+px]=rgb;
            end
            fd=$fopen(filename,"w");check(fd!=0,"native RTL frame preview file opened");
            $fwrite(fd,"P3\n480 272\n255\n");
            scan_pixels=0;last_rising=0;
            @(negedge clk);rst_n=1;
            while(scan_pixels<300300)begin
                @(posedge LCD_CLK);rising_time=$time;#1;
                h=scan_pixels%525;v=(scan_pixels/525)%286;
                if(last_rising!=0)check(rising_time-last_rising==120,"actual frontend pixel clock period is 120ns");
                check(rising_time-last_bus_change>=60,"actual RGB/control setup is at least 60ns");
                last_rising=rising_time;
                check(LCD_HSYNC===(h>=41),"actual frontend HSYNC geometry");
                check(LCD_VSYNC===(v>=10),"actual frontend VSYNC geometry");
                check(LCD_DE===(h>=43 && h<523 && v>=12 && v<284),"actual frontend 480x272 DE geometry");
                if(scan_pixels>=150150)begin
                    actual={LCD_R,LCD_G,LCD_B};
                    if(LCD_DE)begin
                        wanted=raster[(v-12)*480+(h-43)];
                        check(actual===wanted,"actual native scan equals the five-stage RTL renderer after atomic snapshot");
                        exact_pixels=exact_pixels+1;
                        $fwrite(fd,"%0d %0d %0d\n",actual[17:12]*255/63,actual[11:6]*255/63,actual[5:0]*255/63);
                    end else check(actual===0,"actual frontend blanking remains black");
                end
                scan_pixels=scan_pixels+1;
            end
            check(frontend.s_pitch===pitch && frontend.s_pitch_second===pitch_second && frontend.s_pitch_voice===pitch_voice && frontend.s_gain===gain_index,"new fields survive actual frontend atomic snapshot");
            check(frontend.progress_pixels===progress_pixels && frontend.play_centis===play_centis,"frontend paused progress calculation retained");
            $fclose(fd);pages=pages+1;
            @(negedge clk);rst_n=0;
        end
    endtask
    initial begin
        #1;
        for(p=-12;p<=12;p=p+1)for(q=-12;q<=12;q=q+1)begin
            pitch=p;pitch_second=q;gain_index=10+pair_cases%21;
            for(selection=0;selection<2;selection=selection+1)begin
                pitch_voice=selection;#1;check_dual_line();
            end
            pair_cases=pair_cases+1;
        end
        for(g=10;g<=30;g=g+1)begin gain_index=g;#1;check_dual_line();end
        // Exactly two complete source-selected pages remain invariant across
        // every algorithm, recorder state, editor selection, fault and time.
        for(src=0;src<2;src=src+1)for(state=0;state<12;state=state+1)
            for(selection=0;selection<2;selection=selection+1)for(g=0;g<4;g=g+1)begin
                source=src;rec_state=state;pitch_voice=selection;algorithm_mode=g;
                storage_fault=state%3==0;ddr_ready=state%2!=0;#1;
                for(line=0;line<4;line=line+1)begin
                    expected_footer=footer_word(source,line);
                    for(cell_number=0;cell_number<56;cell_number=cell_number+1)
                        check(dashboard.footer_token(line,cell_number)===((expected_footer>>((55-cell_number)*9))&9'h1ff),"fixed source-only footer has no mode/state/voice rotation");
                    for(cell_number=0;cell_number<=50;cell_number=cell_number+1)begin
                        tone_pattern=1;
                        for(k=0;k<6;k=k+1)if(dashboard.footer_token(line,cell_number+k)!==text_token(T_TONE,k))tone_pattern=0;
                        check(!tone_pattern,"normal footer never contains test-tone operation hint");
                    end
                end
                repeat(17)@(posedge clk);
                check(dashboard.footer_row_word(5)===footer_word(source,0),"footer does not rotate as time passes");
            end
        repeat(4)@(negedge clk);snap_rst_n=1;
        for(state=0;state<25;state=state+1)snapshot_case(state);
        pulse_snapshot();expect_snapshot();
        @(negedge clk);snap_rst_n=0;repeat(3)@(negedge clk);
        check(published()===90'd0,"global reset atomically clears all new snapshot fields");
        source=0;active_mode=1;algorithm_mode=3;pitch=4;pitch_second=7;pitch_voice=0;gain_index=19;
        rec_state=4;record_valid=1;record_full=0;storage_fault=0;ddr_ready=1;ddr_diag=16'h040f;
        record_progress=1464844;record_samples=1464844;play_samples=732422;
        rec_centis=3000;total_centis=3000;play_centis=1500;progress_pixels=0;
        render_and_scan("sim/results/lcd_dual_live.ppm");
        source=1;active_mode=0;pitch=-12;pitch_second=12;pitch_voice=1;gain_index=30;rec_state=11;progress_pixels=216;
        render_and_scan("sim/results/lcd_dual_clip.ppm");
        check(pair_cases==625 && snapshot_cases==25 && pages==2 && exact_pixels==261120,"complete dual formatter/snapshot/native frames coverage");
        $display("PASS DUAL_LCD checks=%0d signed_pitch_pairs=%0d gain21 editor_markers=2 snapshot_cases=%0d snapshot_latency=132 exact_pixels=%0d native_pages=%0d pixel_period_ns=120 setup_ns=60 fixed_footer_no_test_tone",checks,pair_cases,snapshot_cases,exact_pixels,pages);
        $finish;
    end
    initial begin #150000000;$fatal(1,"dual LCD timeout");end
endmodule
