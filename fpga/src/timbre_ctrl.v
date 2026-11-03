// timbre_ctrl.v — 音色切换（EC11 的按钮 = C14；2026-10-03 起不再用 KEY0）

module timbre_ctrl (
    input  wire       clk,
    input  wire       rst_n,        // 顶层恒接 1'b1
    input  wire       short_press,  // 来自 btn_shortlong：EC11 短按（松开时发）
    output reg  [2:0] timbre        // 1=钢琴 2=管风琴 3=长笛 4=弦乐
);

    reg [2:0] sel = 3'd4;

    always @(posedge clk) begin
        if (!rst_n)
            sel <= 3'd4;
        else if (short_press) begin
            case (sel)
                3'd1: sel <= 3'd2;      // 钢琴   → 管风琴
                3'd2: sel <= 3'd4;      // 管风琴 → 弦乐
                3'd4: sel <= 3'd3;      // 弦乐   → 长笛
                default: sel <= 3'd1;   // 长笛(3)/正弦(0) → 钢琴
            endcase
        end
    end

    // 用 case 查表，不用 ?: 三目链（工程风格约定）
    always @(*) begin
        case (sel)
            3'd1:    timbre = 3'd1;   // 钢琴
            3'd2:    timbre = 3'd2;   // 管风琴
            3'd4:    timbre = 3'd4;   // 弦乐
            default: timbre = 3'd3;   // 长笛
        endcase
    end

endmodule
