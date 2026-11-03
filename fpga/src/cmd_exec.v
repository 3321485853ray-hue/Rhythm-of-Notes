// cmd_exec.v — 命令执行 + 会话状态机（M3 完整版）

module cmd_exec (
    input  wire         clk,

    // 来自 frame_parser
    input  wire         frame_valid,
    input  wire [127:0] frame,
    input  wire         err_crc,

    // 帧发送（frame_tx）
    output reg          tx_req,
    output reg  [7:0]   tx_cmd,
    output reg  [7:0]   tx_len,
    output reg  [63:0]  tx_pay,
    output reg  [7:0]   tx_echo,
    input  wire         tx_ready,

    // 事件 RAM 写口（曲谱下载）
    output reg          er_we,
    output reg  [12:0]  er_waddr,
    output reg  [63:0]  er_wdata,

    // 事件 RAM 读口（录音回传）
    output wire [12:0]  rec_raddr,
    input  wire [63:0]  rec_rdata,

    // 播放器控制
    output reg          pl_start,
    output reg          pl_stop,
    output reg  [15:0]  pl_total,
    output reg  [15:0]  pl_tick,
    output reg  [7:0]   pl_loop,
    input  wire         pl_busy,
    input  wire         pl_done,

    // 键位表（影子表写 + 提交）
    output reg          km_we,
    output reg  [3:0]   km_waddr,
    output reg  [7:0]   km_wdata,
    output reg          km_commit,
    input  wire [95:0]  km_codes,      // 影子表整表码值（给 CRC32 用）

    // 录音器控制
    output reg          rec_on,
    output reg          rec_clr,
    output reg  [31:0]  rec_tick_cyc,
    input  wire [15:0]  rec_count,
    input  wire         rec_full,

    // 对外状态
    output reg  [15:0]  ev_count,
    output wire [2:0]   state_o
);

    localparam [2:0] S_IDLE  = 3'd0,
                     S_LOAD  = 3'd1,
                     S_READY = 3'd2,
                     S_PLAY  = 3'd3,
                     S_ERR   = 3'd4,
                     S_REC   = 3'd5;

    localparam [15:0] CAPACITY = 16'd8192;

    reg [2:0]  state   = S_IDLE;
    reg [15:0] err_cnt = 16'd0;
    reg        err_rpt = 1'b0;

    reg [31:0] crc_r = 32'hFFFFFFFF;   // 曲谱流 CRC32
    reg [15:0] beg_tick = 16'd1;       // BEGIN 下发的 tick_ms

    // 键位表写入的微状态机（一帧最多 6 项，写口一拍一项）
    reg [47:0] km_buf   = 48'd0;       // 待写码值（第 0 项在最高字节）
    reg [2:0]  km_left  = 3'd0;
    reg [3:0]  km_woff  = 4'd0;

    // 二级回包
    reg        st2_pend = 1'b0;
    reg [7:0]  st2_code = 8'd0;
    reg [15:0] st2_arg  = 16'd0;
    reg [7:0]  st2_seq  = 8'd0;

    assign state_o = state;

    wire [7:0]  f_ver = frame[111:104];
    wire [7:0]  f_cmd = frame[103:96];
    wire [7:0]  f_seq = frame[95:88];
    wire [7:0]  f_len = frame[87:80];

    wire [7:0]  p0 = frame[79:72];
    wire [7:0]  p1 = frame[71:64];
    wire [7:0]  p2 = frame[63:56];
    wire [7:0]  p3 = frame[55:48];
    wire [7:0]  p4 = frame[47:40];
    wire [7:0]  p5 = frame[39:32];
    wire [7:0]  p6 = frame[31:24];
    wire [7:0]  p7 = frame[23:16];

    wire [15:0] pay_u16_0 = {p1, p0};           // 小端
    wire [31:0] pay_u32_0 = {p3, p2, p1, p0};   // 小端（KEYMAP_DONE 的整表 CRC 在字节 0..3）
    wire [31:0] pay_u32_2 = {p5, p4, p3, p2};   // 小端
    wire [15:0] pay_u16_6 = {p7, p6};

    // 存进 RAM 的 64 位字按小端整字摆（见 event_ram.v）
    wire [63:0] pay_le = {p7, p6, p5, p4, p3, p2, p1, p0};

    wire [31:0] crc_n;
    crc32_block u_crc32 (
        .crc_in  (crc_r),
        .data    (frame[79:16]),
        .crc_out (crc_n)
    );

    wire [31:0] km_crc;
    crc32_12 u_kmcrc (
        .data (km_codes),
        .crc  (km_crc)
    );

    reg        st_valid = 1'b0;
    reg [7:0]  st_code  = 8'd0;
    reg [15:0] st_arg   = 16'd0;
    reg [7:0]  st_seq   = 8'd0;

    reg        streaming = 1'b0;
    reg [15:0] st_cur    = 16'd0;
    reg [15:0] st_end    = 16'd0;
    reg        st_rdpend = 1'b0;
    reg        rec_frame = 1'b0;
    reg [63:0] rec_pay_r = 64'd0;      // 取到的事件（寄存一拍再送 frame_tx）

    wire [63:0] rec_pay_wire = {rec_pay_r[7:0],   rec_pay_r[15:8],  rec_pay_r[23:16], rec_pay_r[31:24],
                                rec_pay_r[39:32], rec_pay_r[47:40], rec_pay_r[55:48], rec_pay_r[63:56]};

    assign rec_raddr = st_cur[12:0];

    always @(posedge clk) begin
        st_valid <= 1'b0;
        er_we    <= 1'b0;
        pl_start <= 1'b0;
        pl_stop  <= 1'b0;
        km_we    <= 1'b0;
        km_commit<= 1'b0;
        rec_clr  <= 1'b0;
        rec_frame<= 1'b0;

        if (km_left != 3'd0) begin
            km_we    <= 1'b1;
            km_waddr <= km_woff;
            km_wdata <= km_buf[47:40];
            km_buf   <= {km_buf[39:0], 8'h00};
            km_woff  <= km_woff + 4'd1;
            km_left  <= km_left - 3'd1;
        end

        if (st2_pend) begin
            st_valid <= 1'b1;
            st_code  <= st2_code;
            st_arg   <= st2_arg;
            st_seq   <= st2_seq;
            st2_pend <= 1'b0;
        end

        if (err_crc) begin
            err_cnt <= err_cnt + 16'd1;
            if (!err_rpt) begin
                st_valid <= 1'b1;
                st_code  <= 8'h01;
                st_arg   <= err_cnt + 16'd1;
                st_seq   <= 8'd0;
                err_rpt  <= 1'b1;
            end
        end

        if (pl_done && (state == S_PLAY)) begin
            state    <= S_READY;
            ev_count <= 16'd0;
            st_valid <= 1'b1;
            st_code  <= 8'h11;
            st_arg   <= 16'd0;
            st_seq   <= 8'd0;
        end

        if (streaming) begin
            if (!st_rdpend) begin
                if (tx_ready) st_rdpend <= 1'b1;      // 地址已在线上，等一拍取数
            end else begin
                if (tx_ready) begin
                    rec_frame <= 1'b1;
                    rec_pay_r <= rec_rdata;
                    st_rdpend <= 1'b0;
                    if (st_cur + 16'd1 >= st_end) begin
                        streaming <= 1'b0;

                        st2_pend <= 1'b1;
                        st2_code <= 8'h14;
                        st2_arg  <= st_end;
                        st2_seq  <= 8'd0;
                    end else
                        st_cur <= st_cur + 16'd1;
                end
            end
        end

        if (frame_valid) begin
            st_valid <= 1'b1;
            st_seq   <= f_seq;
            st_arg   <= 16'd0;

            if (f_ver != 8'h01) begin
                st_code <= 8'h02;
                st_arg  <= {8'd0, f_len};
            end else begin
                case (f_cmd)

                    8'h01: begin
                        if (f_len == 8'd0) st_code <= 8'h00;
                        else begin st_code <= 8'h02; st_arg <= {8'd0, f_len}; end
                    end

                    8'h02: begin
                        if (f_len != 8'd8) begin
                            st_code <= 8'h02; st_arg <= {8'd0, f_len};
                        end else if (pay_u16_0 > CAPACITY) begin
                            st_code <= 8'h05; st_arg <= CAPACITY;
                        end else if ((pay_u16_6 < 16'd1) || (pay_u16_6 > 16'd10)) begin
                            st_code <= 8'h02; st_arg <= pay_u16_6;
                        end else begin
                            pl_stop   <= 1'b1;
                            crc_r     <= 32'hFFFFFFFF;
                            ev_count  <= 16'd0;
                            err_rpt   <= 1'b0;
                            beg_tick  <= pay_u16_6;
                            state     <= S_LOAD;
                            st_code   <= 8'h00;
                        end
                    end

                    8'h10: begin
                        if (f_len != 8'd8) begin
                            st_code <= 8'h02; st_arg <= {8'd0, f_len};
                        end else if (state != S_LOAD) begin
                            st_code <= 8'h04; st_arg <= {13'd0, state};
                        end else if (ev_count >= CAPACITY) begin
                            st_code <= 8'h05; st_arg <= CAPACITY;
                        end else begin
                            er_we    <= 1'b1;
                            er_waddr <= ev_count[12:0];
                            er_wdata <= pay_le;
                            crc_r    <= crc_n;
                            ev_count <= ev_count + 16'd1;
                            st_valid <= 1'b0;              // LOADING 下 EVENT 不回包
                        end
                    end

                    8'h03: begin
                        if (f_len != 8'd6) begin
                            st_code <= 8'h02; st_arg <= {8'd0, f_len};
                        end else if (state != S_LOAD) begin
                            st_code <= 8'h04; st_arg <= {13'd0, state};
                        end else if (pay_u16_0 != ev_count) begin
                            st_code <= 8'h07; st_arg <= ev_count; state <= S_ERR;
                        end else if (pay_u32_2 != (crc_r ^ 32'hFFFFFFFF)) begin
                            st_code <= 8'h06; st_arg <= ev_count; state <= S_ERR;
                        end else begin
                            state   <= S_READY;
                            st_code <= 8'h00;
                            st_arg  <= ev_count;
                        end
                    end

                    8'h04: begin
                        if (f_len != 8'd1) begin
                            st_code <= 8'h02; st_arg <= {8'd0, f_len};
                        end else if (state != S_READY) begin
                            st_code <= 8'h04; st_arg <= {13'd0, state};
                        end else begin
                            pl_total <= ev_count;
                            pl_tick  <= beg_tick;          // BEGIN 下发的 tick_ms
                            pl_loop  <= p0;
                            pl_start <= 1'b1;
                            state    <= S_PLAY;
                            st_code  <= 8'h00;
                            st2_pend <= 1'b1;
                            st2_code <= 8'h10;
                            st2_arg  <= ev_count;
                            st2_seq  <= f_seq;
                        end
                    end

                    8'h05: begin
                        if (f_len != 8'd0) begin
                            st_code <= 8'h02; st_arg <= {8'd0, f_len};
                        end else begin
                            pl_stop  <= 1'b1;
                            state    <= (ev_count != 16'd0) ? S_READY : S_IDLE;
                            st_code  <= 8'h00;
                            st2_pend <= 1'b1;
                            st2_code <= 8'h12;
                            st2_arg  <= ev_count;
                            st2_seq  <= f_seq;
                        end
                    end

                    8'h0A: begin
                        if (f_len == 8'd0) begin
                            st_code <= (state == S_REC) ? 8'h25 : (8'h20 + {5'd0, state});
                            st_arg  <= ev_count;
                        end else begin
                            st_code <= 8'h02; st_arg <= {8'd0, f_len};
                        end
                    end

                    8'h20: begin
                        if ((f_len != 8'd8) || (p1 == 8'd0) || (p1 > 8'd6)) begin
                            st_code <= 8'h02; st_arg <= {8'd0, f_len};
                        end else if (state == S_PLAY) begin
                            st_code <= 8'h04; st_arg <= {13'd0, state};
                        end else begin
                            // 把这一帧的 6 个码值排进缓冲区，后面由微循环逐拍写入
                            km_buf   <= {p2, p3, p4, p5, p6, p7};
                            km_left  <= {1'b0, p1[2:0]};
                            km_woff  <= p0[3:0];
                            st_code  <= 8'h00;
                        end
                    end

                    8'h21: begin
                        if (f_len != 8'd4) begin
                            st_code <= 8'h02; st_arg <= {8'd0, f_len};
                        end else if (pay_u32_0 == km_crc) begin
                            km_commit <= 1'b1;
                            st_code   <= 8'h00;
                        end else begin
                            st_code <= 8'h06;                  // ERR_STREAM_CRC（旧表不变）
                            st_arg  <= 16'd0;
                        end
                    end

                    8'h40: begin
                        if (f_len != 8'd2) begin
                            st_code <= 8'h02; st_arg <= {8'd0, f_len};
                        end else if ((pay_u16_0 < 16'd1) || (pay_u16_0 > 16'd10)) begin
                            st_code <= 8'h02; st_arg <= pay_u16_0;
                        end else begin
                            pl_stop     <= 1'b1;
                            rec_clr     <= 1'b1;
                            rec_tick_cyc<= pay_u16_0 * 16'd50000;
                            state       <= S_REC;
                            st_code     <= 8'h00;
                        end
                    end

                    8'h41: begin
                        if (f_len != 8'd0) begin
                            st_code <= 8'h02; st_arg <= {8'd0, f_len};
                        end else begin
                            // 录完回 IDLE：录到的内容用 REC_READ 取走，
                            // 想再放一遍就让手机把这份事件流重新下发给 BEGIN（同一套格式）
                            state   <= S_IDLE;
                            st_code <= 8'h00;
                            st_arg  <= rec_count;
                        end
                    end

                    8'h42: begin
                        if (f_len != 8'd4) begin
                            st_code <= 8'h02; st_arg <= {8'd0, f_len};
                        end else if (state == S_REC) begin
                            st_code <= 8'h04; st_arg <= {13'd0, state};
                        end else if (streaming) begin
                            st_code <= 8'h04; st_arg <= {13'd0, state};
                        end else if ({p3, p2} == 16'd0) begin
                            st_code <= 8'h02; st_arg <= 16'd0;
                        end else begin
                            st_cur    <= pay_u16_0;
                            st_end    <= pay_u16_0 + {p3, p2};
                            st_rdpend <= 1'b0;
                            streaming <= 1'b1;
                            st_code   <= 8'h13;            // EVT_REC_START
                            st_arg    <= {p3, p2};
                        end
                    end

                    8'h30: begin
                        st_code <= 8'h03; st_arg <= {8'd0, f_cmd};
                    end

                    default: begin
                        st_code <= 8'h03;
                        st_arg  <= {8'd0, f_cmd};
                    end
                endcase
            end
        end
    end

    always @(posedge clk) begin
        tx_req  <= 1'b0;
        tx_echo <= 8'h00;
        if (rec_frame) begin
            tx_req <= 1'b1;
            tx_cmd <= 8'h81;                 // RECDATA
            tx_len <= 8'd8;
            tx_pay <= rec_pay_wire;
        end else if (st_valid) begin
            tx_req <= 1'b1;
            tx_cmd <= 8'h80;                 // STATUS
            tx_len <= 8'd4;
            tx_pay <= {st_code, st_arg[7:0], st_arg[15:8], st_seq, 32'd0};
            tx_echo<= 8'h00;
        end
    end

    // 录音使能 = 处于 REC 状态
    always @(posedge clk)
        rec_on <= (state == S_REC);

endmodule
