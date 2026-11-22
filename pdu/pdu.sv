module ble_pdu_header_assembler_parser (

    input  logic        clk,
    input  logic        rst_n,

    // 0 : Advertising Physical Channel
    // 1 : Data Physical Channel (ACL)
    input  logic        pkt_type_sel,

    // ---------------- TX INPUTS ----------------

    input  logic [3:0]  tx_adv_pdu_type,
    input  logic        tx_adv_chsel,
    input  logic        tx_adv_txadd,
    input  logic        tx_adv_rxadd,

    input  logic [1:0]  tx_dc_llid,
    input  logic        tx_dc_nesn,
    input  logic        tx_dc_sn,
    input  logic        tx_dc_md,
    input  logic        tx_dc_cp,
    input  logic [7:0]  tx_dc_cte_info,

    input  logic [7:0]  tx_payload_len,
    input  logic        tx_start_en,

    // ---------------- TX OUTPUTS ----------------

    output logic [23:0] tx_header_bits,
    output logic [4:0]  tx_header_len,
    output logic        tx_header_valid,

    // ---------------- RX INPUTS ----------------

    input  logic        rx_bit_in,
    input  logic        rx_bit_en,

    // ---------------- RX OUTPUTS ----------------

    output logic        rx_header_done,

    output logic [3:0]  rx_adv_pdu_type,
    output logic        rx_adv_chsel,
    output logic        rx_adv_txadd,
    output logic        rx_adv_rxadd,

    output logic [1:0]  rx_dc_llid,
    output logic        rx_dc_nesn,
    output logic        rx_dc_sn,
    output logic        rx_dc_md,
    output logic        rx_dc_cp,
    output logic [7:0]  rx_dc_cte_info,

    output logic [7:0]  rx_length_out

);

    // ============================================================
    // TX HEADER ASSEMBLER
    // ============================================================

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            tx_header_bits  <= 24'd0;
            tx_header_len   <= 5'd0;
            tx_header_valid <= 1'b0;

        end

        else begin

            tx_header_valid <= 1'b0;

            if (tx_start_en) begin

                // ------------------------------------------------
                // ADVERTISING PHYSICAL CHANNEL HEADER
                // ------------------------------------------------

                if (pkt_type_sel == 1'b0) begin

                    tx_header_bits <= {
                        8'd0,
                        tx_payload_len,
                        tx_adv_rxadd,
                        tx_adv_txadd,
                        tx_adv_chsel,
                        1'b0,
                        tx_adv_pdu_type
                    };

                    tx_header_len   <= 5'd16;
                    tx_header_valid <= 1'b1;

                end

                // ------------------------------------------------
                // DATA PHYSICAL CHANNEL HEADER (ACL)
                // ------------------------------------------------

                else begin

                    // CP = 1 : CTEInfo present
                    // Header length = 24 bits

                    if (tx_dc_cp) begin

                        tx_header_bits <= {
                            tx_dc_cte_info,
                            tx_payload_len,
                            2'b00,
                            tx_dc_cp,
                            tx_dc_md,
                            tx_dc_sn,
                            tx_dc_nesn,
                            tx_dc_llid
                        };

                        tx_header_len <= 5'd24;

                    end

                    // CP = 0 : CTEInfo absent
                    // Header length = 16 bits

                    else begin

                        tx_header_bits <= {
                            8'd0,
                            tx_payload_len,
                            2'b00,
                            tx_dc_cp,
                            tx_dc_md,
                            tx_dc_sn,
                            tx_dc_nesn,
                            tx_dc_llid
                        };

                        tx_header_len <= 5'd16;

                    end

                    tx_header_valid <= 1'b1;

                end

            end

        end

    end


    // ============================================================
    // RX HEADER PARSER
    // ============================================================

    typedef enum logic [1:0] {

        RX_IDLE,
        RX_COLLECT_HEADER,
        RX_COLLECT_CTEINFO

    } rx_state_t;

    rx_state_t rx_state;

    logic [23:0] rx_shift_reg;
    logic [4:0]  rx_bit_count;

    logic        rx_pkt_type_sel;


    // ============================================================
    // RX FSM
    // ============================================================

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

                    // --------------------------------------------
                    // IDLE
                    // Accept first bit of a new header.
                    // Latch packet type for this header.
                    // --------------------------------------------

                    RX_IDLE: begin

                        rx_shift_reg <= {23'd0, rx_bit_in};

                        rx_bit_count    <= 5'd1;
                        rx_pkt_type_sel <= pkt_type_sel;

                        rx_state <= RX_COLLECT_HEADER;

                    end


                    // --------------------------------------------
                    // COLLECT BASE HEADER
                    // Collect remaining bits up to bit 15.
                    // --------------------------------------------

                    RX_COLLECT_HEADER: begin

                        rx_shift_reg[rx_bit_count] <= rx_bit_in;

                        if (rx_bit_count == 5'd15) begin

                            // ====================================
                            // ADVERTISING HEADER
                            // ====================================

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

                            // ====================================
                            // DATA CHANNEL HEADER (ACL)
                            // ====================================

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

                                // CP = 1 : CTEInfo follows

                                if (rx_shift_reg[5] == 1'b1) begin

                                    rx_bit_count <= 5'd16;
                                    rx_state     <= RX_COLLECT_CTEINFO;

                                end

                                // CP = 0 : Header complete

                                else begin

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


                    // --------------------------------------------
                    // COLLECT CTEINFO
                    // Collect bits [23:16].
                    // --------------------------------------------

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


                    // --------------------------------------------
                    // DEFAULT
                    // --------------------------------------------

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
