module ble_pdu_header_rx (
    input  logic        clk,
    input  logic        rst_n,

    // 0: Advertising Physical Channel
    // 1: Data Physical Channel (ACL)
    input  logic        pkt_type_sel,

    // RX serial inputs
    input  logic        rx_bit_in,
    input  logic        rx_bit_en,

    // RX outputs
    output logic        rx_header_done,

    // Advertising decoded fields
    output logic [3:0]  rx_adv_pdu_type,
    output logic        rx_adv_chsel,
    output logic        rx_adv_txadd,
    output logic        rx_adv_rxadd,

    // Data Channel decoded fields
    output logic [1:0]  rx_dc_llid,
    output logic        rx_dc_nesn,
    output logic        rx_dc_sn,
    output logic        rx_dc_md,
    output logic        rx_dc_cp,
    output logic [7:0]  rx_dc_cte_info,

    output logic [7:0]  rx_length_out
);

    typedef enum logic [1:0] {
        RX_IDLE,
        RX_COLLECT_HEADER,
        RX_COLLECT_CTEINFO
    } rx_state_t;

    rx_state_t rx_state;

    logic [23:0] rx_shift_reg;
    logic [4:0]  rx_bit_count;
    logic        rx_pkt_type_sel;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state        <= RX_IDLE;
            rx_shift_reg    <= 24'd0;
            rx_bit_count    <= 5'd0;
            rx_pkt_type_sel <= 1'b0;

            rx_header_done  <= 1'b0;

            rx_adv_pdu_type <= 4'd0;
            rx_adv_chsel    <= 1'b0;
            rx_adv_txadd    <= 1'b0;
            rx_adv_rxadd    <= 1'b0;

            rx_dc_llid      <= 2'd0;
            rx_dc_nesn      <= 1'b0;
            rx_dc_sn        <= 1'b0;
            rx_dc_md        <= 1'b0;
            rx_dc_cp        <= 1'b0;
            rx_dc_cte_info  <= 8'd0;

            rx_length_out   <= 8'd0;
        end
        else begin
            rx_header_done <= 1'b0;

            if (rx_bit_en) begin
                case (rx_state)

                    // ----------------------------
                    // Wait for first header bit
                    // ----------------------------
                    RX_IDLE: begin
                        rx_shift_reg <= {23'd0, rx_bit_in};
                        rx_bit_count <= 5'd1;

                        // Latch packet format for this header
                        rx_pkt_type_sel <= pkt_type_sel;

                        rx_state <= RX_COLLECT_HEADER;
                    end

                    // ----------------------------
                    // Collect 16-bit base header
                    // ----------------------------
                    RX_COLLECT_HEADER: begin
                        rx_shift_reg[rx_bit_count] <= rx_bit_in;

                        if (rx_bit_count == 5'd15) begin

                            // Advertising Physical Channel
                            if (rx_pkt_type_sel == 1'b0) begin

                                rx_adv_pdu_type <= rx_shift_reg[3:0];
                                rx_adv_chsel    <= rx_shift_reg[5];
                                rx_adv_txadd    <= rx_shift_reg[6];
                                rx_adv_rxadd    <= rx_shift_reg[7];

                                rx_length_out <= {
                                    rx_bit_in,
                                    rx_shift_reg[14:8]
                                };

                                rx_header_done <= 1'b1;

                                rx_bit_count <= 5'd0;
                                rx_shift_reg <= 24'd0;
                                rx_state     <= RX_IDLE;
                            end

                            // Data Physical Channel (ACL)
                            else begin

                                rx_dc_llid <= rx_shift_reg[1:0];
                                rx_dc_nesn <= rx_shift_reg[2];
                                rx_dc_sn   <= rx_shift_reg[3];
                                rx_dc_md   <= rx_shift_reg[4];
                                rx_dc_cp   <= rx_shift_reg[5];

                                rx_length_out <= {
                                    rx_bit_in,
                                    rx_shift_reg[14:8]
                                };

                                if (rx_shift_reg[5] == 1'b1) begin
                                    // CP = 1: collect CTEInfo
                                    rx_bit_count <= 5'd16;
                                    rx_state     <= RX_COLLECT_CTEINFO;
                                end
                                else begin
                                    // CP = 0: header complete
                                    rx_dc_cte_info <= 8'd0;

                                    rx_header_done <= 1'b1;

                                    rx_bit_count <= 5'd0;
                                    rx_shift_reg <= 24'd0;
                                    rx_state     <= RX_IDLE;
                                end
                            end
                        end
                        else begin
                            rx_bit_count <= rx_bit_count + 5'd1;
                        end
                    end

                    // ----------------------------
                    // Collect optional CTEInfo
                    // ----------------------------
                    RX_COLLECT_CTEINFO: begin
                        rx_shift_reg[rx_bit_count] <= rx_bit_in;

                        if (rx_bit_count == 5'd23) begin

                            rx_dc_cte_info <= {
                                rx_bit_in,
                                rx_shift_reg[22:16]
                            };

                            rx_header_done <= 1'b1;

                            rx_bit_count <= 5'd0;
                            rx_shift_reg <= 24'd0;
                            rx_state     <= RX_IDLE;
                        end
                        else begin
                            rx_bit_count <= rx_bit_count + 5'd1;
                        end
                    end

                    default: begin
                        rx_state     <= RX_IDLE;
                        rx_bit_count <= 5'd0;
                        rx_shift_reg <= 24'd0;
                    end

                endcase
            end
        end
    end

endmodule

