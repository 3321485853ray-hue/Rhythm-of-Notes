// voice.v — 一个声部（4 声部复音的最小组件）

module voice #(
    parameter [9:0] SS_PHASE = 10'd0
)(
    input  wire         clk,
    input  wire         sample_strobe, // 每采样一次（fs = 48828.125Hz）一个周期高
    input  wire [3:0]   key_idx,       // 本声部拥有哪个键（0~11），来自 voice_manager
    input  wire [6:0]   note_abs,
    input  wire         note_sel,
    input  wire [83:0]  km_notes,      // 12 × 7 位（来自 keymap.v）
    input  wire         km_sel,
    input  wire [2:0]   octave,        // 八度档位 0~4（2 = 0 八度），全局共享
    input  wire [2:0]   timbre,
    input  wire [1:0]   expr_sel,      // 表情维度：0=关 1=滑音 2=颤音 3=震音（震音在 top 里，不经本模块）
    input  wire [1:0]   expr_amt,      // 表情参数档位 0~3（滑音时间的档位）
    input  wire         glide_tick,    // 相位：滑音"到点才推进"（顶层全局产生，见 glide_tick_gen.v）
    input  wire signed [15:0] vib_q15, // 全局颤音的调制量（vibrato.v 已按 expr_sel 门控，非颤音档恒 0）
    input  wire         gate,          // 1 = 键还按着；0 = 松手，走释放段
    input  wire         trig,          // 电平：分配/重触发时置 1，本模块采到后自行清
    output wire         idle,          // 1 = 包络已归零，声部可被回收
    output wire signed [15:0] audio,   // 16bit 有符号样本（未寄存，由 mixer 统一寄存）
    output wire [12:0]  dc_env         // ≈ env × 8190/32768（未除以 mixer 的 16）
);

reg  [9:0] scnt = 10'd0;
always @(posedge clk)
    scnt <= scnt + 10'd1;
wire ss = (scnt == SS_PHASE);

wire [6:0] base_note_map;

note_map u_note_map (
    .key_idx   (key_idx),
    .base_note (base_note_map)
);

reg [6:0] km_note;
always @(*) begin
    case (key_idx)
        4'd0:    km_note = km_notes[6:0];
        4'd1:    km_note = km_notes[13:7];
        4'd2:    km_note = km_notes[20:14];
        4'd3:    km_note = km_notes[27:21];
        4'd4:    km_note = km_notes[34:28];
        4'd5:    km_note = km_notes[41:35];
        4'd6:    km_note = km_notes[48:42];
        4'd7:    km_note = km_notes[55:49];
        4'd8:    km_note = km_notes[62:56];
        4'd9:    km_note = km_notes[69:63];
        4'd10:   km_note = km_notes[76:70];
        default: km_note = km_notes[83:77];
    endcase
end

wire [6:0] base_note = km_sel ? km_note : base_note_map;

reg [6:0] note_index_kb;

always @(*) begin
    case (octave)
        3'd0:    note_index_kb = base_note - 7'd24;
        3'd1:    note_index_kb = base_note - 7'd12;
        3'd2:    note_index_kb = base_note;
        3'd3:    note_index_kb = base_note + 7'd12;
        3'd4:    note_index_kb = base_note + 7'd24;
        default: note_index_kb = base_note;
    endcase
end

wire [6:0] note_index = note_sel ? note_abs : note_index_kb;

wire [31:0] phase_step;

note_freq u_note_freq (
    .note_index (note_index),
    .phase_step (phase_step)
);

reg [2:0] timbre_hold = 3'd4;       // 上电默认弦乐，与 timbre_ctrl 一致

localparam [15:0] ENV_MAX = 16'd32767;   // 幅度 1.0

localparam [2:0] S_IDLE = 3'd0,
                 S_ATK  = 3'd1,
                 S_DEC  = 3'd2,
                 S_SUS  = 3'd3,
                 S_REL  = 3'd4;

reg [15:0] p_sus, p_knee, p_atk_fast, p_atk_slow, p_dec_step;
reg [3:0]  p_dec_shift, p_rel_shift;
reg        p_dec_lin;

reg        p_oneshot;

always @(*) begin
    case (timbre_hold)

        3'd0: begin
            p_sus      = 16'd22937;   // S = 0.70
            p_knee     = 16'd19660;   // 拐点 0.60
            p_atk_fast = 16'd134;     // 19660/147  → 约 3ms
            p_atk_slow = 16'd7;       // 13107/1872 → 约 38ms
            p_dec_lin  = 1'b1;
            p_dec_step = 16'd1;       // 9830/9766  → 约 200ms
            p_dec_shift= 4'd0;
            p_oneshot  = 1'b0;        // 持续音：松手走释放段
            p_rel_shift= 4'd10;       // 指数释放，约 86.2ms 归零（自 S=0.70 起算）
        end

        3'd1: begin
            p_sus      = 16'd0;       // S = 0（衰减到没）
            p_knee     = 16'd32767;   // 拐点拉到顶 → 两段起音退化成单段
            p_atk_fast = 16'd334;     // 32767/334 = 98 点 → 2.01ms
            p_atk_slow = 16'd1;
            p_dec_lin  = 1'b0;
            p_dec_step = 16'd0;
            p_dec_shift= 4'd10;       // 尾巴起点 1024（−30dB）
            p_oneshot  = 1'b1;
            p_rel_shift= 4'd11;       // 已被 p_oneshot 旁路（钢琴永不进 S_REL），留作备用
        end

        3'd3: begin
            p_sus      = 16'd32767;   // S = 1.0（持续）
            p_knee     = 16'd32767;   // 单段起音
            p_atk_fast = 16'd17;      // 32767/17 ≈ 1927 点 → 39.5ms（比管风琴柔和）
            p_atk_slow = 16'd1;
            p_dec_lin  = 1'b1;
            p_dec_step = 16'd0;
            p_dec_shift= 4'd0;        // 线性分支不用，但必须赋值，否则综合器推断锁存器
            p_oneshot  = 1'b0;        // 持续音：松手走释放段
            p_rel_shift= 4'd10;       // 约 93.6ms
        end

        3'd4: begin
            p_sus      = 16'd32767;   // S = 1.0（弓一直拉）
            p_knee     = 16'd32767;   // 单段起音
            p_atk_fast = 16'd8;       // 32767/8 ≈ 4096 点 → 83.9ms
            p_atk_slow = 16'd1;
            p_dec_lin  = 1'b1;
            p_dec_step = 16'd0;
            p_dec_shift= 4'd0;
            p_oneshot  = 1'b0;        // 持续音：松手走释放段
            p_rel_shift= 4'd10;       // 约 93.6ms
        end

        default: begin
            p_sus      = 16'd32767;   // S = 1.0（满）
            p_knee     = 16'd32767;   // 单段起音
            p_atk_fast = 16'd34;      // 32767/34 = 964 点 → 19.74ms
            p_atk_slow = 16'd1;
            p_dec_lin  = 1'b1;
            p_dec_step = 16'd0;
                                      //   用指数分支的 `(env>>0)+1` 会 16 位溢出，见上面坑 1
            p_dec_shift= 4'd0;
            p_oneshot  = 1'b0;        // 持续音：松手走释放段
            p_rel_shift= 4'd10;       // 约 93.6ms
        end
    endcase
end

reg [2:0]  env_state       = 3'd0;
reg [15:0] env             = 16'd0;
reg        gate_d          = 1'b0;

reg [3:0] dec_cnt = 4'd0;

// 起音/重触发条件：trig（抢占/重分配）或 gate 上升沿。三处用到，抽成一个信号。
wire note_on = trig || (gate && !gate_d);

wire dec_tick = (dec_cnt == 4'd15);      // 固定 ÷16，只在常量和计数器之间解码

always @(posedge clk) begin
    if (ss)
        dec_cnt <= note_on ? 4'd0 : dec_cnt + 4'd1;   // 4bit 自然回绕 15→0
end

always @(posedge clk) begin
    if (ss) begin
        gate_d <= gate;

        // 音色在起音瞬间锁存（见上面 timbre_hold 的说明）
        if (note_on)
            timbre_hold <= timbre;

        // note_on 优先级最高：抢占/重分配时立刻重新起音。
        // 它 = trig（覆盖"gate 一直是 1 但音符换了"的抢占）+ gate 上升沿。
        if (note_on)                            // 分配 / 重触发 / 起音
            env_state <= S_ATK;

        else if (!gate && gate_d)               // 松手
            env_state <= (env_state == S_IDLE || p_oneshot) ? env_state : S_REL;
        else case (env_state)
            // 起音。p_knee 拉到 32767 时慢段分支永远走不到，
            // 自动退化成单段 —— 所以这里不用为单段起音另写一套。
            S_ATK:  if (env < p_knee) begin
                        // 第一段：快速冲到拐点
                        if (env + p_atk_fast > p_knee)
                            env <= p_knee;
                        else
                            env <= env + p_atk_fast;
                    end
                    else if (env + p_atk_slow >= ENV_MAX) begin
                        // 第二段结束
                        env       <= ENV_MAX;
                        env_state <= S_DEC;
                    end
                    else
                        env <= env + p_atk_slow;

            S_DEC:  if (p_dec_lin) begin

                        if (env <= p_sus + p_dec_step) begin
                            env       <= p_sus;
                            env_state <= (p_sus == 16'd0) ? S_IDLE : S_SUS;
                        end else
                            env <= env - p_dec_step;
                    end
                    else if (dec_tick) begin
                        // 指数：先判终止再相减，保证相减时
                        // env > (env>>shift)+1 → 结果恒 ≥ 1，无符号回绕
                        if (env <= ((env >> p_dec_shift) + 16'd1)) begin
                            env       <= p_sus;      // 钢琴 p_sus=0
                            env_state <= (p_sus == 16'd0) ? S_IDLE : S_SUS;
                        end else
                            env <= env - (env >> p_dec_shift) - 16'd1;
                    end

            S_SUS:  env <= p_sus;                    // 钢琴=0，管风琴=32767，正弦=22937

            S_REL:  if (env <= ((env >> p_rel_shift) + 16'd1)) begin
                        env       <= 16'd0;
                        env_state <= S_IDLE;
                    end else
                        env <= env - (env >> p_rel_shift) - 16'd1;

            default: begin
                        env       <= 16'd0;
                        env_state <= S_IDLE;
                    end
        endcase
    end
end

// 包络没走完（含释放尾巴）时波形层继续跑，否则释放段会被相位归零掐断
wire env_active = (env_state != S_IDLE);

assign idle = (env_state == S_IDLE);

localparam [1:0] E_OFF = 2'd0, E_GLIDE = 2'd1, E_VIB = 2'd2, E_TREM = 2'd3;

wire glide_on = (expr_sel == E_GLIDE);

reg [31:0] ps_target = 32'd0;
reg [31:0] ps_cur    = 32'd0;

wire        ps_down = (ps_target < ps_cur);        // 1 = 往下滑
wire [31:0] ps_gap  = ps_down ? (ps_cur - ps_target)   // 差值绝对值
                              : (ps_target - ps_cur);

wire [31:0] ps_step = ps_gap >>> 10;

wire [31:0] ps_adv  = glide_tick ? ps_step : 32'd0;
wire [31:0] ps_next = ps_down ? (ps_cur - ps_adv)
                              : (ps_cur + ps_adv);

reg [14:0] legato_timer = 15'd0;

always @(posedge clk) begin
    if (ss) begin
        if (env_state == S_IDLE) begin
            if (legato_timer != 15'd0) legato_timer <= legato_timer - 15'd1;
        end else
            legato_timer <= 15'd24414;
    end
end

wire legato = (env_state != S_IDLE) || (legato_timer != 15'd0);

always @(posedge clk) begin
    if (ss) begin
        if (glide_on && legato) begin
            // 连奏：从上一个音滑过来
            if (gate) ps_target <= phase_step;          // 按住期间跟随键；松手冻结
            ps_cur <= ps_next;
        end else begin

            if (gate) begin
                ps_target <= phase_step;
                ps_cur    <= phase_step;
            end
        end
    end
end

wire signed [16:0] ps_hi     = ps_cur[31:15];          // = ps_cur >> 15（ps_cur < 2³¹ ⇒ 恒正）
wire signed [31:0] vib_delta = ps_hi * vib_q15;        // 17×16 位 ⇒ 一个 DSP

wire signed [31:0] ps_cur_s  = ps_cur;                 // ps_cur < 2³¹ ⇒ 按有符号解释恒为正
wire signed [31:0] ps_out    = ps_cur_s + vib_delta;

wire signed [15:0] osc_raw;

timbre_gen u_wave (
    .clk           (clk),
    .sample_strobe (ss),
    .gate          (env_active),
    .phase_step    (ps_out),
    .timbre        (timbre_hold),
    .wave          (osc_raw)
);

wire signed [15:0] env_q15  = {1'b0, env[14:0]};
wire signed [31:0] env_prod = osc_raw * env_q15;

assign audio = env_prod[30:15];

assign dc_env = env[14:2];

endmodule
