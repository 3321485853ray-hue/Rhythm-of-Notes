// ble_line.v — 蓝牙状态三行文字（50 MHz 域整行预生成）

module ble_line (
    input  wire [2:0]   state,        // cmd_exec 的会话状态
    input  wire [15:0]  ev_bcd,       // 事件数的 4 位十进制（由 bcd_fsm 慢慢算好）
    input  wire [15:0]  rec_bcd,      // 录音数的 4 位十进制
    output wire [127:0] line1,
    output wire [127:0] line2,
    output wire [127:0] line3
);

    localparam [7:0] SP = 8'h20;

    wire [15:0] ev4  = ev_bcd;
    wire [15:0] rec4 = rec_bcd;

    reg [39:0] sname;
    always @(*) begin
        case (state)
            3'd0:    sname = {8'h49, 8'h44, 8'h4C, 8'h45, SP};   // IDLE
            3'd1:    sname = {8'h4C, 8'h4F, 8'h41, 8'h44, SP};   // LOAD
            3'd2:    sname = {8'h52, 8'h45, 8'h41, 8'h44, 8'h59};// READY
            3'd3:    sname = {8'h50, 8'h4C, 8'h41, 8'h59, SP};   // PLAY
            3'd4:    sname = {8'h45, 8'h52, 8'h52, 8'h4F, 8'h52};// ERROR
            3'd5:    sname = {8'h52, 8'h45, 8'h43, SP,   SP};    // REC
            default: sname = {8'h3F, 8'h3F, 8'h3F, 8'h3F, 8'h3F};// ?????
        endcase
    end

    assign line1 = {8'h42, 8'h4C, 8'h45, SP, sname,
                    SP, SP, SP, SP, SP, SP, SP};

    //  "EVT " + 4 位数字 + 8 空格
    assign line2 = {8'h45, 8'h56, 8'h54, SP,
                    8'd48 + {4'd0, ev4[15:12]},
                    8'd48 + {4'd0, ev4[11:8]},
                    8'd48 + {4'd0, ev4[7:4]},
                    8'd48 + {4'd0, ev4[3:0]},
                    SP, SP, SP, SP, SP, SP, SP, SP};

    //  "REC " + 4 位数字 + 8 空格
    assign line3 = {8'h52, 8'h45, 8'h43, SP,
                    8'd48 + {4'd0, rec4[15:12]},
                    8'd48 + {4'd0, rec4[11:8]},
                    8'd48 + {4'd0, rec4[7:4]},
                    8'd48 + {4'd0, rec4[3:0]},
                    SP, SP, SP, SP, SP, SP, SP, SP};

endmodule
