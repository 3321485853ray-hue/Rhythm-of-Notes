// chorus.v — 合唱

module chorus (
    input  wire               clk,
    input  wire               rst_n,        // 顶层恒接 1'b1
    input  wire               sample_strobe,
    input  wire [1:0]         fx_amt,       // 深度档位 0~3
    input  wire signed [15:0] din,          // 单极性（0..~8190）
    output wire signed [15:0] wet_out,
                                            //   供 `fx.v` 做"三效果并行求和"用（那边要干声只算一次）
    output wire signed [15:0] dout
);

    localparam [11:0] BASE_TAP = 12'd586;      // 12ms —— 合唱的经典基准延迟

    reg [25:0] cnt = 26'd0;

    always @(posedge clk)
        cnt <= cnt + 26'd1;

    wire [15:0] tri16 = cnt[25] ? ~cnt[24:9] : cnt[24:9];      // 0..65535

    // 折成双极：−32768 .. +32767
    wire signed [16:0] lfo_w = $signed({1'b0, tri16}) - 17'sd32768;

    wire [3:0] sh = (fx_amt == 2'd0) ? 4'd10 :
                    (fx_amt == 2'd1) ? 4'd9  :
                    (fx_amt == 2'd2) ? 4'd8  : 4'd7;

    wire signed [16:0] lfo_off = lfo_w >>> sh;

    wire [11:0] tap_calc = BASE_TAP + lfo_off[11:0];

    reg [11:0] tap_r = 12'd586;

    always @(posedge clk) begin
        if (sample_strobe)
            tap_r <= tap_calc;
    end

    wire signed [15:0] dly;

    delay_line #(.DEPTH(4096), .AW(12)) u_dl (
        .clk  (clk),
        .we   (sample_strobe),
        .din  (din),
        .tap  (tap_r),
        .dout (dly)
    );

    wire signed [15:0] wet   = dly >>> 1;      // ×0.5（移位，零乘法器）
    assign wet_out = wet;
    wire signed [16:0] mix_w = din + wet;

    assign dout = (mix_w > 17'sd16380) ? 16'sd16380 :
                  (mix_w < -17'sd16380) ? -16'sd16380 : mix_w[15:0];

endmodule
