// keymap.v — 12 个物理键 → 音高 的可改映射表（协议 §6 的 12 项缩水版）

module keymap (
    input  wire        clk,

    // 影子表写入（来自 cmd_exec 的 KEYMAP 指令）
    input  wire        we,
    input  wire [3:0]  waddr,       // 0..11（越界忽略）
    input  wire [7:0]  wdata,       // 协议码

    // 提交：影子表整体生效
    input  wire        commit,

    // 对外
    output wire [83:0] notes,       // 12 × 7 位，note_freq 表索引
    output wire [11:0] valid,       // 0 = 该键被禁用
    output wire [95:0] codes        // 影子表原始码值（12×8），供 KEYMAP_DONE 算 CRC32
);

    reg [7:0] sh0 = 8'd60, sh1 = 8'd62, sh2 = 8'd64, sh3 = 8'd65,
              sh4 = 8'd67, sh5 = 8'd69, sh6 = 8'd71, sh7 = 8'd61,
              sh8 = 8'd63, sh9 = 8'd66, sh10= 8'd68, sh11= 8'd70;

    reg [7:0] ac0 = 8'd60, ac1 = 8'd62, ac2 = 8'd64, ac3 = 8'd65,
              ac4 = 8'd67, ac5 = 8'd69, ac6 = 8'd71, ac7 = 8'd61,
              ac8 = 8'd63, ac9 = 8'd66, ac10= 8'd68, ac11= 8'd70;

    always @(posedge clk) begin
        if (we) begin
            case (waddr)
                4'd0:  sh0  <= wdata;
                4'd1:  sh1  <= wdata;
                4'd2:  sh2  <= wdata;
                4'd3:  sh3  <= wdata;
                4'd4:  sh4  <= wdata;
                4'd5:  sh5  <= wdata;
                4'd6:  sh6  <= wdata;
                4'd7:  sh7  <= wdata;
                4'd8:  sh8  <= wdata;
                4'd9:  sh9  <= wdata;
                4'd10: sh10 <= wdata;
                4'd11: sh11 <= wdata;
                default: ;
            endcase
        end

        if (commit) begin
            ac0 <= sh0;   ac1 <= sh1;   ac2 <= sh2;   ac3 <= sh3;
            ac4 <= sh4;   ac5 <= sh5;   ac6 <= sh6;   ac7 <= sh7;
            ac8 <= sh8;   ac9 <= sh9;   ac10 <= sh10; ac11 <= sh11;
        end
    end

    function [6:0] code2idx;
        input [7:0] c;
        begin
            if (c[7])                code2idx = 7'd0;          // 0x80.. 保留
            else if (c == 8'd0)      code2idx = 7'd0;          // 禁用
            else if (c <  8'd24)     code2idx = 7'd0;          // 太低，钳到表底
            else if (c >  8'd107)    code2idx = 7'd83;         // 太高，钳到表顶
            else                     code2idx = c - 8'd24;
        end
    endfunction

    function valid_code;
        input [7:0] c;
        begin
            valid_code = (c != 8'd0) && !c[7];
        end
    endfunction

    assign notes = {
        code2idx(ac11), code2idx(ac10), code2idx(ac9), code2idx(ac8),
        code2idx(ac7),  code2idx(ac6),  code2idx(ac5), code2idx(ac4),
        code2idx(ac3),  code2idx(ac2),  code2idx(ac1), code2idx(ac0)
    };

    assign valid = {
        valid_code(ac11), valid_code(ac10), valid_code(ac9), valid_code(ac8),
        valid_code(ac7),  valid_code(ac6),  valid_code(ac5), valid_code(ac4),
        valid_code(ac3),  valid_code(ac2),  valid_code(ac1), valid_code(ac0)
    };

    assign codes = {sh0, sh1, sh2, sh3, sh4, sh5, sh6, sh7, sh8, sh9, sh10, sh11};

endmodule
