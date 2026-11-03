// display_d1.v — D1：HDMI 1080p 彩条（主工程内的显示通路验证）

module display_d1 (
    input  wire        clk,
    output wire        tmds_clk_p_0,
    output wire        tmds_clk_n_0,
    output wire [2:0]  tmds_d_p_0,
    output wire [2:0]  tmds_d_n_0
);

    wire pclk;      // 150 MHz
    wire bclk;      // 750 MHz DDR bit clock (1.5 Gbps/lane)

    Gowin_PLL u_pll (
        .lock    (),
        .clkout0 (pclk),
        .clkout1 (bclk),
        .clkin   (clk)
    );

    wire [23:0] pixel_data;
    wire        den, hs, vs;

    test_pattern_gen u_pattern (
        .pixel_clock      (pclk),
        .reset            (1'b0),
        .video_vsync      (vs),
        .video_hsync      (hs),
        .video_den        (den),
        .video_line_start (),
        .video_pixel_even (pixel_data),
        .video_pixel_odd  ()
    );

    wire [5:0] ctrl;
    assign ctrl[0]   = hs;
    assign ctrl[1]   = vs;
    assign ctrl[5:2] = 4'b0000;

    wire [29:0] tmds_enc;
    wire [1:0]  data_out_to_pins [2:0];

    genvar i;
    generate
        for (i = 0; i < 3; i = i + 1) begin : gen_tmds
            dvi_tx_tmds_enc u_enc (
                .clock  (pclk),
                .reset  (1'b0),
                .den    (den),
                .data   (pixel_data[(8*i) +: 8]),
                .ctrl   (ctrl[(2*i) +: 2]),
                .tmds   (tmds_enc[(10*i) +: 10])
            );

            dvi_tx_tmds_phy u_phy (
                .pixel_clock   (pclk),
                .ddr_bit_clock (bclk),
                .reset         (1'b0),
                .data          (tmds_enc[(10*i) +: 10]),
                .tmds_lane     (data_out_to_pins[i])
            );
        end
    endgenerate

    assign tmds_d_p_0[0] = data_out_to_pins[0][1];
    assign tmds_d_n_0[0] = data_out_to_pins[0][0];
    assign tmds_d_p_0[1] = data_out_to_pins[1][1];
    assign tmds_d_n_0[1] = data_out_to_pins[1][0];
    assign tmds_d_p_0[2] = data_out_to_pins[2][1];
    assign tmds_d_n_0[2] = data_out_to_pins[2][0];

    wire [1:0] tmds_clk;

    dvi_tx_clk_drv u_clk (
        .pixel_clock (pclk),
        .tmds_clk    (tmds_clk)
    );

    assign tmds_clk_p_0 = tmds_clk[1];
    assign tmds_clk_n_0 = tmds_clk[0];

endmodule
