// song_player.v — 曲谱播放器（tick 计时 / 事件消费 / note_on-off 调度 / 循环）

module song_player (
    input  wire        clk,
    input  wire        start,        // 单拍：从事件 0 开始
    input  wire        stop,         // 单拍：停止，全部闭音
    input  wire [15:0] total,        // 事件总数
    input  wire [15:0] tick_ms,      // 1..10
    input  wire [7:0]  loop_cnt,     // 0=一次，1..254=重复次数，255=无限
    output wire [12:0] raddr,
    input  wire [63:0] rdata,

    // 给 score_alloc
    output reg         on_pulse,
    output reg  [6:0]  on_note,
    output reg         off_pulse,
    output reg  [6:0]  off_note,
    output reg         panic,
    output wire        busy,         // 正在播
    output reg         done          // 单拍：曲终
);

    localparam [2:0] S_IDLE  = 3'd0,
                     S_FETCH = 3'd1,
                     S_LOAD  = 3'd2,
                     S_RUN   = 3'd3,
                     S_END   = 3'd4;

    reg [2:0]  st       = S_IDLE;
    reg        running  = 1'b0;
    reg [15:0] idx      = 16'd0;
    reg [31:0] Tn       = 32'd0;       // 当前（预取）事件的绝对 tick
    reg [31:0] song_tick= 32'd0;
    reg [63:0] pe       = 64'd0;       // 预取事件
    reg        end_pend = 1'b0;        // 事件已发完，等音符自然收尾
    reg [7:0]  loop_left= 8'd0;

    assign busy  = running;
    assign raddr = idx[12:0];

    wire [15:0] tick_sel = (tick_ms == 16'd0) ? 16'd1 : tick_ms;
    wire [31:0] tick_cyc = tick_sel * 16'd50000;
    reg  [31:0] div      = 32'd0;
    wire        tick_now = (div + 32'd1 >= tick_cyc);

    reg        ov0 = 1'b0, ov1 = 1'b0, ov2 = 1'b0, ov3 = 1'b0;
    reg [6:0]  on0 = 7'd0, on1 = 7'd0, on2 = 7'd0, on3 = 7'd0;
    reg [31:0] oa0 = 32'd0, oa1 = 32'd0, oa2 = 32'd0, oa3 = 32'd0;

    wire [7:0]  e_note = pe[23:16];
    wire [15:0] e_dur  = pe[47:32];
    // MIDI(0..127) → note_freq 表索引(0..83 = MIDI 24..107)
    wire [6:0]  e_idx  = (e_note <  8'd24) ? 7'd0  :
                         (e_note >  8'd107)? 7'd83 :
                         (e_note - 8'd24);

    always @(posedge clk) begin
        on_pulse  <= 1'b0;
        off_pulse <= 1'b0;
        panic     <= 1'b0;
        done      <= 1'b0;

        if (stop) begin
            running  <= 1'b0;
            st       <= S_IDLE;
            end_pend <= 1'b0;
            panic    <= 1'b1;
            ov0 <= 1'b0; ov1 <= 1'b0; ov2 <= 1'b0; ov3 <= 1'b0;
        end else if (start) begin
            running   <= 1'b1;
            st        <= S_FETCH;
            idx       <= 16'd0;
            Tn        <= 32'd0;
            song_tick <= 32'd0;
            div       <= 32'd0;
            end_pend  <= 1'b0;
            loop_left <= loop_cnt;
            ov0 <= 1'b0; ov1 <= 1'b0; ov2 <= 1'b0; ov3 <= 1'b0;

            panic <= 1'b1;
        end else if (running) begin

            if (tick_now) begin
                div       <= 32'd0;
                song_tick <= song_tick + 32'd1;
            end else
                div <= div + 32'd1;

            if      (ov0 && (song_tick >= oa0)) begin off_pulse <= 1'b1; off_note <= on0; ov0 <= 1'b0; end
            else if (ov1 && (song_tick >= oa1)) begin off_pulse <= 1'b1; off_note <= on1; ov1 <= 1'b0; end
            else if (ov2 && (song_tick >= oa2)) begin off_pulse <= 1'b1; off_note <= on2; ov2 <= 1'b0; end
            else if (ov3 && (song_tick >= oa3)) begin off_pulse <= 1'b1; off_note <= on3; ov3 <= 1'b0; end

            case (st)

                S_FETCH: begin
                    if (idx >= total) st <= S_END;
                    else              st <= S_LOAD;
                end

                S_LOAD: begin
                    pe <= rdata;
                    Tn <= Tn + {16'd0, rdata[15:0]};
                    st <= S_RUN;
                end

                S_RUN: begin
                    if (song_tick >= Tn) begin
                        // 起音（0xFF = NOOP，只消耗时间）
                        if (e_note != 8'hFF) begin
                            on_pulse <= 1'b1;
                            on_note  <= e_idx;

                            if      (ov0 && (on0 == e_idx)) begin oa0 <= song_tick + {16'd0, e_dur}; ov0 <= 1'b1; end
                            else if (ov1 && (on1 == e_idx)) begin oa1 <= song_tick + {16'd0, e_dur}; ov1 <= 1'b1; end
                            else if (ov2 && (on2 == e_idx)) begin oa2 <= song_tick + {16'd0, e_dur}; ov2 <= 1'b1; end
                            else if (ov3 && (on3 == e_idx)) begin oa3 <= song_tick + {16'd0, e_dur}; ov3 <= 1'b1; end
                            else if (!ov0) begin ov0 <= 1'b1; on0 <= e_idx; oa0 <= song_tick + {16'd0, e_dur}; end
                            else if (!ov1) begin ov1 <= 1'b1; on1 <= e_idx; oa1 <= song_tick + {16'd0, e_dur}; end
                            else if (!ov2) begin ov2 <= 1'b1; on2 <= e_idx; oa2 <= song_tick + {16'd0, e_dur}; end
                            else if (!ov3) begin ov3 <= 1'b1; on3 <= e_idx; oa3 <= song_tick + {16'd0, e_dur}; end
                            else begin ov0 <= 1'b1; on0 <= e_idx; oa0 <= song_tick + {16'd0, e_dur}; end
                        end
                        // 取完最后一个事件 ⇒ 进收尾；否则取下一个
                        if (idx + 16'd1 >= total) begin
                            end_pend <= 1'b1;
                            st       <= S_END;
                        end else begin
                            idx <= idx + 16'd1;
                            st  <= S_FETCH;
                        end
                    end
                end

                S_END: begin
                    if (!ov0 && !ov1 && !ov2 && !ov3) begin
                        if (loop_left == 8'd0) begin
                            running <= 1'b0;
                            st      <= S_IDLE;
                            done    <= 1'b1;

                            panic   <= 1'b1;
                        end else begin
                            if (loop_left != 8'd255)
                                loop_left <= loop_left - 8'd1;
                            idx       <= 16'd0;
                            Tn        <= 32'd0;
                            song_tick <= 32'd0;
                            end_pend  <= 1'b0;
                            st        <= S_FETCH;
                        end
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
