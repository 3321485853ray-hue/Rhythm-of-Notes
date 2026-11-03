// display_top.v — D2a：720p60 显示骨架（波形 + 李萨如 + 小键盘 + 面板）

module display_top (
    input  wire               clk,           // 50 MHz
    input  wire               poly,          // 1 = 多键（≥2）：波形显示幅度 ×2
    input  wire               fx_any,        // 1 = 有任一效果器开着（延迟/混响/合唱）
    input  wire               snd_on,        // 1 = 曲谱/录音正在播（没有物理按键也有声音）
    input  wire               snd_evt_tgl,
    input  wire               aud_on,
    input  wire [9:0]         scope_y,        // 已换算好的屏幕 Y（720p：8..270，中线 139）
    input  wire               scope_tgl,
    input  wire               scope_trig,     // 与 scope_tgl 同拍：低通过零
    input  wire signed [15:0] lissa_x,
    input  wire signed [15:0] lissa_y,
    input  wire               lissa_tgl,
    input  wire [11:0]        key_snap,
    input  wire               key_tgl,
    // 参数文字层慢快照（音频域 21 ms 翻转；这里两级同步 + 检沿整体锁存）
    input  wire [2:0]         st_timbre,
    input  wire [2:0]         st_octave,
    input  wire [6:0]         st_vol_pct,
    input  wire [1:0]         st_expr_sel,
    input  wire [1:0]         st_expr_amt,
    input  wire [2:0]         st_fx_on,
    input  wire [1:0]         st_dly_p,
    input  wire [1:0]         st_rev_p,
    input  wire [1:0]         st_cho_p,
    input  wire [3:0]         st_key_cnt,
    input  wire [3:0]         st_voice_cnt,
    input  wire               st_g_mode,
    input  wire [2:0]         st_g_state,
    input  wire               st_g_song,
    input  wire               st_g_adv,
    input  wire [3:0]         st_g_expected,
    input  wire               st_g_wrong_active,
    input  wire [3:0]         st_g_wrong_key,
    input  wire               st_g_msg_show,
    input  wire [5:0]         st_g_step,
    input  wire [3:0]         st_g_adv_next,
    input  wire [275:0]       st_g_tiles,
    input  wire [5:0]         st_g_hits,      // 命中数
    input  wire [2:0]         st_ble_state,
    input  wire [15:0]        st_ble_ev,
    input  wire [15:0]        st_ble_rec,
    input  wire               st_tgl,
    // 频谱柱写口（音频 50 MHz 域；本模块内部用双时钟 BSRAM 跨到 pclk）
    input  wire               bar_we,
    input  wire [7:0]         bar_waddr,
    input  wire [7:0]         bar_wdata,
    input  wire               spec_tgl,       // 每写完一帧翻转一次
    output wire               tmds_clk_p_0,
    output wire               tmds_clk_n_0,
    output wire [2:0]         tmds_d_p_0,
    output wire [2:0]         tmds_d_n_0
);

    wire pclk;      // 75 MHz
    wire bclk;      // 375 MHz DDR

    Gowin_PLL u_pll (
        .lock    (),
        .clkout0 (pclk),
        .clkout1 (bclk),
        .clkin   (clk)
    );

    wire [13:0] px, py;
    wire        den, hs, vs;

    video_timing_ctrl u_timing (
        .pixel_clock      (pclk),
        .reset            (1'b0),
        .ext_sync         (1'b0),
        .timing_h_pos     (),
        .timing_v_pos     (),
        .pixel_x          (px),
        .pixel_y          (py),
        .video_vsync      (vs),
        .video_hsync      (hs),
        .video_den        (den),
        .video_line_start ()
    );

    reg [2:0] stg_s = 3'd0;
    reg [2:0] ltg_s = 3'd0;
    reg [2:0] ktg_s = 3'd0;
    reg [2:0] ptg_s = 3'd0;

    always @(posedge pclk) begin
        stg_s <= {stg_s[1:0], scope_tgl};
        ltg_s <= {ltg_s[1:0], lissa_tgl};
        ktg_s <= {ktg_s[1:0], key_tgl};
        ptg_s <= {ptg_s[1:0], spec_tgl};
    end

    wire scope_evt = stg_s[1] ^ stg_s[2];
    wire lissa_evt = ltg_s[1] ^ ltg_s[2];
    wire key_evt   = ktg_s[1] ^ ktg_s[2];
    wire spec_evt  = ptg_s[1] ^ ptg_s[2];

    reg  [7:0] spec_raddr = 8'd0;
    wire [7:0] spec_rdata;
    spec_bank_ram u_spec_ram (
        .wclk  (clk),           // 音频 50 MHz
        .we    (bar_we),
        .waddr (bar_waddr),
        .wdata (bar_wdata),
        .rclk  (pclk),
        .raddr (spec_raddr),
        .rdata (spec_rdata)
    );

    // 音频域每帧写完就翻 pub_bank；这里镜像同一位（初值 1 ⇒ 第一次事件给出 bank 0）
    reg new_bank  = 1'b1;
    reg disp_bank = 1'b0;
    always @(posedge pclk) if (spec_evt) new_bank <= ~new_bank;

    reg [7:0]  bar_mem [0:127];
    reg [15:0] bar_sm  [0:127];     // Q8 px
    reg [6:0]  ci    = 7'd0;

    reg [1:0]  cph   = 2'd0;
    reg        cbusy = 1'b0;
    reg [16:0] sm_n_r    = 17'd0;   // 打一拍的平滑值（含小数）
    reg        bar_snap_r= 1'b0;
    reg [6:0]  ci_w      = 7'd0;    // 写回用的柱号（与读地址 ci 错开一拍）
    integer bi;
    initial begin
        for (bi = 0; bi < 128; bi = bi + 1) begin
            bar_mem[bi] = 8'd0;
            bar_sm[bi]  = 16'd0;
        end
    end

    localparam [7:0]  BAR_SNAP_PX = 8'd4;
    localparam [16:0] BAR_SNAP_Q8 = {1'b0, BAR_SNAP_PX, 8'b0}; // 4 px = 1024
    wire [7:0] bar_tgt_px = (spec_rdata < BAR_SNAP_PX) ? 8'd0 : spec_rdata;

    wire signed [16:0] sm_d = $signed({1'b0, bar_tgt_px, 8'b0}) - $signed({1'b0, bar_sm[ci]});
    wire signed [16:0] sm_n = $signed({1'b0, bar_sm[ci]}) + ((sm_d + 17'sd4) >>> 3);
    wire bar_snap = (bar_tgt_px == 8'd0) && (sm_n < $signed(BAR_SNAP_Q8));

    reg [11:0] keys_r = 12'd0;
    reg        key_changed = 1'b0;

    wire key_new_press = key_evt && (|(key_snap & ~keys_r));
    reg [3:0]  bar_gate      = 4'd0;
    reg        press_pending = 1'b0;
    reg        bar_clr_f     = 1'b0;
    reg        bar_seed_f    = 1'b0;
    reg [7:0]  seed_r        = 8'd0;
    always @(posedge pclk) begin
        key_changed <= 1'b0;
        if (key_evt) begin
            if (key_snap != keys_r)
                key_changed <= 1'b1;
            keys_r <= key_snap;
        end
    end

    wire        any_key = |keys_r;

    reg [2:0] sev_s = 3'd0;
    always @(posedge pclk) sev_s <= {sev_s[1:0], snd_evt_tgl};
    wire      snd_e = sev_s[1] ^ sev_s[2];      // 翻转沿 = 一个音符事件
    wire      chg   = key_changed | snd_e;

    reg [231:0] gline_st       = 232'd0;
    reg [175:0] gline2_st      = 176'd0;   // row 32
    reg [175:0] gline3_st      = 176'd0;   // row 34
    // 蓝牙状态三行（同上）
    reg [127:0] ble1_st        = 128'd0;
    reg [127:0] ble2_st        = 128'd0;
    reg [127:0] ble3_st        = 128'd0;

    // fx_any 来自音频域（fx.v 的 fx_sel），进 pclk 域必须先两级同步再用
    reg  [1:0]  fx_s = 2'd0;
    always @(posedge pclk) fx_s <= {fx_s[0], fx_any};
    wire        fx_any_s = fx_s[1];

    reg  [1:0]  snd_s = 2'd0;
    always @(posedge pclk) snd_s <= {snd_s[0], snd_on};
    wire        snd_on_s = snd_s[1];

    reg  [1:0]  aud_s = 2'd0;
    always @(posedge pclk) aud_s <= {aud_s[0], aud_on};
    wire        aud_on_s = aud_s[1];

    wire        draw_on  = any_key | fx_any_s | snd_on_s | aud_on_s;

    localparam [9:0] RING_LAST = 10'd1023;
    localparam [9:0] PRE       = 10'd268;   // 256 居中 + 12 低通群延迟补偿（C4 实测最优 ~15）
    localparam [9:0] WIN_LAST  = 10'd511;

    reg [9:0] scope_mem [0:3071];       // 3 banks x 1024 x 10（屏幕 Y 坐标）
    reg [9:0] wr_ptr    = 10'd0;
    reg [1:0] wr_bank   = 2'd0;
    reg [1:0] full_bank = 2'd0;
    reg [1:0] rd_bank   = 2'd0;
    reg [9:0] rd_start  = 10'd0;
    reg [9:0] bank_start0 = 10'd0, bank_start1 = 10'd0, bank_start2 = 10'd0;
    reg [9:0] win_start = 10'd0;
    reg [9:0] win_end   = 10'd0;
    reg       filling   = 1'b0;
    reg       have_data = 1'b0;
    reg [9:0] prefill   = 10'd0;
    reg [12:0] idle_cnt = 13'd0;   // 静音自由运行超时：8191 采样 ≈168 ms

    reg [12:0] idle_max = 13'd8191;
    always @(posedge pclk) idle_max <= (!any_key && fx_any_s) ? 13'd1023 : 13'd8191;

    // 写 bank 正在显示时暂停环形写入（上电第一窗例外）
    wire ring_ok = !have_data || (wr_bank != rd_bank);

    wire [9:0] trig_start = wr_ptr - PRE;
    wire [9:0] trig_end   = trig_start + WIN_LAST;

    // 帧同步：vsync 上升沿锁存“最近完成的一窗”
    reg vs0 = 1'b0, vs0_d = 1'b0;
    always @(posedge pclk) begin
        vs0   <= vs;
        vs0_d <= vs0;
    end
    wire vs_rise = vs0 & ~vs0_d;

    reg [7:0] win_seq         = 8'd0;
    reg [7:0] win_seq_key     = 8'd0;
    reg       sb_seed_pending = 1'b0;
    reg       sb_byp          = 1'b0;
    always @(posedge pclk) begin
        if (chg) begin
            win_seq_key     <= win_seq;
            sb_seed_pending <= 1'b1;
        end
        if (vs_rise) begin
            if (sb_seed_pending && (win_seq != win_seq_key)) begin
                sb_byp          <= 1'b1;
                sb_seed_pending <= 1'b0;
            end else begin
                sb_byp <= 1'b0;
            end
        end
    end

    always @(posedge pclk) begin
        if (key_new_press)
            press_pending <= 1'b1;

        if (vs_rise) begin
            disp_bank  <= new_bank;
            cbusy      <= 1'b1;
            cph        <= 2'd0;
            ci         <= 7'd0;
            spec_raddr <= {new_bank, 7'd0};
            // 起音屏蔽窗：只屏蔽 1 帧
            if (press_pending) begin
                bar_gate      <= 4'd1;
                press_pending <= 1'b0;
                bar_clr_f     <= 1'b1;
                bar_seed_f    <= 1'b0;
            end else begin
                bar_clr_f  <= (bar_gate != 4'd0);
                if (bar_gate != 4'd0) begin
                    bar_seed_f <= (bar_gate == 4'd1);
                    bar_gate   <= bar_gate - 1'b1;
                end
            end
        end else if (cbusy) begin
            if (cph == 2'd0) begin
                cph <= 2'd1;                        // 同步读：数据下一拍到
            end else if (cph == 2'd1) begin
                // 只做算术并寄存：把 RAM 写口留到下一拍
                sm_n_r     <= sm_n;
                seed_r     <= bar_tgt_px;
                bar_snap_r <= bar_snap;
                ci_w       <= ci;
                cph        <= 2'd2;
            end else begin
                if (bar_clr_f) begin
                    bar_sm[ci_w]  <= 16'd0;
                    bar_mem[ci_w] <= 8'd0;
                end else if (bar_seed_f) begin
                    bar_sm[ci_w]  <= {seed_r, 8'b0};
                    bar_mem[ci_w] <= seed_r;
                end else if (bar_snap_r) begin
                    bar_sm[ci_w]  <= 16'd0;
                    bar_mem[ci_w] <= 8'd0;
                end else begin
                    bar_sm[ci_w]  <= sm_n_r[15:0];
                    bar_mem[ci_w] <= sm_n_r[15:8];
                end
                if (ci == 7'd127) begin
                    cbusy <= 1'b0;
                    if (!bar_clr_f) bar_seed_f <= 1'b0;
                end else begin
                    ci         <= ci + 1'b1;
                    cph        <= 2'd0;
                    spec_raddr <= {new_bank, ci + 1'b1};
                end
            end
        end
    end

    wire [9:0] full_start = (full_bank == 2'd0) ? bank_start0 :
                            (full_bank == 2'd1) ? bank_start1 : bank_start2;

    always @(posedge pclk) if (vs_rise) begin
        rd_bank  <= full_bank;
        rd_start <= full_start;
    end

    always @(posedge pclk) begin
        if (chg) begin
            filling  <= 1'b0;       // 换键：中止正在进行的窗口

            idle_cnt <= 13'd0;
        end

        if (scope_evt) begin

            if (ring_ok) begin
                scope_mem[{wr_bank, wr_ptr}] <= scope_y;
                wr_ptr <= (wr_ptr == RING_LAST) ? 10'd0 : (wr_ptr + 1'b1);
                if (prefill != RING_LAST)
                    prefill <= prefill + 1'b1;
            end

            if (!ring_ok) begin
                filling <= 1'b0;
                prefill <= 10'd0;
            end else

            if (filling && (wr_ptr == win_end)) begin
                filling   <= 1'b0;
                have_data <= 1'b1;
                win_seq   <= win_seq + 1'b1;
                full_bank <= wr_bank;
                case (wr_bank)
                    2'd0:    bank_start0 <= win_start;
                    2'd1:    bank_start1 <= win_start;
                    default: bank_start2 <= win_start;
                endcase
                // 换下一 bank，从 0 重新积累预触发历史
                wr_bank <= (wr_bank == 2'd2) ? 2'd0 : (wr_bank + 1'b1);
                wr_ptr  <= 10'd0;
                prefill <= 10'd0;
                idle_cnt <= 13'd0;

            end else if (!filling && ring_ok && (prefill >= PRE)) begin
                if (scope_trig) begin
                    // 触发：窗口围绕低通过零点展开（过零点固定落在窗内第 256 点）
                    win_start <= trig_start;
                    win_end   <= trig_end;
                    filling   <= 1'b1;
                    idle_cnt  <= 13'd0;
                end else if (idle_cnt == idle_max) begin

                    win_start <= trig_start;
                    win_end   <= trig_end;
                    filling   <= 1'b1;
                    idle_cnt  <= 13'd0;
                end else
                    idle_cnt <= idle_cnt + 1'b1;
            end
        end
    end

    localparam integer DISP_LAST = 1023;
    reg [13:0] scope_disp [0:1031];   // Y 10.4 定点（亚像素抗锯齿）

    reg [16:0] disp_acc [0:1023];      // Q8；1K×18 可映射成一块 BSRAM

    localparam integer FAST_N = 32;    // 换键后保持快系数的帧数（≈528 ms @60.6 Hz）
    reg [5:0] fast_win = 6'd0;
    always @(posedge pclk) begin
        if (chg)
            fast_win <= 6'd32;
        else if (vs_rise && (fast_win != 6'd0))
            fast_win <= fast_win - 1'b1;
    end
    wire use_fast = !poly || (fast_win != 6'd0);

    reg [3:0]  sb_st   = 4'd0;         // 0..12（12 拍/像素）
    reg [10:0] sb_bx   = 11'd0;
    reg [9:0]  sb_a    = 10'd0;
    reg [9:0]  sb_b    = 10'd0;
    reg [5:0]  sb_frac = 6'd0;
    reg [9:0]  sb_addr = 10'd0;
    reg [9:0]  sb_rd   = 10'd0;
    reg [13:0] sb_y4   = 14'd0;
    reg [16:0] sb_wq8  = 17'd0;   // 余辉结果（Q8）→ disp_acc
    reg [13:0] sb_wval = 14'd0;   // 同一结果的 Q4 舍入值 → scope_disp
    reg signed [19:0] sb_prod_r = 20'sd0;   // 乘法单独打一拍（pclk 关键路径）
    reg [16:0] sb_old = 17'd0;              // disp_acc 上一帧同列的值（Q8）

    reg [10:0] acc_raddr = 11'd0;

    reg  signed [17:0] sb_diff_r = 18'sd0;
    wire signed [17:0] sb_new_q8 = $signed({sb_y4, 4'b0000});   // Q4 → Q8
    wire signed [17:0] sb_old_q8 = $signed({1'b0, sb_old});
    wire signed [17:0] sb_diff   = sb_new_q8 - sb_old_q8;

    wire sb_seed = (!poly) | sb_byp;
    wire signed [17:0] sb_step   = sb_seed   ? sb_diff_r :
                                   use_fast  ? (sb_diff_r >>> 4) : (sb_diff_r >>> 6);
    wire signed [17:0] sb_blend  = sb_old_q8 + sb_step;
    // 先钳位（有符号常数！），再舍入到 Q4；720p：8..270 px
    wire [16:0] sb_blend_u = (sb_blend < 18'sd2048)  ? 17'd2048  :   //   8 px
                             (sb_blend > 18'sd69120) ? 17'd69120 : sb_blend[16:0];  // 270 px
    wire [13:0] sb_wval_q4 = (sb_blend_u + 17'd8) >> 4;   // 四舍五入，最大 4320

    wire [15:0] sb_pos  = {5'd0, sb_bx} << 5;
    wire [9:0]  sb_idx  = sb_pos[15:6];
    wire [9:0]  sb_idxb = (sb_idx == 10'd511) ? 10'd511 : (sb_idx + 1'b1);

    // 插值（在乘法那一拍寄存，避免长组合路径进 RAM 写口）
    wire signed [12:0] sb_delta = $signed({3'b000, sb_b}) - $signed({3'b000, sb_a});
    wire signed [19:0] sb_a4    = {6'b000000, sb_a, 4'b0000};        // A<<4
    wire signed [19:0] sb_mix4  = sb_a4 + (sb_prod_r >>> 2);          // 1/16 px

    always @(posedge pclk) begin
        sb_rd <= scope_mem[{rd_bank, sb_addr}];

        if (vs_rise) begin
            // 新的窗口已在上面锁存进 rd_bank/rd_start，从下一拍开始重建
            sb_st <= 4'd1;
            sb_bx <= 11'd0;
        end else case (sb_st)
            4'd1: begin
                sb_frac   <= sb_pos[5:0];
                acc_raddr <= sb_bx;                         // 读上一帧同列
                sb_addr   <= (rd_start + sb_idx) & 10'h3FF; // A
                sb_st     <= 4'd2;
            end
            4'd2: sb_st <= 4'd3;                            // 等 A 的 RAM 数据
            4'd3: begin
                sb_old    <= disp_acc[acc_raddr];           // 旧值（同列）
                acc_raddr <= (sb_bx == DISP_LAST) ? 11'd0 : (sb_bx + 1'b1);  // 错开
                sb_st     <= 4'd4;                          // 等 A（再 1 拍，冗余）
            end
            4'd4: begin
                sb_a    <= sb_rd;                           // mem[A]
                sb_addr <= (rd_start + sb_idxb) & 10'h3FF;  // B（idx=511 时 B=A）
                sb_st   <= 4'd5;
            end
            4'd5: sb_st <= 4'd6;                            // 等 B 的 RAM 数据
            4'd6: sb_st <= 4'd7;                            // 等 B（再 1 拍，冗余）
            4'd7: begin
                sb_b  <= sb_rd;                             // mem[B]
                sb_st <= 4'd8;
            end
            4'd8: begin
                sb_prod_r <= sb_delta * $signed({1'b0, sb_frac});   // 只做乘法
                sb_st     <= 4'd9;
            end
            4'd9: begin

                sb_y4 <= (sb_mix4 < 20'sd128)  ? 14'd128  :
                         (sb_mix4 > 20'sd4320) ? 14'd4320 : sb_mix4[13:0];
                sb_st <= 4'd10;
            end
            4'd10: begin
                sb_diff_r <= sb_diff;           // 只做减法（18 位）
                sb_st     <= 4'd11;
            end
            4'd11: begin
                sb_wq8  <= sb_blend_u;          // 移位/mux/加/钳位
                sb_wval <= sb_wval_q4;          // 再舍入到 Q4
                sb_st   <= 4'd12;
            end
            4'd12: begin
                disp_acc[sb_bx]   <= sb_wq8;    // 余辉累加（Q8）
                scope_disp[sb_bx] <= sb_wval;   // 本帧显示值（Q4）
                if (sb_bx == DISP_LAST)
                    sb_st <= 4'd0;              // 等下一个 vsync
                else begin
                    sb_bx <= sb_bx + 1'b1;
                    sb_st <= 4'd1;
                end
            end
            default: sb_st <= 4'd0;
        endcase
    end

    reg [7:0] lissa_mem [0:8191];

    function [7:0] map8;
        input signed [15:0] v;
        reg signed [15:0] t;
        begin
            t = v >>> 6;                // 李萨如输入已两级低通（幅度约剩 1/3）
            // 边缘留 2 格：大信号只贴内边，不会落在 0/255 上引 DDA 端点翻绕
            if (t > 125) t = 125;
            else if (t < -126) t = -126;
            map8 = t[7:0] ^ 8'h80;      // +128，等价于翻转符号位
        end
    endfunction

    localparam LISSA_TEST_CIRCLE = 1'b0;   // 诊断开关：正常为 0
    localparam LISSA_YEQX = 1'b0;          // 诊断开关：正常为 0
    reg [5:0] tst_ph = 6'd0;
    always @(posedge pclk) if (lissa_evt) tst_ph <= tst_ph + 1'b1;

    function [7:0] circ8;
        input [5:0] p;
        reg signed [8:0] v;
        begin
            case (p)
              6'd0 : v = 9'sd0;
              6'd1 : v = 9'sd6;
              6'd2 : v = 9'sd12;
              6'd3 : v = 9'sd18;
              6'd4 : v = 9'sd24;
              6'd5 : v = 9'sd30;
              6'd6 : v = 9'sd35;
              6'd7 : v = 9'sd40;
              6'd8 : v = 9'sd45;
              6'd9 : v = 9'sd49;
              6'd10: v = 9'sd52;
              6'd11: v = 9'sd56;
              6'd12: v = 9'sd58;
              6'd13: v = 9'sd60;
              6'd14: v = 9'sd62;
              6'd15: v = 9'sd63;
              6'd16: v = 9'sd63;
              6'd17: v = 9'sd63;
              6'd18: v = 9'sd62;
              6'd19: v = 9'sd60;
              6'd20: v = 9'sd58;
              6'd21: v = 9'sd56;
              6'd22: v = 9'sd52;
              6'd23: v = 9'sd49;
              6'd24: v = 9'sd45;
              6'd25: v = 9'sd40;
              6'd26: v = 9'sd35;
              6'd27: v = 9'sd30;
              6'd28: v = 9'sd24;
              6'd29: v = 9'sd18;
              6'd30: v = 9'sd12;
              6'd31: v = 9'sd6;
              6'd32: v = 9'sd0;
              6'd33: v = -9'sd6;
              6'd34: v = -9'sd12;
              6'd35: v = -9'sd18;
              6'd36: v = -9'sd24;
              6'd37: v = -9'sd30;
              6'd38: v = -9'sd35;
              6'd39: v = -9'sd40;
              6'd40: v = -9'sd45;
              6'd41: v = -9'sd49;
              6'd42: v = -9'sd52;
              6'd43: v = -9'sd56;
              6'd44: v = -9'sd58;
              6'd45: v = -9'sd60;
              6'd46: v = -9'sd62;
              6'd47: v = -9'sd63;
              6'd48: v = -9'sd63;
              6'd49: v = -9'sd63;
              6'd50: v = -9'sd62;
              6'd51: v = -9'sd60;
              6'd52: v = -9'sd58;
              6'd53: v = -9'sd56;
              6'd54: v = -9'sd52;
              6'd55: v = -9'sd49;
              6'd56: v = -9'sd45;
              6'd57: v = -9'sd40;
              6'd58: v = -9'sd35;
              6'd59: v = -9'sd30;
              6'd60: v = -9'sd24;
              6'd61: v = -9'sd18;
              6'd62: v = -9'sd12;
              6'd63: v = -9'sd6;
              default: v = 9'sd0;
            endcase
            circ8 = 8'd128 + v[7:0];
        end
    endfunction

    wire        poly_l = |(keys_r & (keys_r - 12'd1));
    wire signed [15:0] lx_l = poly_l ? (lissa_x - (lissa_x >>> 2)) : lissa_x;
    wire signed [15:0] ly_l = poly_l ? (lissa_y - (lissa_y >>> 2)) : lissa_y;

    wire [7:0] pt_x8 = LISSA_TEST_CIRCLE ? circ8(tst_ph)      : map8(lx_l);
    wire [7:0] pt_y8 = LISSA_TEST_CIRCLE ? circ8(tst_ph + 6'd16) :
                       LISSA_YEQX         ? pt_x8                 : map8(ly_l);

    reg [12:0] warm = 13'd8191;

    reg draw_ok = 1'b0;
    always @(posedge pclk) draw_ok <= draw_on;
    wire lissa_draw_en = LISSA_TEST_CIRCLE ? 1'b1 : (draw_ok && (warm == 13'd0));

    reg        clr_start  = 1'b0;
    reg        clr_busy   = 1'b0;
    reg        clr_busy_d = 1'b0;
    reg [12:0] clr_addr   = 13'd0;

    always @(posedge pclk) begin
        if (clr_start && !clr_busy) begin
            clr_busy <= 1'b1;
            clr_addr <= 13'd0;
        end else if (clr_busy) begin
            if (clr_addr == 13'd8191)
                clr_busy <= 1'b0;
            else
                clr_addr <= clr_addr + 1'b1;
        end
    end

    always @(posedge pclk) begin

        if (vs_rise)
            clr_start <= 1'b1;
        else
            clr_start <= 1'b0;

        if (chg)
            warm <= 13'd8191;                       // 换键：跳过起音瞬态（≈42 ms）

        else if (lissa_evt && draw_ok && (warm != 13'd0))
            warm <= warm - 1'b1;
    end

    reg [2:0]  pst   = 3'd0;
    reg        pend  = 1'b0;
    reg [7:0]  tgt_x = 8'd128, tgt_y = 8'd128;
    reg [7:0]  seg_x = 8'd128, seg_y = 8'd128;
    reg [7:0]  prv_x = 8'd128, prv_y = 8'd128;
    reg [7:0]  cur_x = 8'd128, cur_y = 8'd128;
    reg [8:0]  adx = 9'd0, ady = 9'd0, ex = 9'd0, ey = 9'd0;
    reg [8:0]  rem = 9'd0, st_max = 9'd0;
    reg        sx = 1'b1, sy = 1'b1;
    reg        prev_valid = 1'b0;       // prv_x/prv_y 是否有效（清屏/停画后置 0）
    reg        draw_en_d  = 1'b0;
    reg [12:0] pt_addr = 13'd0;
    reg [2:0]  pt_bit  = 3'd0;

    // 不再需要 42 ms 暖机：起音瞬态（Y 延迟线里的旧音 + 直流跟踪器的台阶）
    // 已经由 100 ms 的 settle 覆盖（8~15 倍于原来的 42 ms）。
    wire warming = 1'b0;

    reg [12:0] lissa_paddr = 13'd0;
    reg [7:0]  lissa_pdata;
    reg        lissa_we = 1'b0;
    reg [12:0] lissa_waddr = 13'd0;
    reg [7:0]  lissa_wdata = 8'd0;

    // DDA 的增量（与面板映射无关）
    wire [7:0] ldx8 = (tgt_x >= prv_x) ? (tgt_x - prv_x) : (prv_x - tgt_x);
    wire [7:0] ldy8 = (tgt_y >= prv_y) ? (tgt_y - prv_y) : (prv_y - tgt_y);
    wire [8:0] ldx9 = {1'b0, ldx8};
    wire [8:0] ldy9 = {1'b0, ldy8};
    wire [8:0] lstep = (ldx9 > ldy9) ? ldx9 : ldy9;

    always @(posedge pclk) begin
        lissa_we <= 1'b0;
        clr_busy_d <= clr_busy;
        draw_en_d <= lissa_draw_en;

        // 起点失效：清屏完成、停止绘制、按键变化 —— 下一个点只定位不画线
        if (!lissa_draw_en || chg)
            prev_valid <= 1'b0;
        if (clr_busy_d && !clr_busy)
            prev_valid <= 1'b0;

        // 采样点锁存（只在允许画的阶段）
        if (lissa_evt && lissa_draw_en && !warming) begin
            tgt_x <= pt_x8;
            tgt_y <= pt_y8;
            pend  <= 1'b1;
        end

        // 清屏期间冻结 DDA：否则清屏开始前读出的旧像素会在清屏结束后
        // 被"读-改-写"重新写回去，每帧留下几颗残点（看着像毛刺）。
        if (clr_busy) begin
            pst  <= 3'd0;
            pend <= 1'b0;
        end else
        case (pst)
        3'd0: begin
            if (pend && lissa_draw_en && !warming && !clr_busy && !chg) begin
                if (!prev_valid) begin

                    prv_x      <= tgt_x;
                    prv_y      <= tgt_y;
                    prev_valid <= 1'b1;
                    pend       <= 1'b0;
                end else begin
                    seg_x <= tgt_x;
                    seg_y <= tgt_y;
                    if (lstep == 9'd0) begin
                        pend  <= 1'b0;
                        prv_x <= tgt_x;
                        prv_y <= tgt_y;
                    end else begin
                        pend   <= 1'b0;
                        adx    <= ldx9;
                        ady    <= ldy9;
                        st_max <= lstep;
                        rem    <= lstep;
                        sx     <= (tgt_x >= prv_x);
                        sy     <= (tgt_y >= prv_y);
                        ex     <= 9'd0;
                        ey     <= 9'd0;
                        cur_x  <= prv_x;
                        cur_y  <= prv_y;
                        pst    <= 3'd1;
                    end
                end
            end
        end
        3'd1: begin
            lissa_paddr <= {cur_y, cur_x[7:3]};
            pt_addr     <= {cur_y, cur_x[7:3]};
            pt_bit      <= cur_x[2:0];
            pst <= 3'd2;
        end
        3'd2: pst <= 3'd3;                       // 等 RAM 读出
        3'd3: begin
            lissa_waddr <= pt_addr;
            lissa_wdata <= lissa_pdata | (8'b1 << pt_bit);
            lissa_we    <= 1'b1;
            pst <= 3'd4;
        end
        3'd4: begin
            if (rem == 9'd0) begin
                prv_x <= seg_x;
                prv_y <= seg_y;
                pst   <= 3'd0;
            end else begin
                rem <= rem - 1'b1;

                if ({1'b0, ex} + {1'b0, adx} >= st_max) begin
                    ex    <= {1'b0, ex} + {1'b0, adx} - st_max;
                    // 只朝线段终点走，绝不超过/翻绕（0−1→255 会画贯穿竖线）
                    if (cur_x != seg_x)
                        cur_x <= (cur_x < seg_x) ? (cur_x + 1'b1) : (cur_x - 1'b1);
                end else
                    ex <= ex + adx;
                if ({1'b0, ey} + {1'b0, ady} >= st_max) begin
                    ey    <= {1'b0, ey} + {1'b0, ady} - st_max;
                    if (cur_y != seg_y)
                        cur_y <= (cur_y < seg_y) ? (cur_y + 1'b1) : (cur_y - 1'b1);
                end else
                    ey <= ey + ady;
                pst <= 3'd1;
            end
        end
        default: pst <= 3'd0;
        endcase
    end

    wire        lissa_we_final    = clr_busy | lissa_we;
    wire [12:0] lissa_waddr_final = clr_busy ? clr_addr : lissa_waddr;
    wire [7:0]  lissa_wdata_final = clr_busy ? 8'd0 : lissa_wdata;

    // 显示读地址（stage 1 用 x0/y0 算，stage 2 出数据）
    reg [12:0] lissa_raddr;
    reg [2:0]  lissa_bit1, lissa_bit2;
    reg [7:0]  lissa_rdata;

    reg [13:0] x0, y0;              // stage 0 坐标（提前声明，供李萨如地址用）

    reg [7:0]  lx_cell = 8'd0;
    reg [7:0]  ly_cell = 8'd0;
    reg [13:0] py_prev = 14'd0;

    always @(posedge pclk) begin
        lissa_rdata <= lissa_mem[lissa_raddr];
        lissa_pdata <= lissa_mem[lissa_paddr];
        if (lissa_we_final)
            lissa_mem[lissa_waddr_final] <= lissa_wdata_final;
    end

    reg [13:0] tx1 = 14'd0, ty1 = 14'd0;
    reg [13:0] tx2 = 14'd0, ty2 = 14'd0;
    reg [13:0] tx3 = 14'd0, ty3 = 14'd0;
    reg [13:0] tx4 = 14'd0, ty4 = 14'd0;

    reg [13:0] tx5 = 14'd0, ty5 = 14'd0;
    reg [12:0] label_raddr = 13'd0;
    reg [9:0]  font_raddr  = 10'd0;
    wire [7:0] label_dout;
    wire [7:0] font_dout;

    label_rom u_label_rom (
        .clk  (pclk),
        .addr (label_raddr),
        .dout (label_dout)
    );

    font_rom u_font_rom (
        .clk  (pclk),
        .addr (font_raddr),
        .dout (font_dout)
    );

    wire [7:0] tcx1 = tx1[13:3];
    wire [5:0] tcy1 = (ty1 >= 14'd8) ? ((ty1 - 14'd8) >> 4) : 6'd0;
    wire [12:0] taddr1 = {tcy1, 7'd0} + {2'd0, tcy1, 5'd0} + {5'd0, tcx1};

    wire [7:0] tcx2 = tx2[13:3];
    wire [5:0] tcy2 = (ty2 >= 14'd8) ? ((ty2 - 14'd8) >> 4) : 6'd0;
    wire [7:0] dyn_ch2;
    wire       dyn_sel2;
    reg  [7:0] dyn_ch3 = 8'd0;
    reg        dyn_sel3 = 1'b0;

    wire [7:0] vol_ch_h, vol_ch_t, vol_ch_o;
    vol_bcd u_vol_bcd (
        .clk   (clk),
        .v     (st_vol_pct),
        .ch_h  (vol_ch_h),
        .ch_t  (vol_ch_t),
        .ch_o  (vol_ch_o)
    );

    text_dyn u_text_dyn (
        .row        (tcy2),
        .col        (tcx2),
        .timbre     (st_timbre),
        .octave     (st_octave),
        .vol_h      (vol_ch_h),
        .vol_t      (vol_ch_t),
        .vol_o      (vol_ch_o),
        .expr_sel   (st_expr_sel),
        .expr_amt   (st_expr_amt),
        .fx_on      (st_fx_on),
        .dly_p      (st_dly_p),
        .rev_p      (st_rev_p),
        .cho_p      (st_cho_p),
        .key_cnt    (st_key_cnt),
        .voice_cnt  (st_voice_cnt),
        .ch         (dyn_ch2),
        .sel        (dyn_sel2)
    );

    wire [231:0] gline_now;
    wire [175:0] gline2_now, gline3_now;
    guide_line u_guide_line (
        .g_state       (st_g_state),
        .g_song        (st_g_song),
        .g_adv         (st_g_adv),
        .g_expected    (st_g_expected),
        .g_wrong_active(st_g_wrong_active),
        .g_msg_show    (st_g_msg_show),
        .g_step        (st_g_step),
        .g_adv_next    (st_g_adv_next),
        .g_hits        (st_g_hits),
        .octave        (st_octave),
        .line          (gline_now),
        .line2         (gline2_now),
        .line3         (gline3_now)
    );

    wire [127:0] ble1_now, ble2_now, ble3_now;
    wire [15:0]  ble_ev_bcd, ble_rec_bcd;

    bcd_fsm u_ble_bcd (
        .clk  (clk),
        .v0   (st_ble_ev),
        .v1   (st_ble_rec),
        .bcd0 (ble_ev_bcd),
        .bcd1 (ble_rec_bcd)
    );
    ble_line u_ble_line (
        .state     (st_ble_state),
        .ev_bcd    (ble_ev_bcd),
        .rec_bcd   (ble_rec_bcd),
        .line1     (ble1_now),
        .line2     (ble2_now),
        .line3     (ble3_now)
    );

    always @(posedge clk) begin
        ble1_st   <= ble1_now;
        ble2_st   <= ble2_now;
        ble3_st   <= ble3_now;
        gline_st  <= gline_now;
        gline2_st <= gline2_now;
        gline3_st <= gline3_now;
    end

    wire [7:0] g_ch1;
    wire       g_sel1;
    reg  [7:0] g_ch2 = 8'd0;
    reg        g_sel2 = 1'b0;
    reg  [7:0] g_ch3 = 8'd0;
    reg        g_sel3 = 1'b0;

    guide_text u_guide_text (
        .row        (tcy1),
        .col        (tcx1),
        .g_state    (st_g_state),
        .g_song     (st_g_song),
        .line       (gline_st),
        .line2      (gline2_st),
        .line3      (gline3_st),
        .ch         (g_ch1),
        .sel        (g_sel1)
    );

    wire [7:0] ble_ch1;
    wire       ble_sel1;
    reg  [7:0] ble_ch2 = 8'd0, ble_ch3 = 8'd0;
    reg        ble_sel2 = 1'b0, ble_sel3 = 1'b0;

    ble_text u_ble_text (
        .row   (tcy1),
        .col   (tcx1),
        .line1 (ble1_st),
        .line2 (ble2_st),
        .line3 (ble3_st),
        .ch    (ble_ch1),
        .sel   (ble_sel1)
    );

    wire [7:0] txt_ch3   = ble_sel3 ? ble_ch3 :
                           (g_sel3 ? g_ch3 :
                           (dyn_sel3 ? dyn_ch3 : label_dout));
    wire [3:0] txt_row3  = ty3[3:0] - 4'd8;      // y=8..23 -> 0..15（模 16 回绕）

    wire [5:0] txt_code3 = txt_ch3[5:0] - 6'd32;
    wire [9:0] font_addr3= {txt_code3, txt_row3};

    // font_dout bit7 = 最左像素
    function [0:0] font_bit;
        input [7:0] b;
        input [2:0] i;
        begin font_bit = b[3'd7 - i]; end
    endfunction

    wire txt_px3 = (ty5 >= 14'd8) && font_bit(font_dout, tx5[2:0]);

    always @(posedge pclk) begin
        tx1 <= px;  ty1 <= py;
        tx2 <= tx1; ty2 <= ty1;
        tx3 <= tx2; ty3 <= ty2;
        tx4 <= tx3; ty4 <= ty3;
        tx5 <= tx4; ty5 <= ty4;
        dyn_ch3  <= dyn_ch2;      // 与 tx3 <= tx2 同沿；对齐 label_dout
        dyn_sel3 <= dyn_sel2;
        ble_ch2  <= ble_ch1;      // 蓝牙状态：tx1 算，打两拍对齐 tx3
        ble_sel2 <= ble_sel1;
        ble_ch3  <= ble_ch2;
        ble_sel3 <= ble_sel2;
        g_ch2    <= g_ch1;        // GUIDE 文字：tx1 算，打两拍对齐 tx3
        g_sel2   <= g_sel1;
        g_ch3    <= g_ch2;
        g_sel3   <= g_sel2;
        label_raddr <= taddr1;
        font_raddr  <= font_addr3;
    end

    reg        den0, hs0, vs0_r;
    reg [10:0] scope_disp_raddr;
    reg [13:0] scope_rdata;
    reg [6:0]  bar_raddr;          // 频谱柱号（0..127）
    reg [7:0]  bar_rdata;

    always @(posedge pclk) begin
        x0    <= px;
        y0    <= py;
        den0  <= den;
        hs0   <= hs;
        vs0_r <= vs;
        py_prev <= py;

        // X：面板 x 208..463 与点阵 256 列 1:1（每像素进一格）
        if (px == 14'd208)
            lx_cell <= 8'd0;
        else if (px > 14'd208 && px < 14'd464)
            lx_cell <= lx_cell + 1'b1;

        // Y：面板 y 460..715 与点阵 256 行 1:1（每行进一格）
        if (py == 14'd460)
            ly_cell <= 8'd0;
        else if (py != py_prev && py > 14'd460 && py < 14'd716)
            ly_cell <= ly_cell + 1'b1;
    end

    // stage 1：读地址
    reg [13:0] x1, y1;
    reg        den1, hs1, vs1;
    always @(posedge pclk) begin
        x1 <= x0;
        y1 <= y0;
        den1 <= den0;
        hs1 <= hs0;
        vs1 <= vs0_r;
        // 显示缓冲读地址：x 226..1249 → 0..1023
        if (px >= 14'd226 && px < 14'd1250)
            scope_disp_raddr <= px[10:0] - 11'd226;

        if (px >= 14'd224 && px < 14'd1248)
            bar_raddr <= (px[10:0] - 11'd224) >> 3;
        lissa_raddr <= {ly_cell, lx_cell[7:3]};
        lissa_bit1  <= lx_cell[2:0];
    end

    // stage 2：RAM 数据
    reg [13:0] x2, y2;
    reg        den2, hs2, vs2;
    always @(posedge pclk) begin
        x2 <= x1;
        y2 <= y1;
        den2 <= den1;
        hs2 <= hs1;
        vs2 <= vs1;
        scope_rdata <= scope_disp[scope_disp_raddr];
        bar_rdata   <= bar_mem[bar_raddr];
        lissa_bit2  <= lissa_bit1;
    end

    wire in_wave  = (x2 >= 14'd208) && (x2 < 14'd1268) && (y2 >= 14'd6)   && (y2 < 14'd272);
    wire in_spec  = (x2 >= 14'd208) && (x2 < 14'd1268) && (y2 >= 14'd280) && (y2 < 14'd452);
    wire in_lissa = (x2 >= 14'd208) && (x2 < 14'd464)  && (y2 >= 14'd460) && (y2 < 14'd716);
    wire in_guide = (x2 >= 14'd472) && (x2 < 14'd1268) && (y2 >= 14'd460) && (y2 < 14'd716);
    wire in_left  = (x2 < 14'd208);
    wire in_param = (x2 >= 14'd12)  && (x2 < 14'd196)  && (y2 >= 14'd72)  && (y2 < 14'd200);
    wire in_kb    = (x2 >= 14'd12)  && (x2 < 14'd196)  && (y2 >= 14'd212) && (y2 < 14'd292);

    wire bd_wave =
        (x2 >= 14'd208  && x2 < 14'd210  && y2 >= 14'd6   && y2 < 14'd272) ||
        (x2 >= 14'd1266 && x2 < 14'd1268 && y2 >= 14'd6   && y2 < 14'd272) ||
        (x2 >= 14'd208  && x2 < 14'd1268 && y2 >= 14'd6   && y2 < 14'd8)   ||
        (x2 >= 14'd208  && x2 < 14'd1268 && y2 >= 14'd270 && y2 < 14'd272);
    wire bd_spec =
        (x2 >= 14'd208  && x2 < 14'd210  && y2 >= 14'd280 && y2 < 14'd452) ||
        (x2 >= 14'd1266 && x2 < 14'd1268 && y2 >= 14'd280 && y2 < 14'd452) ||
        (x2 >= 14'd208  && x2 < 14'd1268 && y2 >= 14'd280 && y2 < 14'd282) ||
        (x2 >= 14'd208  && x2 < 14'd1268 && y2 >= 14'd450 && y2 < 14'd452);
    wire bd_lissa =
        (x2 >= 14'd208 && x2 < 14'd210 && y2 >= 14'd460 && y2 < 14'd716) ||
        (x2 >= 14'd462 && x2 < 14'd464 && y2 >= 14'd460 && y2 < 14'd716) ||
        (x2 >= 14'd208 && x2 < 14'd464 && y2 >= 14'd460 && y2 < 14'd462) ||
        (x2 >= 14'd208 && x2 < 14'd464 && y2 >= 14'd714 && y2 < 14'd716);
    wire bd_guide =
        (x2 >= 14'd472  && x2 < 14'd474  && y2 >= 14'd460 && y2 < 14'd716) ||
        (x2 >= 14'd1266 && x2 < 14'd1268 && y2 >= 14'd460 && y2 < 14'd716) ||
        (x2 >= 14'd472  && x2 < 14'd1268 && y2 >= 14'd460 && y2 < 14'd462) ||
        (x2 >= 14'd472  && x2 < 14'd1268 && y2 >= 14'd714 && y2 < 14'd716);
    wire bd_param =
        (x2 >= 14'd12 && x2 < 14'd14  && y2 >= 14'd72  && y2 < 14'd200) ||
        (x2 >= 14'd194 && x2 < 14'd196 && y2 >= 14'd72  && y2 < 14'd200) ||
        (x2 >= 14'd12 && x2 < 14'd196 && y2 >= 14'd72  && y2 < 14'd74)  ||
        (x2 >= 14'd12 && x2 < 14'd196 && y2 >= 14'd198 && y2 < 14'd200);
    wire bd_kb =
        (x2 >= 14'd12 && x2 < 14'd14  && y2 >= 14'd212 && y2 < 14'd292) ||
        (x2 >= 14'd194 && x2 < 14'd196 && y2 >= 14'd212 && y2 < 14'd292) ||
        (x2 >= 14'd12 && x2 < 14'd196 && y2 >= 14'd212 && y2 < 14'd214) ||
        (x2 >= 14'd12 && x2 < 14'd196 && y2 >= 14'd290 && y2 < 14'd292);
    wire bd_left  = (x2 == 14'd206) || (x2 == 14'd207);

    // 网格：直接写面板范围，不经过 in_* 嵌套
    wire grid_wave = (x2 >= 14'd226 && x2 < 14'd1250 && y2 >= 14'd6 && y2 < 14'd272) &&
                     ((y2 == 14'd139) || (y2 == 14'd102) || (y2 == 14'd176) ||
                      (x2[6:0] == 7'd98));          // 226 mod 128 = 98
    wire grid_spec = (x2 >= 14'd224 && x2 < 14'd1268 && y2 >= 14'd280 && y2 < 14'd452) &&
                     ((y2 == 14'd428) || (x2[7:0] == 8'd224));  // 224 mod 256 = 224
    wire grid_lissa = (x2 >= 14'd208 && x2 < 14'd464 && y2 >= 14'd460 && y2 < 14'd716) &&
                      ((x2 == 14'd336) || (y2 == 14'd588));
    wire row_lines = (x2 >= 14'd12 && x2 < 14'd196 && y2 >= 14'd72 && y2 < 14'd200) &&
                     (y2[3:0] == 4'd8);           // 72 mod 16 = 8

    wire w0 = in_kb && (x2 >= 14'd14)  && (x2 < 14'd38);
    wire w1 = in_kb && (x2 >= 14'd40)  && (x2 < 14'd64);
    wire w2 = in_kb && (x2 >= 14'd66)  && (x2 < 14'd90);
    wire w3 = in_kb && (x2 >= 14'd92)  && (x2 < 14'd116);
    wire w4 = in_kb && (x2 >= 14'd118) && (x2 < 14'd142);
    wire w5 = in_kb && (x2 >= 14'd144) && (x2 < 14'd168);
    wire w6 = in_kb && (x2 >= 14'd170) && (x2 < 14'd194);

    wire white_hit = w0 || w1 || w2 || w3 || w4 || w5 || w6;
    wire white_pressed = (w0 & keys_r[0]) || (w1 & keys_r[1]) ||
                         (w2 & keys_r[2]) || (w3 & keys_r[3]) ||
                         (w4 & keys_r[4]) || (w5 & keys_r[5]) ||
                         (w6 & keys_r[6]);

    wire b0 = in_kb && (x2 >= 14'd30)  && (x2 < 14'd46)  && (y2 < 14'd260);
    wire b1 = in_kb && (x2 >= 14'd56)  && (x2 < 14'd72)  && (y2 < 14'd260);
    wire b2 = in_kb && (x2 >= 14'd108) && (x2 < 14'd124) && (y2 < 14'd260);
    wire b3 = in_kb && (x2 >= 14'd134) && (x2 < 14'd150) && (y2 < 14'd260);
    wire b4 = in_kb && (x2 >= 14'd160) && (x2 < 14'd176) && (y2 < 14'd260);

    wire black_hit = b0 || b1 || b2 || b3 || b4;
    wire black_pressed = (b0 & keys_r[7])  || (b1 & keys_r[8])  ||
                         (b2 & keys_r[9])  || (b3 & keys_r[10]) ||
                         (b4 & keys_r[11]);
    wire kb_hit = white_hit || black_hit;

    wire [23:0] col_kb = black_hit ? (black_pressed ? 24'hFF8000 : 24'h181818) :
                         (white_pressed ? 24'hFFD040 : 24'hC8C8C8);

    // 背景
    wire [23:0] col_bg = in_left   ? 24'h080810 :
                         (in_wave || in_spec || in_lissa || in_guide) ? 24'h101820 :
                         24'h000008;

    reg in_wave3, in_spec3, in_lissa3, in_guide3, in_left3;
    reg bd_wave3, bd_spec3, bd_lissa3, bd_guide3, bd_param3, bd_kb3, bd_left3;
    reg grid_wave3, grid_spec3, grid_lissa3, row_lines3;
    reg [9:0]  scope_y3;
    reg [9:0]  scope_y3_d = 10'd0;   // 上一列（保留作调试）
    reg [13:0] scope_y4_3 = 14'd2224, scope_y4_d = 14'd2224;   // 中线 139<<4

    wire signed [15:0] dy_disp   = $signed({2'b00, scope_rdata}) - 16'sd2224;
    wire signed [15:0] y2_disp   = 16'sd2224 + (dy_disp <<< 1);
    wire [13:0]        y4_scaled = (y2_disp < 16'sd128)  ? 14'd128  :
                                   (y2_disp > 16'sd4320) ? 14'd4320 : y2_disp[13:0];
    reg [7:0] lissa_rdata3;
    reg [7:0] bar_rdata3;
    reg [2:0] lissa_bit3;
    reg [13:0] x3, y3;
    reg [13:0] x4;                    // S4 寄存的 x（S5 算“是否在波形区”用）
    reg        in_wave4;              // S4 寄存的面板命中

    reg [15:0] wa_t5, wa_b5, wa_r5;   // S4 寄存：带下沿/带上沿/行中心（1/16 px）
    reg den3, hs3, vs3;

    always @(posedge pclk) begin
        in_wave3   <= in_wave;
        in_spec3   <= in_spec;
        in_lissa3  <= in_lissa;
        in_guide3  <= in_guide;
        in_left3   <= in_left;

        bd_wave3   <= bd_wave;
        bd_spec3   <= bd_spec;
        bd_lissa3  <= bd_lissa;
        bd_guide3  <= bd_guide;
        bd_param3  <= bd_param;
        bd_kb3     <= bd_kb;
        bd_left3   <= bd_left;

        grid_wave3 <= grid_wave;
        grid_spec3 <= grid_spec;
        grid_lissa3<= grid_lissa;
        row_lines3 <= row_lines;

        scope_y4_3  <= draw_on ? scope_rdata : 14'd2224;   // 139<<4
        scope_y3    <= draw_on ? scope_rdata[13:4]   : 10'd139;
        lissa_rdata3<= lissa_rdata;
        bar_rdata3  <= bar_rdata;
        lissa_bit3  <= lissa_bit2;

        x3 <= x2;
        y3 <= y2;
        den3 <= den2;
        hs3  <= hs2;
        vs3  <= vs2;
    end

    wire in_kb4 = (x3 >= 14'd12) && (x3 < 14'd196) && (y3 >= 14'd212) && (y3 < 14'd292);
    wire u0 = in_kb4 && (x3 >= 14'd14)  && (x3 < 14'd38);
    wire u1 = in_kb4 && (x3 >= 14'd40)  && (x3 < 14'd64);
    wire u2 = in_kb4 && (x3 >= 14'd66)  && (x3 < 14'd90);
    wire u3 = in_kb4 && (x3 >= 14'd92)  && (x3 < 14'd116);
    wire u4 = in_kb4 && (x3 >= 14'd118) && (x3 < 14'd142);
    wire u5 = in_kb4 && (x3 >= 14'd144) && (x3 < 14'd168);
    wire u6 = in_kb4 && (x3 >= 14'd170) && (x3 < 14'd194);

    wire v0 = in_kb4 && (x3 >= 14'd30)  && (x3 < 14'd46)  && (y3 < 14'd260);
    wire v1 = in_kb4 && (x3 >= 14'd56)  && (x3 < 14'd72)  && (y3 < 14'd260);
    wire v2 = in_kb4 && (x3 >= 14'd108) && (x3 < 14'd124) && (y3 < 14'd260);
    wire v3 = in_kb4 && (x3 >= 14'd134) && (x3 < 14'd150) && (y3 < 14'd260);
    wire v4 = in_kb4 && (x3 >= 14'd160) && (x3 < 14'd176) && (y3 < 14'd260);

    wire white_hit4 = u0 || u1 || u2 || u3 || u4 || u5 || u6;
    wire white_pressed4 = (u0 & keys_r[0]) || (u1 & keys_r[1]) ||
                          (u2 & keys_r[2]) || (u3 & keys_r[3]) ||
                          (u4 & keys_r[4]) || (u5 & keys_r[5]) ||
                          (u6 & keys_r[6]);
    wire black_hit4 = v0 || v1 || v2 || v3 || v4;
    wire black_pressed4 = (v0 & keys_r[7])  || (v1 & keys_r[8])  ||
                          (v2 & keys_r[9])  || (v3 & keys_r[10]) ||
                          (v4 & keys_r[11]);
    wire kb_hit4 = white_hit4 || black_hit4;

    wire [23:0] col_kb4 = black_hit4 ? (black_pressed4 ? 24'h40E0FF : 24'h000000) :
                          (white_pressed4 ? 24'hFF8000 : 24'hFFFFFF);

    wire in_game4 = (x3 >= 14'd726) && (x3 < 14'd1254) &&
                    (y3 >= 14'd466) && (y3 < 14'd713);
    wire in_key4  = in_game4 && (y3 >= 14'd668);
    wire in_lane4 = in_game4 && (y3 <  14'd668);

    wire k0  = in_key4 && (x3 >= 14'd726)  && (x3 < 14'd769);
    wire k1  = in_key4 && (x3 >= 14'd770)  && (x3 < 14'd813);
    wire k2  = in_key4 && (x3 >= 14'd814)  && (x3 < 14'd857);
    wire k3  = in_key4 && (x3 >= 14'd858)  && (x3 < 14'd901);
    wire k4  = in_key4 && (x3 >= 14'd902)  && (x3 < 14'd945);
    wire k5  = in_key4 && (x3 >= 14'd946)  && (x3 < 14'd989);
    wire k6  = in_key4 && (x3 >= 14'd990)  && (x3 < 14'd1033);
    wire k7  = in_key4 && (x3 >= 14'd1034) && (x3 < 14'd1077);
    wire k8  = in_key4 && (x3 >= 14'd1078) && (x3 < 14'd1121);
    wire k9  = in_key4 && (x3 >= 14'd1122) && (x3 < 14'd1165);
    wire k10 = in_key4 && (x3 >= 14'd1166) && (x3 < 14'd1209);
    wire k11 = in_key4 && (x3 >= 14'd1210) && (x3 < 14'd1253);

    wire rkb_hit4 = k0 || k1 || k2 || k3 || k4 || k5 ||
                    k6 || k7 || k8 || k9 || k10 || k11;

    wire [3:0] ck0  = 4'd0,  ck1  = 4'd7,  ck2  = 4'd1,  ck3  = 4'd8;
    wire [3:0] ck4  = 4'd2,  ck5  = 4'd3,  ck6  = 4'd9,  ck7  = 4'd4;
    wire [3:0] ck8  = 4'd10, ck9  = 4'd5,  ck10 = 4'd11, ck11 = 4'd6;

    wire r_pressed = st_g_mode &&
                     ((k0 & keys_r[ck0])  || (k1 & keys_r[ck1])  ||
                      (k2 & keys_r[ck2])  || (k3 & keys_r[ck3])  ||
                      (k4 & keys_r[ck4])  || (k5 & keys_r[ck5])  ||
                      (k6 & keys_r[ck6])  || (k7 & keys_r[ck7])  ||
                      (k8 & keys_r[ck8])  || (k9 & keys_r[ck9])  ||
                      (k10 & keys_r[ck10]) || (k11 & keys_r[ck11]));
    // 提示键（青）只在 SONG(2)/B_RUN(3) 显示；MODE/A_RUN 不提示音符
    wire r_hint_on = (st_g_state == 3'd2) || (st_g_state == 3'd3);
    wire r_guide = r_hint_on &&
                   ((k0  && st_g_expected == ck0)  || (k1  && st_g_expected == ck1)  ||
                    (k2  && st_g_expected == ck2)  || (k3  && st_g_expected == ck3)  ||
                    (k4  && st_g_expected == ck4)  || (k5  && st_g_expected == ck5)  ||
                    (k6  && st_g_expected == ck6)  || (k7  && st_g_expected == ck7)  ||
                    (k8  && st_g_expected == ck8)  || (k9  && st_g_expected == ck9)  ||
                    (k10 && st_g_expected == ck10) || (k11 && st_g_expected == ck11));
    wire r_wrong = st_g_wrong_active &&
                   ((k0  && st_g_wrong_key == ck0)  || (k1  && st_g_wrong_key == ck1)  ||
                    (k2  && st_g_wrong_key == ck2)  || (k3  && st_g_wrong_key == ck3)  ||
                    (k4  && st_g_wrong_key == ck4)  || (k5  && st_g_wrong_key == ck5)  ||
                    (k6  && st_g_wrong_key == ck6)  || (k7  && st_g_wrong_key == ck7)  ||
                    (k8  && st_g_wrong_key == ck8)  || (k9  && st_g_wrong_key == ck9)  ||
                    (k10 && st_g_wrong_key == ck10) || (k11 && st_g_wrong_key == ck11));

    wire r_black = k1 || k3 || k6 || k8 || k10;
    wire [23:0] col_rkb4 = r_wrong   ? 24'hFF3030 :
                           r_pressed ? 24'hFF8000 :
                           r_guide   ? 24'h40E0FF :
                           r_black   ? 24'h000000 : 24'hFFFFFF;

    wire lane_x4 = (x3 == 14'd726) || (x3 == 14'd770) || (x3 == 14'd814) ||
                   (x3 == 14'd858) || (x3 == 14'd902) || (x3 == 14'd946) ||
                   (x3 == 14'd990) || (x3 == 14'd1034) || (x3 == 14'd1078) ||
                   (x3 == 14'd1122) || (x3 == 14'd1166) || (x3 == 14'd1210) ||
                   (x3 == 14'd1254);
    wire lane_line4 = in_game4 && lane_x4;
    wire hit_line4  = (x3 >= 14'd726) && (x3 < 14'd1254) &&
                      ((y3 == 14'd666) || (y3 == 14'd667));

    wire [10:0] x3s = x3[10:0];
    wire [10:0] y3s = y3[10:0];
    wire [45:0] t0 = st_g_tiles[ 45:  0];
    wire [45:0] t1 = st_g_tiles[ 91: 46];
    wire [45:0] t2 = st_g_tiles[137: 92];
    wire [45:0] t3 = st_g_tiles[183:138];
    wire [45:0] t4 = st_g_tiles[229:184];
    wire [45:0] t5 = st_g_tiles[275:230];

    wire f0 = t0[44] && (x3s >= t0[10:0])  && (x3s < t0[21:11]) &&
                         (y3s >= t0[43:33]) && (y3s < t0[32:22]);
    wire f1 = t1[44] && (x3s >= t1[10:0])  && (x3s < t1[21:11]) &&
                         (y3s >= t1[43:33]) && (y3s < t1[32:22]);
    wire f2 = t2[44] && (x3s >= t2[10:0])  && (x3s < t2[21:11]) &&
                         (y3s >= t2[43:33]) && (y3s < t2[32:22]);
    wire f3 = t3[44] && (x3s >= t3[10:0])  && (x3s < t3[21:11]) &&
                         (y3s >= t3[43:33]) && (y3s < t3[32:22]);
    wire f4 = t4[44] && (x3s >= t4[10:0])  && (x3s < t4[21:11]) &&
                         (y3s >= t4[43:33]) && (y3s < t4[32:22]);
    wire f5 = t5[44] && (x3s >= t5[10:0])  && (x3s < t5[21:11]) &&
                         (y3s >= t5[43:33]) && (y3s < t5[32:22]);
    wire fall_hit4  = f0 || f1 || f2 || f3 || f4 || f5;
    // 正在按住的那一块画绿色（其它青色）；失败画面整体变红
    wire fall_held4 = (f0 && t0[45]) || (f1 && t1[45]) || (f2 && t2[45]) ||
                      (f3 && t3[45]) || (f4 && t4[45]) || (f5 && t5[45]);
    wire [23:0] col_fall4 = (st_g_state == 3'd6) ? 24'hFF3030 :
                            fall_held4          ? 24'h40E070 : 24'h40E0FF;

    wire [9:0] y3_w  = y3[9:0];

    wire [13:0] wa_top4 = (scope_y4_3 > scope_y4_d) ? scope_y4_3 : scope_y4_d;
    wire [13:0] wa_bot4 = (scope_y4_3 > scope_y4_d) ? scope_y4_d : scope_y4_3;
    wire [15:0] wa_r16  = {2'b00, y3_w, 4'h8};                 // 行中心，1/16 px

    localparam [15:0] WAVE_HALF = 16'd16;
    wire [15:0] wa_t16  = {2'b00, wa_top4} + WAVE_HALF;
    wire [15:0] wa_b16  = ({2'b00, wa_bot4} > WAVE_HALF) ? ({2'b00, wa_bot4} - WAVE_HALF) : 16'd0;

    wire [15:0] wa_d5   = (wa_r5 > wa_t5) ? (wa_r5 - wa_t5) :
                          (wa_r5 < wa_b5) ? (wa_b5 - wa_r5) : 16'd0;
    wire [4:0]  wa_a5   = (wa_d5 >= 16'd16) ? 5'd0 : (5'd16 - wa_d5[4:0]);
    wire wave_hit5 = in_wave4 &&
                     (x4 >= 14'd226) && (x4 < 14'd1250) && (wa_a5 != 5'd0);
    wire lissa_hit4 = in_lissa3 && lissa_rdata3[lissa_bit3];

    wire [13:0] bx4      = x3 - 14'd224;
    wire        bar_x4   = in_spec3 && (x3 >= 14'd224) && (x3 < 14'd1248) &&
                           (bx4[2:0] < 3'd6);
    wire [13:0] bar_top4 = 14'd428 - {6'd0, bar_rdata3};
    wire        bar_hit4 = bar_x4 && (bar_rdata3 != 8'd0) &&
                           (y3 >= bar_top4) && (y3 < 14'd428);

    localparam [23:0] BAR_COLOR = 24'h40E070;
    wire [23:0] col_bar4 = BAR_COLOR;

    wire border_hit4 = bd_wave3 || bd_spec3 || bd_lissa3 || bd_guide3 ||
                       bd_param3 || bd_kb3 || bd_left3;
    wire grid_hit4 = grid_wave3 || grid_spec3 || grid_lissa3 || row_lines3 ||
                     lane_line4;

    wire [23:0] col_bg4 = in_left3   ? 24'h080810 :
                          (in_wave3 || in_spec3 || in_lissa3 || in_guide3) ? 24'h101820 :
                          24'h000008;

    reg [23:0] l4_bg, l4_kb, l4_bar, l4_rkb, l4_fall;
    reg h4_bd, h4_grid, h4_lissa, h4_kb, h4_bar, h4_txt, h4_rkb, h4_fall, h4_hl;
    reg den4, hs4, vs4;

    always @(posedge pclk) begin
        l4_bg   <= col_bg4;
        l4_kb   <= col_kb4;
        l4_rkb  <= col_rkb4;
        l4_bar  <= col_bar4;
        l4_fall <= col_fall4;
        h4_bd   <= border_hit4;
        h4_grid <= grid_hit4;
        h4_lissa<= lissa_hit4;
        h4_bar  <= bar_hit4;
        h4_kb   <= kb_hit4;
        h4_rkb  <= rkb_hit4;
        h4_fall <= fall_hit4;
        h4_hl   <= hit_line4;
        h4_txt  <= txt_px3;
        // 描迹带几何在此寄存（S3→S4 只剩 max/min + ±32）
        x4        <= x3;
        in_wave4  <= in_wave3;
        wa_t5     <= wa_t16;
        wa_b5     <= wa_b16;
        wa_r5     <= wa_r16;
        scope_y3_d <= scope_y3;
        scope_y4_d <= scope_y4_3;
        den4    <= den3;
        hs4     <= hs3;
        vs4     <= vs3;
    end

    reg [23:0] l5_bg, l5_kb, l5_bar;
    reg [4:0]  wav_a6_r;
    reg [23:0] l5_rkb, l5_fall;
    reg h5_bd, h5_grid, h5_wave, h5_lissa, h5_kb, h5_bar, h5_txt, h5_rkb, h5_fall, h5_hl;
    reg den5, hs5, vs5;

    always @(posedge pclk) begin
        l5_bg    <= l4_bg;
        l5_kb    <= l4_kb;
        l5_rkb   <= l4_rkb;
        l5_bar   <= l4_bar;
        l5_fall  <= l4_fall;
        wav_a6_r <= wa_a5;
        h5_bd    <= h4_bd;
        h5_grid  <= h4_grid;
        h5_wave  <= wave_hit5;
        h5_lissa <= h4_lissa;
        h5_bar   <= h4_bar;
        h5_kb    <= h4_kb;
        h5_rkb   <= h4_rkb;
        h5_fall  <= h4_fall;
        h5_hl    <= h4_hl;
        h5_txt   <= h4_txt;
        den5     <= den4;
        hs5      <= hs4;
        vs5      <= vs4;
    end

    function [23:0] wav_col;
        input [4:0] a;
        begin
            case (a)
                5'd0 : wav_col = 24'h101820;
                5'd1 : wav_col = 24'h132626;
                5'd2 : wav_col = 24'h16342C;
                5'd3 : wav_col = 24'h194332;
                5'd4 : wav_col = 24'h1C5138;
                5'd5 : wav_col = 24'h1F603E;
                5'd6 : wav_col = 24'h226E44;
                5'd7 : wav_col = 24'h257D4A;
                5'd8 : wav_col = 24'h288B50;
                5'd9 : wav_col = 24'h2B9956;
                5'd10: wav_col = 24'h2EA85C;
                5'd11: wav_col = 24'h31B662;
                5'd12: wav_col = 24'h34C568;
                5'd13: wav_col = 24'h37D36E;
                5'd14: wav_col = 24'h3AE274;
                5'd15: wav_col = 24'h3DF07A;
                default: wav_col = 24'h40FF80;   // a=16 全亮
            endcase
        end
    endfunction

    reg [23:0] rgb6;
    reg den6, hs6, vs6;

    always @(posedge pclk) begin
        if (h5_txt)
            rgb6 <= 24'hD8E4FF;      // 文字层最高优先级（白偏蓝）
        else if (h5_kb)
            rgb6 <= l5_kb;
        else if (h5_fall)
            rgb6 <= l5_fall;         // 下落方块（青=下落中 / 绿=正在按住 / 红=失败）
        else if (h5_rkb)
            rgb6 <= l5_rkb;          // 右侧 12 等宽琴键（GUIDE 面板）
        else if (h5_hl)
            rgb6 <= 24'hFFD060;      // 判定线（琴键上边缘，2 px）
        else if (h5_wave)
            rgb6 <= wav_col(wav_a6_r);
        else if (h5_lissa)
            rgb6 <= 24'h80E0FF;
        else if (h5_bar)
            rgb6 <= l5_bar;
        else if (h5_bd)
            rgb6 <= 24'h405080;
        else if (h5_grid)
            rgb6 <= 24'h203048;
        else
            rgb6 <= l5_bg;

        den6 <= den5;
        hs6  <= hs5;
        vs6  <= vs5;
    end

    wire [5:0] ctrl;
    assign ctrl[0]   = hs6;
    assign ctrl[1]   = vs6;
    assign ctrl[5:2] = 4'b0000;

    wire [29:0] tmds_enc;
    wire [1:0]  data_out_to_pins [2:0];

    genvar i;
    generate
        for (i = 0; i < 3; i = i + 1) begin : gen_tmds
            dvi_tx_tmds_enc u_enc (
                .clock  (pclk),
                .reset  (1'b0),
                .den    (den6),
                .data   (rgb6[(8*i) +: 8]),
                .ctrl   (ctrl[(2*i) +: 2]),
                .tmds   (tmds_enc[(10*i) +: 10])
            );

            dvi_tx_tmds_phy u_phy (
                .pixel_clock   (pclk),
                .ddr_bit_clock (bclk),
                .reset         (1'b0),
                .data          (tmds_enc[(10*i) +: 10]),
                .tmds_lane     (data_out_to_pins[i])
            );
        end
    endgenerate

    assign tmds_d_p_0[0] = data_out_to_pins[0][1];
    assign tmds_d_n_0[0] = data_out_to_pins[0][0];
    assign tmds_d_p_0[1] = data_out_to_pins[1][1];
    assign tmds_d_n_0[1] = data_out_to_pins[1][0];
    assign tmds_d_p_0[2] = data_out_to_pins[2][1];
    assign tmds_d_n_0[2] = data_out_to_pins[2][0];

    wire [1:0] tmds_clk;
    dvi_tx_clk_drv u_clk (
        .pixel_clock (pclk),
        .tmds_clk    (tmds_clk)
    );
    assign tmds_clk_p_0 = tmds_clk[1];
    assign tmds_clk_n_0 = tmds_clk[0];

endmodule
