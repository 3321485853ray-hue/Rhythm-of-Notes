// volume_ctrl.v — 音量控制（旋转编码器步进 → Q15 音量）

module volume_ctrl (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cw,         // 顺时针一步脉冲
    input  wire        ccw,        // 逆时针一步脉冲
    output wire [15:0] volume      // Q15 音量 0~32767
);

    localparam [15:0] STEP = 16'd256;

    reg [15:0] volume_r = 16'd32767;   // 默认满音量（= ÷16 定标的电平）
    assign volume = volume_r;

    always @(posedge clk) begin
        if (!rst_n)
            volume_r <= 16'd32767;
        else if (cw) begin
            if (volume_r >= 16'd32767 - STEP)
                volume_r <= 16'd32767;   // 钳顶，防溢出
            else
                volume_r <= volume_r + STEP;
        end
        else if (ccw) begin
            if (volume_r <= STEP)
                volume_r <= 16'd0;       // 钳底
            else
                volume_r <= volume_r - STEP;
        end
    end

endmodule
