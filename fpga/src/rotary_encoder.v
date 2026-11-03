// rotary_encoder.v — EC11 旋转编码器正交解码

module rotary_encoder (
    input  wire clk,
    input  wire rst_n,
    input  wire a,          // EC11 A 相
    input  wire b,          // EC11 B 相
    output wire cw,         // 一个正交跳变（单周期脉冲）
    output wire ccw         // 一个正交跳变（单周期脉冲）
);

    // 两级同步（抗亚稳态/毛刺）
    reg [1:0] a_sync = 2'b00;
    reg [1:0] b_sync = 2'b00;
    always @(posedge clk) begin
        a_sync <= {a_sync[0], a};
        b_sync <= {b_sync[0], b};
    end

    // 当前 / 上一个 Gray 状态
    reg [1:0] q = 2'b00;
    reg [1:0] q_prev = 2'b00;
    always @(posedge clk) begin
        q       <= {a_sync[1], b_sync[1]};
        q_prev  <= q;
    end

    // 只认合法相邻态跳变
    assign cw  = (q_prev == 2'b00 && q == 2'b01) ||
                 (q_prev == 2'b01 && q == 2'b11) ||
                 (q_prev == 2'b11 && q == 2'b10) ||
                 (q_prev == 2'b10 && q == 2'b00);

    assign ccw = (q_prev == 2'b00 && q == 2'b10) ||
                 (q_prev == 2'b10 && q == 2'b11) ||
                 (q_prev == 2'b11 && q == 2'b01) ||
                 (q_prev == 2'b01 && q == 2'b00);

endmodule
