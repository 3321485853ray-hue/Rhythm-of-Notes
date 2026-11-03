// top.v — 12 键机械按键 + 八度 + 音色 + 8 Voice 复音（每声部 32 路加法合成）

module top (
    input        sys_clk,
    input        key_oct,     // AA13（KEY0，原"复位"键）：八度单键循环
    input        key1,        // AB13（板载 KEY1）
    input        key2,        // Y12 （板载 KEY2）
    input  [11:0] Key_note,
    input        ec11_a,      // EC11 A 相（A13）——音量编码器（第 5 只，保持不变）
    input        ec11_b,      // EC11 B 相（C13）
    input        ec11_sw,     // EC11 按键（C14，低有效）——短按切音色
    input        dly_a, input dly_b, input dly_sw,   // C19 / D19 / C20  延迟
    input        rev_a, input rev_b, input rev_sw,   // F19 / E17 / F14  混响
    input        cho_a, input cho_b, input cho_sw,   // D16 / D15 / A19  合唱
    input        exp_a, input exp_b, input exp_sw,   // C17 / B18 / A21  表情（三选一）
    input        ble_rx,      // A14（SDRAM0_DQ6）← 模块 TXD
    output       ble_tx,      // B13（SDRAM0_DQ4）→ 模块 RXD
    output [7:0] LEDs,        // [0]=音色闪速(兼心跳) [3:1]=八度 [5:4]=表情维度 [7:6]=参数档位
    output       HP_BCK,      // Y17  → PT8211 BCK
    output       HP_WS,       // AB17 → PT8211 LRCK
    output       HP_DIN,      // AA16 → PT8211 DIN
    output       PA_EN,       // AB16 → NS4263 PA_EN#（低有效）
    // HDMI（D1 彩条验证；引脚见 top.cst / 官方 hdmi.cst）
    output       tmds_clk_p_0,
    output       tmds_clk_n_0,
    output [2:0] tmds_d_p_0,
    output [2:0] tmds_d_n_0
);

wire sample_strobe;

wire [83:0] km_notes;
wire [11:0] km_valid;

wire [2:0] timbre;
wire [1:0] fx_sel;

wire fx_any = |fx_sel;

wire [2:0] fx_on;             // {cho,rev,dly}
wire [1:0] dly_gear, rev_gear, cho_gear;

wire btn_short, btn_long;

btn_shortlong u_btn_sl (
    .clk           (sys_clk),
    .rst_n         (1'b1),
    .sample_strobe (sample_strobe),
    .key_in        (ec11_sw),      // EC11 按钮（低有效）
    .short_press   (btn_short),    // 松开且没到 0.5s ⇒ 切音色
    .long_press    (btn_long)      // 按住到 0.5s     ⇒ 切效果器
);

timbre_ctrl u_timbre_ctrl (
    .clk         (sys_clk),
    .rst_n       (1'b1),
    .short_press (btn_short),
    .timbre      (timbre)
);

reg [26:0] led_cnt;
always @(posedge sys_clk) begin
    led_cnt <= led_cnt + 1'b1;
end

reg led_bit;

always @(*) begin
    case (timbre)
        3'd1:    led_bit = led_cnt[25];   // 钢琴：慢闪 ~1.5Hz
        3'd2:    led_bit = led_cnt[23];   // 管风琴：快闪 ~6Hz
        3'd4:    led_bit = led_cnt[26];   // 弦乐：最慢 ~0.75Hz
        default: led_bit = led_cnt[24];   // 长笛(3)/正弦(0)：中闪 ~3Hz
    endcase
end

wire [11:0] key_level, key_press, key_release;

key_scan u_key_scan (
    .clk         (sys_clk),
    .rst_n       (1'b1),
    .key_in      (Key_note),
    .key_level   (key_level),
    .key_press   (key_press),
    .key_release (key_release)
);

wire key1_level, key1_release, key2_press;
key_debounce u_key1 (
    .clk         (sys_clk),
    .rst_n       (1'b1),
    .key_in      (key1),
    .key_level   (key1_level),
    .key_press   (),
    .key_release (key1_release)
);
key_debounce u_key2 (
    .clk         (sys_clk),
    .rst_n       (1'b1),
    .key_in      (key2),
    .key_level   (),
    .key_press   (key2_press),
    .key_release ()
);

wire [2:0] octave;

octave_ctrl u_octave_ctrl (
    .clk      (sys_clk),
    .rst_n    (1'b1),
    .key_next (key_oct),
    .octave   (octave)
);

wire [1:0] expr_sel;      // 0=关 1=滑音 2=颤音 3=震音
wire [1:0] expr_amt;      // 表情档位 0~3

wire dly_up, dly_dn, rev_up, rev_dn, cho_up, cho_dn, exp_up, exp_dn;
wire dly_swp, rev_swp, cho_swp, exp_swp;

enc_gear u_enc_dly (.clk(sys_clk), .rst_n(1'b1), .a(dly_a), .b(dly_b), .sw(dly_sw),
                    .step_up(dly_up), .step_down(dly_dn), .sw_press(dly_swp));
enc_gear u_enc_rev (.clk(sys_clk), .rst_n(1'b1), .a(rev_a), .b(rev_b), .sw(rev_sw),
                    .step_up(rev_up), .step_down(rev_dn), .sw_press(rev_swp));
enc_gear u_enc_cho (.clk(sys_clk), .rst_n(1'b1), .a(cho_a), .b(cho_b), .sw(cho_sw),
                    .step_up(cho_up), .step_down(cho_dn), .sw_press(cho_swp));
enc_gear u_enc_exp (.clk(sys_clk), .rst_n(1'b1), .a(exp_a), .b(exp_b), .sw(exp_sw),
                    .step_up(exp_up), .step_down(exp_dn), .sw_press(exp_swp));

expr_ctrl u_expr_ctrl (
    .clk       (sys_clk),
    .rst_n     (1'b1),
    .step_up   (exp_up),
    .step_down (exp_dn),
    .sw_press  (exp_swp),
    .expr_sel  (expr_sel),
    .expr_amt  (expr_amt)
);

// 滑音"推进节拍"：全局算一次，8 个声部共用（见 glide_tick_gen.v：
// 只取决于全局档位，各声部算一份会白费资源、还会多出高扇出网）
wire glide_tick;

glide_tick_gen u_glide_tick (
    .clk           (sys_clk),
    .rst_n         (1'b1),
    .sample_strobe (sample_strobe),
    .expr_amt      (expr_amt),
    .glide_tick    (glide_tick)
);

// 颤音：全局一个 LFO（所有声部共用同一相位，像真实乐器的统一揉弦）
wire signed [15:0] vib_q15;

vibrato u_vibrato (
    .clk           (sys_clk),
    .rst_n         (1'b1),
    .sample_strobe (sample_strobe),
    .expr_sel      (expr_sel),
    .expr_amt      (expr_amt),
    .vib_q15       (vib_q15)
);

// 震音：全局一个 LFO，作用在混音之后（1 个乘法器就够）
wire signed [16:0] trem_q15;

tremolo u_tremolo (
    .clk           (sys_clk),
    .rst_n         (1'b1),
    .sample_strobe (sample_strobe),
    .expr_sel      (expr_sel),
    .expr_amt      (expr_amt),
    .trem_q15      (trem_q15)
);

wire        cw, ccw;
wire [15:0] volume;

rotary_encoder u_rotary (
    .clk  (sys_clk),
    .rst_n(1'b1),
    .a    (ec11_a),
    .b    (ec11_b),
    .cw   (cw),
    .ccw  (ccw)
);

volume_ctrl u_volume (
    .clk   (sys_clk),
    .rst_n (1'b1),
    .cw    (cw),
    .ccw   (ccw),
    .volume(volume)
);

wire [7:0]  v_gate;
wire [7:0]  v_trig;
wire [31:0] v_keys;      // 扁平 8×4：[3:0]=voice0 的键 … [31:28]=voice7 的键
wire [7:0]  v_idle;      // 各声部包络已归零

wire glide_mode = (expr_sel == 2'd1);

wire [11:0] key_level_v   = key_level   & km_valid;
wire [11:0] key_press_v   = key_press   & km_valid;
wire [11:0] key_release_v = key_release | ~km_valid;

voice_manager u_voice_manager (
    .clk           (sys_clk),
    .sample_strobe (sample_strobe),
    .key_level     (key_level_v),
    .key_press     (key_press_v),
    .key_release   (key_release_v),
    .v_idle        (v_idle),
    .glide_mode    (glide_mode),
    .v_gate        (v_gate),
    .v_trig        (v_trig),
    .v_keys        (v_keys)
);

wire       g_mode;
wire [2:0] g_state;
wire       g_song;
wire       g_adv;
wire [3:0] g_expected;
wire       g_wrong_active;
wire [3:0] g_wrong_key;
wire       g_msg_show;
wire [5:0] g_step;
wire [3:0] g_adv_next;
wire [275:0] g_tiles;
wire [5:0] g_hits;
wire [3:0] g_led_note;
wire       g_led_on;

guide u_guide (
    .clk          (sys_clk),
    .key_press    (key_press),
    .key_level    (key_level),
    .key1_level   (key1_level),
    .key1_release (key1_release),
    .key2_press   (key2_press),
    .g_mode       (g_mode),
    .g_state      (g_state),
    .g_song       (g_song),
    .g_adv        (g_adv),
    .g_expected   (g_expected),
    .g_wrong_active(g_wrong_active),
    .g_wrong_key  (g_wrong_key),
    .g_msg_show   (g_msg_show),
    .g_step       (g_step),
    .g_adv_next   (g_adv_next),
    .g_tiles      (g_tiles),
    .g_hits       (g_hits),
    .g_led_note   (g_led_note),
    .g_led_on     (g_led_on)
);

wire [7:0]   ble_byte;
wire         ble_byte_v;
wire [127:0] ble_frame;
wire         ble_frame_v;
wire         ble_crc_err;

uart_rx u_ble_rx (
    .clk        (sys_clk),
    .rx         (ble_rx),
    .dout       (ble_byte),
    .dout_valid (ble_byte_v)
);

frame_parser u_ble_parser (
    .clk         (sys_clk),
    .din         (ble_byte),
    .din_valid   (ble_byte_v),
    .frame_valid (ble_frame_v),
    .frame       (ble_frame),
    .err_crc     (ble_crc_err)
);

// 曲谱下载 / 播放 / 键位表 / 录音的接口
wire        er_we;
wire [12:0] er_waddr;
wire [63:0] er_wdata;
wire        pl_start, pl_stop;
wire [15:0] pl_total, pl_tick;
wire [7:0]  pl_loop;
wire        pl_busy, pl_done;
wire [15:0] ev_count;
wire [2:0]  ble_state;

// 键位表（km_notes/km_valid 已在文件顶部提前声明）
wire        km_we;
wire [3:0]  km_waddr;
wire [7:0]  km_wdata;
wire        km_commit;
wire [95:0] km_codes;

// 录音
wire        rec_on, rec_clr;
wire [31:0] rec_tick_cyc;
wire [15:0] rec_count;
wire        rec_full;
wire        rec_we;
wire [12:0] rec_waddr;
wire [63:0] rec_wdata;

// 帧发送
wire        ft_req;
wire [7:0]  ft_cmd, ft_len, ft_echo;
wire [63:0] ft_pay;
wire        ft_ready;

// 录音回传读口
wire [12:0] rec_raddr;
wire [63:0] rec_rdata;

cmd_exec u_ble_cmd (
    .clk         (sys_clk),
    .frame_valid (ble_frame_v),
    .frame       (ble_frame),
    .err_crc     (ble_crc_err),
    .tx_req      (ft_req),
    .tx_cmd      (ft_cmd),
    .tx_len      (ft_len),
    .tx_pay      (ft_pay),
    .tx_echo     (ft_echo),
    .tx_ready    (ft_ready),
    .er_we       (er_we),
    .er_waddr    (er_waddr),
    .er_wdata    (er_wdata),
    .rec_raddr   (rec_raddr),
    .rec_rdata   (rec_rdata),
    .pl_start    (pl_start),
    .pl_stop     (pl_stop),
    .pl_total    (pl_total),
    .pl_tick     (pl_tick),
    .pl_loop     (pl_loop),
    .pl_busy     (pl_busy),
    .pl_done     (pl_done),
    .km_we       (km_we),
    .km_waddr    (km_waddr),
    .km_wdata    (km_wdata),
    .km_commit   (km_commit),
    .km_codes    (km_codes),
    .rec_on      (rec_on),
    .rec_clr     (rec_clr),
    .rec_tick_cyc(rec_tick_cyc),
    .rec_count   (rec_count),
    .rec_full    (rec_full),
    .ev_count    (ev_count),
    .state_o     (ble_state)
);

frame_tx u_ble_tx (
    .clk      (sys_clk),
    .tx_req   (ft_req),
    .tx_cmd   (ft_cmd),
    .tx_len   (ft_len),
    .tx_pay   (ft_pay),
    .tx_echo  (ft_echo),
    .tx_ready (ft_ready),
    .tx       (ble_tx)
);

keymap u_keymap (
    .clk     (sys_clk),
    .we      (km_we),
    .waddr   (km_waddr),
    .wdata   (km_wdata),
    .commit  (km_commit),
    .notes   (km_notes),
    .valid   (km_valid),
    .codes   (km_codes)
);

localparam LED_PROBE = 1'b0;

localparam PLAY_LED_VOICE = 1'b0;

function [7:0] led7p1;
    input [3:0] k;
    begin
        case (k)
            4'd0:  led7p1 = 8'b0000_0001;   // C
            4'd1:  led7p1 = 8'b0000_0010;   // D
            4'd2:  led7p1 = 8'b0000_0100;   // E
            4'd3:  led7p1 = 8'b0000_1000;   // F
            4'd4:  led7p1 = 8'b0001_0000;   // G
            4'd5:  led7p1 = 8'b0010_0000;   // A
            4'd6:  led7p1 = 8'b0100_0000;   // B
            4'd7:  led7p1 = 8'b1000_0001;   // C# = C + 升号
            4'd8:  led7p1 = 8'b1000_0010;   // D# = D + 升号
            4'd9:  led7p1 = 8'b1000_1000;   // F# = F + 升号
            4'd10: led7p1 = 8'b1001_0000;   // G# = G + 升号
            4'd11: led7p1 = 8'b1010_0000;   // A# = A + 升号
            default: led7p1 = 8'b0000_0000;
        endcase
    end
endfunction

wire [7:0] play_leds = PLAY_LED_VOICE ? ~v_gate :
                       {~fx_sel, ~expr_sel,
                        ~(LED_PROBE ? v_gate[2:0] : (3'b001 << (octave - 3'd1))),
                        led_bit};

wire [7:0] guide_leds =
    (g_state == 3'd5) ? (g_led_on ? ~led7p1(g_led_note) : 8'hFF) :
    (g_state == 3'd3) ? ~led7p1(g_expected) :
    (g_state == 3'd1) ? ~(g_adv ? 8'b0000_0010 : 8'b0000_0001) :
    ((g_state == 3'd2) && g_adv) ? 8'hFF :
    ~(g_song ? 8'b0000_0010 : 8'b0000_0001);

assign LEDs = g_mode ? guide_leds : play_leds;

wire signed [15:0] a0, a1, a2, a3, a4, a5, a6, a7;

wire [12:0] dc0, dc1, dc2, dc3, dc4, dc5, dc6, dc7;

voice #(.SS_PHASE(10'd0)) u_voice0 (
    .clk           (sys_clk),
    .sample_strobe (sample_strobe),
    .key_idx       (v_keys[3:0]),
    .note_abs      (7'd0),
    .note_sel      (1'b0),
    .km_notes      (km_notes),
    .km_sel        (1'b1),
    .octave        (octave),
    .timbre        (timbre),
    .expr_sel      (expr_sel),
    .expr_amt      (expr_amt),
    .glide_tick    (glide_tick),
    .vib_q15       (vib_q15),
    .gate          (v_gate[0]),
    .trig          (v_trig[0]),
    .idle          (v_idle[0]),
    .audio         (a0),
    .dc_env        (dc0)
);

voice #(.SS_PHASE(10'd7)) u_voice1 (
    .clk           (sys_clk),
    .sample_strobe (sample_strobe),
    .key_idx       (v_keys[7:4]),
    .note_abs      (7'd0),
    .note_sel      (1'b0),
    .km_notes      (km_notes),
    .km_sel        (1'b1),
    .octave        (octave),
    .timbre        (timbre),
    .expr_sel      (expr_sel),
    .expr_amt      (expr_amt),
    .glide_tick    (glide_tick),
    .vib_q15       (vib_q15),
    .gate          (v_gate[1]),
    .trig          (v_trig[1]),
    .idle          (v_idle[1]),
    .audio         (a1),
    .dc_env        (dc1)
);

voice #(.SS_PHASE(10'd14)) u_voice2 (
    .clk           (sys_clk),
    .sample_strobe (sample_strobe),
    .key_idx       (v_keys[11:8]),
    .note_abs      (7'd0),
    .note_sel      (1'b0),
    .km_notes      (km_notes),
    .km_sel        (1'b1),
    .octave        (octave),
    .timbre        (timbre),
    .expr_sel      (expr_sel),
    .expr_amt      (expr_amt),
    .glide_tick    (glide_tick),
    .vib_q15       (vib_q15),
    .gate          (v_gate[2]),
    .trig          (v_trig[2]),
    .idle          (v_idle[2]),
    .audio         (a2),
    .dc_env        (dc2)
);

voice #(.SS_PHASE(10'd21)) u_voice3 (
    .clk           (sys_clk),
    .sample_strobe (sample_strobe),
    .key_idx       (v_keys[15:12]),
    .note_abs      (7'd0),
    .note_sel      (1'b0),
    .km_notes      (km_notes),
    .km_sel        (1'b1),
    .octave        (octave),
    .timbre        (timbre),
    .expr_sel      (expr_sel),
    .expr_amt      (expr_amt),
    .glide_tick    (glide_tick),
    .vib_q15       (vib_q15),
    .gate          (v_gate[3]),
    .trig          (v_trig[3]),
    .idle          (v_idle[3]),
    .audio         (a3),
    .dc_env        (dc3)
);

voice #(.SS_PHASE(10'd28)) u_voice4 (
    .clk           (sys_clk),
    .sample_strobe (sample_strobe),
    .key_idx       (v_keys[19:16]),
    .note_abs      (7'd0),
    .note_sel      (1'b0),
    .km_notes      (km_notes),
    .km_sel        (1'b1),
    .octave        (octave),
    .timbre        (timbre),
    .expr_sel      (expr_sel),
    .expr_amt      (expr_amt),
    .glide_tick    (glide_tick),
    .vib_q15       (vib_q15),
    .gate          (v_gate[4]),
    .trig          (v_trig[4]),
    .idle          (v_idle[4]),
    .audio         (a4),
    .dc_env        (dc4)
);

voice #(.SS_PHASE(10'd35)) u_voice5 (
    .clk           (sys_clk),
    .sample_strobe (sample_strobe),
    .key_idx       (v_keys[23:20]),
    .note_abs      (7'd0),
    .note_sel      (1'b0),
    .km_notes      (km_notes),
    .km_sel        (1'b1),
    .octave        (octave),
    .timbre        (timbre),
    .expr_sel      (expr_sel),
    .expr_amt      (expr_amt),
    .glide_tick    (glide_tick),
    .vib_q15       (vib_q15),
    .gate          (v_gate[5]),
    .trig          (v_trig[5]),
    .idle          (v_idle[5]),
    .audio         (a5),
    .dc_env        (dc5)
);

voice #(.SS_PHASE(10'd42)) u_voice6 (
    .clk           (sys_clk),
    .sample_strobe (sample_strobe),
    .key_idx       (v_keys[27:24]),
    .note_abs      (7'd0),
    .note_sel      (1'b0),
    .km_notes      (km_notes),
    .km_sel        (1'b1),
    .octave        (octave),
    .timbre        (timbre),
    .expr_sel      (expr_sel),
    .expr_amt      (expr_amt),
    .glide_tick    (glide_tick),
    .vib_q15       (vib_q15),
    .gate          (v_gate[6]),
    .trig          (v_trig[6]),
    .idle          (v_idle[6]),
    .audio         (a6),
    .dc_env        (dc6)
);

voice #(.SS_PHASE(10'd49)) u_voice7 (
    .clk           (sys_clk),
    .sample_strobe (sample_strobe),
    .key_idx       (v_keys[31:28]),
    .note_abs      (7'd0),
    .note_sel      (1'b0),
    .km_notes      (km_notes),
    .km_sel        (1'b1),
    .octave        (octave),
    .timbre        (timbre),
    .expr_sel      (expr_sel),
    .expr_amt      (expr_amt),
    .glide_tick    (glide_tick),
    .vib_q15       (vib_q15),
    .gate          (v_gate[7]),
    .trig          (v_trig[7]),
    .idle          (v_idle[7]),
    .audio         (a7),
    .dc_env        (dc7)
);

wire [12:0] er_raddr;
wire [63:0] er_rdata;

wire        pl_on, pl_off, pl_panic;
wire [6:0]  pl_on_note, pl_off_note;

recorder u_recorder (
    .clk         (sys_clk),
    .rec_on      (rec_on),
    .clr         (rec_clr),
    .tick_cyc    (rec_tick_cyc),
    .key_press   (key_press),
    .key_release (key_release),
    .km_notes    (km_notes),
    .km_valid    (km_valid),
    .we          (rec_we),
    .waddr       (rec_waddr),
    .wdata       (rec_wdata),
    .count       (rec_count),
    .full        (rec_full)
);

wire        ram_we    = (ble_state == 3'd5) ? rec_we    : er_we;
wire [12:0] ram_waddr = (ble_state == 3'd5) ? rec_waddr : er_waddr;
wire [63:0] ram_wdata = (ble_state == 3'd5) ? rec_wdata : er_wdata;
wire [12:0] ram_raddr = (ble_state == 3'd3) ? er_raddr  : rec_raddr;

wire [63:0] ram_rdata;

event_ram u_event_ram (
    .clk   (sys_clk),
    .we    (ram_we),
    .waddr (ram_waddr),
    .wdata (ram_wdata),
    .raddr (ram_raddr),
    .rdata (ram_rdata)
);

assign er_rdata  = ram_rdata;
assign rec_rdata = ram_rdata;

song_player u_player (
    .clk       (sys_clk),
    .start     (pl_start),
    .stop      (pl_stop),
    .total     (pl_total),
    .tick_ms   (pl_tick),
    .loop_cnt  (pl_loop),
    .raddr     (er_raddr),
    .rdata     (er_rdata),
    .on_pulse  (pl_on),
    .on_note   (pl_on_note),
    .off_pulse (pl_off),
    .off_note  (pl_off_note),
    .panic     (pl_panic),
    .busy      (pl_busy),
    .done      (pl_done)
);

wire [3:0]  s_gate, s_trig;
wire [27:0] s_note;

reg  snd_evt_tgl = 1'b0;
always @(posedge sys_clk)
    if (pl_on | pl_off)
        snd_evt_tgl <= ~snd_evt_tgl;

score_alloc u_score_alloc (
    .clk       (sys_clk),
    .on_pulse  (pl_on),
    .on_note   (pl_on_note),
    .off_pulse (pl_off),
    .off_note  (pl_off_note),
    .panic     (pl_panic),
    .s_gate    (s_gate),
    .s_trig    (s_trig),
    .s_note    (s_note)
);

wire signed [15:0] a8, a9, a10, a11;
wire [12:0] dc8, dc9, dc10, dc11;

wire sc_strobe;
strobe1024 u_sc_strobe (.clk (sys_clk), .strobe (sc_strobe));

voice #(.SS_PHASE(10'd56)) u_voice8 (
    .clk           (sys_clk),
    .sample_strobe (sc_strobe),
    .key_idx       (4'd0),
    .note_abs      (s_note[6:0]),      // 曲谱旁路
    .note_sel      (1'b1),
    .km_notes      (84'd0),          // 曲谱声部不走键位表
    .km_sel        (1'b0),
    .octave        (octave),
    .timbre        (timbre),
    .expr_sel      (2'd0),
    .expr_amt      (2'd0),
    .glide_tick    (1'b0),
    .vib_q15       (16'sd0),
    .gate          (s_gate[0]),
    .trig          (s_trig[0]),
    .idle          (),
    .audio         (a8),
    .dc_env        (dc8)
);

voice #(.SS_PHASE(10'd63)) u_voice9 (
    .clk           (sys_clk),
    .sample_strobe (sc_strobe),
    .key_idx       (4'd0),
    .note_abs      (s_note[13:7]),
    .note_sel      (1'b1),
    .km_notes      (84'd0),          // 曲谱声部不走键位表
    .km_sel        (1'b0),
    .octave        (octave),
    .timbre        (timbre),
    .expr_sel      (2'd0),
    .expr_amt      (2'd0),
    .glide_tick    (1'b0),
    .vib_q15       (16'sd0),
    .gate          (s_gate[1]),
    .trig          (s_trig[1]),
    .idle          (),
    .audio         (a9),
    .dc_env        (dc9)
);

voice #(.SS_PHASE(10'd70)) u_voice10 (
    .clk           (sys_clk),
    .sample_strobe (sc_strobe),
    .key_idx       (4'd0),
    .note_abs      (s_note[20:14]),
    .note_sel      (1'b1),
    .km_notes      (84'd0),          // 曲谱声部不走键位表
    .km_sel        (1'b0),
    .octave        (octave),
    .timbre        (timbre),
    .expr_sel      (2'd0),
    .expr_amt      (2'd0),
    .glide_tick    (1'b0),
    .vib_q15       (16'sd0),
    .gate          (s_gate[2]),
    .trig          (s_trig[2]),
    .idle          (),
    .audio         (a10),
    .dc_env        (dc10)
);

voice #(.SS_PHASE(10'd77)) u_voice11 (
    .clk           (sys_clk),
    .sample_strobe (sc_strobe),
    .key_idx       (4'd0),
    .note_abs      (s_note[27:21]),
    .note_sel      (1'b1),
    .km_notes      (84'd0),          // 曲谱声部不走键位表
    .km_sel        (1'b0),
    .octave        (octave),
    .timbre        (timbre),
    .expr_sel      (2'd0),
    .expr_amt      (2'd0),
    .glide_tick    (1'b0),
    .vib_q15       (16'sd0),
    .gate          (s_gate[3]),
    .trig          (s_trig[3]),
    .idle          (),
    .audio         (a11),
    .dc_env        (dc11)
);

wire signed [15:0] mix;

mixer u_mixer (
    .clk (sys_clk),
    .a0  (a0),
    .a1  (a1),
    .a2  (a2),
    .a3  (a3),
    .a4  (a4),
    .a5  (a5),
    .a6  (a6),
    .a7  (a7),
    .a8  (a8),
    .a9  (a9),
    .a10 (a10),
    .a11 (a11),
    .mix (mix)
);

wire signed [31:0] trem_prod = mix * trem_q15;
wire signed [15:0] mix_t     = trem_prod[30:15];

wire signed [15:0] mix_fx;

wire [16:0] dc_sum = dc0 + dc1 + dc2 + dc3 + dc4 + dc5 + dc6 + dc7
                   + dc8 + dc9 + dc10 + dc11;

fx u_fx (
    .clk           (sys_clk),
    .rst_n         (1'b1),
    .sample_strobe (sample_strobe),

    .dly_up (dly_up), .dly_dn (dly_dn), .dly_sw (dly_swp),
    .rev_up (rev_up), .rev_dn (rev_dn), .rev_sw (rev_swp),
    .cho_up (cho_up), .cho_dn (cho_dn), .cho_sw (cho_swp),
    .fx_sel        (fx_sel),
    .fx_on         (fx_on),
    .dly_gear      (dly_gear),
    .rev_gear      (rev_gear),
    .cho_gear      (cho_gear),
    .din           (mix_t),
    .dc_in         (dc_sum[15:4]),
    .dout          (mix_fx)
);

wire signed [15:0] vol_q15  = {1'b0, volume[14:0]};   // 0~32767，恒为正
wire signed [31:0] vol_prod = mix_fx * vol_q15;
wire signed [15:0] vol_out  = vol_prod[30:15];

reg [9:0] lbase_cnt = 10'd0;
always @(posedge sys_clk) lbase_cnt <= lbase_cnt + 10'd1;
wire lbase_tick = (lbase_cnt == 10'd0);

localparam LIFT_K = 15;                                  // 释放 τ = 2^15 采样 ≈ 671 ms

wire [12:0] dc_tgt   = dc_sum[15:3];                     // = 原来的 dc_out（13 位，≤8191）
wire [24:0] dc_tgt_q = {dc_tgt, 12'b0};                  // ×4096（Q12）；8191×4096 < 2^25 ✓
reg  [24:0] dc_slow  = 25'd0;                            // 峰值保持寄存器（Q12）

always @(posedge sys_clk) if (lbase_tick) begin
    if (dc_tgt_q >= dc_slow)
        dc_slow <= dc_tgt_q;                             // 上升/持平：立刻跟上（= 改造前行为）
    else
        dc_slow <= dc_slow - (dc_slow >> LIFT_K);        // 下降：指数释放（常数移位）
end

wire [12:0] dc_out = dc_slow[24:12];                     // 回到整数；与原 dc_out 同宽、同值域
wire signed [16:0] dc_out_s = $signed({4'b0, dc_out});
wire signed [16:0] out_w    = vol_out + dc_out_s;
wire [15:0] audio_l = (out_w > 17'sd16380) ? 16'd16380 :
                      (out_w < 17'sd0)     ? 16'd0     : out_w[15:0];wire [15:0] audio_r = audio_l;        // 单声道（PT8211 双声道送同一路）

i2s_tx u_i2s (
    .clk_sys       (sys_clk),
    .rst_n         (1'b1),
    .audio_l       (audio_l),
    .audio_r       (audio_r),
    .bck           (HP_BCK),
    .lrck          (HP_WS),
    .din           (HP_DIN),
    .pa_en         (PA_EN),
    .sample_strobe (sample_strobe)
);

wire signed [15:0] disp_ac;
wire [9:0]         scope_y;
wire               scope_trig;
wire               scope_tgl;
wire signed [15:0] lissa_x, lissa_y;
wire               lissa_tgl;
wire [11:0]        key_snap;
wire               key_tgl;
wire               bar_we;         // 频谱柱写口（音频域，写双 bank BSRAM）
wire [7:0]         bar_waddr;
wire [7:0]         bar_wdata;
wire               spec_tgl;

reg [3:0] disp_nkeys = 4'd0;
always @(posedge sys_clk)
    disp_nkeys <= key_level[0] + key_level[1] + key_level[2]  + key_level[3]  +
                  key_level[4] + key_level[5] + key_level[6]  + key_level[7]  +
                  key_level[8] + key_level[9] + key_level[10] + key_level[11];
wire signed [15:0] disp_g;

wire disp_poly = (disp_nkeys >= 4'd2) || pl_busy;

wire disp_active;

wire disp_aud = disp_active && (timbre == 3'd1);

display_cond u_disp_cond (
    .clk     (sys_clk),
    .mix_fx  (mix_fx),
    .fx_n    (fx_sel),      // 已开效果器个数：有湿声时显示增益 ×16 → ×8
    .disp_ac (disp_ac),
    .active  (disp_active)
);

assign disp_g = disp_ac;

display_scope u_disp_scope (
    .clk          (sys_clk),
    .disp_ac      (disp_g),
    .att          (2'd0),
    .scope_y      (scope_y),
    .scope_trig   (scope_trig),
    .scope_tgl    (scope_tgl)
);

display_lissa u_disp_lissa (
    .clk       (sys_clk),
    .disp_ac   (disp_g),
    // 开效果器时 X/Y 先 >>1：信号本身大（实测 1.8~2.7 倍），
    // 李萨如因此缩小一半才不会贴框。放在音频域，不占 pclk 时序。
    .att       (fx_any ? 2'd1 : 2'd0),
    .lissa_x   (lissa_x),
    .lissa_y   (lissa_y),
    .lissa_tgl (lissa_tgl)
);

display_keysnap u_disp_keysnap (
    .clk       (sys_clk),
    .key_level (key_level),
    .key_snap  (key_snap),
    .key_tgl   (key_tgl)
);

wire [2:0] st_timbre, st_octave;
wire [6:0] st_vol_pct;
wire [1:0] st_expr_sel, st_expr_amt;
wire [2:0] st_fx_on;
wire [1:0] st_dly_p, st_rev_p, st_cho_p;
wire [3:0] st_key_cnt, st_voice_cnt;
wire       st_g_mode;
wire [2:0] st_g_state;
wire       st_g_song;
wire       st_g_adv;
wire [3:0] st_g_expected;
wire       st_g_wrong_active;
wire [3:0] st_g_wrong_key;
wire       st_g_msg_show;
wire [5:0] st_g_step;
wire [3:0] st_g_adv_next;
wire [275:0] st_g_tiles;
wire [5:0] st_g_hits;
wire       st_tgl;

wire [2:0]  st_ble_state;
wire [15:0] st_ble_ev, st_ble_rec;

wire [13:0] disp_vol_mul = volume[15:8] * 8'd100;
wire [6:0]  disp_vol_pct = (volume[15:8] == 8'd127) ? 7'd100 : disp_vol_mul[13:7];

// 按键数 0..12 / 活跃声部数 0..8（并行加法，21 ms 才用一次）
wire [3:0] disp_key_cnt =
    {3'd0, key_level[0]}  + {3'd0, key_level[1]}  +
    {3'd0, key_level[2]}  + {3'd0, key_level[3]}  +
    {3'd0, key_level[4]}  + {3'd0, key_level[5]}  +
    {3'd0, key_level[6]}  + {3'd0, key_level[7]}  +
    {3'd0, key_level[8]}  + {3'd0, key_level[9]}  +
    {3'd0, key_level[10]} + {3'd0, key_level[11]};

wire [3:0] disp_voice_cnt =
    {3'd0, v_gate[0]} + {3'd0, v_gate[1]} +
    {3'd0, v_gate[2]} + {3'd0, v_gate[3]} +
    {3'd0, v_gate[4]} + {3'd0, v_gate[5]} +
    {3'd0, v_gate[6]} + {3'd0, v_gate[7]};

assign st_timbre   = timbre;
assign st_octave   = octave;
assign st_vol_pct  = disp_vol_pct;
assign st_expr_sel = expr_sel;
assign st_expr_amt = expr_amt;
assign st_fx_on    = fx_on;
assign st_dly_p    = dly_gear;
assign st_rev_p    = rev_gear;
assign st_cho_p    = cho_gear;
assign st_key_cnt  = disp_key_cnt;
assign st_voice_cnt= disp_voice_cnt;
assign st_g_mode        = g_mode;
assign st_g_state       = g_state;
assign st_g_song        = g_song;
assign st_g_adv         = g_adv;
assign st_g_expected    = g_expected;
assign st_g_wrong_active= g_wrong_active;
assign st_g_wrong_key   = g_wrong_key;
assign st_g_msg_show    = g_msg_show;
assign st_g_step        = g_step;
assign st_g_adv_next    = g_adv_next;
assign st_g_tiles       = g_tiles;
assign st_g_hits        = g_hits;
assign st_ble_state     = ble_state;
assign st_ble_ev        = ev_count;
assign st_ble_rec       = rec_count;
assign st_tgl           = 1'b0;      // display_top 里已不用（改用帧起始）

spectrum_fft u_spectrum (
    .clk       (sys_clk),
    .din       (disp_ac),
    .bar_we    (bar_we),
    .bar_waddr (bar_waddr),
    .bar_wdata (bar_wdata),
    .spec_tgl  (spec_tgl)
);

display_top u_display_top (
    .clk           (sys_clk),
    .poly          (disp_poly),
    .fx_any        (fx_any),       // 有任一效果器开着：显示尾音 + 李萨如换档

    .snd_on        (pl_busy),

    .snd_evt_tgl   (snd_evt_tgl),

    .aud_on        (disp_aud),
    .scope_y       (scope_y),
    .scope_trig    (scope_trig),
    .scope_tgl     (scope_tgl),
    .lissa_x       (lissa_x),
    .lissa_y       (lissa_y),
    .lissa_tgl     (lissa_tgl),
    .key_snap      (key_snap),
    .key_tgl       (key_tgl),
    // 文字层参数快照
    .st_timbre     (st_timbre),
    .st_octave     (st_octave),
    .st_vol_pct    (st_vol_pct),
    .st_expr_sel   (st_expr_sel),
    .st_expr_amt   (st_expr_amt),
    .st_fx_on      (st_fx_on),
    .st_dly_p      (st_dly_p),
    .st_rev_p      (st_rev_p),
    .st_cho_p      (st_cho_p),
    .st_key_cnt    (st_key_cnt),
    .st_voice_cnt  (st_voice_cnt),
    .st_g_mode     (st_g_mode),
    .st_g_state    (st_g_state),
    .st_g_song     (st_g_song),
    .st_g_adv      (st_g_adv),
    .st_g_expected (st_g_expected),
    .st_g_wrong_active(st_g_wrong_active),
    .st_g_wrong_key(st_g_wrong_key),
    .st_g_msg_show (st_g_msg_show),
    .st_g_step     (st_g_step),
    .st_g_adv_next (st_g_adv_next),
    .st_g_tiles    (st_g_tiles),
    .st_g_hits     (st_g_hits),
    .st_ble_state  (st_ble_state),
    .st_ble_ev     (st_ble_ev),
    .st_ble_rec    (st_ble_rec),
    .st_tgl        (st_tgl),
    .bar_we        (bar_we),
    .bar_waddr     (bar_waddr),
    .bar_wdata     (bar_wdata),
    .spec_tgl      (spec_tgl),
    .tmds_clk_p_0  (tmds_clk_p_0),
    .tmds_clk_n_0  (tmds_clk_n_0),
    .tmds_d_p_0    (tmds_d_p_0),
    .tmds_d_n_0    (tmds_d_n_0)
);

endmodule
