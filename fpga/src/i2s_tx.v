// i2s_tx.v — PT8211 右对齐（Right-Justified / LSBJ）16bit I²S 发送器

module i2s_tx (
    input  wire        clk_sys,       // 50MHz
    input  wire        rst_n,         // 异步复位，低有效
    input  wire [15:0] audio_l,       // 左声道样本（有符号）
    input  wire [15:0] audio_r,       // 右声道样本（有符号）
    output wire        bck,           // 3.125 MHz 位时钟
    output wire        lrck,          // 48.828 kHz 字选
    output reg         din,           // 串行数据（右对齐）
    output wire        pa_en,         // 功放使能（低有效）
    output wire        sample_strobe  // 每 fs 一个周期高，通知 DSP 出新样本
);

reg [9:0] cnt;
always @(posedge clk_sys) begin
    if (!rst_n)
        cnt <= 10'd0;
    else
        cnt <= cnt + 1'b1;
end

assign bck  = cnt[3];               // 50M / 16  = 3.125 MHz
assign lrck = cnt[9];               // 50M / 1024 = 48.828 kHz
assign sample_strobe = (cnt == 10'd0);

reg [15:0] latched_l, latched_r;
always @(posedge clk_sys) begin
    if (!rst_n) begin
        latched_l <= 16'd0;
        latched_r <= 16'd0;
    end else if (sample_strobe) begin
        latched_l <= audio_l;
        latched_r <= audio_r;
    end
end

// 当前声道样本：LRCK=0 -> 左，LRCK=1 -> 右
wire [15:0] cur_sample = cnt[9] ? latched_r : latched_l;

wire [3:0] bit_pos    = cnt[7:4];          // 数据相内 0~15
wire       data_phase = cnt[8];            // 1 = 序号 >= 16
wire       din_bit    = cur_sample[15 - bit_pos]; // MSB 先

always @(posedge clk_sys) begin
    if (!rst_n)
        din <= 1'b0;
    else if (cnt[3:0] == 4'd8)             // BCK 上升沿更新数据
        din <= data_phase ? din_bit : 1'b0;
end

reg pa_en_r = 1'b1;
assign pa_en = pa_en_r;

reg [23:0] delay_cnt;
always @(posedge clk_sys) begin
    if (!rst_n) begin
        delay_cnt <= 24'd0;
        pa_en_r <= 1'b1;                   // 复位时关功放
    end else if (!delay_cnt[23]) begin     // 等 2^23 周期 ≈ 0.17s
        delay_cnt <= delay_cnt + 1'b1;
        pa_en_r <= 1'b1;                   // 仍关闭
    end else begin
        pa_en_r <= 1'b0;                   // 开功放
    end
end

endmodule
