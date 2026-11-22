module ble_pdu_header_tx (
    input  logic        clk,
    input  logic        rst_n,

    // 0: Advertising Physical Channel
    // 1: Data Physical Channel (ACL)
    input  logic        pkt_type_sel,

    // Advertising TX inputs
    input  logic [3:0]  tx_adv_pdu_type,
    input  logic        tx_adv_chsel,
    input  logic        tx_adv_txadd,
    input  logic        tx_adv_rxadd,

    // Data Channel TX inputs
    input  logic [1:0]  tx_dc_llid,
    input  logic        tx_dc_nesn,
    input  logic        tx_dc_sn,
    input  logic        tx_dc_md,
    input  logic        tx_dc_cp,
    input  logic [7:0]  tx_dc_cte_info,

    input  logic [7:0]  tx_payload_len,
    input  logic        tx_start_en,

    // TX outputs
    output logic [23:0] tx_header_bits,
    output logic [4:0]  tx_header_len,
    output logic        tx_header_valid
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_header_bits  <= 24'd0;
            tx_header_len   <= 5'd0;
            tx_header_valid <= 1'b0;
        end
        else begin
            tx_header_valid <= 1'b0;

            if (tx_start_en) begin

                // --------------------------------
                // Advertising Physical Channel
                // --------------------------------
                if (pkt_type_sel == 1'b0) begin

                    tx_header_bits <= {
                        8'd0,
                        tx_payload_len,
                        tx_adv_rxadd,
                        tx_adv_txadd,
                        tx_adv_chsel,
                        1'b0,                 // RFU
                        tx_adv_pdu_type
                    };

                    tx_header_len   <= 5'd16;
                    tx_header_valid <= 1'b1;
                end

                // --------------------------------
                // Data Physical Channel (ACL)
                // --------------------------------
                else begin

                    if (tx_dc_cp) begin
                        // CP = 1: CTEInfo present
                        tx_header_bits <= {
                            tx_dc_cte_info,
                            tx_payload_len,
                            2'b00,            // RFU
                            tx_dc_cp,
                            tx_dc_md,
                            tx_dc_sn,
                            tx_dc_nesn,
                            tx_dc_llid
                        };

                        tx_header_len <= 5'd24;
                    end
                    else begin
                        // CP = 0: CTEInfo absent
                        tx_header_bits <= {
                            8'd0,
                            tx_payload_len,
                            2'b00,            // RFU
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

endmodule

