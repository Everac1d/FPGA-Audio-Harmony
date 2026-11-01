// Sipeed 6+1 Mic Array: twelve SK9822 LEDs, clock/data on the verified FPC.
// Frame: 32 zero start bits, LED_COUNT x {111,global[4:0],B,G,R},
// then 32 one end bits, all MSB first. Default global brightness is 8/31;
// RGB is capped at 127 by level/2. The RGB mask selects the lit channels;
// level and mask are latched together once per frame. Brightness scaling,
// sound-level input, refresh timing and the serializer are unchanged.
// 50 MHz / (2*50) = 500 kHz LED clock, refreshed every 20 ms by default.
module sk9822_ring_softlow #(
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
    // Dim quiet levels to half the original minimum; recover original global 8 at level64.
    // Global brightness is captured with all RGB channels atomically per frame.
    wire [4:0] global_brightness = (level < 8'd64) ? (5'd4 + {3'd0,level[5:4]}) : 5'd8;
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
                    frame_pixel <= {3'b111,global_brightness,blue,green,red};
                    shift_word <= 32'd0;
                    word_index <= {WORD_WIDTH{1'b0}};
                    bit_index <= 5'd31;
                    half_count <= {HALF_WIDTH{1'b0}};
                    busy <= 1'b1;
                end
            end else if (half_count == HALF_PERIOD_CYCLES-1) begin
                half_count <= {HALF_WIDTH{1'b0}};
                if (!led_ck) begin
                    // Data was set at the preceding falling clock edge.
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
