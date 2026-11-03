// note_map.v — 键号 → 基础音符索引（10 项查表）

module note_map (
    input  wire [3:0] key_idx,     // 键号 0~11，来自 voice_manager
    output reg  [6:0] base_note    // 基础音符索引（未加八度偏移）
);

    always @(*) begin
        case (key_idx)

            4'd0:  base_note = 7'd36;  // C4   261.63Hz
            4'd1:  base_note = 7'd38;  // D4   293.66Hz
            4'd2:  base_note = 7'd40;  // E4   329.63Hz
            4'd3:  base_note = 7'd41;  // F4   349.23Hz
            4'd4:  base_note = 7'd43;  // G4   392.00Hz
            4'd5:  base_note = 7'd45;  // A4   440.00Hz
            4'd6:  base_note = 7'd47;  // B4   493.88Hz

            4'd7:  base_note = 7'd37;  // C#4  277.18Hz
            4'd8:  base_note = 7'd39;  // D#4  311.13Hz
            4'd9:  base_note = 7'd42;  // F#4  369.99Hz
            4'd10: base_note = 7'd44;  // G#4  415.30Hz
            4'd11: base_note = 7'd46;  // A#4  466.16Hz
            default: base_note = 7'd36;  // 越界兜底 → C4
        endcase
    end

endmodule
