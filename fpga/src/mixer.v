// mixer.v — 4 Voice 混音（二级加法树 + 定标 + 饱和保险）

module mixer (
    input  wire               clk,
    input  wire signed [15:0] a0,
    input  wire signed [15:0] a1,
    input  wire signed [15:0] a2,
    input  wire signed [15:0] a3,
    input  wire signed [15:0] a4,
    input  wire signed [15:0] a5,
    input  wire signed [15:0] a6,
    input  wire signed [15:0] a7,
    input  wire signed [15:0] a8,
    input  wire signed [15:0] a9,
    input  wire signed [15:0] a10,
    input  wire signed [15:0] a11,
    output wire signed [15:0] mix
);

    reg signed [15:0] mix_r = 16'sd0;
    assign mix = mix_r;

    localparam [3:0] SUM_SHIFT = 4'd4;

    wire signed [16:0] s01   = a0  + a1;
    wire signed [16:0] s23   = a2  + a3;
    wire signed [16:0] s45   = a4  + a5;
    wire signed [16:0] s67   = a6  + a7;
    wire signed [16:0] s89   = a8  + a9;
    wire signed [16:0] s1011 = a10 + a11;
    wire signed [17:0] q03   = s01  + s23;
    wire signed [17:0] q47   = s45  + s67;
    wire signed [17:0] q811  = s89  + s1011;
    wire signed [18:0] r07   = q03  + q47;
    wire signed [19:0] sum   = r07 + q811;

    wire signed [19:0] sc = { {4{sum[19]}}, sum[19:4] };   // = sum >>> 4（÷16），20 位

    always @(posedge clk) begin
        if      (sc >  20'sd32767) mix_r <= 16'sh7FFF;   // +32767
        else if (sc < -20'sd32768) mix_r <= 16'sh8000;   // -32768
        else                       mix_r <= sc[15:0];
    end

endmodule
