// uart_rx.v — 115200 8N1 接收器（16× 过采样，相位累加器分频）

module uart_rx #(
    parameter [31:0] STEP = 32'd158329674   // 16 × 115200 × 2^32 / 50e6
)(
    input  wire       clk,
    input  wire       rx,           // 原始串口输入（空闲为高）
    output reg  [7:0] dout,         // 收到的字节
    output reg        dout_valid    // 单拍脉冲
);

    reg  [31:0] acc = 32'd0;
    wire [32:0] acc_n = {1'b0, acc} + {1'b0, STEP};
    wire        tick  = acc_n[32];              // 进位 = 一个 16× 节拍

    always @(posedge clk)
        acc <= acc_n[31:0];

    reg rx_s1 = 1'b1, rx_s2 = 1'b1;
    always @(posedge clk) begin
        rx_s1 <= rx;
        rx_s2 <= rx_s1;
    end

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0] st   = S_IDLE;
    reg [3:0] tcnt = 4'd0;      // 位内 16× 节拍计数（自然回绕 15→0）
    reg [2:0] bcnt = 3'd0;      // 数据位序号
    reg [7:0] sh   = 8'd0;      // 移位寄存器（LSB 先移入）

    always @(posedge clk) begin
        dout_valid <= 1'b0;

        case (st)
            // 等起始位：同步后看到 1→0 的边沿（rx_s1 比 rx_s2 早一拍）
            S_IDLE: begin
                tcnt <= 4'd0;

                if (!rx_s1 && rx_s2) begin
                    st   <= S_START;
                    bcnt <= 3'd0;
                    sh   <= 8'd0;
                end
            end

            // 起始位中点确认（毛刺则丢弃）
            S_START: if (tick) begin
                tcnt <= tcnt + 4'd1;
                if (tcnt == 4'd7) begin
                    if (~rx_s1) st <= S_DATA;
                    else        st <= S_IDLE;
                end
            end

            // 8 个数据位，中点采样，LSB 先
            S_DATA: if (tick) begin
                tcnt <= tcnt + 4'd1;
                if (tcnt == 4'd7) begin
                    sh <= {rx_s1, sh[7:1]};
                    if (bcnt == 3'd7) st   <= S_STOP;
                    else              bcnt <= bcnt + 3'd1;
                end
            end

            // 停止位中点：高 = 正常收完，低 = 帧错（丢弃，不报）
            S_STOP: if (tick) begin
                tcnt <= tcnt + 4'd1;
                if (tcnt == 4'd7) begin
                    if (rx_s1) begin
                        dout       <= sh;      // 8 次移位后 sh 正好是 {d7..d0}
                        dout_valid <= 1'b1;
                    end
                    st   <= S_IDLE;
                    tcnt <= 4'd0;
                end
            end

            default: st <= S_IDLE;
        endcase
    end

endmodule
