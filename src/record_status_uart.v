// R3 status plus D3 first-DDR-failure packet for UserCode 00032503.
// All inputs already belong to clk. One atomic snapshot per complete line.
// 50 MHz / rounded 115200 = 434 clocks per bit, 8 data bits, no parity, 1 stop.
// R3 is 103 bytes; D3 is 164 bytes, both including CRLF. One atomic pair.
// D3 V=00032503 J=x B=xxxxxxxx W=<64 hex expected> R=<64 hex actual>\r\n
// N is the original 5-bit two's-complement code, zero extended to two hex digits.
module record_status_uart #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200,
    parameter integer REPORT_CYCLES = 25000000,
    parameter integer FINE_GAIN=0,
    parameter integer DUAL_VOICE_ENABLE=0,
    parameter [31:0] USER_CODE=32'h00032503
) (
    input wire clk,
    input wire rst_n,
    input wire source,
    input wire [1:0] live_mode,
    input wire [1:0] algorithm_mode,
    input wire signed [4:0] pitch_semitones,pitch_second,
    input wire pitch_voice,
    input wire [4:0] gain_index,
    input wire [3:0] rec_state,
    input wire [20:0] record_samples,
    input wire [20:0] play_samples,
    input wire ddr_ready,
    input wire storage_error,
    input wire [15:0] ddr_diag,
    input wire [544:0] ddr_failure,
    input wire record_full,
    input wire mic_ready,
    input wire [31:0] queue_underflow_count,
    input wire [31:0] queue_overflow_count,
    output reg uart_tx
);
    localparam integer CLKS_PER_BIT = (CLK_HZ + BAUD/2) / BAUD;
    localparam [2:0] IDLE=0, LOAD=1, START=2, DATA=3, STOP=4;
    reg [2:0] state;
    reg [31:0] report_timer, bit_timer;
    reg [8:0] byte_index;
    reg [2:0] bit_index;
    reg [7:0] tx_byte;
    reg snap_source, snap_ddr, snap_error, snap_full, snap_mic;
    reg [1:0] snap_live, snap_algorithm;
    reg [4:0] snap_pitch,snap_pitch_second;reg snap_pitch_voice;
    reg [4:0] snap_gain;
    reg [3:0] snap_state;
    reg [20:0] snap_record, snap_play;
    reg [31:0] snap_underflow, snap_overflow;
    reg [15:0] snap_diag;
    reg [544:0] snap_failure;

    function [7:0] hex_ascii;
        input [3:0] nibble;
        begin hex_ascii=(nibble<10) ? 8'h30+nibble : 8'h41+nibble-10; end
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
    function [7:0] legacy_report_byte;
        input [8:0] index;
        begin
            if(index>=103) legacy_report_byte=failure_byte(index-9'd103);
            else if(index>=5 && index<=12)
                legacy_report_byte=hex_ascii(USER_CODE >> ((12-index)*4));
            else if (index>=41 && index<=46)
                legacy_report_byte=hex_ascii({3'd0,snap_record} >> ((46-index)*4));
            else if (index>=50 && index<=55)
                legacy_report_byte=hex_ascii({3'd0,snap_play} >> ((55-index)*4));
            else if (index>=75 && index<=82)
                legacy_report_byte=hex_ascii(snap_underflow >> ((82-index)*4));
            else if (index>=86 && index<=93)
                legacy_report_byte=hex_ascii(snap_overflow >> ((93-index)*4));
            else if (index>=97 && index<=100)
                legacy_report_byte=hex_ascii(snap_diag >> ((100-index)*4));
            else case(index)
                0:legacy_report_byte="R"; 1:legacy_report_byte="3"; 3:legacy_report_byte="V";
                4,15,19,23,27,32,36,40,49,58,62,66,70,74,85:legacy_report_byte="=";
                14:legacy_report_byte="S"; 16:legacy_report_byte=hex_ascii({3'd0,snap_source});
                18:legacy_report_byte="M"; 20:legacy_report_byte=hex_ascii({2'd0,snap_live});
                22:legacy_report_byte="A"; 24:legacy_report_byte=hex_ascii({2'd0,snap_algorithm});
                26:legacy_report_byte="N"; 28:legacy_report_byte=hex_ascii({3'd0,snap_pitch[4]});
                29:legacy_report_byte=hex_ascii(snap_pitch[3:0]);
                31:legacy_report_byte="H"; 33:legacy_report_byte=hex_ascii({1'd0,snap_gain[2:0]});
                35:legacy_report_byte="T"; 37:legacy_report_byte=hex_ascii(snap_state);
                39:legacy_report_byte="L"; 48:legacy_report_byte="P";
                57:legacy_report_byte="D"; 59:legacy_report_byte=hex_ascii({3'd0,snap_ddr});
                61:legacy_report_byte="E"; 63:legacy_report_byte=hex_ascii({3'd0,snap_error});
                65:legacy_report_byte="F"; 67:legacy_report_byte=hex_ascii({3'd0,snap_full});
                69:legacy_report_byte="I"; 71:legacy_report_byte=hex_ascii({3'd0,snap_mic});
                73:legacy_report_byte="U"; 84:legacy_report_byte="O";
                95:legacy_report_byte="X";96:legacy_report_byte="=";
                101:legacy_report_byte=8'h0d; 102:legacy_report_byte=8'h0a;
                default:legacy_report_byte=" ";
            endcase
        end
    endfunction


    // R4 adds a second H digit. H=0A..1E is the gain in tenths, not a
    // legacy gain index. All other fields and the atomic D3 packet are kept.
    localparam integer STATUS_BYTES=(DUAL_VOICE_ENABLE!=0) ? 113 : ((FINE_GAIN!=0) ? 104 : 103);
    function [7:0] report_byte;
        input [8:0] index;
        begin
            if(DUAL_VOICE_ENABLE!=0 && index>=113)report_byte=failure_byte(index-9'd113);
            else if(DUAL_VOICE_ENABLE!=0 && index>=102)begin
                case(index)
                102,107:report_byte=" ";103:report_byte="Q";104,109:report_byte="=";
                105:report_byte=hex_ascii({3'd0,snap_pitch_second[4]});
                106:report_byte=hex_ascii(snap_pitch_second[3:0]);
                108:report_byte="C";110:report_byte=hex_ascii({3'd0,snap_pitch_voice});
                111:report_byte=8'h0d;112:report_byte=8'h0a;
                default:report_byte=" ";endcase
            end
            else if(DUAL_VOICE_ENABLE!=0 && index==1)report_byte="5";
            else if(FINE_GAIN==0)report_byte=legacy_report_byte(index);
            else if(index>=104)report_byte=failure_byte(index-9'd104);
            else if(index==1)report_byte="4";
            else if(index==33)report_byte=hex_ascii({3'd0,snap_gain[4]});
            else if(index==34)report_byte=hex_ascii(snap_gain[3:0]);
            else report_byte=legacy_report_byte(index>34 ? index-1'b1 : index);
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
