// display_stat.v —— 参数文字层的慢速快照（音频 50 MHz 域）

module display_stat (
    input  wire        clk,          // 系统 50 MHz（音频域）
    input  wire [2:0]  timbre,
    input  wire [2:0]  octave,
    input  wire [15:0] volume,       // Q15 0..32767
    input  wire [1:0]  expr_sel,
    input  wire [1:0]  expr_amt,
    input  wire [2:0]  fx_on,        // {cho,rev,dly}
    input  wire [1:0]  dly_p,
    input  wire [1:0]  rev_p,
    input  wire [1:0]  cho_p,
    input  wire [11:0] key_level,
    input  wire [7:0]  v_gate,
    input  wire        g_mode,
    input  wire [2:0]  g_state,
    input  wire        g_song,
    input  wire        g_adv,
    input  wire [3:0]  g_expected,
    input  wire        g_wrong_active,
    input  wire [3:0]  g_wrong_key,
    input  wire        g_msg_show,
    input  wire [5:0]  g_step,
    input  wire [3:0]  g_adv_next,
    input  wire [275:0] g_tiles,
    input  wire [5:0]  g_hits,
    input  wire [2:0]  ble_state,
    input  wire [15:0] ble_ev,
    input  wire [15:0] ble_rec,
    output reg  [2:0]  st_timbre,
    output reg  [2:0]  st_octave,
    output reg  [6:0]  st_vol_pct,
    output reg  [1:0]  st_expr_sel,
    output reg  [1:0]  st_expr_amt,
    output reg  [2:0]  st_fx_on,
    output reg  [1:0]  st_dly_p,
    output reg  [1:0]  st_rev_p,
    output reg  [1:0]  st_cho_p,
    output reg  [3:0]  st_key_cnt,
    output reg  [3:0]  st_voice_cnt,
    output reg         st_g_mode,
    output reg  [2:0]  st_g_state,
    output reg         st_g_song,
    output reg         st_g_adv,
    output reg  [3:0]  st_g_expected,
    output reg         st_g_wrong_active,
    output reg  [3:0]  st_g_wrong_key,
    output reg         st_g_msg_show,
    output reg  [5:0]  st_g_step,
    output reg  [3:0]  st_g_adv_next,
    output reg  [275:0] st_g_tiles,
    output reg  [5:0]  st_g_hits,
    output reg  [2:0]  st_ble_state,
    output reg  [15:0] st_ble_ev,
    output reg  [15:0] st_ble_rec,
    output reg         st_tgl
);

    // 21 ms：2^20 / 50 MHz = 20.97 ms。计数器自由运行，无复位。
    reg [19:0] cnt = 20'd0;

    wire [3:0] key_cnt =
        {3'd0, key_level[0]}  + {3'd0, key_level[1]}  +
        {3'd0, key_level[2]}  + {3'd0, key_level[3]}  +
        {3'd0, key_level[4]}  + {3'd0, key_level[5]}  +
        {3'd0, key_level[6]}  + {3'd0, key_level[7]}  +
        {3'd0, key_level[8]}  + {3'd0, key_level[9]}  +
        {3'd0, key_level[10]} + {3'd0, key_level[11]};

    wire [3:0] voice_cnt =
        {3'd0, v_gate[0]} + {3'd0, v_gate[1]} +
        {3'd0, v_gate[2]} + {3'd0, v_gate[3]} +
        {3'd0, v_gate[4]} + {3'd0, v_gate[5]} +
        {3'd0, v_gate[6]} + {3'd0, v_gate[7]};

    wire [13:0] vol_mul = volume[15:8] * 8'd100;
    // 上电/满幅 volume=32767 时显示 100%（audio 本来就是满幅；旧公式
    // 因只取高 8 位会截成 99%）。
    wire [6:0]  vol_pct = (volume[15:8] == 8'd127) ? 7'd100 : vol_mul[13:7];

    always @(posedge clk)
        cnt <= cnt + 20'd1;

    always @(posedge clk) begin
        if (cnt == 20'd0) begin
            st_tgl       <= ~st_tgl;
            st_timbre    <= timbre;
            st_octave    <= octave;
            st_vol_pct   <= vol_pct;
            st_expr_sel  <= expr_sel;
            st_expr_amt  <= expr_amt;
            st_fx_on     <= fx_on;
            st_dly_p     <= dly_p;
            st_rev_p     <= rev_p;
            st_cho_p     <= cho_p;
            st_key_cnt   <= key_cnt;
            st_voice_cnt <= voice_cnt;
            st_g_mode         <= g_mode;
            st_g_state        <= g_state;
            st_g_song         <= g_song;
            st_g_adv          <= g_adv;
            st_g_expected     <= g_expected;
            st_g_wrong_active <= g_wrong_active;
            st_g_wrong_key    <= g_wrong_key;
            st_g_msg_show     <= g_msg_show;
            st_g_step         <= g_step;
            st_g_adv_next     <= g_adv_next;
            st_g_tiles        <= g_tiles;
            st_g_hits         <= g_hits;
            st_ble_state      <= ble_state;
            st_ble_ev         <= ble_ev;
            st_ble_rec        <= ble_rec;
        end
    end

endmodule
