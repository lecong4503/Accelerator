`timescale 1ns / 1ps

module tile_array #(
    parameter I_F_BW = 8,
    parameter W_BW = 8,
    parameter M_BW = 16,
    parameter AK_BW = 20,
    parameter AC_BW = 24,
    parameter ROWS = 5,
    parameter COLS = 5,
    parameter T_ROWS = 5,       // tile array ROWS
    parameter T_COLS = 5        // tile array COLS
)
(
    input                                   clk,
    input                                   rst_n,

    // control signal port
    input                                   i_en_tf,
    input   [1:0]                           i_cal_state,
    input   [2:0]                           i_layer_state,
    // data port
    input   [(I_F_BW*COLS*T_COLS)-1:0]      i_fmap,
    input   [(W_BW*ROWS*T_ROWS)-1:0]        i_weight,
    
    output  [(AC_BW*COLS*T_ROWS)-1:0]       o_acc_kernel 
);

    wire [(I_F_BW*COLS*T_COLS)-1:0]         r_in_bus;
    wire [(W_BW*ROWS*T_ROWS)-1:0]           c_in_bus;

    wire [(M_BW*ROWS*T_ROWS)-1:0]           c_ot_ps;

    wire [(I_F_BW*ROWS*COLS*T_ROWS)-1:0]    w_hor;
    wire [(W_BW*COLS*ROWS*T_COLS)-1:0]      w_ver;
    wire [(AK_BW*COLS*ROWS*T_COLS)-1:0]     w_acc;

    genvar r, c;

    generate
        for (c=0; c<T_COLS; c=c+1) begin
            assign c_ot_ps[(c+1)*W_BW-1 -: W_BW] = w_ver[(c*T_ROWS+T_ROWS)*W_BW-1 -: W_BW];
        end
        for (r=0; r<T_ROWS; r=r+1) begin : gen_row
            for (c=0; c<T_COLS; c=c+1) begin : gen_col

                localparam HOR_OUTPUT_OFFSET    = (r*ROWS+(c+1))*(I_F_BW*COLS)       ;
                localparam HOR_INPUT_OFFSET     = (r*ROWS+c)*(I_F_BW*COLS)           ;

                localparam VER_OUTPUT_OFFSET    = (c*COLS+(r+1))*(W_BW*ROWS)       ;
                localparam VER_INPUT_OFFSET     = (c*COLS+r)*(W_BW*ROWS)           ;

                localparam ACC_OFFSET           = (c*T_ROWS+(r+1))*(AK_BW*ROWS)     ;

                if ((r==0) && (c==0)) begin

                    top_tile u_tile_zero (
                        .clk(clk),
                        .rst_n(rst_n),

                        .i_en_tf(i_en_tf),
                        .i_cal_state(i_cal_state),
                        .i_layer_state(i_layer_state),

                        .i_fmap(r_in_bus[(r+1)*(I_F_BW*COLS)-1 -: I_F_BW*COLS]),
                        .i_weight(c_in_bus[(c+1)*(W_BW*ROWS)-1 -: W_BW*ROWS]),

                        .o_fmap(w_hor[HOR_OUTPUT_OFFSET-1 -: I_F_BW*COLS]),
                        .o_weight(w_ver[VER_OUTPUT_OFFSET-1 -: W_BW*ROWS]),
                        .o_acc_pp(w_acc[ACC_OFFSET-1 -: AK_BW*ROWS])
                    );

                end else if (c==0) begin

                    top_tile u_tile_left_col (
                        .clk(clk),
                        .rst_n(rst_n),
                        .i_en_tf(i_en_tf),
                        .i_cal_state(i_cal_state),
                        .i_layer_state(i_layer_state),

                        .i_fmap(r_in_bus[(r+1)*(I_F_BW*COLS)-1 -: I_F_BW*COLS]),
                        .i_weight(w_ver[VER_INPUT_OFFSET-1 -: W_BW*ROWS]),

                        .o_fmap(w_hor[HOR_OUTPUT_OFFSET-1 -: I_F_BW*COLS]),
                        .o_weight(w_ver[VER_OUTPUT_OFFSET-1 -: W_BW*ROWS]),
                        .o_acc_pp(w_acc[ACC_OFFSET-1 -: AK_BW*ROWS])
                    );

                end else if (r==0) begin

                    top_tile u_tile_top_row (
                        .clk(clk),
                        .rst_n(rst_n),

                        .i_en_tf(i_en_tf),
                        .i_cal_state(i_cal_state),
                        .i_layer_state(i_layer_state),

                        .i_fmap(w_hor[HOR_INPUT_OFFSET-1 -: I_F_BW*COLS]),
                        .i_weight(c_in_bus[(c+1)*(W_BW*ROWS)-1 -: W_BW*ROWS]),

                        .o_fmap(w_hor[HOR_OUTPUT_OFFSET-1 -: I_F_BW*COLS]),
                        .o_weight(w_ver[VER_OUTPUT_OFFSET-1 -: W_BW*ROWS]),
                        .o_acc_pp(w_acc[ACC_OFFSET-1 -: AK_BW*ROWS])
                    );

                end else begin

                    top_tile u_PE (
                        .clk(clk),
                        .rst_n(rst_n),

                        .i_en_tf(i_en_tf),
                        .i_cal_state(i_cal_state),
                        .i_layer_state(i_layer_state),

                        .i_fmap(w_hor[HOR_INPUT_OFFSET-1 -: I_F_BW*COLS]),
                        .i_weight(w_ver[VER_INPUT_OFFSET-1 -: W_BW*ROWS]),

                        .o_fmap(w_hor[HOR_OUTPUT_OFFSET-1 -: I_F_BW*COLS]),
                        .o_weight(w_ver[VER_OUTPUT_OFFSET-1 -: W_BW*ROWS]),
                        .o_acc_pp(w_acc[ACC_OFFSET-1 -: AK_BW*ROWS])
                    );
                end
            end
        end
    endgenerate

    wire [AK_BW*COLS*T_COLS-1:0] w_tile_acc [T_COLS-1:0];
    wire [AC_BW*COLS-1:0] w_ot_tile_acc [T_COLS-1:0];

    genvar i;
    generate
        for (i=0; i<T_COLS; i=i+1) begin
            assign w_tile_acc[i] = w_acc[(i+1)*AK_BW*COLS*T_COLS-1 -: AK_BW*COLS*T_COLS];

            top_acc #(
                .M_BW(20),
                .AK_BW(24)
            ) u_tile_acc (
                .clk(clk),
                .rst_n(rst_n),
                .i_layer_state(i_layer_state),
                .i_mul_result(w_tile_acc[i]),
                .o_acc_kernel(w_ot_tile_acc[i])
            );
        end
    endgenerate

    assign r_in_bus = i_fmap;
    assign c_in_bus = i_weight;

    assign o_acc_kernel = {w_ot_tile_acc[4], w_ot_tile_acc[3], w_ot_tile_acc[2], w_ot_tile_acc[1], w_ot_tile_acc[0]};

endmodule