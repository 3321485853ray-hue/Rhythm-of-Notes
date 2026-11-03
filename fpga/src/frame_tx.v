// frame_tx.v — FPGA → 手机 帧发送器（任意 CMD，16 字节定长）

module frame_tx (
    input  wire        clk,

    // 入队（单拍）
    input  wire        tx_req,
    input  wire [7:0]  tx_cmd,
    input  wire [7:0]  tx_len,
    input  wire [63:0] tx_pay,
    input  wire [7:0]  tx_echo,      // 只有 STATUS 用；其它命令填 0
    output wire        tx_ready,     // 队列没满（可以发，满了会丢最旧的）
    output wire        tx
);

    reg [87:0] f0 = 88'd0, f1 = 88'd0, f2 = 88'd0, f3 = 88'd0;
    reg [2:0]  fc = 3'd0;

    reg        pend_push = 1'b0;
    reg [87:0] pend_data = 88'd0;

    reg         sending = 1'b0;
    reg [3:0]   bi      = 4'd0;
    reg [127:0] fb      = 128'd0;
    reg [7:0]   seq_cnt = 8'd0;

    wire        popping = ~sending && (fc != 3'd0);

    wire        uart_ready;
    wire [7:0]  uart_din_w   = fb[127:120];
    wire        uart_valid_w = sending;

    assign tx_ready = (fc != 3'd4);

    // 正在组帧的那条
    wire [7:0]  c_cmd  = f0[87:80];
    wire [7:0]  c_len  = f0[79:72];
    wire [7:0]  c_echo = f0[71:64];
    wire [63:0] c_pay  = f0[63:0];

    wire [95:0] crc_d = {8'h01, c_cmd, seq_cnt, c_len, c_pay};
    wire [15:0] crc_v;
    crc16_calc u_crc (
        .data (crc_d),
        .crc  (crc_v)
    );

    wire [87:0] push_data = {tx_cmd, tx_len, tx_echo, tx_pay};

    always @(posedge clk) begin

        if (tx_req) begin
            if (popping) begin
                pend_push <= 1'b1;
                pend_data <= push_data;
            end else begin
                if (fc == 3'd0)      f0 <= push_data;
                else if (fc == 3'd1) f1 <= push_data;
                else if (fc == 3'd2) f2 <= push_data;
                else                 f3 <= push_data;
                if (fc != 3'd4) fc <= fc + 3'd1;
            end
        end else if (pend_push) begin
            if (fc == 3'd0)      f0 <= pend_data;
            else if (fc == 3'd1) f1 <= pend_data;
            else if (fc == 3'd2) f2 <= pend_data;
            else                 f3 <= pend_data;
            if (fc != 3'd4) fc <= fc + 3'd1;
            pend_push <= 1'b0;
        end

        if (popping) begin
            fb      <= {8'hAA, 8'h5A, 8'h01, c_cmd, seq_cnt, c_len,
                        c_pay, crc_v[7:0], crc_v[15:8]};
            seq_cnt <= seq_cnt + 8'd1;
            bi      <= 4'd0;
            sending <= 1'b1;
            f0 <= f1;
            f1 <= f2;
            f2 <= f3;
            fc <= fc - 3'd1;
        end

        if (sending && uart_ready) begin
            fb <= {fb[119:0], 8'h00};
            bi <= bi + 4'd1;
            if (bi == 4'd15)
                sending <= 1'b0;
        end
    end

    uart_tx u_uart_tx (
        .clk       (clk),
        .din       (uart_din_w),
        .din_valid (uart_valid_w),
        .din_ready (uart_ready),
        .tx        (tx)
    );

endmodule
