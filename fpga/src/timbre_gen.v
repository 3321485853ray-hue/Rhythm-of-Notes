// timbre_gen.v — 波形生成层

module timbre_gen (
    input  wire               clk,
    input  wire               sample_strobe,  // 每采样一次（fs = 48828.125Hz）一个周期高
    input  wire               gate,           // = env_active：包络走完（含释放尾巴）前保持 1
    input  wire [31:0]        phase_step,     // 音高（已锁存）
    input  wire [2:0]         timbre,
    output wire signed [15:0] wave            // 16bit 有符号波形样本（bit15 恒 0）
);

    localparam CANARY_SINE = 1'b0;

    wire [2:0] timbre_eff = CANARY_SINE ? 3'd0 : timbre;

    additive_engine u_eng (
        .clk           (clk),
        .sample_strobe (sample_strobe),
        .gate          (gate),
        .phase_step    (phase_step),
        .timbre        (timbre_eff),
        .wave          (wave)
    );

endmodule
