// frame_parser.v — 16 字节定长帧解析（滑动窗口 + CRC16）

module frame_parser (
    input  wire         clk,
    input  wire [7:0]   din,
    input  wire         din_valid,
    output reg          frame_valid,   // 单拍：收到一个 CRC 正确的 16 字节帧
    output reg  [127:0] frame,         // frame[127:120] = 第 0 字节
    output reg          err_crc        // 单拍：窗口以 AA 5A 开头但 CRC 不符
);

    reg [127:0] sr = 128'd0;           // 移位窗口，sr[7:0] = 最新字节
    reg [4:0]   n  = 5'd0;             // 已积累字节数（饱和在 16）

    // 把"新字节进来以后"的窗口摆好，再整体判定
    wire [127:0] srn = {sr[119:0], din};

    wire [7:0]  b0 = srn[120 +: 8];    // 第 0 字节
    wire [7:0]  b1 = srn[112 +: 8];    // 第 1 字节
    wire [95:0] dfld = srn[111:16];    // 第 2..13 字节（CRC 覆盖域），b2 在最高位
    wire [15:0] crc_in = {srn[7:0], srn[15:8]};   // 小端：第14 = 低字节，第15 = 高字节

    wire [15:0] crc_calc;
    crc16_calc u_crc (
        .data (dfld),
        .crc  (crc_calc)
    );

    always @(posedge clk) begin
        frame_valid <= 1'b0;
        err_crc     <= 1'b0;

        if (din_valid) begin
            sr <= srn;
            if (n < 5'd16) n <= n + 5'd1;

            // 攒够 16 字节才判（这个字节进来之后正好满 16 ⇒ n == 15）
            if ((n >= 5'd15) && (b0 == 8'hAA) && (b1 == 8'h5A)) begin
                if (crc_calc == crc_in) begin
                    frame       <= srn;
                    frame_valid <= 1'b1;
                    n           <= 5'd0;   // 消费掉这 16 字节，推进
                end else begin
                    err_crc <= 1'b1;       // 报给 cmd_exec 做 ERR_FRAME_CRC 统计
                end
            end
        end
    end

endmodule
