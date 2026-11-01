// Candidate 4.3-inch RGB timing; exact panel datasheet remains to be verified.
// Pixel clock is an OUTPUT ONLY. Every internal register uses the 50 MHz clk.
// Data/DE/HS/VS change at its falling edge, 60 ns before the rising sample edge.
module lcd_rgb_timing #(
    parameter integer PIXEL_DIV=6,
    parameter integer H_SYNC=41,H_BACK=2,H_ACTIVE=480,H_FRONT=2,
    parameter integer V_SYNC=10,V_BACK=2,V_ACTIVE=272,V_FRONT=2,
    parameter HS_ACTIVE=1'b0,VS_ACTIVE=1'b0,
    // Leave off until panel LED ratings and Dock current are confirmed.
    parameter integer BACKLIGHT_ENABLE=0,
    parameter integer BACKLIGHT_DELAY=2500000,
    parameter integer TEST_PATTERN=0
)(
    input wire clk,rst_n,test_pattern_en,
    input wire [17:0] pixel_rgb,
    output wire [9:0] x,
    output wire [8:0] y,
    output wire frame_start,
    output reg LCD_CLK,LCD_HSYNC,LCD_VSYNC,LCD_DE,LCD_BL,
    output reg [5:0] LCD_R,LCD_G,LCD_B
);
    localparam integer H_TOTAL=H_SYNC+H_BACK+H_ACTIVE+H_FRONT;
    localparam integer V_TOTAL=V_SYNC+V_BACK+V_ACTIVE+V_FRONT;
    reg [9:0] h_count;
    reg [8:0] v_count;
    reg [3:0] phase;
    reg [31:0] light_count;
    wire visible=(h_count>=H_SYNC+H_BACK && h_count<H_SYNC+H_BACK+H_ACTIVE &&
        v_count>=V_SYNC+V_BACK && v_count<V_SYNC+V_BACK+V_ACTIVE);
    assign x=h_count>=H_SYNC+H_BACK ? h_count-(H_SYNC+H_BACK) : 10'd0;
    assign y=v_count>=V_SYNC+V_BACK ? v_count-(V_SYNC+V_BACK) : 9'd0;
    assign frame_start=(phase==0 && h_count==0 && v_count==0 && rst_n);
    reg [17:0] pattern;
    always @* begin
        // W Y C G M R B K; asymmetric border identifies orientation.
        case(x/60)
        0:pattern=18'h3ffff;1:pattern={6'd63,6'd63,6'd0};
        2:pattern={6'd0,6'd63,6'd63};3:pattern={6'd0,6'd63,6'd0};
        4:pattern={6'd63,6'd0,6'd63};5:pattern={6'd63,6'd0,6'd0};
        6:pattern={6'd0,6'd0,6'd63};default:pattern=0;
        endcase
        if(x<2 || y<2 || x>=478 || y>=270)pattern=18'h3ffff;
        if(x>=8 && x<32 && y>=8 && y<32)pattern={6'd63,6'd0,6'd0};
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            h_count<=0;v_count<=0;phase<=0;light_count<=0;
            LCD_CLK<=0;LCD_HSYNC<=!HS_ACTIVE;LCD_VSYNC<=!VS_ACTIVE;
            LCD_DE<=0;LCD_BL<=0;LCD_R<=0;LCD_G<=0;LCD_B<=0;
        end else begin
            if(light_count<BACKLIGHT_DELAY)light_count<=light_count+1'b1;
            else LCD_BL<=(BACKLIGHT_ENABLE!=0);
            if(phase==PIXEL_DIV-1)phase<=0;else phase<=phase+1'b1;
            if(phase==PIXEL_DIV/2)LCD_CLK<=1;
            if(phase==0)begin
                LCD_CLK<=0;
                LCD_HSYNC<=(h_count<H_SYNC) ? HS_ACTIVE : !HS_ACTIVE;
                LCD_VSYNC<=(v_count<V_SYNC) ? VS_ACTIVE : !VS_ACTIVE;
                LCD_DE<=visible;
                {LCD_R,LCD_G,LCD_B}<=visible ?
                    ((TEST_PATTERN!=0 || test_pattern_en) ? pattern : pixel_rgb) : 18'd0;
                if(h_count==H_TOTAL-1)begin
                    h_count<=0;
                    if(v_count==V_TOTAL-1)v_count<=0;else v_count<=v_count+1'b1;
                end else h_count<=h_count+1'b1;
            end
        end
    end
endmodule
