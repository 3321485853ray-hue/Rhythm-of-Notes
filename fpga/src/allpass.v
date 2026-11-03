// allpass.v — 真·Schroeder 全通滤波器

module allpass #(
    parameter integer  DEPTH = 1024,       // 延迟线深度，必须是 2 的幂
    parameter integer  AW    = 10,         // log2(DEPTH)
    parameter [AW-1:0] M     = 10'd615     // 延迟长度（采样点）
)(
    input  wire               clk,
    input  wire               we,           // 写使能（每个采样点一次 = sample_strobe）
    input  wire signed [15:0] x,            // 输入
    input  wire signed [15:0] mod_q4,
    output wire signed [15:0] y             // 输出（|H| ≡ 1，无损）
);

    wire signed [15:0] x_d;                 // x[n−M]
    wire signed [15:0] y_d;                 // y[n−M]
    wire signed [15:0] y_s;                 // 本拍输出（= y[n]，也写回 y 延迟线）

    wire [15:0]   tapq  = ({{(16-AW){1'b0}}, M} << 4) + mod_q4[15:0];
    wire [AW-1:0] tap_i = tapq[AW+3 : 4];
    wire [3:0]    tap_f = tapq[3:0];

    delay_line_frac #(.DEPTH(DEPTH), .AW(AW)) u_x
        (.clk(clk), .we(we), .din(x),   .tap_i(tap_i), .tap_f(tap_f), .dout(x_d));
    delay_line_frac #(.DEPTH(DEPTH), .AW(AW)) u_y
        (.clk(clk), .we(we), .din(y_s), .tap_i(tap_i), .tap_f(tap_f), .dout(y_d));

    wire signed [15:0] gx  = x   >>> 1;                  // g·x[n]     (g = 0.5)
    wire signed [15:0] gy  = y_d >>> 1;                  // g·y[n−M]

    wire signed [16:0] y_w = x_d - gx + gy;

    // 饱和是对称的（±16380）：内部交流可以略微过零，不像 `fx.v` 的延迟线
    // 那样要求恒 ≥ 0（那条单极性约束属于延迟线内部，这里不是）。
    assign y_s = (y_w > 17'sd16380)  ? 16'sd16380 :
                 (y_w < -17'sd16380) ? -16'sd16380 : y_w[15:0];

    assign y = y_s;

endmodule
