// uart_tx.v — 115200 8N1 发送器（相位累加器定位周期）

module uart_tx #(
    parameter [31:0] STEP = 32'd9895605     // 115200 × 2^32 / 50e6
)(
    input  wire       clk,
    input  wire [7:0] din,
    input  wire       din_valid,
    output wire       din_ready,    // 空闲才收
    output reg        tx = 1'b1
);

    reg  [31:0] acc = 32'd0;
    wire [32:0] acc_n = {1'b0, acc} + {1'b0, STEP};
    wire        tick  = acc_n[32];

    reg [9:0] sh   = 10'h3FF;    // {停止位1, 数据[7:0], 起始位0}
    reg [3:0] bitn = 4'd0;
    reg       busy = 1'b0;

    assign din_ready = ~busy;

    always @(posedge clk) begin
        acc <= acc_n[31:0];

        if (!busy) begin
            acc <= 32'd0;
            if (din_valid) begin
                sh   <= {1'b1, din, 1'b0};
                tx   <= 1'b0;             // 起始位
                bitn <= 4'd0;
                busy <= 1'b1;
            end
        end else if (tick) begin
            if (bitn == 4'd9) begin       // 停止位已发满一位
                busy <= 1'b0;
                tx   <= 1'b1;
            end else begin
                tx   <= sh[1];
                sh   <= {1'b1, sh[9:1]};  // 右移，高位补 1（停止位）
                bitn <= bitn + 4'd1;
            end
        end
    end

endmodule
