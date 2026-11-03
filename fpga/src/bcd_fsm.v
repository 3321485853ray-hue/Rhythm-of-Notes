// bcd_fsm.v — 二进制 → 4 位十进制（多周期软拆位）

module bcd_fsm (
    input  wire        clk,
    input  wire [15:0] v0,          // 待转换值 0（事件数）
    input  wire [15:0] v1,          // 待转换值 1（录音数）
    output reg  [15:0] bcd0,        // {千,百,十,个} 各 4 位
    output reg  [15:0] bcd1
);

    localparam [1:0] S_IDLE = 2'd0,
                     S_C0   = 2'd1,
                     S_C1   = 2'd2;

    reg [1:0]  st   = S_IDLE;
    reg [4:0]  step = 5'd0;         // 0..28
    reg [15:0] x    = 16'd0;
    reg [3:0]  th   = 4'd0, hu = 4'd0, te = 4'd0;
    reg [15:0] last0 = 16'hFFFF, last1 = 16'hFFFF;

    always @(posedge clk) begin
        case (st)
            S_IDLE: begin
                if ((v0 != last0) || (v1 != last1)) begin
                    st   <= S_C0;
                    step <= 5'd0;
                    x    <= v0;
                    th   <= 4'd0;
                    hu   <= 4'd0;
                    te   <= 4'd0;
                end
            end

            S_C0, S_C1: begin
                if (step < 5'd9) begin                 // 千位：最多减 9 次
                    if (x >= 16'd1000) begin x <= x - 16'd1000; th <= th + 4'd1; end
                    step <= step + 5'd1;
                end else if (step < 5'd19) begin       // 百位：最多 9 次（给 10 拍余量）
                    if (x >= 16'd100) begin x <= x - 16'd100; hu <= hu + 4'd1; end
                    step <= step + 5'd1;
                end else if (step < 5'd29) begin       // 十位
                    if (x >= 16'd10) begin x <= x - 16'd10; te <= te + 4'd1; end
                    step <= step + 5'd1;
                end else begin
                    if (st == S_C0) begin
                        bcd0  <= {th, hu, te, x[3:0]};
                        last0 <= v0;
                        st    <= S_C1;
                        step  <= 5'd0;
                        x     <= v1;
                        th    <= 4'd0; hu <= 4'd0; te <= 4'd0;
                    end else begin
                        bcd1  <= {th, hu, te, x[3:0]};
                        last1 <= v1;
                        st    <= S_IDLE;
                    end
                end
            end

            default: st <= S_IDLE;
        endcase
    end

endmodule
