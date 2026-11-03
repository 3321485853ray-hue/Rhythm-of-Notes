// display_cond.v — 显示抽头调理（音频域，只读）

module display_cond (
    input  wire               clk,        // 50 MHz
    input  wire signed [15:0] mix_fx,     // 单极性 0..16380
    input  wire [1:0]         fx_n,        // 已开启的效果器个数（0..3，来自 fx.fx_sel）
    output wire signed [15:0] disp_ac,    // 双极性，±32767
    output wire               active
);

    reg signed [15:0] disp_r = 16'sd0;
    assign disp_ac = disp_r;

    // 48.828 kHz 本地节拍：tick 每 1024 拍一个
    reg [9:0] tick_cnt = 10'd0;
    always @(posedge clk) tick_cnt <= tick_cnt + 1'b1;
    wire tick = (tick_cnt == 10'd0);

    wire signed [16:0] x = {mix_fx[15], mix_fx};
    wire signed [24:0] x_ext = {{8{x[16]}}, x};

    reg  signed [32:0] dc_q = 33'sd0;
    wire signed [32:0] x_q  = {x_ext, 8'b0};         // x×256
    wire signed [32:0] diff_q = x_q - dc_q;
    wire signed [24:0] dc_acc = dc_q[32:8];          // 取回整数部分
    always @(posedge clk) begin
        if (tick)
            dc_q <= dc_q + ((diff_q + 33'sd128) >>> 8);  // Q8 内有符号四舍五入
    end

    wire signed [24:0] ac   = x_ext - dc_acc;

    reg  [2:0]  gsh    = 3'd4;           // 初值 ×16（上电与旧行为一致）
    reg  [32:0] avg_q8 = 33'd0;          // |ac| 的均值包络（Q8）
    wire [24:0] aabs   = ac[24] ? (~ac + 25'd1) : ac;      // |ac|
    wire [32:0] aabs_q8 = {aabs, 8'b0};
    wire signed [33:0] avg_d = $signed({1'b0, aabs_q8}) - $signed({1'b0, avg_q8});

    wire signed [33:0] avg_n = $signed({1'b0, avg_q8}) + ((avg_d + 34'sd2048) >>> 12);
    wire [24:0] avg = avg_q8[32:8];      // 取回整数部分

    assign active = (avg > 25'd8);

    always @(posedge clk) begin
        if (tick) begin
            avg_q8 <= avg_n[32:0];                             // Q8 内四舍五入，无死区

            if (avg > 25'd100) case (gsh)
                3'd0: if (avg < 25'd3800)                       gsh <= 3'd1;
                3'd1: if (avg < 25'd1900)                       gsh <= 3'd2;
                      else if (avg > 25'd4750)                  gsh <= 3'd0;
                3'd2: if (avg < 25'd950)                        gsh <= 3'd3;
                      else if (avg > 25'd2375)                  gsh <= 3'd1;
                3'd3: if (avg < 25'd475)                        gsh <= 3'd4;
                      else if (avg > 25'd1187)                  gsh <= 3'd2;
                3'd4: if (avg > 25'd593)                        gsh <= 3'd3;
                default: gsh <= 3'd4;
            endcase
        end
    end

    wire signed [29:0] ac_g = (gsh == 3'd0) ? {{5{ac[24]}}, ac}             :
                              (gsh == 3'd1) ? {{4{ac[24]}}, ac, 1'b0}       :
                              (gsh == 3'd2) ? {{3{ac[24]}}, ac, 2'b00}      :
                              (gsh == 3'd3) ? {{2{ac[24]}}, ac, 3'b000}     :
                              (gsh == 3'd4) ? {{1{ac[24]}}, ac, 4'b0000}    :
                                              {ac, 5'b00000};               // ×32（30 位）

    always @(posedge clk) begin
        if (ac_g > 30'sd32767)
            disp_r <= 16'sd32767;
        else if (ac_g < -30'sd32768)
            disp_r <= -16'sd32768;
        else
            disp_r <= ac_g[15:0];
    end

endmodule
