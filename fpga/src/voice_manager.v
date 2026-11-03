// voice_manager.v — 按键 → 声部分配 / 抢占 / 释放（8 声部）

module voice_manager (
    input  wire        clk,
    input  wire        sample_strobe,
    input  wire [11:0] key_level,
    input  wire [11:0] key_press,     // 按下单周期脉冲
    input  wire [11:0] key_release,   // 松开单周期脉冲
    input  wire [7:0]  v_idle,        // 各声部包络已归零（来自 voice.v）
    input  wire        glide_mode,
    output wire [7:0]  v_gate,        // 各声部"键还按着"
    output wire [7:0]  v_trig,        // 电平触发
    output wire [31:0] v_keys         // 各声部拥有哪个键（扁平 8×4）
);

reg [3:0] k0 = 4'd0, k1 = 4'd0, k2 = 4'd0, k3 = 4'd0;
reg [3:0] k4 = 4'd0, k5 = 4'd0, k6 = 4'd0, k7 = 4'd0;

assign v_keys = {k7, k6, k5, k4, k3, k2, k1, k0};

reg [7:0] gate_r = 8'b0;
reg [7:0] trig_r = 8'b0;

assign v_gate = gate_r;
assign v_trig = trig_r;

wire rel0 = gate_r[0] && key_release[k0];
wire rel1 = gate_r[1] && key_release[k1];
wire rel2 = gate_r[2] && key_release[k2];
wire rel3 = gate_r[3] && key_release[k3];
wire rel4 = gate_r[4] && key_release[k4];
wire rel5 = gate_r[5] && key_release[k5];
wire rel6 = gate_r[6] && key_release[k6];
wire rel7 = gate_r[7] && key_release[k7];

reg [11:0] pend = 12'h000;

wire [11:0] want = pend | key_press;   // 本拍要处理的全部按下事件
wire        any_want = |want;

reg [3:0] pk;

always @(*) begin
    if      (want[0]) pk = 4'd0;
    else if (want[1]) pk = 4'd1;
    else if (want[2]) pk = 4'd2;
    else if (want[3]) pk = 4'd3;
    else if (want[4]) pk = 4'd4;
    else if (want[5]) pk = 4'd5;
    else if (want[6]) pk = 4'd6;
    else if (want[7]) pk = 4'd7;
    else if (want[8]) pk = 4'd8;
    else if (want[9]) pk = 4'd9;
    else if (want[10]) pk = 4'd10;
    else if (want[11]) pk = 4'd11;
    else              pk = 4'd0;
end

// 这一拍要清掉的那一位
wire [11:0] kill = any_want ? (12'b1 << pk) : 12'b0;

always @(posedge clk) begin
    pend <= want & ~kill;
end

wire [7:0] idle_mask = v_idle & ~gate_r;   // ① 完全空闲：包络已归零
wire [7:0] free_mask = ~gate_r;            // ② 键已松开（含正在释放尾巴上的）

reg [31:0] alloc_seq = 32'd0;
reg [31:0] ts0 = 32'd0, ts1 = 32'd0, ts2 = 32'd0, ts3 = 32'd0;
reg [31:0] ts4 = 32'd0, ts5 = 32'd0, ts6 = 32'd0, ts7 = 32'd0;

reg [2:0] oldest;

always @(*) begin
    if      (ts0 <= ts1 && ts0 <= ts2 && ts0 <= ts3 && ts0 <= ts4 && ts0 <= ts5 && ts0 <= ts6 && ts0 <= ts7) oldest = 3'd0;
    else if (ts1 <= ts2 && ts1 <= ts3 && ts1 <= ts4 && ts1 <= ts5 && ts1 <= ts6 && ts1 <= ts7)               oldest = 3'd1;
    else if (ts2 <= ts3 && ts2 <= ts4 && ts2 <= ts5 && ts2 <= ts6 && ts2 <= ts7)                           oldest = 3'd2;
    else if (ts3 <= ts4 && ts3 <= ts5 && ts3 <= ts6 && ts3 <= ts7)                                         oldest = 3'd3;
    else if (ts4 <= ts5 && ts4 <= ts6 && ts4 <= ts7)                                                       oldest = 3'd4;
    else if (ts5 <= ts6 && ts5 <= ts7)                                                                     oldest = 3'd5;
    else if (ts6 <= ts7)                                                                                   oldest = 3'd6;
    else                                                                                                   oldest = 3'd7;
end

reg [2:0] last_sel = 3'd0;                  // 上一次分配给了谁（声明处初值）
wire      last_free = ~gate_r[last_sel];    // 它还空着吗

reg [2:0] sel;

always @(*) begin
    if      (glide_mode)   sel = last_sel;
    else if (last_free)    sel = last_sel;
    else if (idle_mask[0]) sel = 3'd0;
    else if (idle_mask[0]) sel = 3'd0;
    else if (idle_mask[1]) sel = 3'd1;
    else if (idle_mask[2]) sel = 3'd2;
    else if (idle_mask[3]) sel = 3'd3;
    else if (idle_mask[4]) sel = 3'd4;
    else if (idle_mask[5]) sel = 3'd5;
    else if (idle_mask[6]) sel = 3'd6;
    else if (idle_mask[7]) sel = 3'd7;
    else if (free_mask[0]) sel = 3'd0;
    else if (free_mask[1]) sel = 3'd1;
    else if (free_mask[2]) sel = 3'd2;
    else if (free_mask[3]) sel = 3'd3;
    else if (free_mask[4]) sel = 3'd4;
    else if (free_mask[5]) sel = 3'd5;
    else if (free_mask[6]) sel = 3'd6;
    else if (free_mask[7]) sel = 3'd7;
    else                   sel = oldest;      // 全都按着 → 抢最早分配的那个
end

always @(posedge clk) begin

    if (sample_strobe)
        trig_r <= 8'b0;

    if (rel0) gate_r[0] <= 1'b0;
    if (rel1) gate_r[1] <= 1'b0;
    if (rel2) gate_r[2] <= 1'b0;
    if (rel3) gate_r[3] <= 1'b0;
    if (rel4) gate_r[4] <= 1'b0;
    if (rel5) gate_r[5] <= 1'b0;
    if (rel6) gate_r[6] <= 1'b0;
    if (rel7) gate_r[7] <= 1'b0;

    if (any_want) begin

        if (key_level[pk]) begin
            gate_r[sel]  <= 1'b1;

            trig_r[sel]  <= glide_mode ? ~gate_r[sel] : 1'b1;
            // 记下"这个声部是第几次分配"（唯一的、递增的），抢占时比它
            case (sel)
                3'd0: begin k0 <= pk; ts0 <= alloc_seq; end
                3'd1: begin k1 <= pk; ts1 <= alloc_seq; end
                3'd2: begin k2 <= pk; ts2 <= alloc_seq; end
                3'd3: begin k3 <= pk; ts3 <= alloc_seq; end
                3'd4: begin k4 <= pk; ts4 <= alloc_seq; end
                3'd5: begin k5 <= pk; ts5 <= alloc_seq; end
                3'd6: begin k6 <= pk; ts6 <= alloc_seq; end
                3'd7: begin k7 <= pk; ts7 <= alloc_seq; end
            endcase
            last_sel  <= sel;
            alloc_seq <= alloc_seq + 32'd1;
        end
    end
end

endmodule
