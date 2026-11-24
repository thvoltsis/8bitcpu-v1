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

    // Αποθήκευση τελευταίας εκτελεσμένης εντολής (για να μην τρεμοπαίζει στο FETCH)
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

    // Κωδικοί χαρακτήρων (32 σύμβολα -> ακριβώς 5-bit)
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
            4'b0001: begin mn0 = CH_A
