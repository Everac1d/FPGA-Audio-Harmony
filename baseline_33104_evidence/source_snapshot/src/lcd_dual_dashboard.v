// 480x272 Chinese direct-scan UI, RGB666, all registers on clk_50m.
// Latency FIVE clk cycles: geometry -> formatted row -> token -> ROM -> color.
// A Chinese glyph occupies two 12px half-cells; Latin/digits occupy one.
// Main fields keep 24px text. Four fixed footer rows use true 16px text.
module lcd_dual_dashboard #(
    // Fine panel gain is in tenths: 10..30 = 1.0..3.0. Default retains
    // the legacy H0/H2/H4/H5/H6 interface for independent baseline tests.
    parameter integer FINE_GAIN=0
)(
    input wire clk,
    input wire [9:0] x,
    input wire [8:0] y,
    input wire source,
    input wire [1:0] active_mode,algorithm_mode,
    input wire signed [4:0] pitch,pitch_second,
    input wire pitch_voice,
    input wire [4:0] gain_index,
    input wire [3:0] rec_state,
    input wire record_valid,record_full,storage_fault,ddr_ready,
    input wire [15:0] ddr_diag,
    input wire [11:0] rec_centis,total_centis,play_centis,
    input wire [8:0] progress_pixels,
    output reg [17:0] rgb
);
    `include "src/lcd_ui_text.vh"
    `include "src/lcd_footer_text.vh"
    localparam [17:0] BG={6'd1,6'd2,6'd4},HEADER={6'd3,6'd9,6'd16},
        WHITE={6'd61,6'd62,6'd63},CYAN={6'd15,6'd61,6'd61},
        GREEN={6'd24,6'd60,6'd38},RED={6'd63,6'd28,6'd24},
        AMBER={6'd63,6'd50,6'd20},TRACK={6'd10,6'd17,6'd24};
    function [8:0] text_at;
        input [332:0] text;input integer index;
        begin
            if(index<0 || index>=37)text_at=0;
            else text_at=text >> ((36-index)*9);
        end
    endfunction
    function [8:0] digit;
        input integer value;
        begin digit={1'b0,G_U0030}+value;end
    endfunction
    function [8:0] hex_digit;
        input [3:0] value;
        begin
            if(value<10)hex_digit=digit(value);
            else case(value)
            10:hex_digit={1'b0,G_U0041};11:hex_digit={1'b0,G_U0042};
            12:hex_digit={1'b0,G_U0043};13:hex_digit={1'b0,G_U0044};
            14:hex_digit={1'b0,G_U0045};default:hex_digit={1'b0,G_U0046};
            endcase
        end
    endfunction
    function [8:0] time_token;
        input [11:0] value;input integer index;reg [11:0] bounded;
        begin
            bounded=value>3000 ? 12'd3000 : value;
            case(index)
            0:time_token=digit(bounded/1000);
            1:time_token=digit((bounded/100)%10);
            2:time_token={1'b0,G_U002E};
            3:time_token=digit((bounded/10)%10);
            4:time_token=digit(bounded%10);
            5,6:time_token=text_at(T_SECONDS,index-5);
            default:time_token=0;
            endcase
        end
    endfunction
    function [8:0] empty_time_token;
        input integer index;
        begin
            if(index==2)empty_time_token={1'b0,G_U002E};
            else if(index<5)empty_time_token={1'b0,G_U002D};
            else empty_time_token=text_at(T_SECONDS,index-5);
        end
    endfunction
    function [8:0] status_token;
        input integer index;
        input storage_fault,source;
        input [3:0] rec_state;
        input [1:0] active_mode;
        begin
            if(storage_fault || rec_state==10)status_token=text_at(T_FAULT,index);
            else if(!source)status_token=active_mode==0 ? text_at(T_LIVE_IDLE,index) : text_at(T_LIVE_RUNNING,index);
            else case(rec_state)
            0:status_token=text_at(T_DDR_INIT,index);
            1:status_token=text_at(T_EMPTY,index);
            2:status_token=text_at(T_RECORDING,index);
            3:status_token=text_at(T_SAVING,index);
            4:status_token=text_at(T_READY,index);
            5:status_token=text_at(T_PREPARE,index);
            6:status_token=text_at(T_WARMUP,index);
            7:status_token=text_at(T_PLAYING,index);
            8:status_token=text_at(T_TAIL,index);
            9:status_token=text_at(T_DRAIN,index);
            11:status_token=text_at(T_PAUSED,index);
            default:status_token=text_at(T_UNKNOWN,index);
            endcase
        end
    endfunction
    function [8:0] line_token_raw;
        input integer line,index;
        input source;
        input [1:0] active_mode,algorithm_mode;
        input signed [4:0] pitch,pitch_second;
        input pitch_voice;
        input [4:0] gain_index;
        input [3:0] rec_state;
        input record_valid,record_full,storage_fault,ddr_ready;
        input [15:0] ddr_diag;
        input [11:0] rec_centis,total_centis,play_centis;
        reg [4:0] magnitude,magnitude_second;
        reg [4:0] gain_tenths;
        begin
            line_token_raw=0;magnitude=pitch[4] ? -pitch : pitch;
            magnitude_second=pitch_second[4] ? -pitch_second : pitch_second;
            gain_tenths=(gain_index>=10 && gain_index<=30) ? gain_index : 5'd10;
            case(line)
            0:begin
                if(index<4)line_token_raw=source ? text_at(T_CLIP,index) : text_at(T_LIVE,index);
                else if(index>=6 && index<14)begin
                    if(source)line_token_raw=text_at(T_RECORD,index-6);
                    else case(active_mode)
                    0:line_token_raw=text_at(T_MUTED,index-6);
                    1:line_token_raw=text_at(T_MIC,index-6);
                    2:line_token_raw=text_at(T_TONE,index-6);
                    default:line_token_raw=text_at(T_UNKNOWN,index-6);
                    endcase
                end else if(index>=28)line_token_raw=text_at(T_TITLE,index-28);
            end
            1:begin
                if(algorithm_mode==3 && index<21)begin
                    if(index<6)line_token_raw=text_at(T_DUAL,index);
                    else case(index)
                    7:line_token_raw=!pitch_voice ? {1'b0,G_U003E}:9'd0;
                    8:line_token_raw=digit(1);
                    9,16:line_token_raw={1'b0,G_U003A};
                    10:line_token_raw=pitch[4] ? {1'b0,G_U002D}:{1'b0,G_U002B};
                    11:line_token_raw=digit(magnitude/10);
                    12:line_token_raw=digit(magnitude%10);
                    14:line_token_raw=pitch_voice ? {1'b0,G_U003E}:9'd0;
                    15:line_token_raw=digit(2);
                    17:line_token_raw=pitch_second[4] ? {1'b0,G_U002D}:{1'b0,G_U002B};
                    18:line_token_raw=digit(magnitude_second/10);
                    19:line_token_raw=digit(magnitude_second%10);
                    default:line_token_raw=0;
                    endcase
                end
                else if(index<4)line_token_raw=text_at(T_EFFECT,index);
                else if(index>=5 && index<9)case(algorithm_mode)
                0:line_token_raw=text_at(T_ORIGINAL,index-5);
                1:line_token_raw=text_at(T_PITCH,index-5);
                2:line_token_raw=text_at(T_HARMONY,index-5);
                default:line_token_raw=text_at(T_UNKNOWN,index-5);
                endcase
                else if(index>=11 && index<15)line_token_raw=text_at(T_SEMITONE,index-11);
                else if(index==16)line_token_raw=pitch[4] ? {1'b0,G_U002D} : {1'b0,G_U002B};
                else if(index==17)line_token_raw=digit(magnitude/10);
                else if(index==18)line_token_raw=digit(magnitude%10);
                else if(index>=21 && index<25)line_token_raw=text_at(T_GAIN,index-21);
                else if(index==26)begin
                    if(FINE_GAIN!=0)line_token_raw=digit(gain_tenths/10);
                    else case(gain_index)
                    0,2:line_token_raw=digit(1);4,5:line_token_raw=digit(2);6:line_token_raw=digit(3);
                    default:line_token_raw={1'b0,G_U003F};
                    endcase
                end
                else if(index==27)line_token_raw={1'b0,G_U002E};
                else if(index==28)line_token_raw=digit(FINE_GAIN!=0 ? gain_tenths%10 :
                    (gain_index==2 || gain_index==5 ? 5 : 0));
                else if(index==29 || index==30)line_token_raw=text_at(T_TIMES,index-29);
            end
            2:begin
                if(index<4)line_token_raw=text_at(T_STATUS,index);
                else if(index>=5 && index<25)line_token_raw=status_token(index-5,storage_fault,source,rec_state,active_mode);
                else if(index>=26)begin
                    if(record_full && record_valid && !storage_fault && rec_state!=10)line_token_raw=text_at(T_FULL,index-26);
                    else if(!storage_fault && rec_state!=10)
                        line_token_raw=ddr_ready ? text_at(T_DDR_READY,index-26) : text_at(T_DDR_STANDBY,index-26);
                end
            end
            3:begin
                if(index<4)line_token_raw=text_at(T_RECORD,index);
                else if(index>=5 && index<12)line_token_raw=time_token(rec_centis,index-5);
                else if(index>=14 && index<18)line_token_raw=text_at(T_TOTAL,index-14);
                else if(index>=19 && index<26)line_token_raw=record_valid ? time_token(total_centis,index-19) : empty_time_token(index-19);
            end
            4:begin
                if(storage_fault || rec_state==10)begin
                    if(index<6)line_token_raw=text_at(T_ERROR_CODE,index);
                    else if(index>=7 && index<11)case(index)
                    7:line_token_raw=hex_digit(ddr_diag[15:12]);8:line_token_raw=hex_digit(ddr_diag[11:8]);
                    9:line_token_raw=hex_digit(ddr_diag[7:4]);10:line_token_raw=hex_digit(ddr_diag[3:0]);
                    endcase
                    else if(index>=13)line_token_raw=text_at(T_RESET,index-13);
                end else begin
                    if(index<4)line_token_raw=text_at(T_PLAY,index);
                    else if(index>=5 && index<12)line_token_raw=time_token(play_centis,index-5);
                    else if(index==13)line_token_raw={1'b0,G_U002F};
                    else if(index>=15 && index<22)line_token_raw=record_valid ? time_token(total_centis,index-15) : empty_time_token(index-15);
                end
            end
            default:line_token_raw=0;
            endcase
        end
    endfunction
    // Format each cell at a CONSTANT elaboration index. This removes all
    // index offsets and wide string shifts from the pixel-address path.
    wire [332:0] display_row0,display_row1,display_row2,display_row3;
    wire [332:0] display_row4;
    genvar cell_number;
    generate for(cell_number=0;cell_number<37;cell_number=cell_number+1)begin: format_cells
        assign display_row0[(36-cell_number)*9 +: 9]=line_token_raw(0,cell_number,source,active_mode,algorithm_mode,pitch,pitch_second,pitch_voice,gain_index,rec_state,record_valid,record_full,storage_fault,ddr_ready,ddr_diag,rec_centis,total_centis,play_centis);
        assign display_row1[(36-cell_number)*9 +: 9]=line_token_raw(1,cell_number,source,active_mode,algorithm_mode,pitch,pitch_second,pitch_voice,gain_index,rec_state,record_valid,record_full,storage_fault,ddr_ready,ddr_diag,rec_centis,total_centis,play_centis);
        assign display_row2[(36-cell_number)*9 +: 9]=line_token_raw(2,cell_number,source,active_mode,algorithm_mode,pitch,pitch_second,pitch_voice,gain_index,rec_state,record_valid,record_full,storage_fault,ddr_ready,ddr_diag,rec_centis,total_centis,play_centis);
        assign display_row3[(36-cell_number)*9 +: 9]=line_token_raw(3,cell_number,source,active_mode,algorithm_mode,pitch,pitch_second,pitch_voice,gain_index,rec_state,record_valid,record_full,storage_fault,ddr_ready,ddr_diag,rec_centis,total_centis,play_centis);
        assign display_row4[(36-cell_number)*9 +: 9]=line_token_raw(4,cell_number,source,active_mode,algorithm_mode,pitch,pitch_second,pitch_voice,gain_index,rec_state,record_valid,record_full,storage_fault,ddr_ready,ddr_diag,rec_centis,total_centis,play_centis);
    end endgenerate
    function [8:0] cell_at;
        input [332:0] word;input [5:0] index;
        begin case(index)
        6'd0:cell_at=word[332 -: 9];
        6'd1:cell_at=word[323 -: 9];
        6'd2:cell_at=word[314 -: 9];
        6'd3:cell_at=word[305 -: 9];
        6'd4:cell_at=word[296 -: 9];
        6'd5:cell_at=word[287 -: 9];
        6'd6:cell_at=word[278 -: 9];
        6'd7:cell_at=word[269 -: 9];
        6'd8:cell_at=word[260 -: 9];
        6'd9:cell_at=word[251 -: 9];
        6'd10:cell_at=word[242 -: 9];
        6'd11:cell_at=word[233 -: 9];
        6'd12:cell_at=word[224 -: 9];
        6'd13:cell_at=word[215 -: 9];
        6'd14:cell_at=word[206 -: 9];
        6'd15:cell_at=word[197 -: 9];
        6'd16:cell_at=word[188 -: 9];
        6'd17:cell_at=word[179 -: 9];
        6'd18:cell_at=word[170 -: 9];
        6'd19:cell_at=word[161 -: 9];
        6'd20:cell_at=word[152 -: 9];
        6'd21:cell_at=word[143 -: 9];
        6'd22:cell_at=word[134 -: 9];
        6'd23:cell_at=word[125 -: 9];
        6'd24:cell_at=word[116 -: 9];
        6'd25:cell_at=word[107 -: 9];
        6'd26:cell_at=word[98 -: 9];
        6'd27:cell_at=word[89 -: 9];
        6'd28:cell_at=word[80 -: 9];
        6'd29:cell_at=word[71 -: 9];
        6'd30:cell_at=word[62 -: 9];
        6'd31:cell_at=word[53 -: 9];
        6'd32:cell_at=word[44 -: 9];
        6'd33:cell_at=word[35 -: 9];
        6'd34:cell_at=word[26 -: 9];
        6'd35:cell_at=word[17 -: 9];
        6'd36:cell_at=word[8 -: 9];
        default:cell_at=0;
        endcase end
    endfunction
    function [332:0] row_word;
        input [3:0] line;
        begin case(line)
        0:row_word=display_row0;1:row_word=display_row1;
        2:row_word=display_row2;3:row_word=display_row3;
        4:row_word=display_row4;default:row_word=0;
        endcase end
    endfunction
    // Verification and character decoding use the same formatted rows.
    function [8:0] line_token;
        input integer line,index;
        begin
            if(line<0 || line>=5 || index<0 || index>=37)line_token=0;
            else line_token=cell_at(row_word(line[3:0]),index[5:0]);
        end
    endfunction
    // Only the frame-atomic source bit selects these two complete pages.
    // No timer, rotating help page or recorder-state-dependent hint exists.
    function [503:0] footer_row_word;
        input [3:0] line;
        begin case(line)
        5:footer_row_word=source ? TF_CLIP_0 : TF_LIVE_0;
        6:footer_row_word=source ? TF_CLIP_1 : TF_LIVE_1;
        7:footer_row_word=source ? TF_CLIP_2 : TF_LIVE_2;
        8:footer_row_word=source ? TF_CLIP_3 : TF_LIVE_3;
        default:footer_row_word=0;
        endcase end
    endfunction
    function [8:0] footer_cell_at;
        input [503:0] word;input [5:0] index;
        begin case(index)
        6'd0:footer_cell_at=word[503 -: 9];
        6'd1:footer_cell_at=word[494 -: 9];
        6'd2:footer_cell_at=word[485 -: 9];
        6'd3:footer_cell_at=word[476 -: 9];
        6'd4:footer_cell_at=word[467 -: 9];
        6'd5:footer_cell_at=word[458 -: 9];
        6'd6:footer_cell_at=word[449 -: 9];
        6'd7:footer_cell_at=word[440 -: 9];
        6'd8:footer_cell_at=word[431 -: 9];
        6'd9:footer_cell_at=word[422 -: 9];
        6'd10:footer_cell_at=word[413 -: 9];
        6'd11:footer_cell_at=word[404 -: 9];
        6'd12:footer_cell_at=word[395 -: 9];
        6'd13:footer_cell_at=word[386 -: 9];
        6'd14:footer_cell_at=word[377 -: 9];
        6'd15:footer_cell_at=word[368 -: 9];
        6'd16:footer_cell_at=word[359 -: 9];
        6'd17:footer_cell_at=word[350 -: 9];
        6'd18:footer_cell_at=word[341 -: 9];
        6'd19:footer_cell_at=word[332 -: 9];
        6'd20:footer_cell_at=word[323 -: 9];
        6'd21:footer_cell_at=word[314 -: 9];
        6'd22:footer_cell_at=word[305 -: 9];
        6'd23:footer_cell_at=word[296 -: 9];
        6'd24:footer_cell_at=word[287 -: 9];
        6'd25:footer_cell_at=word[278 -: 9];
        6'd26:footer_cell_at=word[269 -: 9];
        6'd27:footer_cell_at=word[260 -: 9];
        6'd28:footer_cell_at=word[251 -: 9];
        6'd29:footer_cell_at=word[242 -: 9];
        6'd30:footer_cell_at=word[233 -: 9];
        6'd31:footer_cell_at=word[224 -: 9];
        6'd32:footer_cell_at=word[215 -: 9];
        6'd33:footer_cell_at=word[206 -: 9];
        6'd34:footer_cell_at=word[197 -: 9];
        6'd35:footer_cell_at=word[188 -: 9];
        6'd36:footer_cell_at=word[179 -: 9];
        6'd37:footer_cell_at=word[170 -: 9];
        6'd38:footer_cell_at=word[161 -: 9];
        6'd39:footer_cell_at=word[152 -: 9];
        6'd40:footer_cell_at=word[143 -: 9];
        6'd41:footer_cell_at=word[134 -: 9];
        6'd42:footer_cell_at=word[125 -: 9];
        6'd43:footer_cell_at=word[116 -: 9];
        6'd44:footer_cell_at=word[107 -: 9];
        6'd45:footer_cell_at=word[98 -: 9];
        6'd46:footer_cell_at=word[89 -: 9];
        6'd47:footer_cell_at=word[80 -: 9];
        6'd48:footer_cell_at=word[71 -: 9];
        6'd49:footer_cell_at=word[62 -: 9];
        6'd50:footer_cell_at=word[53 -: 9];
        6'd51:footer_cell_at=word[44 -: 9];
        6'd52:footer_cell_at=word[35 -: 9];
        6'd53:footer_cell_at=word[26 -: 9];
        6'd54:footer_cell_at=word[17 -: 9];
        6'd55:footer_cell_at=word[8 -: 9];
        default:footer_cell_at=0;
        endcase end
    endfunction
    function [8:0] footer_token;
        input integer line,index;
        begin
            if(line<0 || line>=4 || index<0 || index>=56)footer_token=0;
            else footer_token=footer_cell_at(footer_row_word(line+5),index[5:0]);
        end
    endfunction
    reg [3:0] line_s1;
    reg [5:0] cell_s1,cell_s2;
    reg [332:0] word_s2;
    reg [503:0] footer_word_s2;
    reg small_s1,small_s2,small_s3,small_s4;
    reg [4:0] row_s1,row_s2,row_s3,column_s3;
    reg [3:0] half_x_s1,half_x_s2;
    reg [7:0] glyph_s3;
    reg text_s1,text_s2,text_s3,text_s4;
    reg [17:0] ink_s1,ink_s2,ink_s3,ink_s4,bg_s1,bg_s2,bg_s3,bg_s4;
    wire [8:0] token=small_s2 ? footer_cell_at(footer_word_s2,cell_s2) : cell_at(word_s2,cell_s2);
    reg text_enable;
    reg [17:0] ink,background;
    integer line,cell_index,dx,dy;
    wire glyph_pixel,small_pixel;
    lcd_cjk24_font font(.clk(clk),.glyph(glyph_s3),.row(row_s3),.column(column_s3),.pixel(glyph_pixel));
    lcd_cjk16_font footer_font(.clk(clk),.glyph(glyph_s3),.row(row_s3[3:0]),.column(column_s3),.pixel(small_pixel));
    always @* begin
        line=15;cell_index=0;dx=0;dy=0;text_enable=0;ink=WHITE;background=BG;
        if(y<36)background=HEADER;
        if(y==36 || y==201)background=TRACK;
        if(y>=182 && y<194 && x>=24 && x<456)begin
            background=TRACK;
            if((x-24)<progress_pixels)background=(storage_fault || rec_state==10 || rec_state==2) ? RED : CYAN;
        end
        if(x>=16 && x<460)begin
            if(y>=8 && y<32)begin line=0;dy=y-8;end
            else if(y>=44 && y<68)begin line=1;dy=y-44;end
            else if(y>=80 && y<104)begin line=2;dy=y-80;end
            else if(y>=114 && y<138)begin line=3;dy=y-114;end
            else if(y>=148 && y<172)begin line=4;dy=y-148;end
            if(line<5)begin
                dx=x-16;cell_index=dx/12;text_enable=1;
                if(line==0)ink=CYAN;
                else if(line==1 && algorithm_mode==3)begin
                    if(cell_index<6 || (!pitch_voice && cell_index>=7 && cell_index<=12) ||
                        (pitch_voice && cell_index>=14 && cell_index<=19))ink=GREEN;
                    else if(cell_index>=26)ink=AMBER;
                    else ink=WHITE;
                end
                else if(line==1 && cell_index>=5 && cell_index<9)ink=GREEN;
                else if(line==1 && (cell_index>=16 && cell_index<=18 || cell_index>=26))ink=AMBER;
                else if(line==2 && cell_index>=5)begin
                    if(storage_fault || rec_state==10)ink=RED;
                    else if(cell_index>=26 && record_full && record_valid)ink=AMBER;
                    else if(source && rec_state==2)ink=RED;
                    else if(source && rec_state==11)ink=AMBER;
                    else if(source && rec_state==4)ink=GREEN;
                    else ink=CYAN;
                end else if(line==4 && (storage_fault || rec_state==10))ink=RED;
            end
        end
        if(x>=16 && x<464)begin
            if(y>=204 && y<220)begin line=5;dy=y-204;end
            else if(y>=221 && y<237)begin line=6;dy=y-221;end
            else if(y>=238 && y<254)begin line=7;dy=y-238;end
            else if(y>=255 && y<271)begin line=8;dy=y-255;end
            if(line>=5 && line<=8)begin
                dx=x-16;cell_index=dx/8;text_enable=1;ink=WHITE;
            end
        end
    end
    always @(posedge clk)begin
        line_s1<=line;cell_s1<=cell_index;row_s1<=dy;
        small_s1<=line>=5 && line<=8;
        if(line>=5 && line<=8)half_x_s1<=dx[2:0];else half_x_s1<=dx%12;
        text_s1<=text_enable;ink_s1<=ink;bg_s1<=background;
        word_s2<=row_word(line_s1);footer_word_s2<=footer_row_word(line_s1);
        cell_s2<=cell_s1;row_s2<=row_s1;half_x_s2<=half_x_s1;small_s2<=small_s1;
        text_s2<=text_s1;ink_s2<=ink_s1;bg_s2<=bg_s1;
        glyph_s3<=token[7:0];column_s3<=half_x_s2+(token[8] ? (small_s2 ? 5'd8 : 5'd12) : 5'd0);row_s3<=row_s2;small_s3<=small_s2;
        text_s3<=text_s2;ink_s3<=ink_s2;bg_s3<=bg_s2;
        text_s4<=text_s3;ink_s4<=ink_s3;bg_s4<=bg_s3;small_s4<=small_s3;
        rgb<=text_s4 && (small_s4 ? small_pixel : glyph_pixel) ? ink_s4 : bg_s4;
    end
endmodule
