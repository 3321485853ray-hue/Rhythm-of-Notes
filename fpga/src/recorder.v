// recorder.v — 录制键盘演奏 → 存成和曲谱完全相同的事件记录

module recorder (
    input  wire        clk,
    input  wire        rec_on,        // 电平：正在录制
    input  wire        clr,           // 单拍：清空（REC_BEGIN）
    input  wire [31:0] tick_cyc,      // 一个 tick 多少 clk
    input  wire [11:0] key_press,
    input  wire [11:0] key_release,
    input  wire [83:0] km_notes,      // 12×7（来自 keymap）
    input  wire [11:0] km_valid,

    // 写 event_ram
    output reg         we,
    output reg  [12:0] waddr,
    output reg  [63:0] wdata,
    output reg  [15:0] count,         // 已录事件数
    output reg         full
);

    reg [31:0] tick     = 32'd0;      // 当前 ms
    reg [31:0] tick_div = 32'd0;
    reg [31:0] last_t   = 32'd0;      // 上一个事件的起点

    reg        pend  [0:11];
    reg [12:0] paddr [0:11];
    reg [31:0] ptime [0:11];
    reg [15:0] pdelta[0:11];
    reg [7:0]  pnote [0:11];

    reg [11:0] ppend = 12'd0;
    reg [11:0] rpend = 12'd0;

    wire [11:0] kpress  = key_press & km_valid;

    wire [11:0] ppend_n = ppend | kpress;
    wire [11:0] rpend_n = rpend | key_release;

    reg [3:0] pk;

    integer n;
    always @(*) begin
        pk = 4'd0;
        casez (ppend_n)
            12'b???????????1: pk = 4'd0;
            12'b??????????10: pk = 4'd1;
            12'b?????????100: pk = 4'd2;
            12'b????????1000: pk = 4'd3;
            12'b???????10000: pk = 4'd4;
            12'b??????100000: pk = 4'd5;
            12'b?????1000000: pk = 4'd6;
            12'b????10000000: pk = 4'd7;
            12'b???100000000: pk = 4'd8;
            12'b??1000000000: pk = 4'd9;
            12'b?10000000000: pk = 4'd10;
            default:          pk = 4'd11;
        endcase
    end

    reg [3:0] rk;
    always @(*) begin
        rk = 4'd0;
        casez (rpend_n)
            12'b???????????1: rk = 4'd0;
            12'b??????????10: rk = 4'd1;
            12'b?????????100: rk = 4'd2;
            12'b????????1000: rk = 4'd3;
            12'b???????10000: rk = 4'd4;
            12'b??????100000: rk = 4'd5;
            12'b?????1000000: rk = 4'd6;
            12'b????10000000: rk = 4'd7;
            12'b???100000000: rk = 4'd8;
            12'b??1000000000: rk = 4'd9;
            12'b?10000000000: rk = 4'd10;
            default:          rk = 4'd11;
        endcase
    end

    wire [15:0] dlt = tick - last_t;

    // 键位表查表：同样不能用变量位选（见 voice.v 同一处注释）
    reg [6:0] kn;
    always @(*) begin
        case (pk)
            4'd0:    kn = km_notes[6:0];
            4'd1:    kn = km_notes[13:7];
            4'd2:    kn = km_notes[20:14];
            4'd3:    kn = km_notes[27:21];
            4'd4:    kn = km_notes[34:28];
            4'd5:    kn = km_notes[41:35];
            4'd6:    kn = km_notes[48:42];
            4'd7:    kn = km_notes[55:49];
            4'd8:    kn = km_notes[62:56];
            4'd9:    kn = km_notes[69:63];
            4'd10:   kn = km_notes[76:70];
            default: kn = km_notes[83:77];   // 键 11
        endcase
    end

    wire [7:0] kn_midi = {1'b0, kn} + 8'd24;

    // 松手时刻的时长（至少 1 ms；用中间量是因为 Verilog 不允许对表达式做位选）
    wire [31:0] dur32 = tick - ptime[rk];
    wire [15:0] dur16 = (dur32 == 32'd0) ? 16'd1 : dur32[15:0];

    always @(posedge clk) begin
        we <= 1'b0;

        if (clr) begin
            tick     <= 32'd0;
            tick_div <= 32'd0;
            last_t   <= 32'd0;
            count    <= 16'd0;
            full     <= 1'b0;
            ppend    <= 12'd0;
            rpend    <= 12'd0;
            for (n = 0; n < 12; n = n + 1) begin
                pend[n]  <= 1'b0;
                paddr[n] <= 13'd0;
                ptime[n] <= 32'd0;
                pdelta[n]<= 16'd0;
                pnote[n] <= 8'd0;
            end
        end else if (rec_on) begin

            if (tick_div + 32'd1 >= tick_cyc) begin
                tick_div <= 32'd0;
                tick     <= tick + 32'd1;
            end else
                tick_div <= tick_div + 32'd1;

            if ((ppend_n != 12'd0) && !full) begin
                we    <= 1'b1;
                waddr <= count[12:0];

                wdata <= {8'd0, 8'd0, 16'd0, 8'd100,
                          kn_midi, dlt};
                paddr[pk]  <= count[12:0];
                ptime[pk]  <= tick;
                pdelta[pk] <= dlt;
                pnote[pk]  <= kn_midi;
                pend[pk]   <= 1'b1;
                last_t     <= tick;
                count      <= count + 16'd1;
                ppend      <= ppend_n & ~(12'b1 << pk);
                rpend      <= rpend_n;
                if (count + 16'd1 >= 16'd8192) full <= 1'b1;
            end

            else if (rpend_n != 12'd0) begin
                ppend <= ppend_n;

                if (pend[rk]) begin
                    we    <= 1'b1;
                    waddr <= paddr[rk];
                    // dur = 松开时刻 − 按下时刻（至少 1 ms）
                    wdata <= {8'd0, 8'd0, dur16, 8'd100, pnote[rk], pdelta[rk]};
                    pend[rk] <= 1'b0;
                end
                rpend <= rpend_n & ~(12'b1 << rk);
            end

            else begin
                ppend <= ppend_n;
                rpend <= rpend_n;
            end
        end else begin
            ppend <= 12'd0;
            rpend <= 12'd0;
        end
    end

endmodule
