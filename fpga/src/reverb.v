// reverb.v — 混响

module reverb (
    input  wire               clk,
    input  wire               rst_n,        // 顶层恒接 1'b1
    input  wire               sample_strobe,
    input  wire [1:0]         gear_in,
    input  wire signed [15:0] din,          // 单极性（0..~8190）
    input  wire [11:0]        dc_in,
    output wire signed [19:0] wet_out,
    output wire signed [15:0] dout
);

    wire [1:0] rev_gear = gear_in;

    wire signed [15:0] p0, p1, p2, p3, p4, p5, p6, p7;

`ifndef REV_MOD_SH
    `define REV_MOD_SH 7           // >>>7 ⇒ ±128（Q4）⇒ ±8 个采样点
`endif

    reg [25:0] lfo_cnt = 26'd0;
    always @(posedge clk) lfo_cnt <= lfo_cnt + 26'd1;

    function [14:0] tri15;             // 26 位相位 → 15 位三角波 0..32767
        input [25:0] p;
        begin
            tri15 = p[25] ? ~p[24:10] : p[24:10];
        end
    endfunction

    wire [25:0] ph0 = lfo_cnt + 26'h000_0000;
    wire [25:0] ph1 = lfo_cnt + 26'h080_0000;
    wire [25:0] ph2 = lfo_cnt + 26'h100_0000;
    wire [25:0] ph3 = lfo_cnt + 26'h180_0000;
    wire [25:0] ph4 = lfo_cnt + 26'h200_0000;
    wire [25:0] ph5 = lfo_cnt + 26'h280_0000;
    wire [25:0] ph6 = lfo_cnt + 26'h300_0000;
    wire [25:0] ph7 = lfo_cnt + 26'h380_0000;

    wire [25:0] ph8  = lfo_cnt + 26'h040_0000;
    wire [25:0] ph9  = lfo_cnt + 26'h140_0000;
    wire [25:0] ph10 = lfo_cnt + 26'h2C0_0000;

`ifdef REV_MOD_OFF
    wire signed [15:0] mod0 = 16'sd0;   // 关掉调制：恒 0 ⇒ 插值退化成取整数抽头
    wire signed [15:0] mod1 = 16'sd0;
    wire signed [15:0] mod2 = 16'sd0;
    wire signed [15:0] mod3 = 16'sd0;
    wire signed [15:0] mod4 = 16'sd0;
    wire signed [15:0] mod5 = 16'sd0;
    wire signed [15:0] mod6 = 16'sd0;
    wire signed [15:0] mod7 = 16'sd0;
    wire signed [15:0] modd0 = 16'sd0;  // 扩散级三路（同样可关）
    wire signed [15:0] modd1 = 16'sd0;
    wire signed [15:0] modd2 = 16'sd0;
`else
    wire signed [15:0] mod0 = ($signed({1'b0, tri15(ph0)}) - 16'sd16384) >>> `REV_MOD_SH;
    wire signed [15:0] mod1 = ($signed({1'b0, tri15(ph1)}) - 16'sd16384) >>> `REV_MOD_SH;
    wire signed [15:0] mod2 = ($signed({1'b0, tri15(ph2)}) - 16'sd16384) >>> `REV_MOD_SH;
    wire signed [15:0] mod3 = ($signed({1'b0, tri15(ph3)}) - 16'sd16384) >>> `REV_MOD_SH;
    wire signed [15:0] mod4 = ($signed({1'b0, tri15(ph4)}) - 16'sd16384) >>> `REV_MOD_SH;
    wire signed [15:0] mod5 = ($signed({1'b0, tri15(ph5)}) - 16'sd16384) >>> `REV_MOD_SH;
    wire signed [15:0] mod6 = ($signed({1'b0, tri15(ph6)}) - 16'sd16384) >>> `REV_MOD_SH;
    wire signed [15:0] mod7 = ($signed({1'b0, tri15(ph7)}) - 16'sd16384) >>> `REV_MOD_SH;

    wire signed [15:0] modd0 = ($signed({1'b0, tri15(ph8 )}) - 16'sd16384) >>> `REV_MOD_SH;
    wire signed [15:0] modd1 = ($signed({1'b0, tri15(ph9 )}) - 16'sd16384) >>> `REV_MOD_SH;
    wire signed [15:0] modd2 = ($signed({1'b0, tri15(ph10)}) - 16'sd16384) >>> `REV_MOD_SH;
`endif

    reg [9:0] rc = 10'd0;
    always @(posedge clk) rc <= rc + 10'd1;
    wire st_c0 = (rc == 10'd200);   // 并联梳状 0..3
    wire st_c1 = (rc == 10'd300);   // 并联梳状 4..7
    wire st_a  = (rc == 10'd400);   // 扩散级全通
    wire st_d  = (rc == 10'd500);   // 直流斜坡

    comb_norm #(.DEPTH(2048), .AW(11), .M(11'd1235)) u_p0
        (.clk(clk), .we(st_c0), .x(din), .gear(rev_gear), .mod_q4(mod0 ), .y(p0 ));
    comb_norm #(.DEPTH(2048), .AW(11), .M(11'd1315)) u_p1
        (.clk(clk), .we(st_c0), .x(din), .gear(rev_gear), .mod_q4(mod1 ), .y(p1 ));
    comb_norm #(.DEPTH(2048), .AW(11), .M(11'd1413)) u_p2
        (.clk(clk), .we(st_c0), .x(din), .gear(rev_gear), .mod_q4(mod2 ), .y(p2 ));
    comb_norm #(.DEPTH(2048), .AW(11), .M(11'd1501)) u_p3
        (.clk(clk), .we(st_c0), .x(din), .gear(rev_gear), .mod_q4(mod3 ), .y(p3 ));
    comb_norm #(.DEPTH(2048), .AW(11), .M(11'd1574)) u_p4
        (.clk(clk), .we(st_c1), .x(din), .gear(rev_gear), .mod_q4(mod4 ), .y(p4 ));
    comb_norm #(.DEPTH(2048), .AW(11), .M(11'd1650)) u_p5
        (.clk(clk), .we(st_c1), .x(din), .gear(rev_gear), .mod_q4(mod5 ), .y(p5 ));
    comb_norm #(.DEPTH(2048), .AW(11), .M(11'd1724)) u_p6
        (.clk(clk), .we(st_c1), .x(din), .gear(rev_gear), .mod_q4(mod6 ), .y(p6 ));
    comb_norm #(.DEPTH(2048), .AW(11), .M(11'd1790)) u_p7
        (.clk(clk), .we(st_c1), .x(din), .gear(rev_gear), .mod_q4(mod7 ), .y(p7 ));

    wire signed [18:0] par_sum = p0 + p1 + p2 + p3 + p4 + p5 + p6 + p7;
    wire signed [15:0] par_mix = par_sum >>> 3;

    wire signed [15:0] d1, d2, d3;

    allpass #(.DEPTH(1024), .AW(10), .M(10'd615)) u_d1
        (.clk(clk), .we(st_a), .x(par_mix), .mod_q4(modd0), .y(d1));
    allpass #(.DEPTH(1024), .AW(10), .M(10'd488)) u_d2
        (.clk(clk), .we(st_a), .x(d1),      .mod_q4(modd1), .y(d2));
    allpass #(.DEPTH(1024), .AW(10), .M(10'd377)) u_d3
        (.clk(clk), .we(st_a), .x(d2),      .mod_q4(modd2), .y(d3));

    wire signed [15:0] wet = d3;

`ifndef REV_WET_SH

  `define REV_WET_SH 2
`endif
    wire signed [16:0] dc_w   = $signed({5'b0, dc_in});   // 干声的直流（稳态值，精确）

    wire signed [16:0] dry_ac = $signed({{1{din[15]}}, din}) - dc_w;   // 干声的纯交流

    wire signed [24:0] dc_in_q   = {1'b0, dc_in, 12'b0};        // dc_in × 4096（Q12.12）
    reg  signed [24:0] dc_ramp_q = 25'sd0;

    wire signed [24:0] dc_dq13 = (dc_in_q - dc_ramp_q) >>> 13;   // τ = 8192 采样 ≈ 168 ms（档0/档1）
    wire signed [24:0] dc_dq14 = (dc_in_q - dc_ramp_q) >>> 14;   // τ = 16384 采样 ≈ 336 ms（档2）

    wire signed [24:0] dc_dq15 = (dc_in_q - dc_ramp_q) >>> 15;   // τ = 32768 采样 ≈ 671 ms

    wire signed [24:0] dc_dq   = (rev_gear == 2'd3) ? dc_dq15 :
                                 (rev_gear == 2'd2) ? dc_dq14 : dc_dq13;

    always @(posedge clk) if (st_d)
        dc_ramp_q <= dc_ramp_q + dc_dq;
    wire signed [12:0] dc_ramp_i = dc_ramp_q[24:12];           // 整数部分
    wire signed [16:0] dc_ramp   = $signed({{4{dc_ramp_i[12]}}, dc_ramp_i});
    wire signed [16:0] wet_ac = $signed({{1{wet[15]}}, wet}) - dc_ramp;   // 湿声的纯交流

    wire signed [19:0] wet_s0 = {{2{wet_ac[16]}}, wet_ac, 1'b0};   // ×2
    wire signed [19:0] wet_s1 = {{2{wet_ac[16]}}, wet_ac, 1'b0}    // ×2
                              + {{3{wet_ac[16]}}, wet_ac};         // + ×1 ⇒ ×3（档1，g=0.75）

    wire signed [19:0] wet_s2 = {{1{wet_ac[16]}}, wet_ac, 2'b00};  // ×4（档2，g=0.875）
    wire signed [19:0] wet_s3 = {{2{wet_ac[16]}}, wet_ac, 1'b0}    // ×2
                              + {{1{wet_ac[16]}}, wet_ac, 2'b00}   // + ×4
                              + {{3{wet_ac[16]}}, wet_ac};         // + ×1 ⇒ ×7（档3，g=0.9375）
    wire signed [19:0] wet_mux = (rev_gear == 2'd0) ? wet_s0 :
                                 (rev_gear == 2'd1) ? wet_s1 :
                                 (rev_gear == 2'd2) ? wet_s2 : wet_s3;

    assign wet_out = wet_mux;

    wire signed [23:0] mix_w  = {{7{dry_ac[16]}}, dry_ac}
                              + {{4{wet_mux[19]}}, wet_mux};     // 20 位符号扩展成 24 位

    assign dout = (mix_w > 24'sd16380) ? 16'sd16380 :
                  (mix_w < -24'sd16380) ? -16'sd16380 : mix_w[15:0];

endmodule
