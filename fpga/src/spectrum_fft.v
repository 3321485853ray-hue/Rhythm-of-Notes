// spectrum_fft.v — 2048 点定点 FFT 实时频谱（音频 50 MHz 域，只读抽头）

module spectrum_fft (
    input  wire               clk,        // 50 MHz
    input  wire signed [15:0] din,        // disp_ac
    // 柱高写口（写 spec_bank_ram 的双 bank BSRAM，写时钟 = 本模块 clk）
    output wire               bar_we,          // 一帧内逐根写，S_PEAK 期间有效
    output wire [7:0]         bar_waddr,       // {bank, bar[6:0]}
    output wire [7:0]         bar_wdata,       // 柱高（px，0..BAR_MAX_PX）
    output reg                spec_tgl = 1'b0
);

    localparam integer BAR_MAX_PX = 140;  // 柱高（基线 428 → 顶 288，框内留 8 px）

    reg [9:0] cnt = 10'd0;
    always @(posedge clk) cnt <= cnt + 1'b1;
    wire tick = (cnt == 10'd0);

    reg [9:0] fdiv = 10'd0;
    always @(posedge clk) if (tick) fdiv <= fdiv + 1'b1;
    wire frame_tick = tick && (fdiv == 10'd0);

    reg signed [15:0] ring [0:4095];
    reg [11:0] wr_ptr    = 12'd0;
    reg [11:0] fill_cnt  = 12'd0;
    reg        ring_full = 1'b0;
    reg [11:0] ld_raddr  = 12'd0;
    reg signed [15:0] ring_dout = 16'sd0;

    always @(posedge clk) begin
        ring_dout <= ring[ld_raddr];        // 同步读（BSRAM）
        if (tick) begin
            ring[wr_ptr] <= din;
            wr_ptr <= wr_ptr + 1'b1;
            if (fill_cnt != 12'd2047)
                fill_cnt <= fill_cnt + 1'b1;
            else
                ring_full <= 1'b1;
        end
    end

    reg signed [23:0] re_mem [0:2047];
    reg signed [23:0] im_mem [0:2047];
    reg [10:0] rd_addr = 11'd0;
    reg [10:0] wr_addr = 11'd0;
    reg        re_we = 1'b0, im_we = 1'b0;
    reg signed [23:0] re_wdat = 24'sd0, im_wdat = 24'sd0;
    reg signed [23:0] re_dout = 24'sd0, im_dout = 24'sd0;

    always @(posedge clk) begin
        re_dout <= re_mem[rd_addr];
        im_dout <= im_mem[rd_addr];
        if (re_we) re_mem[wr_addr] <= re_wdat;
        if (im_we) im_mem[wr_addr] <= im_wdat;
    end

    // Hann 窗（2048 点）
    reg [10:0] hann_addr = 11'd0;
    wire [15:0] hann_dout;
    hann_rom u_hann (.clk(clk), .addr(hann_addr), .dout(hann_dout));

    // 旋转因子 {cos[15:0], sin[15:0]}（1024 项）
    reg [9:0]  tw_addr = 10'd0;
    wire [31:0] tw_dout;
    twiddle_rom u_tw (.clk(clk), .addr(tw_addr), .dout(tw_dout));

    // bin → 柱（1024 bin）
    reg [9:0]  b2b_addr = 10'd0;
    wire [7:0]  b2b_dout;
    bin2bar_rom u_b2b (.clk(clk), .addr(b2b_addr), .dout(b2b_dout));

    localparam [4:0]
        S_IDLE = 5'd0,
        S_LOAD_A = 5'd1, S_LOAD_B = 5'd2, S_LOAD_C = 5'd3, S_LOAD_W = 5'd4,
        S_BF_A = 5'd5, S_BF_B = 5'd6, S_BF_C = 5'd7, S_BF_D = 5'd8,
        S_BF_MUL = 5'd9, S_BF_SUM = 5'd10,
        S_BF_W0 = 5'd11, S_BF_W1 = 5'd12, S_BF_W2 = 5'd13, S_BF_W3 = 5'd14,
        S_MAG_A = 5'd15, S_MAG_B = 5'd16, S_MAG_C = 5'd17, S_MAG_D = 5'd18,
        S_MAG_E = 5'd19, S_MAG_F = 5'd20, S_MAG_HS = 5'd21, S_MAG_G = 5'd22,
        S_CLR = 5'd23, S_PEAK = 5'd24, S_PUB = 5'd25, S_THIN = 5'd26;

    reg [4:0] fs = 5'd0;

    reg [11:0] ld_start = 12'd0;
    reg [10:0] ld_idx   = 11'd0;
    reg signed [15:0] ld_x = 16'sd0;
    reg [15:0] ld_w = 16'd0;                 // 本样本的窗值（S_LOAD_C 寄存）

    wire [11:0] ld_ring_addr = ld_start + ld_idx;
    // 11 位位倒序（2048 点）
    wire [10:0] ld_br_w = {ld_idx[0],  ld_idx[1],  ld_idx[2],  ld_idx[3],
                           ld_idx[4],  ld_idx[5],  ld_idx[6],  ld_idx[7],
                           ld_idx[8],  ld_idx[9],  ld_idx[10]};

    wire signed [31:0] ld_prod = ld_x * $signed({1'b0, ld_w});
    wire signed [23:0] ld_y    = ld_prod >>> 11;

    reg [10:0] st_half = 11'd1;
    reg [10:0] st_step = 11'd1024;
    reg [10:0] st_base = 11'd0;
    reg [10:0] st_k    = 11'd0;
    reg [3:0]  st_age  = 4'd1;
    reg [10:0] bf_i0 = 11'd0, bf_i1 = 11'd0;
    reg signed [23:0] bf_ar = 24'sd0, bf_ai = 24'sd0;
    reg signed [23:0] bf_br = 24'sd0, bf_bi = 24'sd0;
    reg signed [15:0] bf_c = 16'sd0, bf_s = 16'sd0;
    reg signed [39:0] bf_p1 = 40'sd0, bf_p2 = 40'sd0;
    reg signed [25:0] bf_tr = 26'sd0, bf_ti = 26'sd0;
    reg signed [25:0] bf_o0r = 26'sd0, bf_o0i = 26'sd0;
    reg signed [25:0] bf_o1r = 26'sd0, bf_o1i = 26'sd0;

    wire [10:0] tw_mul_w = st_k * st_step;     // 恒 < 1024（10 位内）

    reg [9:0]  mg_k = 10'd0;
    reg signed [23:0] mg_re = 24'sd0, mg_im = 24'sd0;
    reg [7:0]  mg_bar = 8'd0;
    reg signed [47:0] mg_p1 = 48'sd0, mg_p2 = 48'sd0;
    reg [48:0] mg_mag2 = 49'd0;
    reg [5:0]  mg_msb  = 6'd0;
    reg [9:0]  mg_logq4 = 10'd0;
    reg [7:0]  mg_lvl = 8'd0;

    // 最高有效位（组合；49 位优先级）
    reg [5:0] msb_c;
    integer jj;
    always @(*) begin
        msb_c = 6'd0;
        for (jj = 0; jj < 49; jj = jj + 1)
            if (mg_mag2[jj]) msb_c = jj[5:0];
    end

    // log2(1+m/16) 的 Q4 表
    function [3:0] log2mant;
        input [3:0] m;
        begin
            case (m)
                4'd0:  log2mant = 4'd0;
                4'd1:  log2mant = 4'd1;
                4'd2:  log2mant = 4'd3;
                4'd3:  log2mant = 4'd4;
                4'd4:  log2mant = 4'd5;
                4'd5:  log2mant = 4'd6;
                4'd6:  log2mant = 4'd7;
                4'd7:  log2mant = 4'd8;
                4'd8:  log2mant = 4'd8;
                4'd9:  log2mant = 4'd9;
                4'd10: log2mant = 4'd10;
                4'd11: log2mant = 4'd11;
                4'd12: log2mant = 4'd11;
                4'd13: log2mant = 4'd12;
                4'd14: log2mant = 4'd13;
                default: log2mant = 4'd13;
            endcase
        end
    endfunction

    wire [5:0]  mg_nsh = 6'd48 - mg_msb;
    wire [48:0] mg_sh  = mg_mag2 << mg_nsh;
    wire [3:0]  mg_mant = mg_sh[47:44];
    wire [9:0]  mg_log_c = {mg_msb, 4'b0000} + {6'd0, log2mant(mg_mant)};

    localparam [9:0] LVL_START = 10'd200;
    localparam [16:0] LVL_GAIN = 17'd15;      // 15/16 = 0.9375
    wire [16:0] lvl_m  = (mg_logq4 <= LVL_START) ? 17'd0 :
                         (({7'd0, mg_logq4} - {7'd0, LVL_START}) * LVL_GAIN);
    wire [11:0] lvl_sh = lvl_m[15:4];         // ×13/16
    wire [7:0]  lvl_c  = (lvl_sh > 12'd255) ? 8'd255 : lvl_sh[7:0];

    reg [7:0]  bar_acc [0:127];   // 本帧柱电平（每帧清零）
    reg [7:0]  bar_lvl [0:127];   // 平滑后的柱电平（跨帧保持）
    reg pub_bank = 1'b0;
    reg [6:0] pk_i = 7'd0;
    reg [6:0] clr_i = 7'd0;

    integer i;
    initial begin
        for (i = 0; i < 128; i = i + 1) begin
            bar_acc[i] = 8'd0;
            bar_lvl[i] = 8'd0;
        end
    end

    localparam [7:0] PK_THR = 8'd8;
    wire [7:0]  acc_v  = bar_acc[pk_i];
    wire [7:0]  lvl_v  = bar_lvl[pk_i];
    // 快起慢落：本帧更大 ⇒ 立即跟随；更小 ⇒ 每帧回落 1/4（τ≈4 帧）
    wire [7:0]  lvl_n  = (acc_v >= lvl_v) ? acc_v :
                         (lvl_v - ((lvl_v - acc_v + 8'd2) >> 2));
    // 稀疏判定用平滑后的邻居：左严格、右非严格（平台取最左一根）
    wire [6:0]  pk_l   = (pk_i == 7'd0)   ? 7'd0   : (pk_i - 1'b1);
    wire [6:0]  pk_r   = (pk_i == 7'd127) ? 7'd127 : (pk_i + 1'b1);
    wire [7:0]  lvl_l  = bar_lvl[pk_l];
    wire [7:0]  lvl_r  = bar_lvl[pk_r];
    wire        is_pk  = ((pk_i == 7'd0)   || (lvl_v >  lvl_l)) &&
                         ((pk_i == 7'd127) || (lvl_v >= lvl_r)) &&
                         (lvl_v >= PK_THR);
    wire [7:0]  bar_v  = is_pk ? lvl_v : 8'd0;
    // 柱高：bar_v × 140 >> 8（140 = 128+8+4，用移位加，不占 DSP）
    wire [15:0] px_m   = ({8'd0, bar_v} << 7) + ({8'd0, bar_v} << 3) + ({8'd0, bar_v} << 2);

    // 写口（组合输出：由 BSRAM 在 clk 上升沿采样当前值；只在 S_THIN 写）
    assign bar_we    = (fs == S_THIN);
    assign bar_waddr = {pub_bank, pk_i};
    assign bar_wdata = px_m[15:8];

    always @(posedge clk) begin
        re_we <= 1'b0;
        im_we <= 1'b0;

        if (ring_full && (fs == S_IDLE) && frame_tick) begin
            fs       <= S_LOAD_A;
            ld_start <= wr_ptr - 12'd2048;   // 50% 重叠：最近 2048 个采样
            ld_idx   <= 11'd0;
        end else case (fs)

        S_LOAD_A: begin
            ld_raddr  <= ld_ring_addr;
            hann_addr <= ld_idx;
            fs <= S_LOAD_B;
        end
        S_LOAD_B: begin
            fs <= S_LOAD_C;                      // 等环读 / Hann 数据
        end
        S_LOAD_C: begin
            ld_x <= ring_dout;                   // 同步读：A 发地址、B 出数据
            ld_w <= hann_dout;
            fs <= S_LOAD_W;
        end
        S_LOAD_W: begin
            re_we   <= 1'b1;
            im_we   <= 1'b1;
            wr_addr <= ld_br_w;                  // 位倒序（组合，直接进写口）
            re_wdat <= ld_y;                     // 组合乘积，本拍寄存
            im_wdat <= 24'sd0;
            if (ld_idx == 11'd2047) begin
                st_age  <= 4'd1;
                st_half <= 11'd1;
                st_step <= 11'd1024;
                st_base <= 11'd0;
                st_k    <= 11'd0;
                fs <= S_BF_A;
            end else begin
                ld_idx <= ld_idx + 1'b1;
                fs <= S_LOAD_A;
            end
        end

        S_BF_A: begin
            bf_i0   <= st_base + st_k;
            bf_i1   <= st_base + st_k + st_half;
            rd_addr <= st_base + st_k;
            tw_addr <= tw_mul_w[9:0];
            fs <= S_BF_B;
        end
        S_BF_B: begin
            rd_addr <= bf_i1;                    // 发 B 的地址
            fs <= S_BF_C;                        // 本拍末 data(A) 才有效
        end
        S_BF_C: begin
            bf_ar <= re_dout;                    // mem[i0]
            bf_ai <= im_dout;
            bf_c  <= tw_dout[31:16];             // 旋转因子（A 发地址，此时有效）
            bf_s  <= tw_dout[15:0];
            fs <= S_BF_D;
        end
        S_BF_D: begin
            bf_br <= re_dout;                    // mem[i1]
            bf_bi <= im_dout;
            fs <= S_BF_MUL;
        end
        S_BF_MUL: begin

            bf_p1 <= bf_br * bf_c - bf_bi * bf_s;
            bf_p2 <= bf_br * bf_s + bf_bi * bf_c;
            fs <= S_BF_SUM;
        end
        S_BF_SUM: begin
            bf_tr  <= (bf_p1 + 40'sd16384) >>> 15;
            bf_ti  <= (bf_p2 + 40'sd16384) >>> 15;
            // 蝶形输出（每级 >>1 防溢出）
            bf_o0r <= (bf_ar + ((bf_p1 + 40'sd16384) >>> 15)) >>> 1;
            bf_o0i <= (bf_ai + ((bf_p2 + 40'sd16384) >>> 15)) >>> 1;
            bf_o1r <= (bf_ar - ((bf_p1 + 40'sd16384) >>> 15)) >>> 1;
            bf_o1i <= (bf_ai - ((bf_p2 + 40'sd16384) >>> 15)) >>> 1;
            fs <= S_BF_W0;
        end
        S_BF_W0: begin
            re_we   <= 1'b1;
            wr_addr <= bf_i0;
            re_wdat <= bf_o0r[23:0];
            rd_addr <= bf_i1;          // 读地址与写地址保持不同（PA2122）
            fs <= S_BF_W1;
        end
        S_BF_W1: begin
            im_we   <= 1'b1;
            wr_addr <= bf_i0;
            im_wdat <= bf_o0i[23:0];
            rd_addr <= bf_i1;
            fs <= S_BF_W2;
        end
        S_BF_W2: begin
            re_we   <= 1'b1;
            wr_addr <= bf_i1;
            re_wdat <= bf_o1r[23:0];
            rd_addr <= bf_i0;
            fs <= S_BF_W3;
        end
        S_BF_W3: begin
            im_we   <= 1'b1;
            wr_addr <= bf_i1;
            im_wdat <= bf_o1i[23:0];
            rd_addr <= bf_i0;

            if (st_k + 11'd1 == st_half) begin
                st_k <= 11'd0;
                if ({1'b0, st_base} + {st_half, 1'b0} >= 12'd2048) begin
                    st_base <= 11'd0;
                    if (st_age == 4'd11) begin
                        clr_i <= 7'd0;          // 先清柱累加器，再进幅值阶段
                        fs <= S_CLR;
                    end else begin
                        st_age  <= st_age + 1'b1;
                        st_half <= st_half << 1;
                        st_step <= st_step >> 1;
                        fs <= S_BF_A;
                    end
                end else begin
                    st_base <= st_base + {st_half, 1'b0};
                    fs <= S_BF_A;
                end
            end else begin
                st_k <= st_k + 1'b1;
                fs <= S_BF_A;
            end
        end

        S_MAG_A: begin
            rd_addr  <= {1'b0, mg_k};
            b2b_addr <= mg_k;
            fs <= S_MAG_B;
        end
        S_MAG_B: begin
            fs <= S_MAG_C;                       // 等 RAM/ROM 数据（1 拍延迟）
        end
        S_MAG_C: begin
            mg_re  <= re_dout;
            mg_im  <= im_dout;
            mg_bar <= b2b_dout;
            fs <= S_MAG_D;
        end
        S_MAG_D: begin
            mg_p1 <= mg_re * mg_re;
            mg_p2 <= mg_im * mg_im;
            fs <= S_MAG_E;
        end
        S_MAG_E: begin
            mg_mag2 <= mg_p1 + mg_p2;
            fs <= S_MAG_F;
        end
        S_MAG_F: begin
            mg_msb <= msb_c;                 // 第一拍：只做 49 位优先编码
            fs <= S_MAG_HS;
        end
        S_MAG_HS: begin
            mg_logq4 <= mg_log_c;            // 第二拍：桶形移位 + 尾数 LUT + 相加
            fs <= S_MAG_G;
        end
        S_MAG_G: begin
            mg_lvl <= lvl_c;
            if (mg_bar != 8'd255) begin
                if (lvl_c > bar_acc[mg_bar])
                    bar_acc[mg_bar] <= lvl_c;
            end
            if (mg_k == 10'd1023) begin
                pk_i <= 7'd0;
                fs <= S_PEAK;
            end else begin
                mg_k <= mg_k + 1'b1;
                fs <= S_MAG_A;
            end
        end

        S_CLR: begin
            bar_acc[clr_i] <= 8'd0;
            if (clr_i == 7'd127) begin
                mg_k <= 10'd0;
                fs <= S_MAG_A;
            end else begin
                clr_i <= clr_i + 1'b1;
            end
        end
        S_PEAK: begin
            // Pass A：更新平滑电平（跨帧保持）
            bar_lvl[pk_i] <= lvl_n;
            if (pk_i == 7'd127) begin
                pk_i <= 7'd0;
                fs   <= S_THIN;
            end else
                pk_i <= pk_i + 1'b1;
        end
        S_THIN: begin
            // Pass B：用 Pass A 更新后的邻居做局部极大判定并写 bank
            //   bar_we / bar_waddr / bar_wdata 是本状态的组合输出
            if (pk_i == 7'd127) fs <= S_PUB;
            else pk_i <= pk_i + 1'b1;
        end
        S_PUB: begin
            spec_tgl  <= ~spec_tgl;      // 本帧要写的 bank 已全部写完
            pub_bank  <= ~pub_bank;
            fs <= S_IDLE;
        end
        default: fs <= S_IDLE;
        endcase
    end

endmodule
