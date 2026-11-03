// key_scan.v — 12 路按键并行采集（手动例化，不用 generate）

module key_scan (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] key_in,      // 原始输入（低有效）
    output wire [11:0] key_level,   // 消抖后电平（1 = 按下）
    output wire [11:0] key_press,   // 按下脉冲
    output wire [11:0] key_release  // 松开脉冲
);

    wire [11:0] lvl, prs, rel;

    key_debounce u0  (.clk(clk), .rst_n(rst_n), .key_in(key_in[0]),  .key_level(lvl[0]),  .key_press(prs[0]),  .key_release(rel[0]));
    key_debounce u1  (.clk(clk), .rst_n(rst_n), .key_in(key_in[1]),  .key_level(lvl[1]),  .key_press(prs[1]),  .key_release(rel[1]));
    key_debounce u2  (.clk(clk), .rst_n(rst_n), .key_in(key_in[2]),  .key_level(lvl[2]),  .key_press(prs[2]),  .key_release(rel[2]));
    key_debounce u3  (.clk(clk), .rst_n(rst_n), .key_in(key_in[3]),  .key_level(lvl[3]),  .key_press(prs[3]),  .key_release(rel[3]));
    key_debounce u4  (.clk(clk), .rst_n(rst_n), .key_in(key_in[4]),  .key_level(lvl[4]),  .key_press(prs[4]),  .key_release(rel[4]));
    key_debounce u5  (.clk(clk), .rst_n(rst_n), .key_in(key_in[5]),  .key_level(lvl[5]),  .key_press(prs[5]),  .key_release(rel[5]));
    key_debounce u6  (.clk(clk), .rst_n(rst_n), .key_in(key_in[6]),  .key_level(lvl[6]),  .key_press(prs[6]),  .key_release(rel[6]));
    key_debounce u7  (.clk(clk), .rst_n(rst_n), .key_in(key_in[7]),  .key_level(lvl[7]),  .key_press(prs[7]),  .key_release(rel[7]));
    key_debounce u8  (.clk(clk), .rst_n(rst_n), .key_in(key_in[8]),  .key_level(lvl[8]),  .key_press(prs[8]),  .key_release(rel[8]));
    key_debounce u9  (.clk(clk), .rst_n(rst_n), .key_in(key_in[9]),  .key_level(lvl[9]),  .key_press(prs[9]),  .key_release(rel[9]));
    key_debounce u10 (.clk(clk), .rst_n(rst_n), .key_in(key_in[10]), .key_level(lvl[10]), .key_press(prs[10]), .key_release(rel[10]));
    key_debounce u11 (.clk(clk), .rst_n(rst_n), .key_in(key_in[11]), .key_level(lvl[11]), .key_press(prs[11]), .key_release(rel[11]));

    assign key_level   = lvl;
    assign key_press   = prs;
    assign key_release = rel;

endmodule
