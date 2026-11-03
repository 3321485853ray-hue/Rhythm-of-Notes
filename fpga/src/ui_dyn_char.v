// ui_dyn_char.v —— 屏幕上的动态数值字符

module ui_dyn_char (
    input  wire [5:0]  row,
    input  wire [6:0]  col,
    input  wire [2:0]  timbre,      // 0=正弦 1=钢琴 2=管风琴 3=长笛 4=弦乐
    input  wire [2:0]  octave,      // 0~4 偏移 +2（2 = 0 八度）
    input  wire [6:0]  vol_pct,     // 0..99
    input  wire [1:0]  expr_sel,
    input  wire [1:0]  expr_amt,
    input  wire [2:0]  fx_on,       // {cho,rev,dly}
    input  wire [1:0]  dly_p, rev_p, cho_p,
    input  wire [7:0]  v_gate,
    input  wire [31:0] v_keys,
    input  wire [3:0]  key_cnt,     // 0..12
    input  wire [3:0]  voice_cnt,   // 0..8
    output reg  [7:0]  ch,
    output reg         sel          // 1 = 这一格是动态值（整行高亮）
);

    function [7:0] kletter;
        input [3:0] k;
        begin
            case (k)
                4'd0, 4'd7:  kletter = "C";
                4'd1, 4'd8:  kletter = "D";
                4'd2:        kletter = "E";
                4'd3, 4'd9:  kletter = "F";
                4'd4, 4'd10: kletter = "G";
                4'd5, 4'd11: kletter = "A";
                4'd6:        kletter = "B";
                default:     kletter = " ";
            endcase
        end
    endfunction

    // 键号 7..11 是黑键
    function is_sharp;
        input [3:0] k;
        begin is_sharp = (k >= 4'd7); end
    endfunction

    // 八度数字：octave 编码 1/2/3 -> '3'/'4'/'5'
    function [7:0] octdigit;
        input [2:0] o;
        begin octdigit = 8'h30 + {5'd0, o} + 8'd2; end
    endfunction

    // 十位/个位（0..99）
    function [3:0] tens10;
        input [6:0] v;
        begin
            if      (v >= 7'd90) tens10 = 4'd9;
            else if (v >= 7'd80) tens10 = 4'd8;
            else if (v >= 7'd70) tens10 = 4'd7;
            else if (v >= 7'd60) tens10 = 4'd6;
            else if (v >= 7'd50) tens10 = 4'd5;
            else if (v >= 7'd40) tens10 = 4'd4;
            else if (v >= 7'd30) tens10 = 4'd3;
            else if (v >= 7'd20) tens10 = 4'd2;
            else if (v >= 7'd10) tens10 = 4'd1;
            else                 tens10 = 4'd0;
        end
    endfunction

    function [3:0] ones10;
        input [6:0] v;
        begin ones10 = v - {3'd0, tens10(v)} * 4'd10; end
    endfunction

    // 音色名字（最多 7 字符）
    function [7:0] timbre_char;
        input [2:0] t;
        input [3:0] i;
        begin
            case (t)
                3'd1: case (i) 0:"P" 1:"I" 2:"A" 3:"N" 4:"O" 5:" " 6:" " default:" " endcase
                3'd2: case (i) 0:"O" 1:"R" 2:"G" 3:"A" 4:"N" 5:" " 6:" " default:" " endcase
                3'd3: case (i) 0:"F" 1:"L" 2:"U" 3:"T" 4:"E" 5:" " 6:" " default:" " endcase
                3'd4: case (i) 0:"S" 1:"T" 2:"R" 3:"I" 4:"N" 5:"G" 6:"S" default:" " endcase
                default: case (i) 0:"S" 1:"I" 2:"N" 3:"E" 4:" " 5:" " 6:" " default:" " endcase
            endcase
        end
    endfunction

    // 表情名字（最多 7 字符）
    function [7:0] expr_char;
        input [1:0] e;
        input [3:0] i;
        begin
            case (e)
                2'd1: case (i) 0:"G" 1:"L" 2:"I" 3:"D" 4:"E" 5:" " 6:" " default:" " endcase
                2'd2: case (i) 0:"V" 1:"I" 2:"B" 3:"R" 4:"A" 5:"T" 6:"O" default:" " endcase
                2'd3: case (i) 0:"T" 1:"R" 2:"E" 3:"M" 4:"O" 5:"L" 6:"O" default:" " endcase
                default: case (i) 0:"O" 1:"F" 2:"F" 3:" " 4:" " 5:" " 6:" " default:" " endcase
            endcase
        end
    endfunction

    function [7:0] dly_ms_char;
        input [1:0] p;
        input [1:0] i;
        begin
            case (p)
                2'd0: case (i) 0:" " 1:"8" 2:"0" default:" " endcase
                2'd1: case (i) 0:"1" 1:"6" 2:"0" default:" " endcase
                2'd2: case (i) 0:"2" 1:"4" 2:"0" default:" " endcase
                default: case (i) 0:"3" 1:"2" 2:"0" default:" " endcase
            endcase
        end
    endfunction

    integer i;
    reg [3:0] vidx;

    always @(*) begin
        ch  = 8'h20;
        sel = 1'b0;

        case (row)

        6'd5: if (col >= 7'd16 && col <= 7'd22) begin
            sel = 1'b1;
            ch  = timbre_char(timbre, col[3:0] - 4'd16);
        end

        6'd6: if (col == 7'd16) begin
            sel = 1'b1;
            ch  = (octave == 3'd1) ? "-" : (octave == 3'd3) ? "+" : " ";
        end else if (col == 7'd17) begin
            sel = 1'b1;
            ch  = (octave == 3'd2) ? "0" : "1";
        end

        6'd7: if (col == 7'd16) begin
            sel = 1'b1;
            ch  = 8'h20;                       // 百位恒 0
        end else if (col == 7'd17) begin
            sel = 1'b1;
            ch  = 8'h30 + {4'd0, tens10(vol_pct)};
        end else if (col == 7'd18) begin
            sel = 1'b1;
            ch  = 8'h30 + {4'd0, ones10(vol_pct)};
        end else if (col == 7'd19) begin
            sel = 1'b1;
            ch  = "%";
        end

        6'd8: if (col >= 7'd16 && col <= 7'd22) begin
            sel = 1'b1;
            ch  = expr_char(expr_sel, col[3:0] - 4'd16);
        end else if (col == 7'd32) begin
            sel = 1'b1;
            ch  = 8'h31 + {6'd0, expr_amt};     // '1'..'4'
        end

        6'd10: if (col >= 7'd12 && col <= 7'd14) begin
            sel = 1'b1;
            case (col - 7'd12)
                7'd0: ch = fx_on[0] ? "O" : "O";
                7'd1: ch = fx_on[0] ? "N" : "F";
                7'd2: ch = fx_on[0] ? " " : "F";
                default: ch = " ";
            endcase
        end else if (col == 7'd17) begin
            sel = 1'b1;
            ch  = 8'h31 + {6'd0, dly_p};
        end else if (col >= 7'd23 && col <= 7'd25) begin
            sel = 1'b1;
            ch  = dly_ms_char(dly_p, col[1:0] - 2'd3);  // 23,24,25 -> 0,1,2
        end

        6'd11: if (col >= 7'd12 && col <= 7'd14) begin
            sel = 1'b1;
            case (col - 7'd12)
                7'd0: ch = "O";
                7'd1: ch = fx_on[1] ? "N" : "F";
                7'd2: ch = fx_on[1] ? " " : "F";
                default: ch = " ";
            endcase
        end else if (col == 7'd17) begin
            sel = 1'b1;
            ch  = 8'h31 + {6'd0, rev_p};
        end

        6'd12: if (col >= 7'd12 && col <= 7'd14) begin
            sel = 1'b1;
            case (col - 7'd12)
                7'd0: ch = "O";
                7'd1: ch = fx_on[2] ? "N" : "F";
                7'd2: ch = fx_on[2] ? " " : "F";
                default: ch = " ";
            endcase
        end else if (col == 7'd17) begin
            sel = 1'b1;
            ch  = 8'h31 + {6'd0, cho_p};
        end

        6'd12: if (col >= 7'd68) begin
            case (col)
                7'd68, 7'd76, 7'd91, 7'd99, 7'd107: begin sel = 1'b1; ch = kletter(black_key_at(col)); end
                7'd69, 7'd77, 7'd92, 7'd100, 7'd108: begin sel = 1'b1; ch = "#"; end
                7'd70, 7'd78, 7'd93, 7'd101, 7'd109: begin sel = 1'b1; ch = octdigit(octave); end
                default: ;
            endcase
        end

        6'd14: if (col == 7'd18) begin
            sel = 1'b1;
            ch  = (key_cnt >= 4'd10) ? "1" : " ";
        end else if (col == 7'd19) begin
            sel = 1'b1;
            ch  = (key_cnt >= 4'd10) ? (8'h30 + {4'd0, key_cnt} - 8'd10) : (8'h30 + {4'd0, key_cnt});
        end

        6'd15: if (col == 7'd19) begin
            sel = 1'b1;
            ch  = 8'h30 + {4'd0, voice_cnt};
        end

        6'd18: begin
            case (col)
                7'd65, 7'd73, 7'd80, 7'd88, 7'd96, 7'd103, 7'd111:
                    begin sel = 1'b1; ch = kletter(white_key_at(col)); end
                7'd66, 7'd74, 7'd81, 7'd89, 7'd97, 7'd104, 7'd112:
                    begin sel = 1'b1; ch = octdigit(octave); end
                default: ;
            endcase
        end

        6'd22: begin
            for (i = 0; i < 8; i = i + 1) begin
                if (col == (7'd4 + i * 7'd15)) begin
                    sel = 1'b1;
                    ch  = v_gate[i] ? kletter(v_keys[i*4 +: 4]) : "-";
                end else if (col == (7'd5 + i * 7'd15)) begin
                    sel = 1'b1;
                    ch  = v_gate[i] && is_sharp(v_keys[i*4 +: 4]) ? "#" : " ";
                end else if (col == (7'd6 + i * 7'd15)) begin
                    sel = 1'b1;
                    ch  = v_gate[i] ? octdigit(octave) : "-";
                end
            end
        end

        default: ;
        endcase
    end

    function [3:0] black_key_at;
        input [6:0] c;
        begin
            case (c)
                7'd68, 7'd69, 7'd70:   black_key_at = 4'd7;
                7'd76, 7'd77, 7'd78:   black_key_at = 4'd8;
                7'd91, 7'd92, 7'd93:   black_key_at = 4'd9;
                7'd99, 7'd100, 7'd101: black_key_at = 4'd10;
                default:               black_key_at = 4'd11;   // 107..109
            endcase
        end
    endfunction

    // 白键列 -> 键号（白键排：键0..6 = C4 D4 E4 F4 G4 A4 B4）
    function [3:0] white_key_at;
        input [6:0] c;
        begin
            case (c)
                7'd65, 7'd66:   white_key_at = 4'd0;
                7'd73, 7'd74:   white_key_at = 4'd1;
                7'd80, 7'd81:   white_key_at = 4'd2;
                7'd88, 7'd89:   white_key_at = 4'd3;
                7'd96, 7'd97:   white_key_at = 4'd4;
                7'd103, 7'd104: white_key_at = 4'd5;
                default:        white_key_at = 4'd6;   // 111,112
            endcase
        end
    endfunction

endmodule
