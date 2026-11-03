// 和声专用副本：内部混音器在模式 3 提供固定延迟对齐的原声。
// 单时钟、单写单读同步块 RAM 调度器，采用 Q20 小数读取。
// 两路读取延迟相差半个音粒，采用互补平滑阶跃窗。
// 仅在空闲时接收新输入；输入间隔须不少于 32 个时钟周期。
// 每次接收输入后，在第 17 个时钟周期产生一次有效输出，包括启动阶段的零值。
// 忙碌期间若收到违反接口约定的输入，锁存静音故障直至复位；不提供反压。
// 参数约束：GRAIN_LOG2>=6；RAM_ADDR_BITS>GRAIN_LOG2；GUARD>=2；
// GUARD+(1<<GRAIN_LOG2)+2 < (1<<RAM_ADDR_BITS)。不复位 RAM 内容。
module pcm_harmony_read_pitch #(
    parameter integer RAM_ADDR_BITS=14,GRAIN_LOG2=13,GUARD_SAMPLES=32,
    // 启用动态配置时，下一个被接收的样本锁存新参数。
    // 修改参数时，历史数据与读取相位保持连续。
    parameter integer DYNAMIC_CONFIG=0
) (
    input wire clk,rst_n,
    input wire signed [15:0] pcm_in,
    input wire in_valid,
    input wire [1:0] mode,
    input wire signed [4:0] pitch_semitones,
    output wire signed [15:0] pcm_out,
    output wire out_valid
);
    localparam integer FRAC_BITS=20;
    localparam integer PHASE_BITS=GRAIN_LOG2+FRAC_BITS;
    localparam integer POSITION_BITS=RAM_ADDR_BITS+FRAC_BITS;
    localparam integer GRAIN=1<<GRAIN_LOG2;
    localparam integer FILL_SAMPLES=GUARD_SAMPLES+GRAIN+2;
    localparam integer DRY_DELAY=GUARD_SAMPLES+GRAIN/2;
    localparam [PHASE_BITS:0] GRAIN_Q20={1'b1,{PHASE_BITS{1'b0}}};
    localparam [POSITION_BITS-1:0] GUARD_Q20=GUARD_SAMPLES;
    reg [4:0] state;
    reg fault,configured;
    reg [1:0] configured_mode;
    reg signed [4:0] configured_pitch;
    reg [RAM_ADDR_BITS-1:0] write_address,read_address;
    reg [RAM_ADDR_BITS:0] fill_count;
    reg [15:0] startup_gain;
    reg [PHASE_BITS-1:0] delay_phase;
    reg read_enable;
    (* syn_ramstyle="block_ram" *) reg signed [15:0] history[0:(1<<RAM_ADDR_BITS)-1];
    reg signed [15:0] ram_q;
    wire accept=rst_n && in_valid && (state==0);
    always @(posedge clk) begin
        if(accept) history[write_address]<=pcm_in;
        if(read_enable) ram_q<=history[read_address];
    end
    function signed [4:0] clamp_pitch;
        input signed [4:0] pitch;
        begin
            if(pitch>5'sd12) clamp_pitch=5'sd12;
            else if(pitch < -5'sd12) clamp_pitch=-5'sd12;
            else clamp_pitch=pitch;
        end
    endfunction
    function [21:0] ratio_q20;
        input signed [4:0] pitch;
        begin
            case(pitch)
                // 通过 round(2**(pitch/12)*2**20) 生成。
                -5'sd12:ratio_q20=524288; -5'sd11:ratio_q20=555464;
                -5'sd10:ratio_q20=588493; -5'sd9:ratio_q20=623487;
                -5'sd8:ratio_q20=660561; -5'sd7:ratio_q20=699841;
                -5'sd6:ratio_q20=741455; -5'sd5:ratio_q20=785544;
                -5'sd4:ratio_q20=832255; -5'sd3:ratio_q20=881744;
                -5'sd2:ratio_q20=934175; -5'sd1:ratio_q20=989724;
                5'sd0:ratio_q20=1048576; 5'sd1:ratio_q20=1110928;
                5'sd2:ratio_q20=1176987; 5'sd3:ratio_q20=1246974;
                5'sd4:ratio_q20=1321123; 5'sd5:ratio_q20=1399681;
                5'sd6:ratio_q20=1482910; 5'sd7:ratio_q20=1571089;
                5'sd8:ratio_q20=1664511; 5'sd9:ratio_q20=1763488;
                5'sd10:ratio_q20=1868350; 5'sd11:ratio_q20=1979448;
                5'sd12:ratio_q20=2097152;
                default:ratio_q20=1048576;
            endcase
        end
    endfunction
    wire [1:0] selected_mode=(DYNAMIC_CONFIG!=0) ? mode : (configured ? configured_mode : mode);
    wire signed [4:0] selected_pitch=(DYNAMIC_CONFIG!=0) ? clamp_pitch(pitch_semitones) :
        (configured ? configured_pitch : clamp_pitch(pitch_semitones));
    wire signed [22:0] delay_step=23'sd1048576-$signed({1'b0,ratio_q20(selected_pitch)});
    wire [PHASE_BITS-1:0] increment={{(PHASE_BITS-23){delay_step[22]}},delay_step};
    wire [PHASE_BITS-1:0] other_phase=delay_phase^{1'b1,{(PHASE_BITS-1){1'b0}}};
    wire [POSITION_BITS-1:0] position_a={write_address,20'd0}-(GUARD_Q20<<20)-
        {{(RAM_ADDR_BITS-GRAIN_LOG2){1'b0}},delay_phase};
    wire [POSITION_BITS-1:0] position_b={write_address,20'd0}-(GUARD_Q20<<20)-
        {{(RAM_ADDR_BITS-GRAIN_LOG2){1'b0}},other_phase};
    wire [PHASE_BITS:0] mirrored=GRAIN_Q20-{1'b0,delay_phase};
    wire [PHASE_BITS:0] folded=delay_phase[PHASE_BITS-1] ? mirrored : {1'b0,delay_phase};
    wire [15:0] triangle=folded[PHASE_BITS-1:PHASE_BITS-16];
    wire filled=(fill_count>=FILL_SAMPLES);
    wire [15:0] next_gain=filled ? ((startup_gain<32768) ? startup_gain+16'd256 : 16'd32768) : 16'd0;
    reg job_filled;
    reg [1:0] job_mode;
    reg [15:0] job_gain,job_triangle;
    reg [RAM_ADDR_BITS-1:0] address_a,address_b,address_dry;
    reg [19:0] fraction_a,fraction_b;
    reg signed [15:0] a0,a1,b0,b1,aligned_dry,direct_dry;
    reg signed [16:0] difference_a,difference_b;
    reg signed [37:0] fraction_product_a,fraction_product_b;
    reg signed [15:0] interpolated_a,interpolated_b;
    function signed [15:0] interp;
        input signed [15:0] low;
        input signed [37:0] fractional;
        reg signed [38:0] value,rounded;
        begin
            value=($signed({{23{low[15]}},low})<<<20)+$signed({fractional[37],fractional});
            if(value<0) rounded=-(((-value)+39'sd524288)>>>20);
            else rounded=(value+39'sd524288)>>>20;
            if(rounded>32767) interp=16'sh7fff;
            else if(rounded < -32768) interp=16'sh8000;
            else interp=rounded[15:0];
        end
    endfunction
    reg fade_valid;
    wire signed [15:0] wet,mixer_pcm;
    wire wet_valid,mixer_valid;
    pcm_crossfade fade (
        .clk(clk),.rst_n(rst_n),.in_valid(fade_valid),
        .head_a(interpolated_a),.head_b(interpolated_b),
        .triangle_q15(job_triangle),.pcm_out(wet),.out_valid(wet_valid)
    );
    pcm_harmony_voice_mixer mixer (
        .clk(clk),.rst_n(rst_n),.in_valid(wet_valid),.mode(job_mode),
        .direct_dry(direct_dry),.aligned_dry(aligned_dry),.wet(wet),
        .wet_gain_q15(job_gain),.pcm_out(mixer_pcm),.out_valid(mixer_valid)
    );
    assign pcm_out = fault ? 16'sd0 : mixer_pcm;
    assign out_valid=mixer_valid;
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=0;fault<=0;configured<=0;configured_mode<=0;configured_pitch<=0;
            write_address<=0;read_address<=0;fill_count<=0;startup_gain<=0;delay_phase<=0;
            read_enable<=0;job_filled<=0;job_mode<=0;job_gain<=0;job_triangle<=0;
            address_a<=0;address_b<=0;address_dry<=0;fraction_a<=0;fraction_b<=0;
            a0<=0;a1<=0;b0<=0;b1<=0;aligned_dry<=0;direct_dry<=0;
            difference_a<=0;difference_b<=0;fraction_product_a<=0;fraction_product_b<=0;
            interpolated_a<=0;interpolated_b<=0;fade_valid<=0;
        end else begin
            fade_valid<=0;
            if(in_valid && state!=0) fault<=1;
            case(state)
                0: if(in_valid) begin
                    configured<=1;configured_mode<=selected_mode;configured_pitch<=selected_pitch;
                    write_address<=write_address+1'b1;
                    if(!filled) fill_count<=fill_count+1'b1;
                    startup_gain<=next_gain;
                    delay_phase<=delay_phase+increment;
                    job_filled<=filled;job_mode<=selected_mode;job_gain<=next_gain;
                    job_triangle<=triangle;direct_dry<=pcm_in;
                    address_a<=position_a[POSITION_BITS-1:20];
                    address_b<=position_b[POSITION_BITS-1:20];
                    address_dry<=write_address-DRY_DELAY;
                    fraction_a<=position_a[19:0];fraction_b<=position_b[19:0];
                    read_address<=position_a[POSITION_BITS-1:20];
                    read_enable<=filled;state<=1;
                end
                1:begin read_address<=address_a+1'b1;state<=2;end
                2:begin a0<=job_filled?ram_q:16'sd0;read_address<=address_b;state<=3;end
                3:begin a1<=job_filled?ram_q:16'sd0;read_address<=address_b+1'b1;state<=4;end
                4:begin b0<=job_filled?ram_q:16'sd0;read_address<=address_dry;state<=5;end
                5:begin b1<=job_filled?ram_q:16'sd0;read_enable<=0;state<=6;end
                6:begin
                    aligned_dry<=job_filled?ram_q:16'sd0;
                    difference_a<=$signed({a1[15],a1})-$signed({a0[15],a0});
                    difference_b<=$signed({b1[15],b1})-$signed({b0[15],b0});state<=7;
                end
                7:begin
                    fraction_product_a<=difference_a*$signed({1'b0,fraction_a});
                    fraction_product_b<=difference_b*$signed({1'b0,fraction_b});state<=8;
                end
                8:begin interpolated_a<=interp(a0,fraction_product_a);interpolated_b<=interp(b0,fraction_product_b);state<=9;end
                9:begin fade_valid<=1;state<=10;end
                10:if(mixer_valid) state<=0;
                default:begin fault<=1;state<=0;read_enable<=0;end
            endcase
        end
    end
endmodule
