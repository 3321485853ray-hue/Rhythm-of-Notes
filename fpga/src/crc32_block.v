// crc32_block.v — CRC-32/ISO-HDLC（zlib 同款）组合计算器：吃 8 字节

module crc32_block (
    input  wire [31:0] crc_in,   // 未取反的内部值（首条事件前 = 0xFFFFFFFF）
    input  wire [63:0] data,     // 8 字节，data[63:56] 最先
    output reg  [31:0] crc_out
);

    integer i, b;
    reg [31:0] c;
    reg [7:0]  db;

    always @(*) begin
        c = crc_in;
        for (i = 7; i >= 0; i = i - 1) begin
            db = data[8*i +: 8];
            c  = c ^ {24'd0, db};
            for (b = 0; b < 8; b = b + 1)
                c = c[0] ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
        end
        crc_out = c;
    end

endmodule
