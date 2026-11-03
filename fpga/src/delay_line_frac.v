// delay_line_frac.v — 分数延迟线

module delay_line_frac #(
    parameter integer DEPTH = 2048,     // 深度，必须是 2 的幂
    parameter integer AW    = 11        // log2(DEPTH)
)(
    input  wire               clk,
    input  wire               we,           // 写使能（每个采样点一次 = sample_strobe）
    input  wire signed [15:0] din,
    input  wire [AW-1:0]      tap_i,        // 延迟的整数部分
    input  wire [3:0]         tap_f,        // 延迟的小数部分（Q4，1/16 采样点）
    output reg  signed [15:0] dout
);

    reg signed [15:0] mem [0:DEPTH-1];
    reg [AW-1:0]      wptr = 0;

    reg [1:0]         ph  = 2'd0;          // 读相位：1 → 读 a_r，2 → 读 a_r−1，0 → 空闲
    reg [1:0]         phd = 2'd0;          // `ph` 延一拍（与 BSRAM 读输出对齐）
    reg [AW-1:0]      a_r = 0;
    reg [3:0]         f_r = 0;
    reg signed [15:0] rd  = 16'sd0;        // BSRAM 同步读输出（比地址晚一拍）
    reg signed [15:0] r0  = 16'sd0;        // mem[a_r]     = din[n − tap_i]
    reg signed [15:0] r1  = 16'sd0;        // mem[a_r − 1] = din[n − tap_i − 1]

    wire [AW-1:0] addr_rd = (ph == 2'd2) ? (a_r - 1'b1) : a_r;

    wire signed [20:0] df   = $signed({{4{r1[15]}}, r1}) - $signed({{4{r0[15]}}, r0});
    wire signed [20:0] tf3  = f_r[3] ? (df <<< 3) : 21'sd0;
    wire signed [20:0] tf2  = f_r[2] ? (df <<< 2) : 21'sd0;
    wire signed [20:0] tf1  = f_r[1] ? (df <<< 1) : 21'sd0;
    wire signed [20:0] tf0  = f_r[0] ?  df        : 21'sd0;
    wire signed [20:0] dsum = tf3 + tf2 + tf1 + tf0;          // = (r1−r0)·f

    wire signed [20:0] y_w = $signed({{4{r0[15]}}, r0}) + (dsum >>> 4);

    // 钳位保留 —— 值域虽然可证，但它是保险：改小数位宽 / 改 mem 内容时挡一道
    wire signed [15:0] y_calc = (y_w > 21'sd32767)  ? 16'sd32767 :
                                (y_w < -21'sd32768) ? -16'sd32768 : y_w[15:0];

    always @(posedge clk) begin
        if (we) begin
            mem[wptr] <= din;
            wptr      <= wptr + 1'b1;          // 2 的幂 ⇒ 自然回绕
            a_r       <= wptr + 1'b1 - tap_i;
            f_r       <= tap_f;
            ph        <= 2'd1;
        end else if (ph == 2'd1) begin
            ph        <= 2'd2;
        end else if (ph == 2'd2) begin
            ph        <= 2'd0;
        end

        rd  <= mem[addr_rd];
        phd <= ph;
        if (phd == 2'd1)      r0 <= rd;
        else if (phd == 2'd2) r1 <= rd;

        dout <= y_calc;
    end

endmodule
