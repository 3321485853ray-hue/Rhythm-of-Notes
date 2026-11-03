// comb_norm.v — 归一化梳状滤波器

module comb_norm #(
    parameter integer  DEPTH = 2048,       // 延迟线深度，必须是 2 的幂
    parameter integer  AW    = 11,         // log2(DEPTH)
    parameter [AW-1:0] M     = 11'd1235     // 延迟长度（采样点）
)(
    input  wire               clk,
    input  wire               we,           // 写使能（每个采样点一次 = sample_strobe）
    input  wire signed [15:0] x,            // 输入（单极性 ≥ 0）
    input  wire [1:0]         gear,         // 衰减档位 0~3（扩散级固定接 2'd0）
    input  wire signed [15:0] mod_q4,
    output wire signed [15:0] y             // 输出（单极性 ≥ 0，可证）
);

    wire signed [15:0] y_d;

    wire signed [15:0] a_x = (gear == 2'd0) ? ((x + 16'sd1) >>> 1) :   // a=0.5
                             (gear == 2'd1) ? ((x + 16'sd2) >>> 2) :   // a=0.25
                             (gear == 2'd2) ? ((x + 16'sd4) >>> 3) :   // a=0.125
                                              ((x + 16'sd8) >>> 4);    // a=0.0625

    reg signed [15:0] damp_s = 16'sd0;
    always @(posedge clk) if (we)
        damp_s <= (y_d - ((y_d + 16'sd1) >>> 1)) + ((damp_s + 16'sd1) >>> 1);

    wire signed [15:0] y_lp = damp_s;        // 阻尼后的反馈支路（直流增益 = 1）

    // 与上面 `a_x` 配套：`g = 1 − a`，用前缀和（1~4 项常数移位相加）
    wire signed [15:0] g_y = (gear == 2'd0) ? ((y_lp + 16'sd1) >>> 1) :                                  // g=0.5
                             (gear == 2'd1) ? (((y_lp + 16'sd1) >>> 1) + ((y_lp + 16'sd2) >>> 2)) :      // g=0.75
                             (gear == 2'd2) ? (((y_lp + 16'sd1) >>> 1) + ((y_lp + 16'sd2) >>> 2) +
                                               ((y_lp + 16'sd4) >>> 3)) :                                // g=0.875
                                              (((y_lp + 16'sd1) >>> 1) + ((y_lp + 16'sd2) >>> 2) +
                                               ((y_lp + 16'sd4) >>> 3) + ((y_lp + 16'sd8) >>> 4));       // g=0.9375

    wire signed [16:0] y_w = a_x + g_y;

    wire signed [15:0] y_s = (y_w > 17'sd16380) ? 16'sd16380 :
                             (y_w < -17'sd16380) ? -16'sd16380 : y_w[15:0];

    assign y = y_s;

    wire [15:0]    tapq  = ({{(16-AW){1'b0}}, M} << 4) + mod_q4[15:0];
    wire [AW-1:0]  tap_i = tapq[AW+3 : 4];      // 整数部分
    wire [3:0]     tap_f = tapq[3:0];           // 小数部分（Q4）

    delay_line_frac #(.DEPTH(DEPTH), .AW(AW)) u_dl (
        .clk   (clk),
        .we    (we),
        .din   (y_s),         // 写回去的是这一拍的 y，下 M 拍后从 dout 读出来
        .tap_i (tap_i),
        .tap_f (tap_f),
        .dout  (y_d)
    );

endmodule
