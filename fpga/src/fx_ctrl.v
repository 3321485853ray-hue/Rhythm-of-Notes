// fx_ctrl.v — 效果器选择器

module fx_ctrl (
    input  wire       clk,
    input  wire       rst_n,       // 顶层恒接 1'b1
    input  wire       long_press,  // 来自 btn_shortlong，一个采样周期的高
    output wire [1:0] fx_sel       // 0=关 1=延迟 2=混响 3=合唱
);

    reg [1:0] sel_r = 2'd0;

    always @(posedge clk) begin
        if (!rst_n)
            sel_r <= 2'd0;
        else if (long_press)
            sel_r <= sel_r + 2'd1;      // 2 位自然回绕：3+1=0 ⇒ 4 态循环
    end

    // sel_r 的编码定义就是 fx_sel 的编码，不用再翻译一层
    assign fx_sel = sel_r;

endmodule
