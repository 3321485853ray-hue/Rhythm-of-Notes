// strobe1024.v — 本地 48.83 kHz 采样节拍（每 1024 拍一个高电平）

module strobe1024 (
    input  wire clk,
    output wire strobe
);

    reg [9:0] cnt = 10'd0;

    always @(posedge clk)
        cnt <= cnt + 10'd1;

    assign strobe = (cnt == 10'd512);

endmodule
