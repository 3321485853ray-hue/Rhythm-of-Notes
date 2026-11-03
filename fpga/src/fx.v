// fx.v — FPGA 内部数字音频效果器

module fx (
    input  wire               clk,
    input  wire               rst_n,        // 顶层恒接 1'b1
    input  wire               sample_strobe,// 每采样一次一个周期高
    input  wire               dly_up,
    input  wire               dly_dn,       //             逆时针一格
    input  wire               dly_sw,       //             SW 按下（开关）
    input  wire               rev_up,
    input  wire               rev_dn,
    input  wire               rev_sw,
    input  wire               cho_up,
    input  wire               cho_dn,
    input  wire               cho_sw,
    input  wire signed [15:0] din,          // 单极性（0..~8190）
    input  wire [11:0]        dc_in,
    output wire [1:0]         fx_sel,
    output wire [2:0]         fx_on,        // {cho_on, rev_on, dly_on}
    output wire [1:0]         dly_gear,
    output wire [1:0]         rev_gear,
    output wire [1:0]         cho_gear,
    output wire signed [15:0] dout
);

    reg dly_on = 1'b0;
    reg rev_on = 1'b0;
    reg cho_on = 1'b0;

    assign fx_sel = {1'b0, dly_on} + {1'b0, rev_on} + {1'b0, cho_on};

    // 文字层用的只读扇出：开关位与各自档位（不参与音频运算）
    assign fx_on    = {cho_on, rev_on, dly_on};

    reg [1:0] dly_p = 2'd0;      // 延迟时间 80/160/240/320 ms（= 原来的 famt_r=0）

    reg [1:0] rev_p = 2'd0;      // 混响 小房间→大厅，上电 = 档0（L1，最干）
    reg [1:0] cho_p = 2'd0;      // 合唱深度（= 原来的 famt_r=0 ⇒ sh=10）

    // 文字层只读扇出（放在档位 reg 之后，见上）
    assign dly_gear = dly_p;
    assign rev_gear = rev_p;
    assign cho_gear = cho_p;

    always @(posedge clk) begin

        if (dly_up   && dly_p != 2'd3) dly_p <= dly_p + 2'd1;
        if (dly_dn   && dly_p != 2'd0) dly_p <= dly_p - 2'd1;
        // 混响 4 档 0~3，两端夹紧（档3 = 最湿 = 上电默认）
        if (rev_up   && rev_p != 2'd3) rev_p <= rev_p + 2'd1;
        if (rev_dn   && rev_p != 2'd0) rev_p <= rev_p - 2'd1;
        if (cho_up   && cho_p != 2'd3) cho_p <= cho_p + 2'd1;
        if (cho_dn   && cho_p != 2'd0) cho_p <= cho_p - 2'd1;

        if (dly_sw) dly_on <= ~dly_on;
        if (rev_sw) rev_on <= ~rev_on;
        if (cho_sw) cho_on <= ~cho_on;
    end

    reg [9:0] fc = 10'd0;
    always @(posedge clk) fc <= fc + 10'd1;
    wire st_dly = (fc == 10'd0);
    wire st_rev = (fc == 10'd64);
    wire st_cho = (fc == 10'd128);

    wire [13:0] dly_tap = (dly_p == 2'd0) ? 14'd3906  :
                          (dly_p == 2'd1) ? 14'd7812  :
                          (dly_p == 2'd2) ? 14'd11719 : 14'd15625;

    wire signed [15:0] dly;
    wire signed [15:0] dly_in;

    delay_line #(.DEPTH(16384), .AW(14)) u_dl (
        .clk  (clk),
        .we   (st_dly),
        .din  (dly_in),
        .tap  (dly_tap),
        .dout (dly)
    );

    wire signed [15:0] fb = (dly >>> 2) + (dly >>> 3);

    wire signed [16:0] dly_in_w = din + fb;          // 17 位，加法不溢出

    assign dly_in = (dly_in_w > 17'sd16380) ? 16'sd16380 :
                    (dly_in_w < 17'sd0)     ? 16'sd0     : dly_in_w[15:0];

    wire signed [15:0] wet   = dly >>> 1;            // ×0.5（移位）

    wire signed [16:0] dry_ac = $signed({{1{din[15]}}, din}) - $signed({5'b0, dc_in});

    reg [15:0] warm = 16'd0;

    always @(posedge clk) begin
        if (!rst_n)
            warm <= 16'd0;
        else if (st_dly && warm != 16'hFFFF)
            warm <= warm + 16'd1;
    end

    wire wet_ok = (warm == 16'hFFFF);

    wire signed [15:0] rev_out;
    wire signed [15:0] cho_out;
    wire signed [19:0] rev_wet;
    wire signed [15:0] cho_wet;

    reverb u_reverb (
        .clk           (clk),
        .rst_n         (rst_n),
        .sample_strobe (st_rev),
        .gear_in       (rev_p),
        .din           (din),
        .dc_in         (dc_in),
        .wet_out       (rev_wet),
        .dout          (rev_out)
    );

    chorus u_chorus (
        .clk           (clk),
        .rst_n         (rst_n),
        .sample_strobe (st_cho),
        .fx_amt        (cho_p),
        .din           (din),
        .wet_out       (cho_wet),
        .dout          (cho_out)
    );

    wire signed [15:0] dc_w = $signed({4'b0, dc_in});                          // 干声的直流

    wire signed [27:0] dc_q = {dc_w, 12'b0};              // dc_w × 4096（Q12.12）

    reg  signed [27:0] dramp = 28'sd0;
    wire signed [27:0] da13 = (dc_q - dramp) >>> 13;
    wire signed [27:0] da14 = (dc_q - dramp) >>> 14;
    wire signed [27:0] da15 = (dc_q - dramp) >>> 15;
    wire signed [27:0] dda  = (dly_p == 2'd2) ? da14 : (dly_p == 2'd3) ? da15 : da13;

    reg  signed [27:0] cramp = 28'sd0;
    wire signed [27:0] cda  = (dc_q - cramp) >>> 10;

    reg [9:0] ssdiv = 10'd0;
    always @(posedge clk) ssdiv <= ssdiv + 10'd1;
    wire ss_l = (ssdiv == 10'd0);          // 50MHz/1024 ≈ 48.8kHz

    always @(posedge clk) if (ss_l) begin
        dramp <= dramp + dda;
        cramp <= cramp + cda;
    end

    wire signed [16:0] dc_rd   = dramp[24:12];                                  // 延迟的直流（整数部分）
    wire signed [16:0] dc_rc   = cramp[24:12];                                  // 合唱的直流
    wire signed [16:0] dly_dc  = (dc_rd >>> 1) + (dc_rd >>> 2) + (dc_rd >>> 4); // ≈0.8125×
    wire signed [16:0] cho_dc  = (dc_rc >>> 1);                                 // 0.5×（精确）
    wire signed [16:0] w_dly   = $signed({{1{wet[15]}}, wet})         - dly_dc; // 延迟的纯湿声
    wire signed [16:0] w_cho   = $signed({{1{cho_wet[15]}}, cho_wet}) - cho_dc; // 合唱的纯湿声

    wire signed [20:0] wet_sum = (dly_on ? $signed({{4{w_dly[16]}}, w_dly}) : 21'sd0)
                               + (rev_on ? $signed({{1{rev_wet[19]}}, rev_wet}) : 21'sd0)
                               + (cho_on ? $signed({{4{w_cho[16]}}, w_cho}) : 21'sd0);

    wire signed [20:0] wet_sc = (dly_on & rev_on & cho_on)
                              ? (wet_sum - (wet_sum >>> 2))
                              : wet_sum;

    wire signed [22:0] fx_mix = $signed({{6{dry_ac[16]}}, dry_ac}) + $signed({{1{wet_sc[20]}}, wet_sc});

    wire signed [15:0] fx_out = (fx_mix > 23'sd16380) ? 16'sd16380 :
                                (fx_mix < -23'sd16380) ? -16'sd16380 : fx_mix[15:0];

    wire any_on = dly_on | rev_on | cho_on;

    assign dout = (any_on && wet_ok) ? fx_out : din;

endmodule
