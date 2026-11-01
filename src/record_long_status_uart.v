// Five-minute raw PCM status: R6 is117 bytes, D3 is164, one atomic281-byte pair.
module record_long_status_uart #(
    parameter integer CLK_HZ=50000000,BAUD=115200,REPORT_CYCLES=25000000,
    parameter [31:0] USER_CODE=32'h00033105
)(
    input wire clk,rst_n,source,
    input wire [1:0] live_mode,algorithm_mode,
    input wire signed [4:0] pitch_semitones,pitch_second,
    input wire pitch_voice,
    input wire [4:0] gain_index,
    input wire [3:0] rec_state,
    input wire [31:0] record_samples,play_samples,
    input wire ddr_ready,storage_error,
    input wire [15:0] ddr_diag,
    input wire [544:0] ddr_failure,
    input wire record_full,mic_ready,
    input wire [31:0] queue_underflow_count,queue_overflow_count,
    output reg uart_tx
);
    localparam integer CLKS_PER_BIT=(CLK_HZ+BAUD/2)/BAUD;
    localparam [2:0] IDLE=0,LOAD=1,START=2,DATA=3,STOP=4;
    localparam integer STATUS_BYTES=117;
    reg [2:0] state;
    reg [31:0] report_timer,bit_timer;
    reg [8:0] byte_index;
    reg [2:0] bit_index;
    reg [7:0] tx_byte;
    reg snap_source,snap_ddr,snap_error,snap_full,snap_mic,snap_pitch_voice;
    reg [1:0] snap_live,snap_algorithm;
    reg [4:0] snap_pitch,snap_pitch_second,snap_gain;
    reg [3:0] snap_state;
    reg [31:0] snap_record,snap_play,snap_underflow,snap_overflow;
    reg [15:0] snap_diag;
    reg [544:0] snap_failure;
    function [7:0] hex_ascii;
        input [3:0] nibble;
        begin hex_ascii=nibble<10 ? 8'h30+nibble : 8'h41+nibble-10;end
    endfunction
    function [7:0] failure_byte;
        input [8:0] index;
        begin
            if(index>=5 && index<=12)
                failure_byte=hex_ascii(USER_CODE >> ((12-index)*4));
            else if(index>=20 && index<=27)
                failure_byte=hex_ascii({3'd0,snap_failure[540:512]} >> ((27-index)*4));
            else if(index>=31 && index<=94)
                failure_byte=hex_ascii(snap_failure[511:256] >> ((94-index)*4));
            else if(index>=98 && index<=161)
                failure_byte=hex_ascii(snap_failure[255:0] >> ((161-index)*4));
            else case(index)
                0:failure_byte="D";1:failure_byte="3";3:failure_byte="V";
                4,15,19,30,97:failure_byte="=";
                14:failure_byte="J";16:failure_byte=hex_ascii(snap_failure[544:541]);
                18:failure_byte="B";29:failure_byte="W";96:failure_byte="R";
                162:failure_byte=8'h0d;163:failure_byte=8'h0a;
                default:failure_byte=" ";
            endcase
        end
    endfunction
    function [7:0] report_byte;
        input [8:0] index;
        begin
            if(index>=117)report_byte=failure_byte(index-9'd117);
            else if(index>=5 && index<=12)report_byte=hex_ascii(USER_CODE >> ((12-index)*4));
            else if(index>=16 && index<=16)report_byte=hex_ascii(snap_source >> ((16-index)*4));
            else if(index>=20 && index<=20)report_byte=hex_ascii(snap_live >> ((20-index)*4));
            else if(index>=24 && index<=24)report_byte=hex_ascii(snap_algorithm >> ((24-index)*4));
            else if(index>=28 && index<=29)report_byte=hex_ascii(snap_pitch >> ((29-index)*4));
            else if(index>=33 && index<=34)report_byte=hex_ascii(snap_gain >> ((34-index)*4));
            else if(index>=38 && index<=38)report_byte=hex_ascii(snap_state >> ((38-index)*4));
            else if(index>=42 && index<=49)report_byte=hex_ascii(snap_record >> ((49-index)*4));
            else if(index>=53 && index<=60)report_byte=hex_ascii(snap_play >> ((60-index)*4));
            else if(index>=64 && index<=64)report_byte=hex_ascii(snap_ddr >> ((64-index)*4));
            else if(index>=68 && index<=68)report_byte=hex_ascii(snap_error >> ((68-index)*4));
            else if(index>=72 && index<=72)report_byte=hex_ascii(snap_full >> ((72-index)*4));
            else if(index>=76 && index<=76)report_byte=hex_ascii(snap_mic >> ((76-index)*4));
            else if(index>=80 && index<=87)report_byte=hex_ascii(snap_underflow >> ((87-index)*4));
            else if(index>=91 && index<=98)report_byte=hex_ascii(snap_overflow >> ((98-index)*4));
            else if(index>=102 && index<=105)report_byte=hex_ascii(snap_diag >> ((105-index)*4));
            else if(index>=109 && index<=110)report_byte=hex_ascii(snap_pitch_second >> ((110-index)*4));
            else if(index>=114 && index<=114)report_byte=hex_ascii(snap_pitch_voice >> ((114-index)*4));
            else case(index)
                0:report_byte=8'h52;
                1:report_byte=8'h36;
                2:report_byte=8'h20;
                3:report_byte=8'h56;
                4:report_byte=8'h3d;
                13:report_byte=8'h20;
                14:report_byte=8'h53;
                15:report_byte=8'h3d;
                17:report_byte=8'h20;
                18:report_byte=8'h4d;
                19:report_byte=8'h3d;
                21:report_byte=8'h20;
                22:report_byte=8'h41;
                23:report_byte=8'h3d;
                25:report_byte=8'h20;
                26:report_byte=8'h4e;
                27:report_byte=8'h3d;
                30:report_byte=8'h20;
                31:report_byte=8'h48;
                32:report_byte=8'h3d;
                35:report_byte=8'h20;
                36:report_byte=8'h54;
                37:report_byte=8'h3d;
                39:report_byte=8'h20;
                40:report_byte=8'h4c;
                41:report_byte=8'h3d;
                50:report_byte=8'h20;
                51:report_byte=8'h50;
                52:report_byte=8'h3d;
                61:report_byte=8'h20;
                62:report_byte=8'h44;
                63:report_byte=8'h3d;
                65:report_byte=8'h20;
                66:report_byte=8'h45;
                67:report_byte=8'h3d;
                69:report_byte=8'h20;
                70:report_byte=8'h46;
                71:report_byte=8'h3d;
                73:report_byte=8'h20;
                74:report_byte=8'h49;
                75:report_byte=8'h3d;
                77:report_byte=8'h20;
                78:report_byte=8'h55;
                79:report_byte=8'h3d;
                88:report_byte=8'h20;
                89:report_byte=8'h4f;
                90:report_byte=8'h3d;
                99:report_byte=8'h20;
                100:report_byte=8'h58;
                101:report_byte=8'h3d;
                106:report_byte=8'h20;
                107:report_byte=8'h51;
                108:report_byte=8'h3d;
                111:report_byte=8'h20;
                112:report_byte=8'h43;
                113:report_byte=8'h3d;
                115:report_byte=8'h0d;
                116:report_byte=8'h0a;
                default:report_byte=" ";
            endcase
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; uart_tx<=1; report_timer<=0; bit_timer<=0;
            byte_index<=0; bit_index<=0; tx_byte<=0;
            snap_source<=0;snap_ddr<=0;snap_error<=0;snap_full<=0;snap_mic<=0;
            snap_live<=0;snap_algorithm<=0;snap_pitch<=0;snap_pitch_second<=0;snap_pitch_voice<=0;snap_gain<=0;snap_state<=0;
            snap_record<=0;snap_play<=0;snap_underflow<=0;snap_overflow<=0;snap_diag<=0;snap_failure<=0;
        end else begin
            // Saturate while busy: an unusually short report period cannot
            // overwrite the active packet or accumulate an unbounded backlog.
            if (report_timer < REPORT_CYCLES-1) report_timer<=report_timer+1'b1;
            case(state)
                IDLE: begin
                    uart_tx<=1;
                    if (report_timer==REPORT_CYCLES-1) begin
                        snap_source<=source;snap_live<=live_mode;snap_algorithm<=algorithm_mode;
                        snap_pitch<=pitch_semitones;snap_pitch_second<=pitch_second;snap_pitch_voice<=pitch_voice;snap_gain<=gain_index;snap_state<=rec_state;
                        snap_record<=record_samples;snap_play<=play_samples;
                        snap_ddr<=ddr_ready;snap_error<=storage_error;snap_full<=record_full;snap_mic<=mic_ready;
                        snap_underflow<=queue_underflow_count;snap_overflow<=queue_overflow_count;
                        snap_diag<=ddr_diag;
                        snap_failure<=ddr_failure;
                        report_timer<=0;byte_index<=0;state<=LOAD;
                    end
                end
                LOAD:begin
                    tx_byte<=report_byte(byte_index);bit_index<=0;bit_timer<=0;
                    uart_tx<=0;state<=START;
                end
                START:begin
                    if(bit_timer==CLKS_PER_BIT-1) begin
                        bit_timer<=0;uart_tx<=tx_byte[0];state<=DATA;
                    end else bit_timer<=bit_timer+1'b1;
                end
                DATA:begin
                    if(bit_timer==CLKS_PER_BIT-1) begin
                        bit_timer<=0;
                        if(bit_index==7) begin uart_tx<=1;state<=STOP;end
                        else begin bit_index<=bit_index+1'b1;uart_tx<=tx_byte[bit_index+1'b1];end
                    end else bit_timer<=bit_timer+1'b1;
                end
                STOP:begin
                    if(bit_timer==CLKS_PER_BIT-1) begin
                        bit_timer<=0;
                        if(byte_index==STATUS_BYTES+163) state<=IDLE;
                        else begin byte_index<=byte_index+1'b1;state<=LOAD;end
                    end else bit_timer<=bit_timer+1'b1;
                end
                default:begin state<=IDLE;uart_tx<=1;report_timer<=0;end
            endcase
        end
    end
endmodule
