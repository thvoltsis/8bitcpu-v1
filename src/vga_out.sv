`default_nettype none

module vga_out (
    input  logic       clk,        // 25.175 MHz
    input  logic       rst_n,
    input  logic       exec_en,
    input  logic [3:0] opcode,
    input  logic [7:0] op_a,
    input  logic [7:0] op_b,
    input  logic [7:0] acc,
    input  logic       overflow,
    output logic [7:0] vga_uo_out
);

    logic [9:0] h_cnt, v_cnt;
    logic [3:0] last_op;
    logic [7:0] last_a, last_b;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt   <= 10'd0;
            v_cnt   <= 10'd0;
            last_op <= 4'd0;
            last_a  <= 8'd0;
            last_b  <= 8'd0;
        end else begin
            if (h_cnt == 10'd799) begin
                h_cnt <= 10'd0;
                v_cnt <= (v_cnt == 10'd524) ? 10'd0 : (v_cnt + 10'd1);
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end

            if (exec_en) begin
                last_op <= opcode;
                last_a  <= op_a;
                last_b  <= op_b;
            end
        end
    end

    logic hsync, vsync, video_active;
    assign hsync        = ~((h_cnt >= 10'd656) && (h_cnt < 10'd752));
    assign vsync        = ~((v_cnt >= 10'd490) && (v_cnt < 10'd492));
    assign video_active = (h_cnt < 10'd640) && (v_cnt < 10'd480);

    // 8 χαρακτήρες στο x=256..511 (32px ο καθένας), y=192..231 (40px ύψος) -> 0 subtractors
    logic       in_box;
    logic [2:0] char_idx, row;
    logic [1:0] col;

    assign in_box   = (h_cnt[9:8] == 2'b01) && (v_cnt[9:6] == 4'd3) && (v_cnt[5:3] < 3'd5);
    assign char_idx = h_cnt[7:5]; // 0..7
    assign col      = h_cnt[4:3]; // 0..2 (3 = κενό)
    assign row      = v_cnt[5:3]; // 0..4

    // Κωδικοί συμβόλων (0..15 = 0..F, 16..26 = σύμβολα)
    localparam logic [4:0]
        SYM_ADD = 5'd16, SYM_SUB = 5'd17, SYM_SHL = 5'd18, SYM_SHR = 5'd19,
        SYM_OR  = 5'd20, SYM_XOR = 5'd21, SYM_NOT = 5'd22, SYM_EQ  = 5'd23,
        SYM_L   = 5'd24, SYM_J   = 5'd25, SYM_H   = 5'd26;

    // Αντιστοίχιση opcode -> 1 σύμβολο
    logic [4:0] op_sym;
    always_comb begin
        case (last_op)
            4'b0000: op_sym = 5'd12;    // C (CLR)
            4'b0001: op_sym = SYM_ADD;  // + (ADD)
            4'b0010: op_sym = SYM_SUB;  // - (SUB)
            4'b0011: op_sym = SYM_ADD;  // + (INC)
            4'b0100: op_sym = SYM_SUB;  // - (DEC)
            4'b0101: op_sym = SYM_L;    // L (LDA)
            4'b0110: op_sym = 5'd5;     // 5/S (STA)
            4'b0111: op_sym = 5'd10;    // A (AND)
            4'b1000: op_sym = SYM_OR;   // | (OR)
            4'b1001: op_sym = SYM_XOR;  // x (XOR)
            4'b1010: op_sym = SYM_NOT;  // ~ (NOT)
            4'b1011: op_sym = SYM_SHL;  // < (SHL)
            4'b1100: op_sym = SYM_SHR;  // > (SHR)
            4'b1101: op_sym = SYM_J;    // J (JMP)
            4'b1110: op_sym = SYM_J;    // J (JPZ)
            4'b1111: op_sym = SYM_H;    // H (HLT)
        endcase
    end

    // Μορφή: "AAoBB=RR"
    logic [4:0] glyph;
    always_comb begin
        case (char_idx)
            3'd0: glyph = {1'b0, last_a[7:4]};
            3'd1: glyph = {1'b0, last_a[3:0]};
            3'd2: glyph = op_sym;
            3'd3: glyph = {1'b0, last_b[7:4]};
            3'd4: glyph = {1'b0, last_b[3:0]};
            3'd5: glyph = SYM_EQ;
            3'd6: glyph = {1'b0, acc[7:4]};
            3'd7: glyph = {1'b0, acc[3:0]};
        endcase
    end

    // Compact 3x5 Font ROM
    logic [14:0] bitmap;
    always_comb begin
        case (glyph)
            5'd0:    bitmap = 15'b111_101_101_101_111; // 0
            5'd1:    bitmap = 15'b010_110_010_010_111; // 1
            5'd2:    bitmap = 15'b111_001_111_100_111; // 2
            5'd3:    bitmap = 15'b111_001_111_001_111; // 3
            5'd4:    bitmap = 15'b101_101_111_001_001; // 4
            5'd5:    bitmap = 15'b111_100_111_001_111; // 5 / S
            5'd6:    bitmap = 15'b111_100_111_101_111; // 6
            5'd7:    bitmap = 15'b111_001_001_001_001; // 7
            5'd8:    bitmap = 15'b111_101_111_101_111; // 8
            5'd9:    bitmap = 15'b111_101_111_001_111; // 9
            5'd10:   bitmap = 15'b010_101_111_101_101; // A
            5'd11:   bitmap = 15'b110_101_110_101_110; // B
            5'd12:   bitmap = 15'b111_100_100_100_111; // C
            5'd13:   bitmap = 15'b110_101_101_101_110; // D
            5'd14:   bitmap = 15'b111_100_110_100_111; // E
            5'd15:   bitmap = 15'b111_100_110_100_100; // F
            SYM_ADD: bitmap = 15'b000_010_111_010_000; // +
            SYM_SUB: bitmap = 15'b000_000_111_000_000; // -
            SYM_SHL: bitmap = 15'b001_010_100_010_001; // <
            SYM_SHR: bitmap = 15'b100_010_001_010_100; // >
            SYM_OR:  bitmap = 15'b010_010_010_010_010; // |
            SYM_XOR: bitmap = 15'b000_101_010_101_000; // x
            SYM_NOT: bitmap = 15'b000_010_101_000_000; // ~
            SYM_EQ:  bitmap = 15'b000_111_000_111_000; // =
            SYM_L:   bitmap = 15'b100_100_100_100_111; // L
            SYM_J:   bitmap = 15'b001_001_001_101_111; // J
            SYM_H:   bitmap = 15'b101_101_111_101_101; // H
            default: bitmap = 15'b000_000_000_000_000;
        endcase
    end

    // Επιλογή γραμμής & στήλης χωρίς πολλαπλασιαστή
    logic [2:0] row_bits;
    always_comb begin
        case (row)
            3'd0: row_bits = bitmap[14:12];
            3'd1: row_bits = bitmap[11:9];
            3'd2: row_bits = bitmap[8:6];
            3'd3: row_bits = bitmap[5:3];
            3'd4: row_bits = bitmap[2:0];
            default: row_bits = 3'b000;
        endcase
    end

    logic pixel_on;
    always_comb begin
        if (!in_box) begin
            pixel_on = 1'b0;
        end else begin
            case (col)
                2'd0: pixel_on = row_bits[2];
                2'd1: pixel_on = row_bits[1];
                2'd2: pixel_on = row_bits[0];
                default: pixel_on = 1'b0;
            endcase
        end
    end

    logic [1:0] R, G, B;
    always_comb begin
        if (!video_active) begin
            R = 2'b00; G = 2'b00; B = 2'b00;
        end else if (pixel_on) begin
            R = 2'b11; G = 2'b11; B = 2'b11;
        end else begin
            R = overflow ? 2'b10 : 2'b00;
            G = 2'b00;
            B = overflow ? 2'b00 : 2'b01;
        end
    end

    assign vga_uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

endmodule
