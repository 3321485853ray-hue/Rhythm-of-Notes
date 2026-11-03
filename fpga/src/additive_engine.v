// additive_engine.v — 阶段9 加法合成引擎（32 路谐波分量，时分复用）

module additive_engine (
    input  wire               clk,
    input  wire               sample_strobe,  // 每采样一次（fs = 48828.125Hz）一个周期高
    input  wire               gate,           // = env_active：包络走完（含释放尾巴）前保持 1
    input  wire [31:0]        phase_step,     // 音高（已锁存）
    input  wire [2:0]         timbre,
    output reg  signed [15:0] wave = 16'sd8190 // 静止值 = BIAS，不是 0（防上电满幅跳变）
);

    localparam signed [17:0] BIAS      = 18'sd8190;         // 直流偏置 = 目标峰值上限
    localparam        [17:0] WAVE_MAX  = 18'sd16380;        // 输出上限（bit15 恒 0）

    localparam        [36:0] AA_THRESH = 37'd1932735283;    // = 0.45 * 2^32
    localparam               AA_GATE_EN = 1'b1;             // 1=开抗混叠门控；0=全 32 路常开

    localparam               H = 32;                        // 谐波分量数

    reg [31:0] ph [1:32];

    reg [36:0] hps      = 37'd0;
    reg [36:0] hps_slot = 37'd0;    // 本槽的 h·ps，留到 s6 累加进队头用
    reg        aa       = 1'b1;     // 本槽门控决定
    reg        aa_r     = 1'b1;     // 传到累加级的门控决定

    wire [36:0] hps_n = hps + {5'd0, phase_step};

    reg [8:0] ff = 9'd0;

    always @(posedge clk)
        if (sample_strobe)    ff <= 9'd0;
        else if (ff < 9'd257) ff <= ff + 9'd1;

    wire [2:0] sub  = ff[2:0];              // 0 .. 7
    wire       busy = (ff < 9'd256);

    reg [31:0] sel = 32'd1;                 // bit k = 当前处理第 k+1 路

    wire [36:0] hps_seed = {5'd0, phase_step};
    wire [36:0] hps_nxt  = (ff == 9'd0) ? hps_seed : hps_n;

    reg signed [15:0] BANK_SIN [0:31];
    reg signed [15:0] BANK_PIA [0:31];   // timbre=1 钢琴：h=1..10 实测 + 1/h 平滑尾巴
    reg signed [15:0] BANK_ORG [0:31];   // timbre=2 管风琴：打击杆 h=1..8 + 偶次小尾巴
    reg signed [15:0] BANK_FLT [0:31];   // timbre=3 长笛：h=1..3 + 奇次小尾巴
    reg signed [15:0] BANK_STR [0:31];   // timbre=4 弦乐(小提琴)：源×弓位梳状×琴马峰（见下方注释）

    initial begin
        BANK_SIN[ 0]=16'sd8738;
        BANK_SIN[ 1]=16'sd0; BANK_SIN[ 2]=16'sd0; BANK_SIN[ 3]=16'sd0;
        BANK_SIN[ 4]=16'sd0; BANK_SIN[ 5]=16'sd0; BANK_SIN[ 6]=16'sd0;
        BANK_SIN[ 7]=16'sd0; BANK_SIN[ 8]=16'sd0; BANK_SIN[ 9]=16'sd0;
        BANK_SIN[10]=16'sd0; BANK_SIN[11]=16'sd0; BANK_SIN[12]=16'sd0;
        BANK_SIN[13]=16'sd0; BANK_SIN[14]=16'sd0; BANK_SIN[15]=16'sd0;
        BANK_SIN[16]=16'sd0; BANK_SIN[17]=16'sd0; BANK_SIN[18]=16'sd0;
        BANK_SIN[19]=16'sd0; BANK_SIN[20]=16'sd0; BANK_SIN[21]=16'sd0;
        BANK_SIN[22]=16'sd0; BANK_SIN[23]=16'sd0; BANK_SIN[24]=16'sd0;
        BANK_SIN[25]=16'sd0; BANK_SIN[26]=16'sd0; BANK_SIN[27]=16'sd0;
        BANK_SIN[28]=16'sd0; BANK_SIN[29]=16'sd0; BANK_SIN[30]=16'sd0;
        BANK_SIN[31]=16'sd0;

        BANK_PIA[ 0]=16'sd  3655; BANK_PIA[ 1]=16'sd  2559; BANK_PIA[ 2]=16'sd  1901; BANK_PIA[ 3]=16'sd  1462;
        BANK_PIA[ 4]=16'sd  1133; BANK_PIA[ 5]=16'sd   914; BANK_PIA[ 6]=16'sd   731; BANK_PIA[ 7]=16'sd   585;
        BANK_PIA[ 8]=16'sd   476; BANK_PIA[ 9]=16'sd   402; BANK_PIA[10]=16'sd   366; BANK_PIA[11]=16'sd   335;
        BANK_PIA[12]=16'sd   309; BANK_PIA[13]=16'sd   288; BANK_PIA[14]=16'sd   268; BANK_PIA[15]=16'sd   251;
        BANK_PIA[16]=16'sd   236; BANK_PIA[17]=16'sd   223; BANK_PIA[18]=16'sd   211; BANK_PIA[19]=16'sd   201;
        BANK_PIA[20]=16'sd   192; BANK_PIA[21]=16'sd   182; BANK_PIA[22]=16'sd   175; BANK_PIA[23]=16'sd   168;
        BANK_PIA[24]=16'sd   161; BANK_PIA[25]=16'sd   155; BANK_PIA[26]=16'sd   149; BANK_PIA[27]=16'sd   143;
        BANK_PIA[28]=16'sd   139; BANK_PIA[29]=16'sd   134; BANK_PIA[30]=16'sd   129; BANK_PIA[31]=16'sd   126;

        BANK_ORG[ 0]=16'sd  4413; BANK_ORG[ 1]=16'sd  3089; BANK_ORG[ 2]=16'sd  2206; BANK_ORG[ 3]=16'sd  1765;
        BANK_ORG[ 4]=16'sd     0; BANK_ORG[ 5]=16'sd  1104; BANK_ORG[ 6]=16'sd     0; BANK_ORG[ 7]=16'sd   794;
        BANK_ORG[ 8]=16'sd     0; BANK_ORG[ 9]=16'sd   636; BANK_ORG[10]=16'sd     0; BANK_ORG[11]=16'sd   529;
        BANK_ORG[12]=16'sd     0; BANK_ORG[13]=16'sd   454; BANK_ORG[14]=16'sd     0; BANK_ORG[15]=16'sd   397;
        BANK_ORG[16]=16'sd     0; BANK_ORG[17]=16'sd   353; BANK_ORG[18]=16'sd     0; BANK_ORG[19]=16'sd   318;
        BANK_ORG[20]=16'sd     0; BANK_ORG[21]=16'sd   289; BANK_ORG[22]=16'sd     0; BANK_ORG[23]=16'sd   265;
        BANK_ORG[24]=16'sd     0; BANK_ORG[25]=16'sd   245; BANK_ORG[26]=16'sd     0; BANK_ORG[27]=16'sd   227;
        BANK_ORG[28]=16'sd     0; BANK_ORG[29]=16'sd   212; BANK_ORG[30]=16'sd     0; BANK_ORG[31]=16'sd   199;

        BANK_FLT[ 0]=16'sd  8169; BANK_FLT[ 1]=16'sd  1633; BANK_FLT[ 2]=16'sd   491; BANK_FLT[ 3]=16'sd     0;
        BANK_FLT[ 4]=16'sd   294; BANK_FLT[ 5]=16'sd     0; BANK_FLT[ 6]=16'sd   210; BANK_FLT[ 7]=16'sd     0;
        BANK_FLT[ 8]=16'sd   164; BANK_FLT[ 9]=16'sd     0; BANK_FLT[10]=16'sd   133; BANK_FLT[11]=16'sd     0;
        BANK_FLT[12]=16'sd   113; BANK_FLT[13]=16'sd     0; BANK_FLT[14]=16'sd    98; BANK_FLT[15]=16'sd     0;
        BANK_FLT[16]=16'sd    87; BANK_FLT[17]=16'sd     0; BANK_FLT[18]=16'sd    78; BANK_FLT[19]=16'sd     0;
        BANK_FLT[20]=16'sd    70; BANK_FLT[21]=16'sd     0; BANK_FLT[22]=16'sd    64; BANK_FLT[23]=16'sd     0;
        BANK_FLT[24]=16'sd    58; BANK_FLT[25]=16'sd     0; BANK_FLT[26]=16'sd    54; BANK_FLT[27]=16'sd     0;
        BANK_FLT[28]=16'sd    51; BANK_FLT[29]=16'sd     0; BANK_FLT[30]=16'sd    48; BANK_FLT[31]=16'sd     0;

        BANK_STR[ 0]=16'sd  2605; BANK_STR[ 1]=16'sd  1890; BANK_STR[ 2]=16'sd  1691; BANK_STR[ 3]=16'sd  1582;
        BANK_STR[ 4]=16'sd  1431; BANK_STR[ 5]=16'sd  1196; BANK_STR[ 6]=16'sd   913; BANK_STR[ 7]=16'sd   645;
        BANK_STR[ 8]=16'sd   431; BANK_STR[ 9]=16'sd   271; BANK_STR[10]=16'sd   149; BANK_STR[11]=16'sd   199;
        BANK_STR[12]=16'sd   254; BANK_STR[13]=16'sd   291; BANK_STR[14]=16'sd   309; BANK_STR[15]=16'sd   310;
        BANK_STR[16]=16'sd   294; BANK_STR[17]=16'sd   265; BANK_STR[18]=16'sd   225; BANK_STR[19]=16'sd   179;
        BANK_STR[20]=16'sd   128; BANK_STR[21]=16'sd    79; BANK_STR[22]=16'sd    99; BANK_STR[23]=16'sd   133;
        BANK_STR[24]=16'sd   160; BANK_STR[25]=16'sd   176; BANK_STR[26]=16'sd   183; BANK_STR[27]=16'sd   179;
        BANK_STR[28]=16'sd   166; BANK_STR[29]=16'sd   145; BANK_STR[30]=16'sd   118; BANK_STR[31]=16'sd    87;
    end

    function signed [15:0] cf;
        input integer hidx;      // 0..31
        input [2:0]   t;
        begin
            case (t)
                3'd0:    cf = BANK_SIN[hidx];
                3'd1:    cf = BANK_PIA[hidx];
                3'd2:    cf = BANK_ORG[hidx];
                3'd3:    cf = BANK_FLT[hidx];
                default: cf = BANK_STR[hidx];   // 3'd4 弦乐
            endcase
        end
    endfunction

    reg signed [15:0] act [0:31];

    wire [9:0] ph_top =
        ({10{sel[ 0]}} & ph[ 1][31:22]) | ({10{sel[ 1]}} & ph[ 2][31:22]) |
        ({10{sel[ 2]}} & ph[ 3][31:22]) | ({10{sel[ 3]}} & ph[ 4][31:22]) |
        ({10{sel[ 4]}} & ph[ 5][31:22]) | ({10{sel[ 5]}} & ph[ 6][31:22]) |
        ({10{sel[ 6]}} & ph[ 7][31:22]) | ({10{sel[ 7]}} & ph[ 8][31:22]) |
        ({10{sel[ 8]}} & ph[ 9][31:22]) | ({10{sel[ 9]}} & ph[10][31:22]) |
        ({10{sel[10]}} & ph[11][31:22]) | ({10{sel[11]}} & ph[12][31:22]) |
        ({10{sel[12]}} & ph[13][31:22]) | ({10{sel[13]}} & ph[14][31:22]) |
        ({10{sel[14]}} & ph[15][31:22]) | ({10{sel[15]}} & ph[16][31:22]) |
        ({10{sel[16]}} & ph[17][31:22]) | ({10{sel[17]}} & ph[18][31:22]) |
        ({10{sel[18]}} & ph[19][31:22]) | ({10{sel[19]}} & ph[20][31:22]) |
        ({10{sel[20]}} & ph[21][31:22]) | ({10{sel[21]}} & ph[22][31:22]) |
        ({10{sel[22]}} & ph[23][31:22]) | ({10{sel[23]}} & ph[24][31:22]) |
        ({10{sel[24]}} & ph[25][31:22]) | ({10{sel[25]}} & ph[26][31:22]) |
        ({10{sel[26]}} & ph[27][31:22]) | ({10{sel[27]}} & ph[28][31:22]) |
        ({10{sel[28]}} & ph[29][31:22]) | ({10{sel[29]}} & ph[30][31:22]) |
        ({10{sel[30]}} & ph[31][31:22]) | ({10{sel[31]}} & ph[32][31:22]);

    wire signed [15:0] aq_sel =
        (sel[ 0] ? act[ 0] : 16'sd0) | (sel[ 1] ? act[ 1] : 16'sd0) |
        (sel[ 2] ? act[ 2] : 16'sd0) | (sel[ 3] ? act[ 3] : 16'sd0) |
        (sel[ 4] ? act[ 4] : 16'sd0) | (sel[ 5] ? act[ 5] : 16'sd0) |
        (sel[ 6] ? act[ 6] : 16'sd0) | (sel[ 7] ? act[ 7] : 16'sd0) |
        (sel[ 8] ? act[ 8] : 16'sd0) | (sel[ 9] ? act[ 9] : 16'sd0) |
        (sel[10] ? act[10] : 16'sd0) | (sel[11] ? act[11] : 16'sd0) |
        (sel[12] ? act[12] : 16'sd0) | (sel[13] ? act[13] : 16'sd0) |
        (sel[14] ? act[14] : 16'sd0) | (sel[15] ? act[15] : 16'sd0) |
        (sel[16] ? act[16] : 16'sd0) | (sel[17] ? act[17] : 16'sd0) |
        (sel[18] ? act[18] : 16'sd0) | (sel[19] ? act[19] : 16'sd0) |
        (sel[20] ? act[20] : 16'sd0) | (sel[21] ? act[21] : 16'sd0) |
        (sel[22] ? act[22] : 16'sd0) | (sel[23] ? act[23] : 16'sd0) |
        (sel[24] ? act[24] : 16'sd0) | (sel[25] ? act[25] : 16'sd0) |
        (sel[26] ? act[26] : 16'sd0) | (sel[27] ? act[27] : 16'sd0) |
        (sel[28] ? act[28] : 16'sd0) | (sel[29] ? act[29] : 16'sd0) |
        (sel[30] ? act[30] : 16'sd0) | (sel[31] ? act[31] : 16'sd0);

    wire signed [15:0] rom_dout;
    reg  [9:0]         addr = 10'd0;

    sine_rom u_sin (
        .clk  (clk),
        .addr (addr),
        .dout (rom_dout)
    );

    reg signed [15:0] aq_r = 16'sd0;
    reg signed [31:0] prod = 32'sd0;
    reg signed [31:0] term = 32'sd0;
    reg signed [17:0] acc  = 18'sd0;

    wire signed [31:0] prod_n = aq_r * rom_dout;    // 两边都 signed，乘积才是 signed
    wire signed [31:0] term_n = prod >>> 15;        // 右移 15 还原 Q15 量级

    // 输出和值（加直流偏置，抬到正区间）
    wire signed [17:0] wave_sum = acc + BIAS;

    reg gate_d   = 1'b0;
    reg frame_ok = 1'b0;

    reg [5:0] clr_cnt = 6'd0;                    // `!frame_ok` 期间连续轮转了几拍
    wire      clr_done = (clr_cnt >= 6'd32);     // 满 32 拍 = 32 个槽各扫过一遍
    wire      clearing = (!frame_ok && !clr_done);

    always @(posedge clk) begin
        if (frame_ok)       clr_cnt <= 6'd0;     // 允许累加 ⇒ 下次静音重新起一轮
        else if (!clr_done) clr_cnt <= clr_cnt + 6'd1;
    end

    always @(posedge clk) begin
        gate_d <= gate;
        if (!gate)                       frame_ok <= 1'b0;   // 没有音符：一直不允许
        else if (ff == 9'd0 && clr_done) frame_ok <= 1'b1;   // 帧首且清零完毕才放行
    end

    integer i;

    wire slot_we = busy && (sub == 3'd6) && frame_ok;   // 本拍是否落在"累加"的槽位

    always @(posedge clk) begin

        if      (sel[ 0] && clearing)  ph[ 1] <= 32'd0;
        else if (sel[ 0] && slot_we)   ph[ 1] <= ph[ 1] + hps_slot[31:0];
        if      (sel[ 1] && clearing)  ph[ 2] <= 32'd0;
        else if (sel[ 1] && slot_we)   ph[ 2] <= ph[ 2] + hps_slot[31:0];
        if      (sel[ 2] && clearing)  ph[ 3] <= 32'd0;
        else if (sel[ 2] && slot_we)   ph[ 3] <= ph[ 3] + hps_slot[31:0];
        if      (sel[ 3] && clearing)  ph[ 4] <= 32'd0;
        else if (sel[ 3] && slot_we)   ph[ 4] <= ph[ 4] + hps_slot[31:0];
        if      (sel[ 4] && clearing)  ph[ 5] <= 32'd0;
        else if (sel[ 4] && slot_we)   ph[ 5] <= ph[ 5] + hps_slot[31:0];
        if      (sel[ 5] && clearing)  ph[ 6] <= 32'd0;
        else if (sel[ 5] && slot_we)   ph[ 6] <= ph[ 6] + hps_slot[31:0];
        if      (sel[ 6] && clearing)  ph[ 7] <= 32'd0;
        else if (sel[ 6] && slot_we)   ph[ 7] <= ph[ 7] + hps_slot[31:0];
        if      (sel[ 7] && clearing)  ph[ 8] <= 32'd0;
        else if (sel[ 7] && slot_we)   ph[ 8] <= ph[ 8] + hps_slot[31:0];
        if      (sel[ 8] && clearing)  ph[ 9] <= 32'd0;
        else if (sel[ 8] && slot_we)   ph[ 9] <= ph[ 9] + hps_slot[31:0];
        if      (sel[ 9] && clearing)  ph[10] <= 32'd0;
        else if (sel[ 9] && slot_we)   ph[10] <= ph[10] + hps_slot[31:0];
        if      (sel[10] && clearing)  ph[11] <= 32'd0;
        else if (sel[10] && slot_we)   ph[11] <= ph[11] + hps_slot[31:0];
        if      (sel[11] && clearing)  ph[12] <= 32'd0;
        else if (sel[11] && slot_we)   ph[12] <= ph[12] + hps_slot[31:0];
        if      (sel[12] && clearing)  ph[13] <= 32'd0;
        else if (sel[12] && slot_we)   ph[13] <= ph[13] + hps_slot[31:0];
        if      (sel[13] && clearing)  ph[14] <= 32'd0;
        else if (sel[13] && slot_we)   ph[14] <= ph[14] + hps_slot[31:0];
        if      (sel[14] && clearing)  ph[15] <= 32'd0;
        else if (sel[14] && slot_we)   ph[15] <= ph[15] + hps_slot[31:0];
        if      (sel[15] && clearing)  ph[16] <= 32'd0;
        else if (sel[15] && slot_we)   ph[16] <= ph[16] + hps_slot[31:0];
        if      (sel[16] && clearing)  ph[17] <= 32'd0;
        else if (sel[16] && slot_we)   ph[17] <= ph[17] + hps_slot[31:0];
        if      (sel[17] && clearing)  ph[18] <= 32'd0;
        else if (sel[17] && slot_we)   ph[18] <= ph[18] + hps_slot[31:0];
        if      (sel[18] && clearing)  ph[19] <= 32'd0;
        else if (sel[18] && slot_we)   ph[19] <= ph[19] + hps_slot[31:0];
        if      (sel[19] && clearing)  ph[20] <= 32'd0;
        else if (sel[19] && slot_we)   ph[20] <= ph[20] + hps_slot[31:0];
        if      (sel[20] && clearing)  ph[21] <= 32'd0;
        else if (sel[20] && slot_we)   ph[21] <= ph[21] + hps_slot[31:0];
        if      (sel[21] && clearing)  ph[22] <= 32'd0;
        else if (sel[21] && slot_we)   ph[22] <= ph[22] + hps_slot[31:0];
        if      (sel[22] && clearing)  ph[23] <= 32'd0;
        else if (sel[22] && slot_we)   ph[23] <= ph[23] + hps_slot[31:0];
        if      (sel[23] && clearing)  ph[24] <= 32'd0;
        else if (sel[23] && slot_we)   ph[24] <= ph[24] + hps_slot[31:0];
        if      (sel[24] && clearing)  ph[25] <= 32'd0;
        else if (sel[24] && slot_we)   ph[25] <= ph[25] + hps_slot[31:0];
        if      (sel[25] && clearing)  ph[26] <= 32'd0;
        else if (sel[25] && slot_we)   ph[26] <= ph[26] + hps_slot[31:0];
        if      (sel[26] && clearing)  ph[27] <= 32'd0;
        else if (sel[26] && slot_we)   ph[27] <= ph[27] + hps_slot[31:0];
        if      (sel[27] && clearing)  ph[28] <= 32'd0;
        else if (sel[27] && slot_we)   ph[28] <= ph[28] + hps_slot[31:0];
        if      (sel[28] && clearing)  ph[29] <= 32'd0;
        else if (sel[28] && slot_we)   ph[29] <= ph[29] + hps_slot[31:0];
        if      (sel[29] && clearing)  ph[30] <= 32'd0;
        else if (sel[29] && slot_we)   ph[30] <= ph[30] + hps_slot[31:0];
        if      (sel[30] && clearing)  ph[31] <= 32'd0;
        else if (sel[30] && slot_we)   ph[31] <= ph[31] + hps_slot[31:0];
        if      (sel[31] && clearing)  ph[32] <= 32'd0;
        else if (sel[31] && slot_we)   ph[32] <= ph[32] + hps_slot[31:0];
    end

    always @(posedge clk) begin

        if (clearing)                   sel <= {sel[30:0], sel[31]};
        else if (ff == 9'd0)            sel <= 32'd1;
        else if (busy && sub == 3'd7)   sel <= {sel[30:0], sel[31]};
    end

    // 系数表载入：帧首按 timbre 选一次（载入索引是常数 ⇒ 零地址译码）
    always @(posedge clk) begin
        if (ff == 9'd0) begin
            for (i = 0; i <= 31; i = i + 1)
                act[i] <= cf(i, timbre);
        end
    end

    always @(posedge clk) begin
        if (busy) begin
            case (sub)
                3'd0: begin
                    hps      <= hps_nxt;
                    hps_slot <= hps_nxt;
                    aa       <= AA_GATE_EN ? (hps_nxt < AA_THRESH) : 1'b1;
                end
                3'd1: begin
                    addr <= ph_top;             // 一热与-或读出，无地址 mux
                    aq_r <= aq_sel;             // 同上
                    aa_r <= aa;
                end
                // 3'd2: ROM 同步读的延迟拍，不做动作
                3'd3: prod <= prod_n;
                3'd4: term <= term_n;
                3'd5: acc  <= acc + (aa_r ? term : 18'sd0);
                // 3'd6: 轮转在另外两个 always 块里做
                // 3'd7: 空闲
                default: ;
            endcase
        end

        if (ff == 9'd256 && frame_ok) begin

            if      (wave_sum > WAVE_MAX) wave <= 16'sd16380;
            else if (wave_sum < 18'sd0)   wave <= 16'sd0;
            else                          wave <= wave_sum[15:0];

            acc <= 18'sd0;
            // hps 不用在这里清 —— 下一帧开头由 hps_nxt 无条件播种
        end

        else if (!frame_ok) acc <= 18'sd0;
    end

endmodule
