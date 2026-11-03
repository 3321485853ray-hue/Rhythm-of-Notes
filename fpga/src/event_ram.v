// event_ram.v — 曲谱事件 RAM（8192 × 64 bit，专用读写口）

module event_ram (
    input  wire        clk,

    // 写口（cmd_exec 下载 / recorder 录制，二选一，由外部 mux）
    input  wire        we,
    input  wire [12:0] waddr,
    input  wire [63:0] wdata,

    // 读口（song_player 播放 / rec_stream 回传，由外部 mux）
    input  wire [12:0] raddr,
    output reg  [63:0] rdata
);

    reg [63:0] mem [0:8191];

    always @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end

endmodule
