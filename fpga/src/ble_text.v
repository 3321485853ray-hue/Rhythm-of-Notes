// ble_text.v — 蓝牙状态三行的像素域查表（只做 (row,col) → 字符）

module ble_text (
    input  wire [5:0]   row,
    input  wire [7:0]   col,
    input  wire [127:0] line1,
    input  wire [127:0] line2,
    input  wire [127:0] line3,
    output reg  [7:0]   ch,
    output reg          sel
);

    always @(*) begin
        ch  = 8'h20;
        sel = 1'b0;
        if ((col >= 8'd2) && (col < 8'd18)) begin
            sel = 1'b1;
            case (row)
                6'd19: case (col)
                    8'd2: ch = line1[127:120];
                    8'd3: ch = line1[119:112];
                    8'd4: ch = line1[111:104];
                    8'd5: ch = line1[103:96];
                    8'd6: ch = line1[95:88];
                    8'd7: ch = line1[87:80];
                    8'd8: ch = line1[79:72];
                    8'd9: ch = line1[71:64];
                    8'd10: ch = line1[63:56];
                    8'd11: ch = line1[55:48];
                    8'd12: ch = line1[47:40];
                    8'd13: ch = line1[39:32];
                    8'd14: ch = line1[31:24];
                    8'd15: ch = line1[23:16];
                    8'd16: ch = line1[15:8];
                    8'd17: ch = line1[7:0];
                    default: ch = 8'h20;
                endcase
                6'd20: case (col)
                    8'd2: ch = line2[127:120];
                    8'd3: ch = line2[119:112];
                    8'd4: ch = line2[111:104];
                    8'd5: ch = line2[103:96];
                    8'd6: ch = line2[95:88];
                    8'd7: ch = line2[87:80];
                    8'd8: ch = line2[79:72];
                    8'd9: ch = line2[71:64];
                    8'd10: ch = line2[63:56];
                    8'd11: ch = line2[55:48];
                    8'd12: ch = line2[47:40];
                    8'd13: ch = line2[39:32];
                    8'd14: ch = line2[31:24];
                    8'd15: ch = line2[23:16];
                    8'd16: ch = line2[15:8];
                    8'd17: ch = line2[7:0];
                    default: ch = 8'h20;
                endcase
                6'd21: case (col)
                    8'd2: ch = line3[127:120];
                    8'd3: ch = line3[119:112];
                    8'd4: ch = line3[111:104];
                    8'd5: ch = line3[103:96];
                    8'd6: ch = line3[95:88];
                    8'd7: ch = line3[87:80];
                    8'd8: ch = line3[79:72];
                    8'd9: ch = line3[71:64];
                    8'd10: ch = line3[63:56];
                    8'd11: ch = line3[55:48];
                    8'd12: ch = line3[47:40];
                    8'd13: ch = line3[39:32];
                    8'd14: ch = line3[31:24];
                    8'd15: ch = line3[23:16];
                    8'd16: ch = line3[15:8];
                    8'd17: ch = line3[7:0];
                    default: ch = 8'h20;
                endcase
                default: sel = 1'b0;
            endcase
        end
    end

endmodule
