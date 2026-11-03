// guide.v —— LED 歌曲指引（KEY1/KEY2 控制）

module guide #(
    // 0.5 s @ 50 MHz = 25,000,000
    parameter [24:0] WRONG_MAX = 25'd25000000,
    // 1.0 s @ 50 MHz = 50,000,000
    parameter [25:0] MSG_MAX   = 26'd50000000,
    // KEY1 长按 1 s 退出
    parameter [26:0] HOLD_MAX  = 27'd50000000,

    parameter [31:0] BEAT100   = 32'd30000000,
    parameter [31:0] BEAT90    = 32'd33333333,
    parameter [31:0] HIT_EARLY = 32'd7500000,
    parameter [31:0] HIT_LATE  = 32'd6000000,
    parameter [31:0] LEAD_CYC  = 32'd105906176,
    parameter [31:0] GAP_CYC   = 32'd6291456,
    parameter [31:0] LEDGAP    = 32'd2000000,
    parameter integer SHIFT    = 19
)(
    input  wire        clk,
    input  wire [11:0] key_press,     // 12 音符键，单拍脉冲
    input  wire [11:0] key_level,     // 12 音符键，按住电平（长块"保持"判定）
    input  wire        key1_level,    // KEY1 消抖后的电平（长按判定）
    input  wire        key1_release,  // KEY1 松手单拍脉冲（短按动作）
    input  wire        key2_press,    // KEY2：菜单切换/选歌/提示
    output wire        g_mode,
    output wire [2:0]  g_state,
    output wire        g_song,
    output wire        g_adv,         // 0=新手指引 1=进阶节奏
    output wire [3:0]  g_expected,    // 新手=期望键 / 进阶=当前音
    output wire        g_wrong_active,
    output wire [3:0]  g_wrong_key,
    output wire        g_msg_show,
    output wire [5:0]  g_step,
    output wire [3:0]  g_adv_next,    // 进阶：下一个要按的音（保留，屏幕不再显示）
    output wire [275:0] g_tiles,      // 进阶：6 槽下落方块几何（送 display_top）
    output wire [5:0]  g_hits,        // 进阶：已命中个数（状态行显示）
    output wire [3:0]  g_led_note,    // 进阶：当前应亮的 LED（7+1 编码前）
    output wire        g_led_on       // 进阶：当前 LED 是否点亮
);

    localparam [2:0] OFF    = 3'd0,
                     MODE   = 3'd1,
                     SONG   = 3'd2,
                     B_RUN  = 3'd3,
                     B_DONE = 3'd4,
                     A_RUN  = 3'd5,      // 进阶：下落方块游戏进行中
                     A_FAIL = 3'd6;      // 进阶：漏按/松手失败，等任意音符键重开

    reg [2:0]  state       = OFF;
    reg        song        = 1'b0;
    reg        adv         = 1'b0;
    reg [5:0]  idx         = 6'd0;
    reg [3:0]  expected    = 4'd0;
    reg        wrong_active= 1'b0;
    reg [3:0]  wrong_key   = 4'd0;
    reg [24:0] wrong_cnt   = 25'd0;
    reg        msg_show    = 1'b0;
    reg [25:0] msg_cnt     = 26'd0;

    // KEY1 长按
    reg [26:0] hold_cnt    = 27'd0;
    reg        hold_fired  = 1'b0;

    // 进阶：下落方块引擎的输出（时间轴全部在 guide_fall.v 内部）
    wire [3:0]  f_cur_key;
    wire        f_cur_on;
    wire [275:0] f_tiles;
    wire [5:0]  f_hits;
    wire        f_fail;
    wire        f_done;

    wire [7:0] rom_cur, rom_nxt, rom_zero;
    wire [5:0] idx_nxt = idx + 6'd1;

    guide_score_rom u_rom_zero (
        .clk  (clk),
        .addr ({song, 6'd0}),
        .dout (rom_zero)
    );
    guide_score_rom u_rom_cur (
        .clk  (clk),
        .addr ({song, idx}),
        .dout (rom_cur)
    );
    guide_score_rom u_rom_nxt (
        .clk  (clk),
        .addr ({song, idx_nxt}),
        .dout (rom_nxt)
    );

    wire any_key = |key_press;                 // 任意音符键（单拍）

    wire fall_start = (((state == SONG) && adv) || (state == A_FAIL)) && any_key;

    wire fall_abort = (state != A_RUN) && (state != A_FAIL);

    guide_fall #(
        .BEAT100  (BEAT100),
        .BEAT90   (BEAT90),
        .HIT_EARLY(HIT_EARLY),
        .HIT_LATE (HIT_LATE),
        .LEAD_CYC (LEAD_CYC),
        .GAP_CYC  (GAP_CYC),
        .LEDGAP   (LEDGAP),
        .SHIFT    (SHIFT)
    ) u_fall (
        .clk       (clk),
        .start     (fall_start),
        .abort     (fall_abort),
        .song      (song),
        .key_press (key_press),
        .key_level (key_level),
        .hits      (f_hits),
        .ev_fail   (f_fail),
        .ev_done   (f_done),
        .cur_key   (f_cur_key),
        .cur_on    (f_cur_on),
        .tiles     (f_tiles)
    );

    assign g_mode         = (state != OFF);
    assign g_state        = state;
    assign g_song         = song;
    assign g_adv          = adv;
    // 新手：当前期望键；进阶：当前音；SONG：选中曲目的第 0 音（READY 提示）
    assign g_expected     = ((state == A_RUN) || (state == A_FAIL)) ? f_cur_key :
                            (state == SONG)  ? rom_zero[3:0] : expected;
    assign g_wrong_active = wrong_active;
    assign g_wrong_key    = wrong_key;
    assign g_msg_show     = msg_show;
    assign g_step         = idx;
    assign g_adv_next     = rom_nxt[3:0];
    assign g_tiles        = f_tiles;
    assign g_hits         = f_hits;
    assign g_led_note     = f_cur_key;
    assign g_led_on       = (state == A_RUN) ? f_cur_on : 1'b0;

    function [3:0] low_key;
        input [11:0] k;
        begin
            if      (k[0])  low_key = 4'd0;
            else if (k[1])  low_key = 4'd1;
            else if (k[2])  low_key = 4'd2;
            else if (k[3])  low_key = 4'd3;
            else if (k[4])  low_key = 4'd4;
            else if (k[5])  low_key = 4'd5;
            else if (k[6])  low_key = 4'd6;
            else if (k[7])  low_key = 4'd7;
            else if (k[8])  low_key = 4'd8;
            else if (k[9])  low_key = 4'd9;
            else if (k[10]) low_key = 4'd10;
            else            low_key = 4'd11;
        end
    endfunction

    wire hit_expected = (key_press != 12'd0) &&
                        (expected <= 4'd11) && key_press[expected];

    always @(posedge clk) begin

        if (wrong_active) begin
            if (wrong_cnt >= WRONG_MAX - 25'd1) begin
                wrong_active <= 1'b0;
                wrong_cnt    <= 25'd0;
            end else
                wrong_cnt <= wrong_cnt + 25'd1;
        end
        if (msg_show) begin
            if (msg_cnt >= MSG_MAX - 26'd1) begin
                msg_show <= 1'b0;
                msg_cnt  <= 26'd0;
            end else
                msg_cnt <= msg_cnt + 26'd1;
        end

        if (f_fail && (state == A_RUN)) state <= A_FAIL;
        if (f_done && (state == A_RUN)) state <= MODE;

        if (key1_release) begin
            if (!hold_fired) begin
                case (state)
                    OFF: begin
                        state        <= MODE;
                        idx          <= 6'd0;
                        expected     <= 4'd0;
                        wrong_active <= 1'b0;
                        wrong_cnt    <= 25'd0;
                        msg_show     <= 1'b0;
                    end
                    MODE: begin
                        state        <= SONG;
                        expected     <= rom_zero[3:0];
                        wrong_active <= 1'b0;
                        wrong_cnt    <= 25'd0;
                    end
                    SONG:    state <= MODE;   // 返回模式菜单
                    B_DONE:  state <= MODE;   // 返回模式菜单
                    A_FAIL:  state <= MODE;   // 失败界面短按 KEY1：回菜单
                    default: ;                // RUN 中短按 KEY1 不动作
                endcase
            end
            hold_fired <= 1'b0;
        end

        if (key2_press) begin
            case (state)
                OFF:  begin msg_show <= 1'b1; msg_cnt <= 26'd0; end
                MODE: adv  <= ~adv;
                SONG: song <= ~song;
                B_DONE: song <= ~song;
                default: ;   // RUN：忽略
            endcase
        end

        if (any_key) begin
            case (state)
                SONG: begin
                    if (adv) begin
                        // 进阶：任意音符键启动下落方块（fall_start 同拍给引擎复位）
                        state        <= A_RUN;
                        idx          <= 6'd0;
                        wrong_active <= 1'b0;
                        wrong_cnt    <= 25'd0;
                    end else begin
                        // 新手：启动键不计入，第 0 音为期望
                        state        <= B_RUN;
                        idx          <= 6'd0;
                        expected     <= rom_zero[3:0];
                        wrong_active <= 1'b0;
                        wrong_cnt    <= 25'd0;
                    end
                end
                B_RUN: begin
                    if (hit_expected) begin
                        wrong_active <= 1'b0;
                        wrong_cnt    <= 25'd0;
                        if (rom_nxt[3:0] == 4'hF) begin
                            state    <= B_DONE;
                            expected <= 4'd0;
                        end else begin
                            idx      <= idx_nxt;
                            expected <= rom_nxt[3:0];
                        end
                    end else begin
                        wrong_key    <= low_key(key_press);
                        wrong_active <= 1'b1;
                        wrong_cnt    <= 25'd0;
                    end
                end
                B_DONE: begin
                    // 重开当前曲（新手）
                    state        <= B_RUN;
                    idx          <= 6'd0;
                    expected     <= rom_zero[3:0];
                    wrong_active <= 1'b0;
                    wrong_cnt    <= 25'd0;
                end
                A_FAIL: begin
                    // 失败后按任意音符键：从第 0 音重开（fall_start 同拍复位引擎）
                    state        <= A_RUN;
                    wrong_active <= 1'b0;
                    wrong_cnt    <= 25'd0;
                end
                default: ;  // OFF/MODE/A_RUN：不干预
            endcase
        end

        if (key1_level) begin
            if (hold_cnt != HOLD_MAX)
                hold_cnt <= hold_cnt + 27'd1;
            if (!hold_fired && (hold_cnt >= HOLD_MAX - 27'd1)) begin
                hold_fired   <= 1'b1;
                state        <= OFF;
                expected     <= 4'd0;
                wrong_active <= 1'b0;
                wrong_cnt    <= 25'd0;
                msg_show     <= 1'b0;
                idx          <= 6'd0;
            end
        end else begin
            hold_cnt <= 27'd0;
        end
    end

endmodule
