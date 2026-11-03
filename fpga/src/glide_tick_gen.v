// glide_tick_gen.v — 滑音的"推进节拍"

module glide_tick_gen (
    input  wire       clk,
    input  wire       rst_n,          // 顶层恒接 1'b1
    input  wire       sample_strobe,
    input  wire [1:0] expr_amt,       // 滑音档位（其它表情档位下这个信号无害）
    output wire       glide_tick      // 1 = 本拍推进一次滑音
);

    // 3 位自由计数器：每采样 +1，8 拍一轮
    reg [2:0] div = 3'd0;

    always @(posedge clk) begin
        if (!rst_n)
            div <= 3'd0;
        else if (sample_strobe)
            div <= div + 3'd1;
    end

    reg [2:0] mask;

    always @(*) begin
        case (expr_amt)
            2'd0:    mask = 3'd0;     // 每拍都推 ⇒ τ=1024 点 ≈ 21ms（默认，快）
            2'd1:    mask = 3'd1;     // 每 2 拍  ⇒ τ ≈ 42ms
            2'd2:    mask = 3'd3;     // 每 4 拍  ⇒ τ ≈ 84ms
            default: mask = 3'd7;     // 每 8 拍  ⇒ τ ≈ 168ms（演示用的慢滑音）
        endcase
    end

    assign glide_tick = (div >= mask);

endmodule
