`default_nettype none

module vga_out (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        exec_en,
    input  logic [3:0]  opcode,
    input  logic [7:0]  op_a,
    input  logic [7:0]  op_b,
    input  logic [7:0]  acc,
    input  logic        overflow,
    output logic [7:0]  vga_uo_out
);

    // Αποφυγή warnings για μη χρησιμοποιημένα σήματα
    logic _unused;
    assign _unused = &{1'b0, exec_en, opcode, op_a, op_b};

    // --- Μετρητές VGA 640x480 @ 60Hz (25.175 MHz) ---
    logic [9:0] h_cnt;
    logic [9:0] v_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else begin
            if (h_cnt == 10'd799) begin
                h_cnt <= 10'd0;
                if (v_cnt == 10'd524)
                    v_cnt <= 10'd0;
                else
                    v_cnt <= v_cnt + 10'd1;
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end
        end
    end

    logic hsync, vsync, video_active;
    assign hsync        = ~((h_cnt >= 10'd656) && (h_cnt < 10'd752));
    assign vsync        = ~((v_cnt >= 10'd490) && (v_cnt < 10'd492));
    assign video_active = (h_cnt < 10'd640) && (v_cnt < 10'd480);

    // --- 8 Κουτάκια Accumulator (y = 192..239, στήλες 1..8) ---
    logic [3:0] col;
    assign col = h_cnt[9:6]; // Κάθε στήλη είναι 64 px

    logic in_box_y, in_box_x, in_box, cur_bit;
    assign in_box_y = (v_cnt >= 10'd192) && (v_cnt < 10'd240);
    assign in_box_x = (col >= 4'd1) && (col <= 4'd8) && (h_cnt[5:0] < 6'd48);
    assign in_box   = in_box_y && in_box_x;

    always_comb begin
        case (col)
            4'd1:    cur_bit = acc[7];
            4'd2:    cur_bit = acc[6];
            4'd3:    cur_bit = acc[5];
            4'd4:    cur_bit = acc[4];
            4'd5:    cur_bit = acc[3];
            4'd6:    cur_bit = acc[2];
            4'd7:    cur_bit = acc[1];
            4'd8:    cur_bit = acc[0];
            default: cur_bit = 1'b0;
        endcase
    end

    // --- Ετικέτες "-128, 64, 32, 16, 8, 4, 2, 1" (y = 256..275) ---
    // Κάθε κελί 64px χωρίζεται σε 4 θέσεις χαρακτήρων των 16px (slot = h_cnt[5:4])
    // Κάθε pixel του 3x5 font είναι 4x4 px στην οθόνη
    logic       in_lbl_y;
    logic [2:0] font_row;
    logic [1:0] font_col;
    logic [1:0] char_slot;
    logic [2:0] char_id;  // 0:κενό, 1:'1', 2:'2', 3:'3', 4:'4', 5:'6', 6:'8', 7:'-'
    logic [2:0] row_bits;
    logic       lbl_pixel;

    assign in_lbl_y  = (v_cnt[9:5] == 5'd8) && (v_cnt[4:2] < 3'd5); // y = 256..275
    assign font_row  = v_cnt[4:2];
    assign char_slot = h_cnt[5:4];
    assign font_col  = h_cnt[3:2];

    // Αντιστοίχιση (στήλη, θέση χαρακτήρα) -> ψηφίο
    always_comb begin
        char_id = 3'd0;
        case ({col, char_slot})
            // Bit 7: -128
            {4'd1, 2'd0}: char_id = 3'd7; // -
            {4'd1, 2'd1}: char_id = 3'd1; // 1
            {4'd1, 2'd2}: char_id = 3'd2; // 2
            {4'd1, 2'd3}: char_id = 3'd6; // 8
            // Bit 6: 64
            {4'd2, 2'd1}: char_id = 3'd5; // 6
            {4'd2, 2'd2}: char_id = 3'd4; // 4
            // Bit 5: 32
            {4'd3, 2'd1}: char_id = 3'd3; // 3
            {4'd3, 2'd2}: char_id = 3'd2; // 2
            // Bit 4: 16
            {4'd4, 2'd1}: char_id = 3'd1; // 1
            {4'd4, 2'd2}: char_id = 3'd5; // 6
            // Bit 3: 8
            {4'd5, 2'd1}: char_id = 3'd6; // 8
            // Bit 2: 4
            {4'd6, 2'd1}: char_id = 3'd4; // 4
            // Bit 1: 2
            {4'd7, 2'd1}: char_id = 3'd2; // 2
            // Bit 0: 1
            {4'd8, 2'd1}: char_id = 3'd1; // 1
            default:      char_id = 3'd0;
        endcase
    end

    // Mini 3x5 Font ROM (μόνο τα 7 σύμβολα που χρειάζονται)
    always_comb begin
        row_bits = 3'b000;
        case (char_id)
            3'd1: case (font_row) // '1'
                3'd0: row_bits = 3'b010;
                3'd1: row_bits = 3'b110;
                3'd2: row_bits = 3'b010;
                3'd3: row_bits = 3'b010;
                3'd4: row_bits = 3'b111;
                default: row_bits = 3'b000;
            endcase
            3'd2: case (font_row) // '2'
                3'd0: row_bits = 3'b111;
                3'd1: row_bits = 3'b001;
                3'd2: row_bits = 3'b111;
                3'd3: row_bits = 3'b100;
                3'd4: row_bits = 3'b111;
                default: row_bits = 3'b000;
            endcase
            3'd3: case (font_row) // '3'
                3'd0: row_bits = 3'b111;
                3'd1: row_bits = 3'b001;
                3'd2: row_bits = 3'b111;
                3'd3: row_bits = 3'b001;
                3'd4: row_bits = 3'b111;
                default: row_bits = 3'b000;
            endcase
            3'd4: case (font_row) // '4'
                3'd0: row_bits = 3'b101;
                3'd1: row_bits = 3'b101;
                3'd2: row_bits = 3'b111;
                3'd3: row_bits = 3'b001;
                3'd4: row_bits = 3'b001;
                default: row_bits = 3'b000;
            endcase
            3'd5: case (font_row) // '6'
                3'd0: row_bits = 3'b111;
                3'd1: row_bits = 3'b100;
                3'd2: row_bits = 3'b111;
                3'd3: row_bits = 3'b101;
                3'd4: row_bits = 3'b111;
                default: row_bits = 3'b000;
            endcase
            3'd6: case (font_row) // '8'
                3'd0: row_bits = 3'b111;
                3'd1: row_bits = 3'b101;
                3'd2: row_bits = 3'b111;
                3'd3: row_bits = 3'b101;
                3'd4: row_bits = 3'b111;
                default: row_bits = 3'b000;
            endcase
            3'd7: case (font_row) // '-'
                3'd2: row_bits = 3'b111;
                default: row_bits = 3'b000;
            endcase
            default: row_bits = 3'b000;
        endcase
    end

    assign lbl_pixel = in_lbl_y && (font_col != 2'd3) && row_bits[2'd2 - font_col];

    // --- Χρώματα (RGB222) ---
    logic [1:0] R, G, B;

    always_comb begin
        if (!video_active) begin
            R = 2'b00; G = 2'b00; B = 2'b00;
        end else if (in_box) begin
            if (cur_bit) begin
                R = 2'b11; G = 2'b11; B = 2'b11; // Άσπρο (bit = 1)
            end else begin
                R = 2'b01; G = 2'b01; B = 2'b01; // Γκρι (bit = 0)
            end
        end else if (lbl_pixel) begin
            R = 2'b11; G = 2'b11; B = 2'b00;     // Κίτρινο για τους αριθμούς
        end else if (overflow) begin
            R = 2'b10; G = 2'b00; B = 2'b00;     // Κόκκινο φόντο (Overflow)
        end else begin
            R = 2'b00; G = 2'b00; B = 2'b01;     // Σκούρο μπλε φόντο
        end
    end

    // TinyVGA pinout: {hsync, B0, G0, R0, vsync, B1, G1, R1}
    assign vga_uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

endmodule
