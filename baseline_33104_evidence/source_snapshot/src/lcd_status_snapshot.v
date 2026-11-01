// One clock domain. Capture atomically in vertical blank, calculate over 132
// clocks, then publish the entire snapshot at the NEXT frame boundary.
// No combinational divider or audio backpressure; all time values are floor(cs).
module lcd_status_snapshot #(
    parameter integer MAX_SAMPLES=1464844
)(
    input wire clk,rst_n,frame_start,
    input wire source,
    input wire [1:0] active_mode,algorithm_mode,
    input wire signed [4:0] pitch,
    input wire [4:0] gain_index,
    input wire [3:0] rec_state,
    input wire record_valid,record_full,storage_fault,ddr_ready,
    input wire [15:0] ddr_diag,
    input wire [20:0] record_progress,record_samples,play_samples,
    output wire source_o,
    output wire [1:0] active_mode_o,algorithm_mode_o,
    output wire signed [4:0] pitch_o,
    output wire [4:0] gain_index_o,
    output wire [3:0] rec_state_o,
    output wire record_valid_o,record_full_o,storage_fault_o,ddr_ready_o,
    output wire [15:0] ddr_diag_o,
    output reg [11:0] rec_centis,total_centis,play_centis,
    output reg [8:0] progress_pixels
);
    reg [38:0] front_status,stage_status;
    assign {source_o,active_mode_o,algorithm_mode_o,pitch_o,gain_index_o,
        rec_state_o,record_valid_o,record_full_o,storage_fault_o,ddr_ready_o,
        ddr_diag_o}=front_status;
    reg [20:0] stage_rec,stage_total,stage_play;
    reg [11:0] calc_rec,calc_total,calc_play;
    reg [8:0] calc_pixels;
    reg busy,ready,load_job;
    reg [1:0] job;
    reg [5:0] bit_count;
    reg [31:0] dividend,divisor,quotient,remainder;
    wire [32:0] trial={remainder,dividend[31]};
    wire subtract_ok=trial>={1'b0,divisor};
    wire [31:0] quotient_next={quotient[30:0],subtract_ok};
    wire [32:0] difference=trial-{1'b0,divisor};
    wire [20:0] safe_rec=record_progress>MAX_SAMPLES ? MAX_SAMPLES : record_progress;
    wire [20:0] safe_total=record_samples>MAX_SAMPLES ? MAX_SAMPLES : record_samples;
    wire [20:0] safe_play=play_samples>safe_total ? safe_total : play_samples;
    reg stage_recording,stage_playback;
    // Four restoring divisions; 32 iterations each. Payload never leaves clk.
    always @(posedge clk) begin
        if(!rst_n)begin
            front_status<=0;stage_status<=0;stage_rec<=0;stage_total<=0;stage_play<=0;
            rec_centis<=0;total_centis<=0;play_centis<=0;progress_pixels<=0;
            calc_rec<=0;calc_total<=0;calc_play<=0;calc_pixels<=0;
            stage_recording<=0;stage_playback<=0;
            busy<=0;ready<=0;load_job<=0;job<=0;bit_count<=0;
            dividend<=0;divisor<=1;quotient<=0;remainder<=0;
        end else if(frame_start && !busy)begin
            if(ready)begin
                front_status<=stage_status;
                rec_centis<=calc_rec;total_centis<=calc_total;
                play_centis<=calc_play;progress_pixels<=calc_pixels;
            end
            stage_status<={source,active_mode,algorithm_mode,pitch,gain_index,
                rec_state,record_valid,record_full,storage_fault,ddr_ready,ddr_diag};
            stage_rec<=safe_rec;
            stage_total<=record_valid ? safe_total : 21'd0;
            stage_play<=record_valid ? safe_play : 21'd0;
            stage_recording<=(rec_state==2 || rec_state==3);
            stage_playback<=(rec_state>=5 && rec_state<=9) || rec_state==11;
            busy<=1;ready<=0;load_job<=1;job<=0;
        end else if(busy)begin
            if(load_job)begin
                case(job)
                0:begin dividend<={1'b0,stage_rec,10'd0};divisor<=500000;end
                1:begin dividend<={1'b0,stage_total,10'd0};divisor<=500000;end
                2:begin dividend<={1'b0,stage_play,10'd0};divisor<=500000;end
                3:begin
                    dividend<=stage_recording ? ({11'd0,stage_rec}*32'd432) :
                        (stage_playback ? ({11'd0,stage_play}*32'd432) : 32'd0);
                    divisor<=stage_recording ? MAX_SAMPLES :
                        (stage_total==0 ? 32'd1 : {11'd0,stage_total});
                end
                endcase
                quotient<=0;remainder<=0;bit_count<=0;load_job<=0;
            end else begin
                dividend<={dividend[30:0],1'b0};
                remainder<=subtract_ok ? difference[31:0] : trial[31:0];
                quotient<=quotient_next;
                if(bit_count==31)begin
                    case(job)
                    0:calc_rec<=quotient_next>3000 ? 12'd3000 : quotient_next[11:0];
                    1:calc_total<=quotient_next>3000 ? 12'd3000 : quotient_next[11:0];
                    2:calc_play<=quotient_next>3000 ? 12'd3000 : quotient_next[11:0];
                    3:calc_pixels<=quotient_next>432 ? 9'd432 : quotient_next[8:0];
                    endcase
                    if(job==3)begin busy<=0;ready<=1;end
                    else begin job<=job+1'b1;load_job<=1;end
                end else bit_count<=bit_count+1'b1;
            end
        end
    end
endmodule
