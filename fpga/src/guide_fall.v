// guide_fall.v —— 钢琴块式下落方块引擎

module guide_fall #(
    parameter [31:0] BEAT100   = 32'd30000000,   // 100 BPM @50 MHz
    parameter [31:0] BEAT90    = 32'd33333333,   //  90 BPM
    parameter [31:0] HIT_EARLY = 32'd7500000,    // 150 ms 提前量
    parameter [31:0] HIT_LATE  = 32'd6000000,    // 120 ms 宽限
    parameter [31:0] LEAD_CYC  = 32'd105906176,  // 202 px × 2^19：第一个音从泳道顶落下
    parameter [31:0] GAP_CYC   = 32'd6291456,    //  12 px × 2^19：相邻方块视觉缝
    parameter [31:0] LEDGAP    = 32'd2000000,    //  40 ms：LED 音尾提前熄灭
    parameter integer SHIFT    = 19
)(
    input  wire         clk,
    input  wire         start,        // 单拍：从第 0 音开始
    input  wire         abort,        // 电平：非游戏态（OFF）强制清空
    input  wire         song,         // 0=小星星 1=欢乐颂
    input  wire [11:0]  key_press,    // 12 键，单拍脉冲
    input  wire [11:0]  key_level,    // 12 键，按住电平
    output wire [5:0]   hits,         // 命中数
    output wire         ev_fail,      // 单拍：判定失败
    output wire         ev_done,      // 单拍：曲终
    output wire [3:0]   cur_key,      // 当前音的键（LED 用）
    output wire         cur_on,       // 当前音是否点亮 LED
    output wire [275:0] tiles        // 6 槽 × 46 bit
);

    localparam [10:0] LANE_TOP = 11'd466;   // 泳道顶
    localparam [10:0] HIT_Y    = 11'd668;   // 判定线 = 琴键上边缘
    localparam [10:0] LANE_X0  = 11'd726;   // 第 0 道左边界
    localparam [9:0]  LANE_W   = 10'd44;
    localparam [9:0]  INSET    = 10'd3;     // 方块左右各内缩 3 px

    localparam [2:0] M_IDLE = 3'd0,
                     M_FILL = 3'd1,
                     M_RUN  = 3'd2,
                     M_FAIL = 3'd3,
                     M_DONE = 3'd4;

    reg [2:0]  mstate = M_IDLE;
    reg [31:0] song_t = 32'd0;
    reg [2:0]  fill   = 3'd0;
    reg [5:0]  nx_idx = 6'd0;
    reg        ended  = 1'b0;
    reg [31:0] fill_t = 32'd0;
    reg [5:0]  hits_r = 6'd0;
    reg        ev_fail_r = 1'b0;
    reg        ev_done_r = 1'b0;
    // 上一个音（LED 用）：命中后队列会提前前移，但 LED 要亮到本音的时值走完
    reg [3:0]  prev_key   = 4'd0;
    reg        prev_valid = 1'b0;

    reg [3:0]  qk    [0:5];       // 键号
    reg [2:0]  qd    [0:5];       // 时值（拍）
    reg [31:0] qt    [0:5];       // 到达判定线的绝对时刻
    reg [31:0] ql    [0:5];       // 方块长度（clk，已扣 GAP）
    reg [31:0] qf    [0:5];       // 音符全长（clk）
    reg        qh    [0:5];       // 已命中
    reg        qdead [0:5];       // 方块已消失（短块命中 / 长块缩没）
    reg        qv    [0:5];       // 槽有效

    wire [7:0] rom_v;
    guide_score_rom u_rom (
        .clk  (clk),
        .addr ({song, nx_idx}),
        .dout (rom_v)
    );
    wire [31:0] beatv   = song ? BEAT90 : BEAT100;
    wire [28:0] dur_mul = rom_v[6:4] * beatv[25:0];
    wire [31:0] dur_cyc = {3'd0, dur_mul};
    wire [31:0] len_cyc = dur_cyc - GAP_CYC;

    wire [31:0] d0     = qt[0] - song_t;
    wire        arr0   = d0[31];                    // 1 = 已到达判定线
    wire [31:0] d0p    = arr0 ? 32'd0 : d0;         // 距到达还有多少 clk（已到达=0）
    wire [31:0] dt0    = d0 + ql[0];                // 尾沿
    wire        dt0a   = dt0[31];                   // 1 = 尾沿已过（方块缩没）
    wire [31:0] late0  = arr0 ? (~d0 + 32'd1) : 32'd0;
    wire [31:0] t_end0 = qt[0] + qf[0];             // 本音时值走完的时刻

    wire hit_now  = (mstate == M_RUN) && qv[0] && !qh[0] && !qdead[0] &&
                    (qk[0] <= 4'd11) &&
                    ((key_press[qk[0]] && (d0p <= HIT_EARLY)) ||
                     (key_level[qk[0]] && arr0));
    wire miss_now = (mstate == M_RUN) && qv[0] && !qh[0] && arr0 && (late0 > HIT_LATE);
    wire hold_bad = (mstate == M_RUN) && qv[0] && qh[0] && (qd[0] >= 3'd2) &&
                    !dt0a && !qdead[0] && !key_level[qk[0]];
    // 队列前移：方块已消失（短块命中 / 长块缩没）就可以前移，
    //   这样下一块的提前判定窗口才是完整的 150 ms；时值走完是兜底条件。
    wire adv      = (mstate == M_RUN) && qv[0] && (qdead[0] || (song_t >= t_end0));
    wire done_now = (mstate == M_RUN) && !qv[0];

    always @(posedge clk) begin
        ev_fail_r <= 1'b0;
        ev_done_r <= 1'b0;

        if (start) begin
            mstate <= M_FILL;
            song_t <= 32'd0;
            fill   <= 3'd0;
            nx_idx <= 6'd0;
            ended  <= 1'b0;
            fill_t <= LEAD_CYC;
            hits_r <= 6'd0;
            qv[0] <= 1'b0; qv[1] <= 1'b0; qv[2] <= 1'b0;
            qv[3] <= 1'b0; qv[4] <= 1'b0; qv[5] <= 1'b0;
        end else if (abort) begin
            mstate <= M_IDLE;
            qv[0] <= 1'b0; qv[1] <= 1'b0; qv[2] <= 1'b0;
            qv[3] <= 1'b0; qv[4] <= 1'b0; qv[5] <= 1'b0;
        end else if (mstate == M_FILL) begin
            // 逐拍填 6 个槽（50 MHz 下 6 拍 = 120 ns，不可见）
            if (!ended && (rom_v != 8'hFF)) begin
                qv[fill]    <= 1'b1;
                qk[fill]    <= rom_v[3:0];
                qd[fill]    <= rom_v[6:4];
                qf[fill]    <= dur_cyc;
                ql[fill]    <= len_cyc;
                qt[fill]    <= fill_t;
                qh[fill]    <= 1'b0;
                qdead[fill] <= 1'b0;
                fill_t      <= fill_t + dur_cyc;
                nx_idx      <= nx_idx + 6'd1;
                if (fill == 3'd5) mstate <= M_RUN;
                else              fill   <= fill + 3'd1;
            end else begin
                ended    <= 1'b1;
                qv[fill] <= 1'b0;
                mstate   <= M_RUN;
            end
        end else if (mstate == M_RUN) begin
            song_t <= song_t + 32'd1;

            // 命中：短块立刻消失；长块进入"按住"状态由 hold_bad 看管
            if (hit_now) begin
                qh[0]  <= 1'b1;
                hits_r <= hits_r + 6'd1;
                if (qd[0] <= 3'd1) qdead[0] <= 1'b1;
            end
            if (qh[0] && dt0a) qdead[0] <= 1'b1;

            // 队列前移一格，从 ROM 补一个新音
            if (adv) begin
                prev_key   <= qk[0];
                prev_valid <= 1'b1;
                qk[0]    <= qk[1];    qd[0]    <= qd[1];
                qt[0]    <= qt[1];    ql[0]    <= ql[1];
                qf[0]    <= qf[1];    qh[0]    <= qh[1];
                qdead[0] <= qdead[1]; qv[0]    <= qv[1];
                qk[1]    <= qk[2];    qd[1]    <= qd[2];
                qt[1]    <= qt[2];    ql[1]    <= ql[2];
                qf[1]    <= qf[2];    qh[1]    <= qh[2];
                qdead[1] <= qdead[2]; qv[1]    <= qv[2];
                qk[2]    <= qk[3];    qd[2]    <= qd[3];
                qt[2]    <= qt[3];    ql[2]    <= ql[3];
                qf[2]    <= qf[3];    qh[2]    <= qh[3];
                qdead[2] <= qdead[3]; qv[2]    <= qv[3];
                qk[3]    <= qk[4];    qd[3]    <= qd[4];
                qt[3]    <= qt[4];    ql[3]    <= ql[4];
                qf[3]    <= qf[4];    qh[3]    <= qh[4];
                qdead[3] <= qdead[4]; qv[3]    <= qv[4];
                qk[4]    <= qk[5];    qd[4]    <= qd[5];
                qt[4]    <= qt[5];    ql[4]    <= ql[5];
                qf[4]    <= qf[5];    qh[4]    <= qh[5];
                qdead[4] <= qdead[5]; qv[4]    <= qv[5];

                if (!ended && (rom_v != 8'hFF)) begin
                    qv[5]    <= 1'b1;
                    qk[5]    <= rom_v[3:0];
                    qd[5]    <= rom_v[6:4];
                    qf[5]    <= dur_cyc;
                    ql[5]    <= len_cyc;
                    qt[5]    <= qt[5] + qf[5];
                    qh[5]    <= 1'b0;
                    qdead[5] <= 1'b0;
                    nx_idx   <= nx_idx + 6'd1;
                end else begin
                    ended <= 1'b1;
                    qv[5] <= 1'b0;
                end
            end else if (prev_valid && (song_t >= qt[0])) begin
                prev_valid <= 1'b0;
            end

            if (miss_now || hold_bad) begin
                mstate    <= M_FAIL;
                ev_fail_r <= 1'b1;
            end
            if (done_now) begin
                mstate    <= M_DONE;
                ev_done_r <= 1'b1;
            end
        end
    end

    wire in_prev = prev_valid && qv[0] && (song_t < qt[0]);
    assign cur_key = in_prev ? prev_key : qk[0];
    assign cur_on  = in_prev ? ((qt[0] - song_t) > LEDGAP)
                             : (qv[0] && arr0 && ((t_end0 - song_t) > LEDGAP));
    assign hits    = hits_r;
    assign ev_fail = ev_fail_r;
    assign ev_done = ev_done_r;

    function [9:0] lane_off;
        input [3:0] k;
        begin
            case (k)
                4'd0:    lane_off = 10'd0;     // C   → 列 0
                4'd1:    lane_off = 10'd88;    // D   → 列 2
                4'd2:    lane_off = 10'd176;   // E   → 列 4
                4'd3:    lane_off = 10'd220;   // F   → 列 5
                4'd4:    lane_off = 10'd308;   // G   → 列 7
                4'd5:    lane_off = 10'd396;   // A   → 列 9
                4'd6:    lane_off = 10'd484;   // B   → 列 11
                4'd7:    lane_off = 10'd44;    // C#  → 列 1
                4'd8:    lane_off = 10'd132;   // D#  → 列 3
                4'd9:    lane_off = 10'd264;   // F#  → 列 6
                4'd10:   lane_off = 10'd352;   // G#  → 列 8
                default: lane_off = 10'd440;   // A#  → 列 10
            endcase
        end
    endfunction

    genvar gi;
    generate
        for (gi = 0; gi < 6; gi = gi + 1) begin : g_tile
            wire [31:0] dk   = qt[gi] - song_t;
            wire        ak   = dk[31];
            wire [31:0] dkp  = ak ? 32'd0 : dk;
            wire [31:0] dtk  = dk + ql[gi];
            wire [31:0] dtkp = dtk[31] ? 32'd0 : dtk;
            wire [31:0] dyb  = dkp  >> SHIFT;
            wire [31:0] dyt  = dtkp >> SHIFT;
            wire [10:0] yb   = (dyb > 32'd202) ? LANE_TOP : (HIT_Y - {3'd0, dyb[7:0]});
            wire [10:0] yt   = (dyt > 32'd202) ? LANE_TOP : (HIT_Y - {3'd0, dyt[7:0]});
            wire [9:0]  xoff = lane_off(qk[gi]);
            wire [10:0] x0   = LANE_X0 + {1'b0, xoff} + {1'b0, INSET};
            wire [10:0] x1   = LANE_X0 + {1'b0, xoff} + LANE_W - {1'b0, INSET};
            wire        on   = qv[gi] && !qdead[gi] && (yt < yb);
            assign tiles[gi*46 +: 46] = {qh[gi], on, yt, yb, x1, x0};
        end
    endgenerate

endmodule
