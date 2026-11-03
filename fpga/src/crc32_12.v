// crc32_12.v — CRC-32/ISO-HDLC 组合计算器：吃 12 字节（一次性整表）

module crc32_12 (
    input  wire [95:0] data,
    output reg  [31:0] crc
);

    integer i, b;
    reg [31:0] c;
    reg [7:0]  db;

    always @(*) begin
        c = 32'hFFFFFFFF;
        for (i = 11; i >= 0; i = i - 1) begin
            db = data[8*i +: 8];
            c  = c ^ {24'd0, db};
            for (b = 0; b < 8; b = b + 1)
                c = c[0] ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
        end
        crc = c ^ 32'hFFFFFFFF;
    end

endmodule
