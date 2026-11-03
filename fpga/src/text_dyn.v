// text_dyn.v —— 文字层里的动态数值字符（720p 参数列）

module text_dyn (
    input  wire [5:0] row,
    input  wire [7:0] col,
    input  wire [2:0] timbre,      // 0=正弦 1=钢琴 2=管风琴 3=长笛 4=弦乐
    input  wire [2:0] octave,      // 1/2/3 => -1/0/+1
    input  wire [7:0] vol_h,       // 百位（v<100 时是空格）
    input  wire [7:0] vol_t,       // 十位
    input  wire [7:0] vol_o,       // 个位
    input  wire [1:0] expr_sel,    // 0=关 1=滑音 2=颤音 3=震音
    input  wire [1:0] expr_amt,    // 0..3
    input  wire [2:0] fx_on,       // {cho,rev,dly}
    input  wire [1:0] dly_p, rev_p, cho_p,
    input  wire [3:0] key_cnt,     // 0..12
    input  wire [3:0] voice_cnt,   // 0..8
    output reg  [7:0] ch,
    output reg        sel          // 1 = 这一格是动态值
);

    function [7:0] timbre_char;
        input [2:0] t;
        input [3:0] i;
        begin
            case (t)
                3'd0: timbre_char = (i == 4'd0) ? "S" : (i == 4'd1) ? "I" :
                                    (i == 4'd2) ? "N" : (i == 4'd3) ? "E" : " ";
                3'd1: timbre_char = (i == 4'd0) ? "P" : (i == 4'd1) ? "I" :
                                    (i == 4'd2) ? "A" : (i == 4'd3) ? "N" :
                                    (i == 4'd4) ? "O" : " ";
                3'd2: timbre_char = (i == 4'd0) ? "O" : (i == 4'd1) ? "R" :
                                    (i == 4'd2) ? "G" : (i == 4'd3) ? "A" :
                                    (i == 4'd4) ? "N" : " ";
                3'd3: timbre_char = (i == 4'd0) ? "F" : (i == 4'd1) ? "L" :
                                    (i == 4'd2) ? "U" : (i == 4'd3) ? "T" :
                                    (i == 4'd4) ? "E" : " ";
                3'd4: timbre_char = (i == 4'd0) ? "S" : (i == 4'd1) ? "T" :
                                    (i == 4'd2) ? "R" : (i == 4'd3) ? "I" :
                                    (i == 4'd4) ? "N" : (i == 4'd5) ? "G" :
                                    (i == 4'd6) ? "S" : " ";
                default: timbre_char = " ";
            endcase
        end
    endfunction

    // 表情名字（最多 7 字符）
    function [7:0] expr_char;
        input [1:0] e;
        input [3:0] i;
        begin
            case (e)
                2'd0: expr_char = (i == 4'd0) ? "O" : (i == 4'd1) ? "F" :
                                  (i == 4'd2) ? "F" : " ";
                2'd1: expr_char = (i == 4'd0) ? "G" : (i == 4'd1) ? "L" :
                                  (i == 4'd2) ? "I" : (i == 4'd3) ? "D" :
                                  (i == 4'd4) ? "E" : " ";
                2'd2: expr_char = (i == 4'd0) ? "V" : (i == 4'd1) ? "I" :
                                  (i == 4'd2) ? "B" : (i == 4'd3) ? "R" :
                                  (i == 4'd4) ? "A" : (i == 4'd5) ? "T" :
                                  (i == 4'd6) ? "O" : " ";
                2'd3: expr_char = (i == 4'd0) ? "T" : (i == 4'd1) ? "R" :
                                  (i == 4'd2) ? "E" : (i == 4'd3) ? "M" :
                                  (i == 4'd4) ? "O" : (i == 4'd5) ? "L" :
                                  (i == 4'd6) ? "O" : " ";
                default: expr_char = " ";
            endcase
        end
    endfunction

    // ON/OFF：i=0..2 => "ON " / "OFF"
    function [7:0] onoff_char;
        input       on;
        input [3:0] i;
        begin
            case (i)
                4'd0: onoff_char = "O";
                4'd1: onoff_char = on ? "N" : "F";
                4'd2: onoff_char = on ? " " : "F";
                default: onoff_char = " ";
            endcase
        end
    endfunction

    function [7:0] dly_ms_char;
        input [1:0] p;
        input [3:0] i;
        begin
            case (p)
                2'd0: dly_ms_char = (i == 4'd0) ? " " : (i == 4'd1) ? "8" : "0";
                2'd1: dly_ms_char = (i == 4'd0) ? "1" : (i == 4'd1) ? "6" : "0";
                2'd2: dly_ms_char = (i == 4'd0) ? "2" : (i == 4'd1) ? "4" : "0";
                default: dly_ms_char = (i == 4'd0) ? "3" : (i == 4'd1) ? "2" : "0";
            endcase
        end
    endfunction

    // "VOICES" 的 6 个字符
    function [7:0] voices_char;
        input [3:0] i;
        begin
            case (i)
                4'd0: voices_char = "V";
                4'd1: voices_char = "O";
                4'd2: voices_char = "I";
                4'd3: voices_char = "C";
                4'd4: voices_char = "E";
                4'd5: voices_char = "S";
                default: voices_char = " ";
            endcase
        end
    endfunction

    always @(*) begin
        ch  = 8'h20;
        sel = 1'b0;

        case (row)

        6'd4: if (col >= 8'd11 && col <= 8'd17) begin
            sel = 1'b1;
            ch  = timbre_char(timbre, col[3:0] - 4'd11);
        end

        6'd5: if (col == 8'd11) begin
            sel = 1'b1;
            ch  = (octave == 3'd1) ? "-" : (octave == 3'd3) ? "+" : " ";
        end else if (col == 8'd12) begin
            sel = 1'b1;
            ch  = (octave == 3'd2) ? "0" : "1";
        end

        6'd6: if (col == 8'd11) begin
            sel = 1'b1;
            ch  = vol_h;
        end else if (col == 8'd12) begin
            sel = 1'b1;
            ch  = vol_t;
        end else if (col == 8'd13) begin
            sel = 1'b1;
            ch  = vol_o;
        end else if (col == 8'd14) begin
            sel = 1'b1;
            ch  = "%";
        end

        6'd7: if (col >= 8'd11 && col <= 8'd17) begin
            sel = 1'b1;
            ch  = expr_char(expr_sel, col[3:0] - 4'd11);
        end else if (col == 8'd18) begin
            sel = 1'b1;
            ch  = " ";
        end else if (col == 8'd19) begin
            sel = 1'b1;
            ch  = (expr_sel == 2'd0) ? " " : "L";
        end else if (col == 8'd20) begin
            sel = 1'b1;
            ch  = (expr_sel == 2'd0) ? " " : (8'h31 + {6'd0, expr_amt});
        end

        6'd8: if (col >= 8'd11 && col <= 8'd13) begin
            sel = 1'b1;
            ch  = onoff_char(fx_on[0], col[3:0] - 4'd11);
        end else if (col == 8'd14) begin
            sel = 1'b1;
            ch  = " ";
        end else if (col == 8'd15) begin
            sel = 1'b1;
            ch  = "L";
        end else if (col == 8'd16) begin
            sel = 1'b1;
            ch  = 8'h31 + {6'd0, dly_p};
        end else if (col == 8'd17) begin
            sel = 1'b1;
            ch  = " ";
        end else if (col >= 8'd18 && col <= 8'd20) begin
            sel = 1'b1;
            ch  = dly_ms_char(dly_p, col[2:0] - 3'd2);   // 18->0, 19->1, 20->2
        end else if (col == 8'd21) begin
            sel = 1'b1;
            ch  = "M";
        end else if (col == 8'd22) begin
            sel = 1'b1;
            ch  = "S";
        end

        6'd9: if (col >= 8'd11 && col <= 8'd13) begin
            sel = 1'b1;
            ch  = onoff_char(fx_on[1], col[3:0] - 4'd11);
        end else if (col == 8'd14) begin
            sel = 1'b1;
            ch  = " ";
        end else if (col == 8'd15) begin
            sel = 1'b1;
            ch  = "L";
        end else if (col == 8'd16) begin
            sel = 1'b1;
            ch  = 8'h31 + {6'd0, rev_p};
        end

        6'd10: if (col >= 8'd11 && col <= 8'd13) begin
            sel = 1'b1;
            ch  = onoff_char(fx_on[2], col[3:0] - 4'd11);
        end else if (col == 8'd14) begin
            sel = 1'b1;
            ch  = " ";
        end else if (col == 8'd15) begin
            sel = 1'b1;
            ch  = "L";
        end else if (col == 8'd16) begin
            sel = 1'b1;
            ch  = 8'h31 + {6'd0, cho_p};
        end

        6'd11: if (col == 8'd11) begin
            sel = 1'b1;
            ch  = (key_cnt >= 4'd10) ? "1" : " ";
        end else if (col == 8'd12) begin
            sel = 1'b1;
            ch  = 8'h30 + ((key_cnt >= 4'd10) ? (key_cnt - 4'd10) : key_cnt);
        end else if (col == 8'd13) begin
            sel = 1'b1;
            ch  = " ";
        end else if (col >= 8'd14 && col <= 8'd19) begin
            sel = 1'b1;
            ch  = voices_char(col[3:0] - 4'd14);
        end else if (col == 8'd20) begin
            sel = 1'b1;
            ch  = " ";
        end else if (col == 8'd21) begin
            sel = 1'b1;
            ch  = 8'h30 + {4'd0, voice_cnt};
        end else if (col == 8'd22) begin
            sel = 1'b1;
            ch  = "/";
        end else if (col == 8'd23) begin
            sel = 1'b1;
            ch  = "8";
        end

        default: ;
        endcase
    end

endmodule
