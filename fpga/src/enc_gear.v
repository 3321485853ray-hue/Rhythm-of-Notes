// enc_gear.v — 旋转编码器"档位步进"前端

module enc_gear (
    input  wire clk,
    input  wire rst_n,       // 顶层恒接 1'b1
    input  wire a,           // EC11 A 相（低有效，内部上拉）
    input  wire b,           // EC11 B 相
    input  wire sw,          // EC11 按键（低有效）
    output wire step_up,
    output wire step_down,
    output wire sw_press     // SW 按下脉冲（已消抖）
);

    wire cw, ccw;

    rotary_encoder u_dec (
        .clk  (clk),
        .rst_n(rst_n),
        .a    (a),
        .b    (b),
        .cw   (cw),
        .ccw  (ccw)
    );

    key_debounce u_sw (
        .clk         (clk),
        .rst_n       (rst_n),
        .key_in      (sw),
        .key_level   (),
        .key_press   (sw_press),
        .key_release ()
    );

    reg [1:0] sub = 2'd0;

    always @(posedge clk) begin
        if (cw)       sub <= sub + 2'd1;   // 顺时针
        else if (ccw) sub <= sub - 2'd1;   // 逆时针（对称抵消抖动）
    end

    // "走满 4 步"的那一拍
    assign step_up   = cw  & (sub == 2'd3);
    assign step_down = ccw & (sub == 2'd0);

endmodule
