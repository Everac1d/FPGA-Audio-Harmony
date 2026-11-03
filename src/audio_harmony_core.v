// 对外提供三种音效：完全原声、单声部变调、双声部和声。
// 两组历史数据始终接收相同样本，在和声模式之外也如此；和声
// 声部为零半音时读取固定对齐的原声抽头，不保留
// 旧的粒度读头相位，因此两个零半音声部始终相同。
// 每个声部均保留已验证的+17时钟周期流水线与启动包络。
module audio_harmony_core #(
    parameter integer RAM_ADDR_BITS=14,
    parameter integer GRAIN_LOG2=13,
    parameter integer GUARD_SAMPLES=32,
    parameter integer DYNAMIC_CONFIG=1
) (
    input wire clk,rst_n,
    input wire signed [15:0] pcm_in,
    input wire pcm_in_valid,
    input wire [1:0] mode,
    input wire signed [4:0] pitch_semitones,
    output wire signed [15:0] pcm_out,
    output wire pcm_out_valid,
    input wire signed [4:0] pitch_second
);
    reg configured;
    reg [1:0] configured_mode,job_mode;
    reg signed [4:0] configured_pitch,configured_second;
    wire [1:0] selected_mode=(DYNAMIC_CONFIG!=0) ? mode :
        (configured ? configured_mode : mode);
    wire signed [4:0] selected_pitch=(DYNAMIC_CONFIG!=0) ? pitch_semitones :
        (configured ? configured_pitch : pitch_semitones);
    wire signed [4:0] selected_second=(DYNAMIC_CONFIG!=0) ? pitch_second :
        (configured ? configured_second : pitch_second);
    always @(posedge clk)begin
        if(!rst_n)begin
            configured<=0;configured_mode<=0;configured_pitch<=0;configured_second<=0;job_mode<=0;
        end else if(pcm_in_valid)begin
            configured<=1;
            if(!configured)begin
                configured_mode<=mode;configured_pitch<=pitch_semitones;configured_second<=pitch_second;
            end
            job_mode<=selected_mode;
        end
    end
    wire [1:0] first_mode=(selected_mode==2'd2) ?
        ((selected_pitch==0) ? 2'd3:2'd1) : selected_mode;
    wire [1:0] second_mode=(selected_second==0) ? 2'd3:2'd1;
    wire signed [15:0] first_out,second_out;
    wire first_valid,second_valid;
    pcm_harmony_read_pitch #(.RAM_ADDR_BITS(RAM_ADDR_BITS),.GRAIN_LOG2(GRAIN_LOG2),
        .GUARD_SAMPLES(GUARD_SAMPLES),.DYNAMIC_CONFIG(DYNAMIC_CONFIG)) algorithm(
        .clk(clk),.rst_n(rst_n),.pcm_in(pcm_in),.in_valid(pcm_in_valid),
        .mode(first_mode),.pitch_semitones(selected_pitch),.pcm_out(first_out),.out_valid(first_valid));
    pcm_harmony_read_pitch #(.RAM_ADDR_BITS(RAM_ADDR_BITS),.GRAIN_LOG2(GRAIN_LOG2),
        .GUARD_SAMPLES(GUARD_SAMPLES),.DYNAMIC_CONFIG(DYNAMIC_CONFIG)) second_algorithm(
        .clk(clk),.rst_n(rst_n),.pcm_in(pcm_in),.in_valid(pcm_in_valid),
        .mode(second_mode),.pitch_semitones(selected_second),.pcm_out(second_out),.out_valid(second_valid));
    wire signed [16:0] sum=$signed({first_out[15],first_out})+$signed({second_out[15],second_out});
    wire signed [16:0] mean=sum/17'sd2;
    assign pcm_out=(job_mode==2'd2) ? mean[15:0] :
        ((job_mode==2'd0 || job_mode==2'd1) ? first_out : 16'sd0);
    assign pcm_out_valid=first_valid && second_valid;
endmodule
