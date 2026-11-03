// vibrato.v — 颤音（音高周期性抖动）LFO + 深度

module vibrato (
    input  wire               clk,
    input  wire               rst_n,      // 顶层恒接 1'b1
    input  wire               sample_strobe,
    input  wire [1:0]         expr_sel,   // 2 = 颤音，其它档输出恒 0
    input  wire [1:0]         expr_amt,   // 深度档位 0~3
    output wire signed [15:0] vib_q15     // 已按 sample_strobe 锁存；非颤音档恒 0
);

    reg [22:0] cnt = 23'd0;

    always @(posedge clk)
        cnt <= cnt + 23'd1;

    wire [15:0] tri16 = cnt[22] ? ~cnt[21:6] : cnt[21:6];      // 0..65535

    // 折成双极：−32768 .. +32767
    wire signed [16:0] lfo_w = {1'b0, tri16} - 17'sd32768;
    wire signed [15:0] lfo_b = lfo_w[15:0];

    reg signed [15:0] depth;

    always @(*) begin
        case (expr_amt)
            2'd0:    depth = 16'sd262;    // 0.8%  ≈ 14 音分（默认档，已经清楚可辨）
            2'd1:    depth = 16'sd459;    // 1.4%  ≈ 24 音分
            2'd2:    depth = 16'sd721;    // 2.2%  ≈ 38 音分
            default: depth = 16'sd1049;   // 3.2%  ≈ 55 音分（很宽，演示用）
        endcase
    end

    // 32767 × 819 = 2.7e7 ⇒ 32 位装得下，不会回绕
    wire signed [31:0] vib_full = lfo_b * depth;
    wire signed [15:0] vib_calc = vib_full[30:15];   // >>15 还原 Q15 量级

    reg signed [15:0] vib_r = 16'sd0;

    always @(posedge clk) begin
        if (sample_strobe)
            vib_r <= (expr_sel == 2'd2) ? vib_calc : 16'sd0;
    end

    assign vib_q15 = vib_r;

endmodule
