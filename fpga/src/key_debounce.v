// key_debounce.v — 单按键消抖 + 边沿检测

module key_debounce #(
    parameter [19:0] CNT_MAX = 20'd150000      // 消抖时间（@50MHz 时 150000 = 3ms）
)(
    input  wire clk,
    input  wire rst_n,
    input  wire key_in,
    output reg  key_level,
    output reg  key_press,
    output reg  key_release
);

    reg [19:0] count    = 20'd0;
    reg        stable   = 1'b1;
    reg        stable_d = 1'b1;
    reg [1:0]  sync     = 2'b11;

    always @(posedge clk) begin
        if (!rst_n) begin
            sync        <= 2'b11;
            count       <= 20'd0;
            stable      <= 1'b1;   // 默认未按下（低有效）
            stable_d    <= 1'b1;
            key_level   <= 1'b0;
            key_press   <= 1'b0;
            key_release <= 1'b0;
        end else begin
            // 两级同步
            sync <= {sync[0], key_in};

            // 消抖：输入需保持 150000 个周期不变才接受
            if (sync[1] != stable) begin
                if (count == CNT_MAX) begin
                    stable <= sync[1];
                    count  <= 20'd0;
                end else
                    count <= count + 1'b1;
            end else
                count <= 20'd0;

            // 输出（时序）
            stable_d    <= stable;
            key_level   <= ~stable;
            key_press   <= stable_d & ~stable;
            key_release <= ~stable_d & stable;
        end
    end

endmodule
