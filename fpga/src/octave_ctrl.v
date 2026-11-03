// octave_ctrl.v — 八度控制（单键 4 态循环）

module octave_ctrl (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key_next,     // 单键循环（低有效）
    output wire [2:0]  octave        // 0~4，偏移 +2（2 = 0 八度）
);

    reg [2:0] octave_r = 3'd2;       // 上电初值：0 八度

    assign octave = octave_r;

    wire press;

    key_debounce u_key (.clk(clk), .rst_n(rst_n), .key_in(key_next), .key_press(press));

    reg second_zero = 1'b0;      // 0 = 这次的"0 八度"是循环里的第一个 0

    always @(posedge clk) begin
        if (!rst_n) begin
            octave_r    <= 3'd2;
            second_zero <= 1'b0;
        end else if (press) begin
            case (octave_r)
                // 0 八度：看这是循环里的第几个 0 才知道该往上还是往下
                3'd2: if (!second_zero) begin
                          octave_r    <= 3'd3;   // 0(第一个) → +1
                          second_zero <= 1'b0;
                      end else begin
                          octave_r    <= 3'd1;   // 0(第二个) → −1
                          second_zero <= 1'b1;
                      end
                // +1 → 0：接下来这个 0 是循环里的第二个 0（按一下该去 −1）
                3'd3: begin
                          octave_r    <= 3'd2;
                          second_zero <= 1'b1;
                      end
                // −1 → 0：接下来这个 0 是 loop 里的第一个 0（按一下该去 +1）
                default: begin
                          octave_r    <= 3'd2;
                          second_zero <= 1'b0;
                      end
            endcase
        end
    end

endmodule
