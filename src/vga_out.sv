`default_nettype none

module vga_out (
    input  logic       clk,        // 25.175 MHz
    input  logic       rst_n,
    input  logic       exec_en,    // 1 όταν εκτελείται εντολή (live || state==EXECUTE)
    input  logic [3:0] opcode,     // a_opcode από controler
    input  logic [7:0] op_a,       // a (Accumulator πριν την πράξη)
    input  logic [7:0] op_b,       // alu_b από controler
    input  logic [7:0] acc,        // a (τρέχων Accumulator)
    input  logic       overflow,   // overflow από controler
    output logic [7:0] vga_uo_out  // TinyVGA PMOD pinout
);

    // 640x480 @ 60Hz timing counters (800x525 total)
    logic [9:0] h_cnt, v_cnt;

    // Αποθήκευση τελευταίας εκτελεσμένης εντολής
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

    // 20 στήλες των 32px (κάθε χαρακτήρας 3x5 x8 scale = 24x40px + 8px κενό)
    logic [4:0] char_col, x_in_char;
    logic [1:0] col;
    logic       line1, line2;
    logic [9:0] y_off;
    logic [2:0] row;

    assign char_col  = h_cnt[9:5];
    assign x_in_char = h_cnt[4:0];
    assign col       = x_in_char[4:3];

    assign line1 = (v_cnt >= 10'd160) && (v_cnt < 10'd200);
    assign line2 = (v_cnt >= 10'd240) && (v_cnt < 10'd280);
    assign y_off = line1 ? (v_cnt - 10'd160) : (v_cnt - 10'd240);
    assign row   = y_off[5:3];

    // Κωδικοί χαρακτήρων (32 σύμβολα -> 5-bit)
    localparam logic [4:0]
        CH_0  = 5'd0,  CH_1  = 5'd1,  CH_2  = 5'd2,  CH_3  = 5'd3,
        CH_4  = 5'd4,  CH_5  = 5'd5,  CH_6  = 5'd6,  CH_7  = 5'd7,
        CH_8  = 5'd8,  CH_9  = 5'd9,  CH_A  = 5'd10, CH_B  = 5'd11,
        CH_C  = 5'd12, CH_D  = 5'd13, CH_E  = 5'd14, CH_F  = 5'd15,
        CH_H  = 5'd16, CH_I  = 5'd17, CH_J  = 5'd18, CH_L  = 5'd19,
        CH_M  = 5'd20, CH_N  = 5'd21, CH_O  = 5'd22, CH_P  = 5'd23,
        CH_R  = 5'd24, CH_S  = 5'd25, CH_T  = 5'd26, CH_U  = 5'd27,
        CH_X  = 5'd28, CH_Z  = 5'd29, CH_EQ = 5'd30, CH_SP = 5'd31;

    // Όλα τα 16 opcodes της CPU σου
    logic [4:0] mn0, mn1, mn2;
    always_comb begin
        case (last_op)
            4'b0000: begin mn0 = CH_C; mn1 = CH_L; mn2 = CH_R;  end // CLR
            4'b0001: begin mn0 = CH_A; mn1 = CH_D; mn2 = CH_D;  end // ADD
            4'b0010: begin mn0 = CH_S; mn1 = CH_U; mn2 = CH_B;  end // SUB
            4'b0011: begin mn0 = CH_I; mn1 = CH_N; mn2 = CH_C;  end // INC
            4'b0100: begin mn0 = CH_D; mn1 = CH_E; mn2 = CH_C;  end // DEC
            4'b0101: begin mn0 = CH_L; mn1 = CH_D; mn2 = CH_A;  end // LDA
            4'b0110: begin mn0 = CH_S; mn1 = CH_T; mn2 = CH_A;  end // STA
            4'b0111: begin mn0 = CH_A; mn1 = CH_N; mn2 = CH_D;  end // AND
            4'b1000: begin mn0 = CH_O; mn1 = CH_R; mn2 = CH_SP; end // OR
            4'b1001: begin mn0 = CH_X; mn1 = CH_O; mn2 = CH_R;  end // XOR
            4'b1010: begin mn0 = CH_N; mn1 = CH_O; mn2 = CH_T;  end // NOT
            4'b1011: begin mn0 = CH_S; mn1 = CH_H; mn2 = CH_L;  end // SHL
            4'b1100: begin mn0 = CH_S; mn1 = CH_H; mn2 = CH_R;  end // SHR
            4'b1101: begin mn0 = CH_J; mn1 = CH_M; mn2 = CH_P;  end // JMP
            4'b1110: begin mn0 = CH_J; mn1 = CH_P; mn2 = CH_Z;  end // JPZ
            4'b1111: begin mn0 = CH_H; mn1 = CH_L; mn2 = CH_T;  end // HLT
        endcase
    end

    // Επιλογή χαρακτήρα ανά γραμμή και στήλη
    logic [4:0] glyph;
    always_comb begin
        glyph = CH_SP;
        if (line1) begin
            case (char_col)
                5'd5:  glyph = mn0;
                5'd6:  glyph = mn1;
                5'd7:  glyph = mn2;
                5'd9:  glyph = {1'b0, last_a[7:4]};
                5'd10: glyph = {1'b0, last_a[3:0]};
                5'd12: glyph = {1'b0, last_b[7:4]};
                5'd13: glyph = {1'b0, last_b[3:0]};
                default: glyph = CH_SP;
            endcase
        end else if (line2) begin
            case (char_col)
                5'd5:  glyph = CH_A;
                5'd6:  glyph = CH_C;
                5'd7:  glyph = CH_C;
                5'd9:  glyph = CH_EQ;
                5'd11: glyph = {1'b0, acc[7:4]};
                5'd12: glyph = {1'b0, acc[3:0]};
                default: glyph = CH_SP;
            endcase
        end
    end

    // 3x5 Font ROM
    logic [14:0] bitmap;
    always_comb begin
        case (glyph)
            CH_0:  bitmap = 15'b111_101_101_101_111;
            CH_1:  bitmap = 15'b010_110_010_010_111;
            CH_2:  bitmap = 15'b111_001_111_100_111;
            CH_3:  bitmap = 15'b111_001_111_001_111;
            CH_4:  bitmap = 15'b101_101_111_001_001;
            CH_5:  bitmap = 15'b111_100_111_001_111;
            CH_6:  bitmap = 15'b111_100_111_101_111;
            CH_7:  bitmap = 15'b111_001_001_001_001;
            CH_8:  bitmap = 15'b111_101_111_101_111;
            CH_9:  bitmap = 15'b111_101_111_001_111;
            CH_A:  bitmap = 15'b010_101_111_101_101;
            CH_B:  bitmap = 15'b110_101_110_101_110;
            CH_C:  bitmap = 15'b111_100_100_100_111;
            CH_D:  bitmap = 15'b110_101_101_101_110;
            CH_E:  bitmap = 15'b111_100_110_100_111;
            CH_F:  bitmap = 15'b111_100_110_100_100;
            CH_H:  bitmap = 15'b101_101_111_101_101;
            CH_I:  bitmap = 15'b111_010_010_010_111;
            CH_J:  bitmap = 15'b001_001_001_101_111;
            CH_L:  bitmap = 15'b100_100_100_100_111;
            CH_M:  bitmap = 15'b101_111_101_101_101;
            CH_N:  bitmap = 15'b111_101_101_101_101;
            CH_O:  bitmap = 15'b111_101_101_101_111;
            CH_P:  bitmap = 15'b111_101_111_100_100;
            CH_R:  bitmap = 15'b110_101_110_101_101;
            CH_S:  bitmap = 15'b111_100_111_001_111;
            CH_T:  bitmap = 15'b111_010_010_010_010;
            CH_U:  bitmap = 15'b101_101_101_101_111;
            CH_X:  bitmap = 15'b101_101_010_101_101;
            CH_Z:  bitmap = 15'b111_001_010_100_111;
            CH_EQ: bitmap = 15'b000_111_000_111_000;
            default: bitmap = 15'b000_000_000_000_000;
        endcase
    end

    logic [3:0] bit_pos;
    logic       pixel_on;
    assign bit_pos  = 4'd14 - ({row, 1'b0} + {1'b0, row} + {2'b0, col});
    assign pixel_on = (line1 || line2) && (x_in_char < 5'd24) && bitmap[bit_pos];

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
