// tremolo.v — 震音（幅度周期性起伏）LFO + 深度

module tremolo (
    input  wire               clk,
    input  wire               rst_n,      // 顶层恒接 1'b1
    input  wire               sample_strobe,
    input  wire [1:0]         expr_sel,   // 3 = 震音，其它档输出 unity
    input  wire [1:0]         expr_amt,   // 深度档位 0~3
    output wire signed [16:0] trem_q15    // 已锁存；恒正；非震音档 = 32768（unity）
);

    reg [21:0] cnt = 22'd0;

    always @(posedge clk)
        cnt <= cnt + 22'd1;

    wire [15:0] tri16 = cnt[21] ? ~cnt[20:5] : cnt[20:5];      // 0..65535

    // 折成单极 0..32767（角度调制只需要"低-高-低"的包络，不需要双极）
    wire [14:0] lfo_u = tri16[15:1];

    reg [15:0] depth;

    always @(*) begin
        case (expr_amt)
            2'd0:    depth = 16'd8192;    // 0.25
            2'd1:    depth = 16'd13107;   // 0.40
            2'd2:    depth = 16'd19661;   // 0.60
            default: depth = 16'd26214;   // 0.80
        endcase
    end

    // 32767 × 22938 = 7.5e8 ⇒ 30 位，装得下
    wire [30:0] drop = ((31'd32767 - {16'd0, lfo_u}) * depth) >> 15;

    wire [16:0] trem_calc = 17'd32768 - drop[16:0];

    reg [16:0] trem_r = 17'd32768;

    always @(posedge clk) begin
        if (sample_strobe)
            trem_r <= (expr_sel == 2'd3) ? trem_calc : 17'd32768;
    end

    assign trem_q15 = trem_r;

endmodule
