// Complementary smoothstep Crossfade. All ports synchronous to clk.
// triangle_q15: unsigned 0..32768. Weight w=t*t*(3-2*t), 1-w.
// No equal-power boost: identical inputs remain bit-exact, including rails.
// One input per clock is supported. Output latency is 4 clock edges.
module pcm_crossfade (
    input wire clk, rst_n, in_valid,
    input wire signed [15:0] head_a, head_b,
    input wire [15:0] triangle_q15,
    output reg signed [15:0] pcm_out,
    output reg out_valid
);
    reg [3:0] valid_pipe;
    reg signed [15:0] a0,b0,a1,b1,a2,b2;
    reg [15:0] t0,t1;
    reg [31:0] square;
    reg [33:0] curve_product;
    reg signed [32:0] product_a,product_b;
    wire [16:0] curve_factor = 17'd98304 - {t1,1'b0};
    wire [15:0] square_q15 = square[30:15];
    wire [15:0] weight = curve_product[30:15];
    wire signed [33:0] total = $signed({product_a[32],product_a}) +
                                      $signed({product_b[32],product_b});
    function signed [15:0] round_q15;
        input signed [33:0] value;
        reg signed [33:0] result;
        begin
            if(value < 0) result = -(((-value)+34'sd16384) >>> 15);
            else result = (value+34'sd16384) >>> 15;
            if(result > 32767) round_q15=16'sh7fff;
            else if(result < -32768) round_q15=16'sh8000;
            else round_q15=result[15:0];
        end
    endfunction
    always @(posedge clk) begin
        if(!rst_n) begin
            valid_pipe<=0; out_valid<=0; pcm_out<=0;
            a0<=0;b0<=0;a1<=0;b1<=0;a2<=0;b2<=0;t0<=0;t1<=0;
            square<=0;curve_product<=0;product_a<=0;product_b<=0;
        end else begin
            valid_pipe <= {valid_pipe[2:0],in_valid};
            out_valid <= valid_pipe[3];
            if(in_valid) begin
                a0<=head_a; b0<=head_b;
                t0 <= (triangle_q15 > 16'd32768) ? 16'd32768 : triangle_q15;
            end
            if(valid_pipe[0]) begin
                square<=t0*t0; t1<=t0; a1<=a0; b1<=b0;
            end
            if(valid_pipe[1]) begin
                curve_product <= square_q15 * curve_factor;
                a2<=a1; b2<=b1;
            end
            if(valid_pipe[2]) begin
                product_a <= a2 * $signed({1'b0,weight});
                product_b <= b2 * $signed(17'd32768-$signed({1'b0,weight}));
            end
            if(valid_pipe[3]) pcm_out <= round_q15(total);
        end
    end
endmodule
