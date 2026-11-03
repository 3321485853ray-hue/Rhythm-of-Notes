// btn_shortlong.v — 短按 / 长按 判别

module btn_shortlong #(
    parameter [14:0] LONG_SAMPLES = 15'd24414,     // 长按阈值：0.5s @ 48828.125Hz
    parameter [19:0] DEB_CNT      = 20'd150000     // 消抖时间（透传给 key_debounce）
)(
    input  wire clk,
    input  wire rst_n,          // 顶层恒接 1'b1
    input  wire sample_strobe,  // 每采样一次一个周期高
    input  wire key_in,         // EC11 按钮（低有效）
    output wire short_press,    // 松开时若没到长按阈值 ⇒ 一个采样周期的高
    output wire long_press      // 达到长按阈值 ⇒ 一个采样周期的高（按住时立即发）
);

    wire level;
    key_debounce #(.CNT_MAX(DEB_CNT)) u_db (
        .clk (clk), .rst_n (rst_n), .key_in (key_in), .key_level (level)
    );

    reg [14:0] cnt     = 15'd0;
    reg        held    = 1'b0;      // 本次按压是否已经发过长按
    reg        level_d = 1'b0;
    reg        short_r = 1'b0;
    reg        long_r  = 1'b0;

    assign short_press = short_r;
    assign long_press  = long_r;

    always @(posedge clk) begin

        short_r <= 1'b0;
        long_r  <= 1'b0;

        if (!rst_n) begin
            cnt <= 15'd0; held <= 1'b0; level_d <= 1'b0;
        end else if (sample_strobe) begin
            level_d <= level;

            if (level && !level_d) begin
                // 按下：重新开始计时
                cnt  <= 15'd1;
                held <= 1'b0;
            end else if (level) begin

                if (!held) begin
                    if (cnt >= LONG_SAMPLES) begin
                        long_r <= 1'b1;
                        held   <= 1'b1;
                    end else
                        cnt <= cnt + 15'd1;
                end
            end else if (level_d) begin
                // 松开：只有"没发过长按"才算短按
                if (!held) short_r <= 1'b1;
                cnt <= 15'd0;
            end
        end
    end

endmodule
