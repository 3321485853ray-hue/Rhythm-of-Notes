// expr_ctrl.v — 表情维度选择 + 档位

module expr_ctrl (
    input  wire       clk,
    input  wire       rst_n,       // 顶层恒接 1'b1
    input  wire       step_up,
    input  wire       step_down,
    input  wire       sw_press,
    output wire [1:0] expr_sel,    // 0=关 1=滑音 2=颤音 3=震音
    output wire [1:0] expr_amt
);

    reg [1:0] sel_r = 2'd0;

    reg [1:0] g_amt = 2'd0;        // 滑音深度
    reg [1:0] v_amt = 2'd0;        // 颤音深度
    reg [1:0] t_amt = 2'd0;        // 震音深度

    always @(posedge clk) begin
        if (!rst_n) begin
            sel_r <= 2'd0;
            g_amt <= 2'd0;  v_amt <= 2'd0;  t_amt <= 2'd0;
        end else begin

            if (sw_press) sel_r <= sel_r + 2'd1;

            if (sel_r == 2'd1) begin                              // 滑音
                if (step_up   && g_amt != 2'd3) g_amt <= g_amt + 2'd1;
                if (step_down && g_amt != 2'd0) g_amt <= g_amt - 2'd1;
            end else if (sel_r == 2'd2) begin                     // 颤音
                if (step_up   && v_amt != 2'd3) v_amt <= v_amt + 2'd1;
                if (step_down && v_amt != 2'd0) v_amt <= v_amt - 2'd1;
            end else if (sel_r == 2'd3) begin                     // 震音
                if (step_up   && t_amt != 2'd3) t_amt <= t_amt + 2'd1;
                if (step_down && t_amt != 2'd0) t_amt <= t_amt - 2'd1;
            end

        end
    end

    assign expr_sel  = sel_r;

    assign expr_amt  = (sel_r == 2'd1) ? g_amt :
                       (sel_r == 2'd2) ? v_amt :
                       (sel_r == 2'd3) ? t_amt : 2'd0;

endmodule
