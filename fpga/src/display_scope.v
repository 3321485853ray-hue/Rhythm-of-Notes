// display_scope.v — 示波器采样抽头（音频域，只读）

module display_scope (
    input  wire               clk,           // 50 MHz
    input  wire signed [15:0] disp_ac,
    input  wire [1:0]         att,           // 0/1/2：按声部数衰减
    output reg  [9:0]         scope_y,
    output reg                scope_trig,    // 与 scope_y 同拍：低通过零触发
    output wire               scope_tgl
);

    reg tgl_r = 1'b0;
    assign scope_tgl = tgl_r;

    reg [9:0] cnt = 10'd0;
    always @(posedge clk) cnt <= cnt + 1'b1;
    wire tick = (cnt == 10'd0);

    wire signed [15:0] v0 = disp_ac;
    wire signed [15:0] v1 = disp_ac >>> 1;
    wire signed [15:0] v2 = disp_ac >>> 2;
    wire signed [15:0] v  = (att == 2'd0) ? v0 :
                            (att == 2'd1) ? v1 : v2;

    localparam signed [22:0] SCOPE_SCALE = 23'sd114;
    wire signed [22:0] prod = v * SCOPE_SCALE;
    wire signed [22:0] p14 = prod >>> 14;
    wire signed [22:0] p15 = prod >>> 15;
    wire signed [22:0] p16 = prod >>> 16;
    wire signed [22:0] psh = (att == 2'd0) ? p14 :
                              (att == 2'd1) ? p15 : p16;

    wire signed [15:0] wy = 16'sd139 + $signed(psh[15:0]);   // 720p 面板中线 139

    reg  signed [17:0] lp = 18'sd0;
    wire signed [17:0] vx = {{2{v[15]}}, v};
    wire signed [17:0] lp_n = lp + ((vx - lp) >>> 4);

    localparam signed [17:0] TRIG_H   = 18'sd128;

    localparam signed [17:0] TRIG_ARM = -18'sd512;
    localparam        [17:0] TRIG_WIN = 18'd64;   // 亚采样相位门控窗（见下方说明）
    reg trig_armed = 1'b0;

    always @(posedge clk) begin
        if (tick) begin
            // Y
            if (wy < 16'sd8)
                scope_y <= 10'd8;
            else if (wy > 16'sd270)
                scope_y <= 10'd270;
            else
                scope_y <= wy[9:0];

            // 低通过零（带滞回），与 scope_y 同拍
            scope_trig <= 1'b0;
            lp <= lp_n;

            if (lp_n < TRIG_ARM)
                trig_armed <= 1'b1;
            else if (trig_armed && (lp_n > TRIG_H)) begin
                trig_armed <= 1'b0;                 // 无论是否接受，本周期的过零都算用掉
                if ((lp_n - TRIG_H) < TRIG_WIN)
                    scope_trig <= 1'b1;
            end

            tgl_r <= ~tgl_r;
        end
    end

endmodule
