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
    assign _unused = &{op_a, op_b, 1'b0};

    logic [9:0] h_cnt, v_cnt;
    logic [3:0] last_op;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt   <= 10'd0;
            v_cnt   <= 10'd0;
            last_op <= 4'd0;
        end else begin
            if (h_cnt == 10'd799) begin
                h_cnt <= 10'd0;
                v_cnt <= (v_cnt == 10'd524) ? 10'd0 : (v_cnt + 10'd1);
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end

            if (exec_en) begin
                last_op <= opcode;
            end
        end
    end

    logic hsync, vsync, video_active;
    assign hsync        = ~((h_cnt >= 10'd656) && (h_cnt < 10'd752));
    assign vsync        = ~((v_cnt >= 10'd490) && (v_cnt < 10'd492));
    assign video_active = (h_cnt < 10'd640) && (v_cnt < 10'd480);

    // 4 θέσεις στο x=256..383 (κέντρο οθόνης), y=192..231
    logic       in_box;
    logic [1:0] char_idx, col;
    logic [2:0] row;

    assign char_idx = h_cnt[6:5]; // 0=OP, 1=κενό, 2=ACC[7:4], 3=ACC[3:0]
    assign col      = h_cnt[4:3]; // 0..2 (3 = κενό)
    assign row      = v_cnt[5:3]; // 0..4
    assign in_box   = (h_cnt[9:7] == 3'b010) && (char_idx != 2'd1) &&
                      (v_cnt[9:6] == 4'd3)   && (v_cnt[5:3] < 3'd5);

    localparam logic [4:0]
        SYM_ADD = 5'd16, SYM_SUB = 5'd17, SYM_SHL = 5'd18, SYM_SHR = 5'd19,
        SYM_OR  = 5'd20, SYM_XOR = 5'd21, SYM_NOT = 5'd22, SYM_L   = 5'd23,
        SYM_J   = 5'd24, SYM_H   = 5'd25;

    logic [4:0] op_sym;
    always_comb begin
        case (last_op)
            4'b0000: op_sym = 5'd12;    // C (CLR)
            4'b0001: op_sym = SYM_ADD;  // + (ADD)
            4'
