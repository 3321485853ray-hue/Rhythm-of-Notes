// spec_bank_ram.v — 频谱柱数据跨时钟域双 bank（256 × 8）

module spec_bank_ram (
    input  wire        wclk,
    input  wire        we,
    input  wire [7:0]  waddr,
    input  wire [7:0]  wdata,
    input  wire        rclk,
    input  wire [7:0]  raddr,
    output reg  [7:0]  rdata = 8'd0
);

    reg [7:0] mem [0:255];

    always @(posedge wclk) begin
        if (we)
            mem[waddr] <= wdata;
    end

    always @(posedge rclk) begin
        rdata <= mem[raddr];
    end

endmodule
