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

    logic _unused;
    assign _unused = &{exec_en, opcode, op_a, op_b, 1'b0};

    logic [9:0] h_cnt, v_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else begin
            if (h_cnt == 10'd799) begin
                h_cnt <= 10'd0;
                v_cnt <= (v_cnt == 10'd524) ? 10'd0 : (v_cnt + 10'd1);
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end
        end
    end

    logic hsync, vsync, video_active;
    assign hsync        = ~((h_cnt >= 10'd656) && (h_cnt < 10'd752));
    assign vsync        = ~((v_cnt >= 10'd490) && (v_cnt < 10'd492));
    assign video_active = (h_cnt < 10'd640) && (v_cnt < 10'd480);

    // 8 τετράγωνα (48x48px) κεντραρισμένα: x=64..575, y=192..239
    logic in_y, in_x_cell, in_box, bit_val;
    assign in_y      = (v_cnt[9:6] == 4'd3) && (v_cnt[5:4] != 2'b11);
    assign in_x_cell = (h_cnt[5:4] != 2'b11);

    always_comb begin
        in_box  = 1'b0;
        bit_val = 1'b0;
        if (in_y && in_x_cell) begin
            case (h_cnt[9:6])
                4'd1: begin in_box = 1'b1; bit_val = acc[7]; end
                4'd2: begin in_box = 1'b1; bit_val = acc[6]; end
                4'd3: begin in_box = 1'b1; bit_val = acc[5]; end
                4'd4: begin in_box = 1'b1; bit_val = acc[4]; end
                4'd5: begin in_box = 1'b1; bit_val = acc[3]; end
                4'd6: begin in_box = 1'b1; bit_val = acc[2]; end
                4'd7: begin in_box = 1'b1; bit_val = acc[1]; end
                4'd8: begin in_box = 1'b1; bit_val = acc[0]; end
                default: begin in_box = 1'b0; bit_val = 1'b0; end
            endcase
        end
    end

    logic [1:0] R, G, B;
    always_comb begin
        if (!video_active) begin
            R = 2'b00; G = 2'b00; B = 2'b00;
        end else if (in_box) begin
            if (bit_val) begin
                R = 2'b11; G = 2'b11; B = 2'b11; // Άσπρο = 1
            end else begin
                R = 2'b01; G = 2'b01; B = 2'b01; // Γκρι = 0
            end
        end else begin
            R = overflow ? 2'b10 : 2'b00;
            G = 2'b00;
            B = overflow ? 2'b00 : 2'b01;
        end
    end

    assign vga_uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

endmodule
