// delay_line.v — 参数化环形延迟线

module delay_line #(
    parameter integer DEPTH = 1024,     // 深度，必须是 2 的幂
    parameter integer AW    = 10        // log2(DEPTH)
)(
    input  wire               clk,
    input  wire               we,           // 写使能（每个采样点一次）
    input  wire signed [15:0] din,
    input  wire [AW-1:0]      tap,          // 延迟量（多少个采样点）
    output reg  signed [15:0] dout
);

    reg signed [15:0] mem [0:DEPTH-1];
    reg [AW-1:0]      wptr = 0;

    always @(posedge clk) begin
        if (we) begin
            mem[wptr] <= din;
            wptr      <= wptr + 1'b1;       // 2 的幂 ⇒ 自然回绕
        end
        // 组合地址 + 同步读：一次寻址一次读，标准 SDP BSRAM 写法
        dout <= mem[wptr - tap];
    end

endmodule
