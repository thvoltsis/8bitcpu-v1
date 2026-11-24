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

    logic in_box_y, in_box_x, in_box, in_divider, cur_bit;
    assign in_box_y   = (v_cnt >= 10'd192) && (v_cnt < 10'd240);
    assign in_box_x   = (col >= 4'd1) && (col <= 4'd8) && (h_cnt[5:0] < 6'd48);
    assign in_box     = in_box_y && in_box_x;

    // Κάθετη διαχωριστική γραμμή (4 px) ακριβώς ανάμεσα στο bit 4 (col 4) και bit 3 (col 5)
    assign in_divider = in_box_y && (col == 4'd4) && (h_cnt[5:2] == 4'd14);

    always_comb begin
        case (col)
            4'd1:    cur_bit = acc[7]; // -128 (πρόσημο)
            4'd2:    cur_bit = acc[6]; // 64
            4'd3:    cur_bit = acc[5]; // 32
            4'd4:    cur_bit = acc[4]; // 16
            4'd5:    cur_bit = acc[3]; // 8
            4'd6:    cur_bit = acc[2]; // 4
            4'd7:    cur_bit = acc[1]; // 2
            4'd8:    cur_bit = acc[0]; // 1
            default: cur_bit = 1'b0;
        endcase
    end

    // --- Χρώματα (RGB222) ---
    logic [1:0] R, G, B;

    always_comb begin
        if (!video_active) begin
            R = 2'b00; G = 2'b00; B = 2'b00;
        end else if (in_box) begin
            if (cur_bit) begin
                if (col == 4'd1) begin
                    R = 2'b11; G = 2'b11; B = 2'b00; // Κίτρινο για το bit προσήμου (-128 = 1)
                end else begin
                    R = 2'b11; G = 2'b11; B = 2'b11; // Άσπρο (bit = 1)
                end
            end else begin
                R = 2'b01; G = 2'b01; B = 2'b01;     // Γκρι (bit = 0)
            end
        end else if (in_divider) begin
            R = 2'b00; G = 2'b11; B = 2'b11;         // Γαλάζια διαχωριστική γραμμή (2 nibbles)
        end else if (overflow) begin
            R = 2'b10; G = 2'b00; B = 2'b00;         // Κόκκινο φόντο (Overflow)
        end else begin
            R = 2'b00; G = 2'b00; B = 2'b01;         // Σκούρο μπλε φόντο
        end
    end

    // TinyVGA pinout: {hsync, B0, G0, R0, vsync, B1, G1, R1}
    assign vga_uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

endmodule
