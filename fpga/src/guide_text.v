// guide_text.v —— GUIDE 面板文字（拆成两个模块）

module guide_line (
    input  wire [2:0]   g_state,        // 0=OFF 1=MODE 2=SONG 3=B_RUN 4=B_DONE 5=A_RUN
    input  wire         g_song,
    input  wire         g_adv,
    input  wire [3:0]   g_expected,
    input  wire         g_wrong_active,
    input  wire         g_msg_show,
    input  wire [5:0]   g_step,
    input  wire [3:0]   g_adv_next,
    input  wire [5:0]   g_hits,
    input  wire [2:0]   octave,
    output wire [231:0] line,
    output wire [175:0] line2,          // row 32，22 字符
    output wire [175:0] line3           // row 34，22 字符
);

    localparam NCHAR = 29;
    localparam MCHAR = 22;

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
        reg [6:0] tmp;
        begin
            tmp = v - {3'd0, tens10(v)} * 4'd10;
            ones10 = tmp[3:0];
        end
    endfunction

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
                default:     kletter = "-";
            endcase
        end
    endfunction

    function is_sharp;
        input [3:0] k;
        begin is_sharp = (k >= 4'd7) && (k <= 4'd11); end
    endfunction

    function [7:0] octdigit;
        input [2:0] o;
        begin
            case (o)
                3'd1: octdigit = "3";
                3'd2: octdigit = "4";
                3'd3: octdigit = "5";
                default: octdigit = "4";
            endcase
        end
    endfunction

    localparam [191:0] MSG_MENU  = 192'h50524553532041204B455920544F20535441525420202020;  // PRESS A KEY TO START
    localparam [191:0] MSG_WRONG = 192'h57524F4E47212054525920414741494E2020202020202020;  // WRONG! TRY AGAIN
    localparam [191:0] MSG_DONE  = 192'h47554944452046494E495348454420202020202020202020;  // GUIDE FINISHED
    localparam [191:0] MSG_OFF   = 192'h5052455353204B4559312046495253542020202020202020;  // PRESS KEY1 FIRST
    localparam [191:0] MSG_MODE0 = 192'h4D4F44453A20424547494E4E455220202020202020202020;  // MODE: BEGINNER
    localparam [191:0] MSG_MODE1 = 192'h4D4F44453A2052485954484D202020202020202020202020;  // MODE: RHYTHM
    localparam [191:0] MSG_FAIL  = 192'h4D495353212050524553532041204B455920202020202020;  // MISS! PRESS A KEY

    function [7:0] msg_byte;
        input [191:0] m;
        input [5:0]   i;
        reg [5:0] ii;
        begin
            ii = (i > 6'd23) ? 6'd23 : i;
            msg_byte = m[8*(6'd23 - ii) +: 8];
        end
    endfunction

    function [7:0] menu_char;
        input [2:0] st;
        input [5:0] i;
        begin
            case (st)
                // MODE: "KEY2 CHANGE  KEY1 OK"
                3'd1: case (i)
                    6'd0: menu_char = "K"; 6'd1: menu_char = "E";
                    6'd2: menu_char = "Y"; 6'd3: menu_char = "2";
                    6'd4: menu_char = " "; 6'd5: menu_char = "C";
                    6'd6: menu_char = "H"; 6'd7: menu_char = "A";
                    6'd8: menu_char = "N"; 6'd9: menu_char = "G";
                    6'd10: menu_char = "E"; 6'd11: menu_char = " ";
                    6'd12: menu_char = " "; 6'd13: menu_char = "K";
                    6'd14: menu_char = "E"; 6'd15: menu_char = "Y";
                    6'd16: menu_char = "1"; 6'd17: menu_char = " ";
                    6'd18: menu_char = "O"; 6'd19: menu_char = "K";
                    default: menu_char = " ";
                endcase
                // SONG / B_DONE: "KEY2 SELECT  KEY1 BACK"
                3'd2, 3'd4: case (i)
                    6'd0: menu_char = "K"; 6'd1: menu_char = "E";
                    6'd2: menu_char = "Y"; 6'd3: menu_char = "2";
                    6'd4: menu_char = " "; 6'd5: menu_char = "S";
                    6'd6: menu_char = "E"; 6'd7: menu_char = "L";
                    6'd8: menu_char = "E"; 6'd9: menu_char = "C";
                    6'd10: menu_char = "T"; 6'd11: menu_char = " ";
                    6'd12: menu_char = " "; 6'd13: menu_char = "K";
                    6'd14: menu_char = "E"; 6'd15: menu_char = "Y";
                    6'd16: menu_char = "1"; 6'd17: menu_char = " ";
                    6'd18: menu_char = "B"; 6'd19: menu_char = "A";
                    6'd20: menu_char = "C"; 6'd21: menu_char = "K";
                    default: menu_char = " ";
                endcase
                default: menu_char = " ";
            endcase
        end
    endfunction

    function [7:0] hint_char;
        input [2:0] st;
        input [5:0] i;
        begin
            if (st == 3'd4) begin
                // "PRESS A KEY TO RESTART"
                case (i)
                    6'd0: hint_char = "P"; 6'd1: hint_char = "R";
                    6'd2: hint_char = "E"; 6'd3: hint_char = "S";
                    6'd4: hint_char = "S"; 6'd5: hint_char = " ";
                    6'd6: hint_char = "A"; 6'd7: hint_char = " ";
                    6'd8: hint_char = "K"; 6'd9: hint_char = "E";
                    6'd10: hint_char = "Y"; 6'd11: hint_char = " ";
                    6'd12: hint_char = "T"; 6'd13: hint_char = "O";
                    6'd14: hint_char = " "; 6'd15: hint_char = "R";
                    6'd16: hint_char = "E"; 6'd17: hint_char = "S";
                    6'd18: hint_char = "T"; 6'd19: hint_char = "A";
                    6'd20: hint_char = "R"; 6'd21: hint_char = "T";
                    default: hint_char = " ";
                endcase
            end else if (st != 3'd0) begin
                // "HOLD KEY1 1S = EXIT"
                case (i)
                    6'd0: hint_char = "H"; 6'd1: hint_char = "O";
                    6'd2: hint_char = "L"; 6'd3: hint_char = "D";
                    6'd4: hint_char = " "; 6'd5: hint_char = "K";
                    6'd6: hint_char = "E"; 6'd7: hint_char = "Y";
                    6'd8: hint_char = "1"; 6'd9: hint_char = " ";
                    6'd10: hint_char = "1"; 6'd11: hint_char = "S";
                    6'd12: hint_char = " "; 6'd13: hint_char = "=";
                    6'd14: hint_char = " "; 6'd15: hint_char = "E";
                    6'd16: hint_char = "X"; 6'd17: hint_char = "I";
                    6'd18: hint_char = "T";
                    default: hint_char = " ";
                endcase
            end else
                hint_char = " ";
        end
    endfunction

    function [7:0] status_char;
        input [2:0] st;
        input       adv;
        input       sng;
        input [3:0] exp_key;
        input [3:0] nxt_key;
        input       wrong;
        input       msg;
        input [5:0] step;
        input [5:0] hits;
        input [2:0] oct;
        input [5:0] i;
        reg [6:0] step1;
        reg [6:0] bpm;
        reg [6:0] bpm_t;
        reg [6:0] hit1;
        reg [6:0] tot;
        begin
            step1 = {1'b0, step} + 7'd1;
            bpm   = sng ? 7'd90 : 7'd100;
            bpm_t = (bpm >= 7'd100) ? (bpm - 7'd100) : bpm;
            hit1  = {1'b0, hits};
            tot   = sng ? 7'd30 : 7'd42;
            case (st)
                3'd1: status_char = msg_byte(adv ? MSG_MODE1 : MSG_MODE0, i);
                3'd2: begin
                    if (!adv)
                        status_char = msg_byte(MSG_MENU, i);
                    else begin
                        // FIRST: <note>  PRESS A KEY
                        case (i)
                            6'd0:  status_char = "F";
                            6'd1:  status_char = "I";
                            6'd2:  status_char = "R";
                            6'd3:  status_char = "S";
                            6'd4:  status_char = "T";
                            6'd5:  status_char = ":";
                            6'd6:  status_char = " ";
                            6'd7:  status_char = kletter(exp_key);
                            6'd8:  status_char = is_sharp(exp_key) ? "#" : octdigit(oct);
                            6'd9:  status_char = is_sharp(exp_key) ? octdigit(oct) : " ";
                            6'd10: status_char = " ";
                            6'd11: status_char = "P";
                            6'd12: status_char = "R";
                            6'd13: status_char = "E";
                            6'd14: status_char = "S";
                            6'd15: status_char = "S";
                            6'd16: status_char = " ";
                            6'd17: status_char = "A";
                            6'd18: status_char = " ";
                            6'd19: status_char = "K";
                            6'd20: status_char = "E";
                            6'd21: status_char = "Y";
                            default: status_char = " ";
                        endcase
                    end
                end
                3'd3: begin
                    if (wrong)
                        status_char = msg_byte(MSG_WRONG, i);
                    else begin
                        case (i)
                            6'd0:  status_char = "N";
                            6'd1:  status_char = "E";
                            6'd2:  status_char = "X";
                            6'd3:  status_char = "T";
                            6'd4:  status_char = ":";
                            6'd5:  status_char = " ";
                            6'd6:  status_char = kletter(exp_key);
                            6'd7:  status_char = is_sharp(exp_key) ? "#" : octdigit(oct);
                            6'd8:  status_char = is_sharp(exp_key) ? octdigit(oct) : " ";
                            6'd10: status_char = "S";
                            6'd11: status_char = "T";
                            6'd12: status_char = "E";
                            6'd13: status_char = "P";
                            6'd14: status_char = " ";
                            6'd15: status_char = (tens10(step1) == 4'd0) ? " " :
                                                 (8'h30 + {4'd0, tens10(step1)});
                            6'd16: status_char = 8'h30 + {4'd0, ones10(step1)};
                            default: status_char = " ";
                        endcase
                    end
                end
                3'd4: status_char = msg_byte(MSG_DONE, i);

                3'd5: begin
                    case (i)
                        6'd0:  status_char = "H";
                        6'd1:  status_char = "I";
                        6'd2:  status_char = "T";
                        6'd3:  status_char = "S";
                        6'd4:  status_char = " ";
                        6'd5:  status_char = (tens10(hit1) == 4'd0) ? " " :
                                             (8'h30 + {4'd0, tens10(hit1)});
                        6'd6:  status_char = 8'h30 + {4'd0, ones10(hit1)};
                        6'd7:  status_char = "/";
                        6'd8:  status_char = (tens10(tot) == 4'd0) ? " " :
                                             (8'h30 + {4'd0, tens10(tot)});
                        6'd9:  status_char = 8'h30 + {4'd0, ones10(tot)};
                        6'd10: status_char = " ";
                        6'd11: status_char = "T";
                        6'd12: status_char = "E";
                        6'd13: status_char = "M";
                        6'd14: status_char = "P";
                        6'd15: status_char = "O";
                        6'd16: status_char = " ";
                        6'd17: status_char = (bpm >= 7'd100) ? "1" : " ";
                        6'd18: status_char = 8'h30 + {4'd0, tens10(bpm_t)};
                        6'd19: status_char = 8'h30 + {4'd0, ones10(bpm_t)};
                        default: status_char = " ";
                    endcase
                end
                // 失败：MISS! PRESS A KEY
                3'd6: status_char = msg_byte(MSG_FAIL, i);
                default: status_char = msg ? msg_byte(MSG_OFF, i) : " ";
            endcase
        end
    endfunction

    genvar gi;
    generate
        for (gi = 0; gi < NCHAR; gi = gi + 1) begin : g_line
            assign line[8*(NCHAR - 1 - gi) +: 8] =
                status_char(g_state, g_adv, g_song, g_expected, g_adv_next,
                            g_wrong_active, g_msg_show, g_step, g_hits, octave, gi);
        end
        for (gi = 0; gi < MCHAR; gi = gi + 1) begin : g_line23
            assign line2[8*(MCHAR - 1 - gi) +: 8] = menu_char(g_state, gi);
            assign line3[8*(MCHAR - 1 - gi) +: 8] = hint_char(g_state, gi);
        end
    endgenerate

endmodule

module guide_text (
    input  wire [5:0]   row,
    input  wire [7:0]   col,
    input  wire [2:0]   g_state,        // 0=OFF 1=MODE 2=SONG 3=B_RUN 4=B_DONE 5=A_RUN
    input  wire         g_song,
    input  wire [231:0] line,           // row 33 打包行
    input  wire [175:0] line2,          // row 32 打包行
    input  wire [175:0] line3,          // row 34 打包行
    output reg  [7:0]   ch,
    output reg          sel
);

    // col 60..88 -> 字符 0..28（row 33）
    wire [7:0] gi    = col - 8'd60;
    wire [7:0] gi_c  = (gi > 8'd28) ? 8'd28 : gi;
    wire [7:0] line_byte = line[8*(8'd28 - gi_c) +: 8];

    // col 60..81 -> 字符 0..21（row 32/34）
    wire [7:0] gi2   = col - 8'd60;
    wire [7:0] gi2_c = (gi2 > 8'd21) ? 8'd21 : gi2;
    wire [7:0] line2_byte = line2[8*(8'd21 - gi2_c) +: 8];
    wire [7:0] line3_byte = line3[8*(8'd21 - gi2_c) +: 8];

    always @(*) begin
        ch  = 8'h20;
        sel = 1'b0;

        case (row)
            // 选中歌曲的 ">" 标记（SONG / B_DONE）
            6'd30: if (col == 8'd60) begin
                sel = 1'b1;
                ch  = ((g_state == 3'd2 || g_state == 3'd4) && (g_song == 1'b0))
                      ? ">" : " ";
            end
            6'd31: if (col == 8'd60) begin
                sel = 1'b1;
                ch  = ((g_state == 3'd2 || g_state == 3'd4) && (g_song == 1'b1))
                      ? ">" : " ";
            end

            // row 32：菜单/提示（整行来自 50 MHz 域）
            6'd32: if (col >= 8'd60 && col <= 8'd81) begin
                sel = 1'b1;
                ch  = line2_byte;
            end

            // row 33：状态行（整行来自 50 MHz 域）
            6'd33: if (col >= 8'd60 && col <= 8'd88) begin
                sel = 1'b1;
                ch  = line_byte;
            end

            // row 34：长按退出 / DONE 重开（整行来自 50 MHz 域）
            6'd34: if (col >= 8'd60 && col <= 8'd81) begin
                sel = 1'b1;
                ch  = line3_byte;
            end

            default: ;
        endcase
    end
endmodule
