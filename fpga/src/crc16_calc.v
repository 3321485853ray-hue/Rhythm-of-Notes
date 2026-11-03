// crc16_calc.v — CRC-16/CCITT-FALSE 组合计算器（定长 12 字节）

module crc16_calc (
    input  wire [95:0] data,   // 12 字节，data[95:88] = 第一个字节
    output reg  [15:0] crc
);

    integer   i, b;
    reg [15:0] c;
    reg [7:0]  db;

    always @(*) begin
        c = 16'hFFFF;
        for (i = 11; i >= 0; i = i - 1) begin     // 从 data[95:88] 开始往后走
            db = data[8*i +: 8];
            c  = c ^ {db, 8'h00};
            for (b = 0; b < 8; b = b + 1)
                c = c[15] ? ((c << 1) ^ 16'h1021) : (c << 1);
        end
        crc = c;
    end

endmodule
