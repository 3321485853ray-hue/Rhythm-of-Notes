// display_lissa.v — 李萨如采样对抽头（音频域，只读）

module display_lissa (
    input  wire               clk,           // 50 MHz
    input  wire signed [15:0] disp_ac,
    input  wire [1:0]         att,           // 0/1/2
    output reg  signed [15:0] lissa_x,
    output reg  signed [15:0] lissa_y,
    output wire               lissa_tgl
);

    // 低通滤波系数：2 = 两级一阶，−3 dB 约 1.2 kHz。
    localparam integer LISSA_LP_K = 2;

    reg tgl_r = 1'b0;
    assign lissa_tgl = tgl_r;

    reg [9:0] cnt = 10'd0;
    always @(posedge clk) cnt <= cnt + 1'b1;

    wire sub_tick   = (cnt[7:0] == 8'd0);              // 每 256 拍 ≈ 195.3 kHz
    wire audio_tick = sub_tick && (cnt[9:8] == 2'd0);  // 每 1024 拍 = 48.83 kHz

    reg  signed [17:0] lp1 = 18'sd0, lp2 = 18'sd0;
    wire signed [17:0] x18   = {{2{disp_ac[15]}}, disp_ac};
    wire signed [17:0] lp1_n = lp1 + ((x18  - lp1) >>> LISSA_LP_K);
    wire signed [17:0] lp2_n = lp2 + ((lp1_n - lp2) >>> LISSA_LP_K);

    wire signed [15:0] flt = (lp2_n > 18'sd32767)  ? 16'sd32767 :
                             (lp2_n < -18'sd32768) ? -16'sd32768 :
                                                     lp2_n[15:0];

    reg signed [15:0] d1 = 16'sd0,  d2 = 16'sd0,  d3 = 16'sd0,  d4 = 16'sd0;
    reg signed [15:0] d5 = 16'sd0,  d6 = 16'sd0,  d7 = 16'sd0,  d8 = 16'sd0;
    reg signed [15:0] d9 = 16'sd0,  d10= 16'sd0,  d11= 16'sd0,  d12= 16'sd0;
    reg signed [15:0] d13= 16'sd0,  d14= 16'sd0,  d15= 16'sd0,  d16= 16'sd0;
    reg signed [15:0] d17= 16'sd0,  d18= 16'sd0,  d19= 16'sd0,  d20= 16'sd0;
    reg signed [15:0] d21= 16'sd0,  d22= 16'sd0,  d23= 16'sd0,  d24= 16'sd0;

    // 移位前读 d24 = flt[n-24]；与 flt[n] 组成当前采样的 (X,Y)
    wire signed [15:0] y_cur = d24;

    function signed [15:0] atts;
        input signed [15:0] v;
        input [1:0]         a;
        begin

            atts = (a == 2'd0) ? (v - (v >>> 2)) :
                   (a == 2'd1) ? (v >>> 1) : (v >>> 2);
        end
    endfunction

    // 相邻两个音频采样点的 (X,Y)（已按 att 缩放）
    reg  signed [15:0] ax = 16'sd0, ay = 16'sd0;   // A = 上一个采样
    reg  signed [15:0] bx = 16'sd0, by = 16'sd0;   // B = 当前采样
    wire signed [15:0] bx_n = atts(flt,   att);
    wire signed [15:0] by_n = atts(y_cur, att);

    wire signed [17:0] axs = {{2{ax[15]}}, ax};
    wire signed [17:0] ays = {{2{ay[15]}}, ay};
    wire signed [17:0] bxs = {{2{bx[15]}}, bx};
    wire signed [17:0] bys = {{2{by[15]}}, by};
    wire signed [17:0] ddx = bxs - axs;
    wire signed [17:0] ddy = bys - ays;
    wire signed [17:0] ix1 = axs + (ddx >>> 2);
    wire signed [17:0] iy1 = ays + (ddy >>> 2);
    wire signed [17:0] ix2 = axs + (ddx >>> 1);
    wire signed [17:0] iy2 = ays + (ddy >>> 1);
    wire signed [17:0] ix3 = axs + ddx - (ddx >>> 2);
    wire signed [17:0] iy3 = ays + ddy - (ddy >>> 2);

    always @(posedge clk) begin
        if (audio_tick) begin
            lp1 <= lp1_n;
            lp2 <= lp2_n;

            d1  <= flt;
            d2  <= d1;
            d3  <= d2;
            d4  <= d3;
            d5  <= d4;
            d6  <= d5;
            d7  <= d6;
            d8  <= d7;
            d9  <= d8;
            d10 <= d9;
            d11 <= d10;
            d12 <= d11;
            d13 <= d12;
            d14 <= d13;
            d15 <= d14;
            d16 <= d15;
            d17 <= d16;
            d18 <= d17;
            d19 <= d18;
            d20 <= d19;
            d21 <= d20;
            d22 <= d21;
            d23 <= d22;
            d24 <= d23;

            // 区间滚动：A ← 上一个 B，B ← 新采样
            ax <= bx;
            ay <= by;
            bx <= bx_n;
            by <= by_n;
        end

        if (sub_tick) begin
            case (cnt[9:8])
                2'd0:    begin lissa_x <= bx;          lissa_y <= by;          end
                2'd1:    begin lissa_x <= ix1[15:0];   lissa_y <= iy1[15:0];   end
                2'd2:    begin lissa_x <= ix2[15:0];   lissa_y <= iy2[15:0];   end
                default: begin lissa_x <= ix3[15:0];   lissa_y <= iy3[15:0];   end
            endcase
            tgl_r <= ~tgl_r;
        end
    end

endmodule
