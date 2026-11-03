// display_gain.v — 按按键数做 1/√N 的显示缩放（只读，不碰音频通路）

module display_gain (
    input  wire signed [15:0] disp_ac,   // display_cond 输出（双极性，±32767）
    input  wire [3:0]         nkeys,     // 当前按键数 0..12
    output wire signed [15:0] disp_g
);

    function [15:0] g_q15;
        input [3:0] n;
        begin
            case (n)
                4'd2:    g_q15 = 16'd23170;   // 1/√2
                4'd3:    g_q15 = 16'd18919;   // 1/√3
                4'd4:    g_q15 = 16'd16384;   // 1/2
                4'd5:    g_q15 = 16'd14654;
                4'd6:    g_q15 = 16'd13377;
                4'd7:    g_q15 = 16'd12384;
                4'd8:    g_q15 = 16'd11585;
                4'd9:    g_q15 = 16'd10923;
                4'd10:   g_q15 = 16'd10362;
                4'd11:   g_q15 = 16'd9880;
                4'd12:   g_q15 = 16'd9460;
                default: g_q15 = 16'd9460;    // N>12 按 12 处理（键盘只有 12 键）
            endcase
        end
    endfunction

    wire        [15:0] g   = g_q15(nkeys);
    wire signed [16:0] g_s = {1'b0, g};                 // 0..32767，正数
    wire signed [32:0] prod = disp_ac * g_s;            // 16×17 → 33 位
    wire signed [32:0] sh   = prod >>> 15;              // Q15 → 原码

    assign disp_g = (nkeys <= 4'd1)          ? disp_ac :   // 单键：逐位旁路
                    (sh > 32'sd32767)        ?  16'sd32767 :
                    (sh < -32'sd32768)       ? -16'sd32768 :
                                               sh[15:0];

endmodule
