// display_keysnap.v — 快速键状态快照（音频域，只读）

module display_keysnap (
    input  wire        clk,           // 50 MHz
    input  wire [11:0] key_level,
    output reg  [11:0] key_snap,
    output reg         key_tgl
);

    reg [15:0] cnt = 16'd0;
    wire tick = (cnt == 16'd49999);   // 1 ms @ 50 MHz
    always @(posedge clk) cnt <= tick ? 16'd0 : (cnt + 1'b1);

    always @(posedge clk) begin
        if (tick) begin
            key_snap <= key_level;
            key_tgl  <= ~key_tgl;
        end
    end

endmodule
