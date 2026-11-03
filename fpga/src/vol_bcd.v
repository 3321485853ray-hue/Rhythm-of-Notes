// vol_bcd.v —— 音量百分比(0..100) → 三个 ASCII 字符（50 MHz 域拆位状态机）

module vol_bcd (
    input  wire       clk,
    input  wire [6:0] v,           // 0..100
    output reg  [7:0] ch_h = 8'h20,
    output reg  [7:0] ch_t = 8'h30,
    output reg  [7:0] ch_o = 8'h30
);

    localparam [1:0] S_IDLE = 2'd0,
                     S_SUB  = 2'd1,
                     S_OUT  = 2'd2;

    reg [1:0] st   = S_IDLE;
    reg [6:0] rem  = 7'd0;
    reg [3:0] tens = 4'd0;
    reg [6:0] last = 7'd127;

    always @(posedge clk) begin
        case (st)
            S_IDLE: begin
                if (v != last) begin
                    rem  <= v;
                    tens <= 4'd0;
                    st   <= S_SUB;
                end
            end

            S_SUB: begin
                // 最多减 9 次：v=100 时 rem 停在 10，由 S_OUT 的特判显示 "100"
                if ((rem >= 7'd10) && (tens < 4'd9)) begin
                    rem  <= rem - 7'd10;
                    tens <= tens + 4'd1;
                end else begin
                    st <= S_OUT;
                end
            end

            default: begin   // S_OUT
                ch_h <= (v == 7'd100) ? "1" : " ";
                ch_t <= 8'h30 + ((v == 7'd100) ? 4'd0 : tens);
                ch_o <= 8'h30 + ((v == 7'd100) ? 4'd0 : rem[3:0]);
                last <= v;
                st   <= S_IDLE;
            end
        endcase
    end

endmodule
