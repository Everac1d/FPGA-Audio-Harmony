// Sipeed 6+1麦克风阵列：十二颗SK9822 LED，通过已验证的FPC传送时钟与数据。
// 帧格式：32个零起始位，LED_COUNT组{111,global[4:0],B,G,R}，
// 然后为32个一结束位，均高位先发；默认全局亮度为8/31；
// RGB通过level/2限制到127；RGB掩码选择点亮的通道；
// 每帧共同锁存一次level与掩码；亮度缩放、
// 音量输入、刷新时序及串行发送器均保持不变。
// LED时钟为50MHz / (2*50) = 500kHz，默认每20毫秒刷新一次。
module sk9822_ring #(
    parameter integer HALF_PERIOD_CYCLES = 50,
    parameter integer REFRESH_CYCLES = 1000000,
    parameter integer LED_COUNT = 12
) (
    input wire clk,
    input wire rst_n,
    input wire [7:0] level,
    input wire [2:0] color_mask_rgb,
    output reg led_ck,
    output reg led_da
);
    localparam integer HALF_WIDTH = (HALF_PERIOD_CYCLES < 2) ? 1 :
                                    $clog2(HALF_PERIOD_CYCLES);
    localparam integer REFRESH_WIDTH = (REFRESH_CYCLES < 2) ? 1 :
                                       $clog2(REFRESH_CYCLES);
    localparam integer WORD_WIDTH = (LED_COUNT < 1) ? 1 : $clog2(LED_COUNT+2);
    reg [HALF_WIDTH-1:0] half_count;
    reg [REFRESH_WIDTH-1:0] refresh_count;
    reg [WORD_WIDTH-1:0] word_index;
    reg [4:0] bit_index;
    reg [31:0] shift_word;
    reg [31:0] frame_pixel;
    reg busy;
    wire [7:0] intensity = {1'b0,level[7:1]};
    wire [7:0] blue = color_mask_rgb[0] ? intensity : 8'd0;
    wire [7:0] green = color_mask_rgb[1] ? intensity : 8'd0;
    wire [7:0] red = color_mask_rgb[2] ? intensity : 8'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            half_count <= {HALF_WIDTH{1'b0}};
            refresh_count <= {REFRESH_WIDTH{1'b0}};
            word_index <= {WORD_WIDTH{1'b0}};
            bit_index <= 5'd31;
            shift_word <= 32'd0;
            frame_pixel <= 32'd0;
            busy <= 1'b0;
            led_ck <= 1'b0;
            led_da <= 1'b0;
        end else begin
            if (refresh_count == REFRESH_CYCLES-1)
                refresh_count <= {REFRESH_WIDTH{1'b0}};
            else refresh_count <= refresh_count + 1'b1;

            if (!busy) begin
                led_ck <= 1'b0;
                led_da <= 1'b0;
                if (refresh_count == 0) begin
                    frame_pixel <= {8'he8,blue,green,red};
                    shift_word <= 32'd0;
                    word_index <= {WORD_WIDTH{1'b0}};
                    bit_index <= 5'd31;
                    half_count <= {HALF_WIDTH{1'b0}};
                    busy <= 1'b1;
                end
            end else if (half_count == HALF_PERIOD_CYCLES-1) begin
                half_count <= {HALF_WIDTH{1'b0}};
                if (!led_ck) begin
                    // 数据已在前一个时钟下降沿设置。
                    led_ck <= 1'b1;
                end else begin
                    led_ck <= 1'b0;
                    if (bit_index != 0) begin
                        bit_index <= bit_index - 1'b1;
                        shift_word <= {shift_word[30:0],1'b0};
                        led_da <= shift_word[30];
                    end else if (word_index < LED_COUNT) begin
                        word_index <= word_index + 1'b1;
                        bit_index <= 5'd31;
                        shift_word <= frame_pixel;
                        led_da <= frame_pixel[31];
                    end else if (word_index == LED_COUNT) begin
                        word_index <= word_index + 1'b1;
                        bit_index <= 5'd31;
                        shift_word <= 32'hffffffff;
                        led_da <= 1'b1;
                    end else begin
                        busy <= 1'b0;
                        led_da <= 1'b0;
                    end
                end
            end else half_count <= half_count + 1'b1;
        end
    end
endmodule
