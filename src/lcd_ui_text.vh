// 由 tools/generate_lcd_cjk24.py 生成；请勿手工编辑。
// 每个字符编码：位 8 表示汉字右半部分，位 7:0 为字形编号。
localparam integer LCD_TEXT_CELLS=37;
localparam [7:0] G_U0020=8'd0;
localparam [7:0] G_U0030=8'd1;
localparam [7:0] G_U0031=8'd2;
localparam [7:0] G_U0032=8'd3;
localparam [7:0] G_U0033=8'd4;
localparam [7:0] G_U0034=8'd5;
localparam [7:0] G_U0035=8'd6;
localparam [7:0] G_U0036=8'd7;
localparam [7:0] G_U0037=8'd8;
localparam [7:0] G_U0038=8'd9;
localparam [7:0] G_U0039=8'd10;
localparam [7:0] G_U002B=8'd11;
localparam [7:0] G_U002D=8'd12;
localparam [7:0] G_U002E=8'd13;
localparam [7:0] G_U003F=8'd14;
localparam [7:0] G_U002F=8'd15;
localparam [7:0] G_U003A=8'd16;
localparam [7:0] G_U0041=8'd17;
localparam [7:0] G_U0042=8'd18;
localparam [7:0] G_U0043=8'd19;
localparam [7:0] G_U0044=8'd20;
localparam [7:0] G_U0045=8'd21;
localparam [7:0] G_U0046=8'd22;
localparam [7:0] G_U003E=8'd119;
// TITLE: 音频特效 (8 个半字格)
localparam integer N_TITLE=8;
localparam [332:0] T_TITLE={9'd23,9'd279,9'd24,9'd280,9'd25,9'd281,9'd26,9'd282,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// LIVE: 实时 (4 个半字格)
localparam integer N_LIVE=4;
localparam [332:0] T_LIVE={9'd27,9'd283,9'd28,9'd284,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// CLIP: 录放 (4 个半字格)
localparam integer N_CLIP=4;
localparam [332:0] T_CLIP={9'd29,9'd285,9'd30,9'd286,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// MUTED: 静音 (4 个半字格)
localparam integer N_MUTED=4;
localparam [332:0] T_MUTED={9'd31,9'd287,9'd23,9'd279,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// MIC: 麦克风 (6 个半字格)
localparam integer N_MIC=6;
localparam [332:0] T_MIC={9'd32,9'd288,9'd33,9'd289,9'd34,9'd290,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// TONE: 测试音 (6 个半字格)
localparam integer N_TONE=6;
localparam [332:0] T_TONE={9'd35,9'd291,9'd36,9'd292,9'd23,9'd279,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// UNKNOWN: 未知 (4 个半字格)
localparam integer N_UNKNOWN=4;
localparam [332:0] T_UNKNOWN={9'd37,9'd293,9'd38,9'd294,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// EFFECT: 音效 (4 个半字格)
localparam integer N_EFFECT=4;
localparam [332:0] T_EFFECT={9'd23,9'd279,9'd26,9'd282,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// ORIGINAL: 原声 (4 个半字格)
localparam integer N_ORIGINAL=4;
localparam [332:0] T_ORIGINAL={9'd39,9'd295,9'd40,9'd296,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// PITCH: 变调 (4 个半字格)
localparam integer N_PITCH=4;
localparam [332:0] T_PITCH={9'd41,9'd297,9'd42,9'd298,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// HARMONY: 和声 (4 个半字格)
localparam integer N_HARMONY=4;
localparam [332:0] T_HARMONY={9'd43,9'd299,9'd40,9'd296,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// SEMITONE: 半音 (4 个半字格)
localparam integer N_SEMITONE=4;
localparam [332:0] T_SEMITONE={9'd44,9'd300,9'd23,9'd279,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// GAIN: 增益 (4 个半字格)
localparam integer N_GAIN=4;
localparam [332:0] T_GAIN={9'd45,9'd301,9'd46,9'd302,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// TIMES: 倍 (2 个半字格)
localparam integer N_TIMES=2;
localparam [332:0] T_TIMES={9'd47,9'd303,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// STATUS: 状态 (4 个半字格)
localparam integer N_STATUS=4;
localparam [332:0] T_STATUS={9'd48,9'd304,9'd49,9'd305,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// LIVE_IDLE: 实时待命 (8 个半字格)
localparam integer N_LIVE_IDLE=8;
localparam [332:0] T_LIVE_IDLE={9'd27,9'd283,9'd28,9'd284,9'd50,9'd306,9'd51,9'd307,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// LIVE_RUNNING: 实时运行 (8 个半字格)
localparam integer N_LIVE_RUNNING=8;
localparam [332:0] T_LIVE_RUNNING={9'd27,9'd283,9'd28,9'd284,9'd52,9'd308,9'd53,9'd309,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// DDR_STANDBY: 内存待机 (8 个半字格)
localparam integer N_DDR_STANDBY=8;
localparam [332:0] T_DDR_STANDBY={9'd54,9'd310,9'd55,9'd311,9'd50,9'd306,9'd56,9'd312,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// DDR_READY: 内存就绪 (8 个半字格)
localparam integer N_DDR_READY=8;
localparam [332:0] T_DDR_READY={9'd54,9'd310,9'd55,9'd311,9'd57,9'd313,9'd58,9'd314,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// DDR_INIT: 内存初始化 (10 个半字格)
localparam integer N_DDR_INIT=10;
localparam [332:0] T_DDR_INIT={9'd54,9'd310,9'd55,9'd311,9'd59,9'd315,9'd60,9'd316,9'd61,9'd317,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// EMPTY: 待录 (4 个半字格)
localparam integer N_EMPTY=4;
localparam [332:0] T_EMPTY={9'd50,9'd306,9'd29,9'd285,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// RECORDING: 录音中 (6 个半字格)
localparam integer N_RECORDING=6;
localparam [332:0] T_RECORDING={9'd29,9'd285,9'd23,9'd279,9'd62,9'd318,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// SAVING: 保存中 (6 个半字格)
localparam integer N_SAVING=6;
localparam [332:0] T_SAVING={9'd63,9'd319,9'd55,9'd311,9'd62,9'd318,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// READY: 录音就绪 (8 个半字格)
localparam integer N_READY=8;
localparam [332:0] T_READY={9'd29,9'd285,9'd23,9'd279,9'd57,9'd313,9'd58,9'd314,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// PREPARE: 播放准备 (8 个半字格)
localparam integer N_PREPARE=8;
localparam [332:0] T_PREPARE={9'd64,9'd320,9'd30,9'd286,9'd65,9'd321,9'd66,9'd322,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// WARMUP: 音效预热 (8 个半字格)
localparam integer N_WARMUP=8;
localparam [332:0] T_WARMUP={9'd23,9'd279,9'd26,9'd282,9'd67,9'd323,9'd68,9'd324,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// PLAYING: 播放中 (6 个半字格)
localparam integer N_PLAYING=6;
localparam [332:0] T_PLAYING={9'd64,9'd320,9'd30,9'd286,9'd62,9'd318,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// TAIL: 音效尾音 (8 个半字格)
localparam integer N_TAIL=8;
localparam [332:0] T_TAIL={9'd23,9'd279,9'd26,9'd282,9'd69,9'd325,9'd23,9'd279,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// DRAIN: 输出排空 (8 个半字格)
localparam integer N_DRAIN=8;
localparam [332:0] T_DRAIN={9'd70,9'd326,9'd71,9'd327,9'd72,9'd328,9'd73,9'd329,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// FAULT: 存储故障 (8 个半字格)
localparam integer N_FAULT=8;
localparam [332:0] T_FAULT={9'd55,9'd311,9'd74,9'd330,9'd75,9'd331,9'd76,9'd332,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// RECORD: 录音 (4 个半字格)
localparam integer N_RECORD=4;
localparam [332:0] T_RECORD={9'd29,9'd285,9'd23,9'd279,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// TOTAL: 总长 (4 个半字格)
localparam integer N_TOTAL=4;
localparam [332:0] T_TOTAL={9'd77,9'd333,9'd78,9'd334,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// PLAY: 播放 (4 个半字格)
localparam integer N_PLAY=4;
localparam [332:0] T_PLAY={9'd64,9'd320,9'd30,9'd286,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// SECONDS: 秒 (2 个半字格)
localparam integer N_SECONDS=2;
localparam [332:0] T_SECONDS={9'd79,9'd335,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// FULL: 录满30秒 (8 个半字格)
localparam integer N_FULL=8;
localparam [332:0] T_FULL={9'd29,9'd285,9'd80,9'd336,9'd4,9'd1,9'd79,9'd335,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// ERROR_CODE: 故障码 (6 个半字格)
localparam integer N_ERROR_CODE=6;
localparam [332:0] T_ERROR_CODE={9'd75,9'd331,9'd76,9'd332,9'd81,9'd337,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// RESET: 长按键1复位 (11 个半字格)
localparam integer N_RESET=11;
localparam [332:0] T_RESET={9'd78,9'd334,9'd82,9'd338,9'd83,9'd339,9'd2,9'd84,9'd340,9'd85,9'd341,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_LIVE_A: 键1切模式 键2切音效 (19 个半字格)
localparam integer N_H_LIVE_A=19;
localparam [332:0] T_H_LIVE_A={9'd83,9'd339,9'd2,9'd86,9'd342,9'd87,9'd343,9'd88,9'd344,9'd0,9'd83,9'd339,9'd3,9'd86,9'd342,9'd23,9'd279,9'd26,9'd282,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_LIVE_B: 旋1调增益 旋2调半音 (19 个半字格)
localparam integer N_H_LIVE_B=19;
localparam [332:0] T_H_LIVE_B={9'd89,9'd345,9'd2,9'd42,9'd298,9'd45,9'd301,9'd46,9'd302,9'd0,9'd89,9'd345,9'd3,9'd42,9'd298,9'd44,9'd300,9'd23,9'd279,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_CLIP_A: 键3录音 键4播放 (15 个半字格)
localparam integer N_H_CLIP_A=15;
localparam [332:0] T_H_CLIP_A={9'd83,9'd339,9'd4,9'd29,9'd285,9'd23,9'd279,9'd0,9'd83,9'd339,9'd5,9'd64,9'd320,9'd30,9'd286,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_RECORD_A: 键3结束录音 (11 个半字格)
localparam integer N_H_RECORD_A=11;
localparam [332:0] T_H_RECORD_A={9'd83,9'd339,9'd4,9'd90,9'd346,9'd91,9'd347,9'd29,9'd285,9'd23,9'd279,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_PLAY_A: 键4暂停 键2切音效 (17 个半字格)
localparam integer N_H_PLAY_A=17;
localparam [332:0] T_H_PLAY_A={9'd83,9'd339,9'd5,9'd92,9'd348,9'd93,9'd349,9'd0,9'd83,9'd339,9'd3,9'd86,9'd342,9'd23,9'd279,9'd26,9'd282,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_CLIP_B: 旋1调增益 旋2调半音 (19 个半字格)
localparam integer N_H_CLIP_B=19;
localparam [332:0] T_H_CLIP_B={9'd89,9'd345,9'd2,9'd42,9'd298,9'd45,9'd301,9'd46,9'd302,9'd0,9'd89,9'd345,9'd3,9'd42,9'd298,9'd44,9'd300,9'd23,9'd279,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_COMMON_A: 旋1按下切声音 (13 个半字格)
localparam integer N_H_COMMON_A=13;
localparam [332:0] T_H_COMMON_A={9'd89,9'd345,9'd2,9'd82,9'd338,9'd94,9'd350,9'd86,9'd342,9'd40,9'd296,9'd23,9'd279,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_COMMON_B: 旋2按下半音归零 (15 个半字格)
localparam integer N_H_COMMON_B=15;
localparam [332:0] T_H_COMMON_B={9'd89,9'd345,9'd3,9'd82,9'd338,9'd94,9'd350,9'd44,9'd300,9'd23,9'd279,9'd95,9'd351,9'd96,9'd352,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_FAULT_A: 存储故障  实时音频仍可使用 (26 个半字格)
localparam integer N_H_FAULT_A=26;
localparam [332:0] T_H_FAULT_A={9'd55,9'd311,9'd74,9'd330,9'd75,9'd331,9'd76,9'd332,9'd0,9'd0,9'd27,9'd283,9'd28,9'd284,9'd23,9'd279,9'd24,9'd280,9'd97,9'd353,9'd98,9'd354,9'd99,9'd355,9'd100,9'd356,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_FAULT_B: 记故障码 长按键1复位 (20 个半字格)
localparam integer N_H_FAULT_B=20;
localparam [332:0] T_H_FAULT_B={9'd101,9'd357,9'd75,9'd331,9'd76,9'd332,9'd81,9'd337,9'd0,9'd78,9'd334,9'd82,9'd338,9'd83,9'd339,9'd2,9'd84,9'd340,9'd85,9'd341,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_WAIT_A: 内存初始化  请稍候 (18 个半字格)
localparam integer N_H_WAIT_A=18;
localparam [332:0] T_H_WAIT_A={9'd54,9'd310,9'd55,9'd311,9'd59,9'd315,9'd60,9'd316,9'd61,9'd317,9'd0,9'd0,9'd102,9'd358,9'd103,9'd359,9'd104,9'd360,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_WAIT_B: 键1回实时 长按2秒复位 (21 个半字格)
localparam integer N_H_WAIT_B=21;
localparam [332:0] T_H_WAIT_B={9'd83,9'd339,9'd2,9'd105,9'd361,9'd27,9'd283,9'd28,9'd284,9'd0,9'd78,9'd334,9'd82,9'd338,9'd3,9'd79,9'd335,9'd84,9'd340,9'd85,9'd341,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_SAVING_A: 正在保存录音  请稍候 (20 个半字格)
localparam integer N_H_SAVING_A=20;
localparam [332:0] T_H_SAVING_A={9'd106,9'd362,9'd107,9'd363,9'd63,9'd319,9'd55,9'd311,9'd29,9'd285,9'd23,9'd279,9'd0,9'd0,9'd102,9'd358,9'd103,9'd359,9'd104,9'd360,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_SAVING_B: 保存完成后按键4播放 (19 个半字格)
localparam integer N_H_SAVING_B=19;
localparam [332:0] T_H_SAVING_B={9'd63,9'd319,9'd55,9'd311,9'd108,9'd364,9'd109,9'd365,9'd110,9'd366,9'd82,9'd338,9'd83,9'd339,9'd5,9'd64,9'd320,9'd30,9'd286,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// PAUSED: 已暂停 (6 个半字格)
localparam integer N_PAUSED=6;
localparam [332:0] T_PAUSED={9'd111,9'd367,9'd92,9'd348,9'd93,9'd349,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_PAUSED_A: 键4继续 长按键4重播 (19 个半字格)
localparam integer N_H_PAUSED_A=19;
localparam [332:0] T_H_PAUSED_A={9'd83,9'd339,9'd5,9'd112,9'd368,9'd113,9'd369,9'd0,9'd78,9'd334,9'd82,9'd338,9'd83,9'd339,9'd5,9'd114,9'd370,9'd64,9'd320,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_CLIP_HELP_A: 旋2按下半音归零 (15 个半字格)
localparam integer N_H_CLIP_HELP_A=15;
localparam [332:0] T_H_CLIP_HELP_A={9'd89,9'd345,9'd3,9'd82,9'd338,9'd94,9'd350,9'd44,9'd300,9'd23,9'd279,9'd95,9'd351,9'd96,9'd352,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_CLIP_HELP_B: 长按键4从头播放 (15 个半字格)
localparam integer N_H_CLIP_HELP_B=15;
localparam [332:0] T_H_CLIP_HELP_B={9'd78,9'd334,9'd82,9'd338,9'd83,9'd339,9'd5,9'd115,9'd371,9'd116,9'd372,9'd64,9'd320,9'd30,9'd286,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_MAINT_A: 键1切模式 长按2秒复位 (21 个半字格)
localparam integer N_H_MAINT_A=21;
localparam [332:0] T_H_MAINT_A={9'd83,9'd339,9'd2,9'd86,9'd342,9'd87,9'd343,9'd88,9'd344,9'd0,9'd78,9'd334,9'd82,9'd338,9'd3,9'd79,9'd335,9'd84,9'd340,9'd85,9'd341,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_MAINT_B: 键2切音效 键3录音/结束 (22 个半字格)
localparam integer N_H_MAINT_B=22;
localparam [332:0] T_H_MAINT_B={9'd83,9'd339,9'd3,9'd86,9'd342,9'd23,9'd279,9'd26,9'd282,9'd0,9'd83,9'd339,9'd4,9'd29,9'd285,9'd23,9'd279,9'd15,9'd90,9'd346,9'd91,9'd347,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// H_MAINT_LIVE_B: 键2切音效 旋2按下归零 (21 个半字格)
localparam integer N_H_MAINT_LIVE_B=21;
localparam [332:0] T_H_MAINT_LIVE_B={9'd83,9'd339,9'd3,9'd86,9'd342,9'd23,9'd279,9'd26,9'd282,9'd0,9'd89,9'd345,9'd3,9'd82,9'd338,9'd94,9'd350,9'd95,9'd351,9'd96,9'd352,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// DUAL: 双变调 (6 个半字格)
localparam integer N_DUAL=6;
localparam [332:0] T_DUAL={9'd117,9'd373,9'd41,9'd297,9'd42,9'd298,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
// VOICE_EDIT: 声部>短按选择 (13 个半字格)
localparam integer N_VOICE_EDIT=13;
localparam [332:0] T_VOICE_EDIT={9'd40,9'd296,9'd118,9'd374,9'd119,9'd120,9'd376,9'd82,9'd338,9'd121,9'd377,9'd122,9'd378,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0,9'd0};
