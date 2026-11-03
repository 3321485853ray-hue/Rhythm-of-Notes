// score_alloc.v — 曲谱专用 4 声部分配器（2026-10-30）

module score_alloc (
    input  wire        clk,

    // 播放器事件
    input  wire        on_pulse,
    input  wire [6:0]  on_note,
    input  wire        off_pulse,
    input  wire [6:0]  off_note,
    input  wire        panic,        // 全部关闭

    // 给 4 个 voice 实例
    output wire [3:0]  s_gate,
    output wire [3:0]  s_trig,
    output wire [27:0] s_note         // 扁平 4×7：[6:0]=voice0 … [27:21]=voice3
);

    reg        g0 = 1'b0, g1 = 1'b0, g2 = 1'b0, g3 = 1'b0;
    reg [6:0]  n0 = 7'd0, n1 = 7'd0, n2 = 7'd0, n3 = 7'd0;
    reg [31:0] t0 = 32'd0, t1 = 32'd0, t2 = 32'd0, t3 = 32'd0;
    reg [31:0] seq = 32'd0;

    reg [3:0]  tg = 4'd0;                 // 电平触发，周期性清

    reg [9:0] hold_cnt = 10'd1023;
    wire      clr      = (hold_cnt == 10'd1023);
    always @(posedge clk) begin
        if (on_pulse)             hold_cnt <= 10'd0;
        else if (!clr)            hold_cnt <= hold_cnt + 10'd1;
    end

    wire [3:0] gate_v = {g3, g2, g1, g0};
    wire [3:0] same   = { (g3 && (n3 == on_note)), (g2 && (n2 == on_note)),
                          (g1 && (n1 == on_note)), (g0 && (n0 == on_note)) };
    wire [3:0] free_v = ~gate_v;

    // 最早分配：ts 最小
    reg [1:0] oldest;
    always @(*) begin
        if      (t0 <= t1 && t0 <= t2 && t0 <= t3) oldest = 2'd0;
        else if (t1 <= t2 && t1 <= t3)             oldest = 2'd1;
        else if (t2 <= t3)                         oldest = 2'd2;
        else                                       oldest = 2'd3;
    end

    reg [1:0] sel;
    always @(*) begin
        if      (same[0])   sel = 2'd0;
        else if (same[1])   sel = 2'd1;
        else if (same[2])   sel = 2'd2;
        else if (same[3])   sel = 2'd3;
        else if (free_v[0]) sel = 2'd0;
        else if (free_v[1]) sel = 2'd1;
        else if (free_v[2]) sel = 2'd2;
        else if (free_v[3]) sel = 2'd3;
        else                sel = oldest;
    end

    wire r0 = g0 && off_pulse && (n0 == off_note);
    wire r1 = g1 && off_pulse && (n1 == off_note);
    wire r2 = g2 && off_pulse && (n2 == off_note);
    wire r3 = g3 && off_pulse && (n3 == off_note);

    always @(posedge clk) begin

        if (clr) tg <= 4'd0;

        if (panic) begin
            g0 <= 1'b0; g1 <= 1'b0; g2 <= 1'b0; g3 <= 1'b0;
        end else begin
            if (r0) g0 <= 1'b0;
            if (r1) g1 <= 1'b0;
            if (r2) g2 <= 1'b0;
            if (r3) g3 <= 1'b0;
        end

        if (on_pulse) begin
            tg[sel] <= 1'b1;
            case (sel)
                2'd0: begin g0 <= 1'b1; n0 <= on_note; t0 <= seq; end
                2'd1: begin g1 <= 1'b1; n1 <= on_note; t1 <= seq; end
                2'd2: begin g2 <= 1'b1; n2 <= on_note; t2 <= seq; end
                2'd3: begin g3 <= 1'b1; n3 <= on_note; t3 <= seq; end
            endcase
            seq <= seq + 32'd1;
        end
    end

    assign s_gate = {g3, g2, g1, g0};
    assign s_trig = tg;
    assign s_note = {n3, n2, n1, n0};

endmodule
