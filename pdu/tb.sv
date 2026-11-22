module tb_ble_pdu_header_assembler_parser;

    // ------------------------------------------------
    // DUT INPUTS
    // ------------------------------------------------

    logic clk;
    logic rst_n;

    logic pkt_type_sel;

    // TX inputs
    logic [3:0] tx_adv_pdu_type;
    logic       tx_adv_chsel;
    logic       tx_adv_txadd;
    logic       tx_adv_rxadd;

    logic [1:0] tx_dc_llid;
    logic       tx_dc_nesn;
    logic       tx_dc_sn;
    logic       tx_dc_md;
    logic       tx_dc_cp;
    logic [7:0] tx_dc_cte_info;

    logic [7:0] tx_payload_len;
    logic       tx_start_en;

    // RX inputs
    logic rx_bit_in;
    logic rx_bit_en;

    // ------------------------------------------------
    // DUT OUTPUTS
    // ------------------------------------------------

    logic [23:0] tx_header_bits;
    logic [4:0]  tx_header_len;
    logic        tx_header_valid;

    logic rx_header_done;

    logic [3:0] rx_adv_pdu_type;
    logic       rx_adv_chsel;
    logic       rx_adv_txadd;
    logic       rx_adv_rxadd;

    logic [1:0] rx_dc_llid;
    logic       rx_dc_nesn;
    logic       rx_dc_sn;
    logic       rx_dc_md;
    logic       rx_dc_cp;
    logic [7:0] rx_dc_cte_info;

    logic [7:0] rx_length_out;

    integer pass_count;
    integer fail_count;

    // ------------------------------------------------
    // DUT INSTANTIATION
    // ------------------------------------------------

    ble_pdu_header_assembler_parser DUT (

        .clk              (clk),
        .rst_n            (rst_n),

        .pkt_type_sel     (pkt_type_sel),

        .tx_adv_pdu_type  (tx_adv_pdu_type),
        .tx_adv_chsel     (tx_adv_chsel),
        .tx_adv_txadd     (tx_adv_txadd),
        .tx_adv_rxadd     (tx_adv_rxadd),

        .tx_dc_llid       (tx_dc_llid),
        .tx_dc_nesn       (tx_dc_nesn),
        .tx_dc_sn         (tx_dc_sn),
        .tx_dc_md         (tx_dc_md),
        .tx_dc_cp         (tx_dc_cp),
        .tx_dc_cte_info   (tx_dc_cte_info),

        .tx_payload_len   (tx_payload_len),
        .tx_start_en      (tx_start_en),

        .tx_header_bits   (tx_header_bits),
        .tx_header_len    (tx_header_len),
        .tx_header_valid  (tx_header_valid),

        .rx_bit_in        (rx_bit_in),
        .rx_bit_en        (rx_bit_en),

        .rx_header_done   (rx_header_done),

        .rx_adv_pdu_type  (rx_adv_pdu_type),
        .rx_adv_chsel     (rx_adv_chsel),
        .rx_adv_txadd     (rx_adv_txadd),
        .rx_adv_rxadd     (rx_adv_rxadd),

        .rx_dc_llid       (rx_dc_llid),
        .rx_dc_nesn       (rx_dc_nesn),
        .rx_dc_sn         (rx_dc_sn),
        .rx_dc_md         (rx_dc_md),
        .rx_dc_cp         (rx_dc_cp),
        .rx_dc_cte_info   (rx_dc_cte_info),

        .rx_length_out    (rx_length_out)

    );
initial begin
    $shm_open("wave.shm");
    $shm_probe("ACTMF");
    end
    // ------------------------------------------------
    // CLOCK GENERATION
    // ------------------------------------------------

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------
    // CHECK TASK
    // ------------------------------------------------

    task automatic check_result(
        input logic condition,
        input string test_name
    );

        begin
            if (condition === 1'b1) begin
                $display("PASS : %s", test_name);
                pass_count = pass_count + 1;
            end
            else begin
                $display("FAIL : %s", test_name);
                fail_count = fail_count + 1;
            end
        end

    endtask

    // ------------------------------------------------
    // TX TEST TASK
    // ------------------------------------------------

    task automatic tx_test(
        input logic [23:0] expected_header,
        input logic [4:0]  expected_length,
        input string       test_name
    );

        begin

            @(negedge clk);
            tx_start_en = 1'b1;

            @(posedge clk);
            #1;

            check_result(
                tx_header_valid == 1'b1,
                {test_name, " - Valid"}
            );

            check_result(
                tx_header_bits === expected_header,
                {test_name, " - Header Bits"}
            );

            check_result(
                tx_header_len === expected_length,
                {test_name, " - Header Length"}
            );

            @(negedge clk);
            tx_start_en = 1'b0;

            @(posedge clk);
            #1;

            check_result(
                tx_header_valid == 1'b0,
                {test_name, " - Valid Pulse"}
            );

        end

    endtask

    // ------------------------------------------------
    // RX SERIAL HEADER INPUT TASK
    //
    // Sends header LSB first.
    // First accepted bit starts the RX FSM.
    // ------------------------------------------------

    task automatic rx_test(
        input logic        packet_type,
        input logic [23:0] header,
        input integer      number_of_bits,
        input string       test_name
    );

        integer i;

        begin

            pkt_type_sel = packet_type;

            for (i = 0; i < number_of_bits; i = i + 1) begin

                @(negedge clk);

                rx_bit_in = header[i];
                rx_bit_en = 1'b1;

                @(posedge clk);
                #1;

                if (i == number_of_bits - 1) begin

                    check_result(
                        rx_header_done == 1'b1,
                        {test_name, " - Header Done"}
                    );

                end
                else begin

                    check_result(
                        rx_header_done == 1'b0,
                        {test_name, " - No Early Done"}
                    );

                end

            end

            @(negedge clk);
            rx_bit_en = 1'b0;
            rx_bit_in = 1'b0;

            @(posedge clk);
            #1;

        end

    endtask

    // ------------------------------------------------
    // MAIN TEST SEQUENCE
    // ------------------------------------------------

    initial begin

        pass_count = 0;
        fail_count = 0;

        rst_n = 1'b0;

        pkt_type_sel = 1'b0;

        tx_adv_pdu_type = 4'd0;
        tx_adv_chsel = 1'b0;
        tx_adv_txadd = 1'b0;
        tx_adv_rxadd = 1'b0;

        tx_dc_llid = 2'b00;
        tx_dc_nesn = 1'b0;
        tx_dc_sn = 1'b0;
        tx_dc_md = 1'b0;
        tx_dc_cp = 1'b0;
        tx_dc_cte_info = 8'd0;

        tx_payload_len = 8'd0;
        tx_start_en = 1'b0;

        rx_bit_in = 1'b0;
        rx_bit_en = 1'b0;

        // Reset
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        repeat (2) @(posedge clk);

        $display("\n====================================");
        $display(" BLE PDU HEADER ASSEMBLER/PARSER TB");
        $display("====================================\n");


        // ====================================================
        // TEST 1: ADVERTISING TX
        // ====================================================

        $display("\nTEST 1: ADVERTISING TX");

        pkt_type_sel = 1'b0;

        tx_adv_pdu_type = 4'd0;
        tx_adv_chsel = 1'b1;
        tx_adv_txadd = 1'b1;
        tx_adv_rxadd = 1'b0;
        tx_payload_len = 8'd20;

        // Expected:
        // [3:0]  = 0000
        // [4]    = 0
        // [5]    = 1
        // [6]    = 1
        // [7]    = 0
        // [15:8] = 20

        tx_test(
            {8'd0, 8'd20, 1'b0, 1'b1, 1'b1, 1'b0, 4'd0},
            5'd16,
            "Advertising TX"
        );


        // ====================================================
        // TEST 2: ADVERTISING RX
        // ====================================================

        $display("\nTEST 2: ADVERTISING RX");

        rx_test(
            1'b0,
            {8'd0, 8'd20, 1'b0, 1'b1, 1'b1, 1'b0, 4'd0},
            16,
            "Advertising RX"
        );

        check_result(
            rx_adv_pdu_type === 4'd0,
            "Advertising RX - PDU Type"
        );

        check_result(
            rx_adv_chsel === 1'b1,
            "Advertising RX - ChSel"
        );

        check_result(
            rx_adv_txadd === 1'b1,
            "Advertising RX - TxAdd"
        );

        check_result(
            rx_adv_rxadd === 1'b0,
            "Advertising RX - RxAdd"
        );

        check_result(
            rx_length_out === 8'd20,
            "Advertising RX - Length"
        );


        // ====================================================
        // TEST 3: ACL TX, CP = 0
        // ====================================================

        $display("\nTEST 3: ACL TX CP=0");

        pkt_type_sel = 1'b1;

        tx_dc_llid = 2'b10;
        tx_dc_nesn = 1'b1;
        tx_dc_sn = 1'b0;
        tx_dc_md = 1'b1;
        tx_dc_cp = 1'b0;

        tx_payload_len = 8'd12;

        tx_test(
            {
                8'd0,
                8'd12,
                2'b00,
                1'b0,
                1'b1,
                1'b0,
                1'b1,
                2'b10
            },
            5'd16,
            "ACL TX CP=0"
        );


        // ====================================================
        // TEST 4: ACL RX, CP = 0
        // ====================================================

        $display("\nTEST 4: ACL RX CP=0");

        rx_test(
            1'b1,
            {
                8'd0,
                8'd12,
                2'b00,
                1'b0,
                1'b1,
                1'b0,
                1'b1,
                2'b10
            },
            16,
            "ACL RX CP=0"
        );

        check_result(
            rx_dc_llid === 2'b10,
            "ACL RX CP=0 - LLID"
        );

        check_result(
            rx_dc_nesn === 1'b1,
            "ACL RX CP=0 - NESN"
        );

        check_result(
            rx_dc_sn === 1'b0,
            "ACL RX CP=0 - SN"
        );

        check_result(
            rx_dc_md === 1'b1,
            "ACL RX CP=0 - MD"
        );

        check_result(
            rx_dc_cp === 1'b0,
            "ACL RX CP=0 - CP"
        );

        check_result(
            rx_dc_cte_info === 8'd0,
            "ACL RX CP=0 - CTEInfo Absent"
        );

        check_result(
            rx_length_out === 8'd12,
            "ACL RX CP=0 - Length"
        );


        // ====================================================
        // TEST 5: ACL TX, CP = 1
        // ====================================================

        $display("\nTEST 5: ACL TX CP=1");

        pkt_type_sel = 1'b1;

        tx_dc_llid = 2'b10;
        tx_dc_nesn = 1'b0;
        tx_dc_sn = 1'b1;
        tx_dc_md = 1'b1;
        tx_dc_cp = 1'b1;

        tx_dc_cte_info = 8'hA5;
        tx_payload_len = 8'd30;

        tx_test(
            {
                8'hA5,
                8'd30,
                2'b00,
                1'b1,
                1'b1,
                1'b1,
                1'b0,
                2'b10
            },
            5'd24,
            "ACL TX CP=1"
        );


        // ====================================================
        // TEST 6: ACL RX, CP = 1
        // ====================================================

        $display("\nTEST 6: ACL RX CP=1");

        rx_test(
            1'b1,
            {
                8'hA5,
                8'd30,
                2'b00,
                1'b1,
                1'b1,
                1'b1,
                1'b0,
                2'b10
            },
            24,
            "ACL RX CP=1"
        );

        check_result(
            rx_dc_llid === 2'b10,
            "ACL RX CP=1 - LLID"
        );

        check_result(
            rx_dc_nesn === 1'b0,
            "ACL RX CP=1 - NESN"
        );

        check_result(
            rx_dc_sn === 1'b1,
            "ACL RX CP=1 - SN"
        );

        check_result(
            rx_dc_md === 1'b1,
            "ACL RX CP=1 - MD"
        );

        check_result(
            rx_dc_cp === 1'b1,
            "ACL RX CP=1 - CP"
        );

        check_result(
            rx_dc_cte_info === 8'hA5,
            "ACL RX CP=1 - CTEInfo"
        );

        check_result(
            rx_length_out === 8'd30,
            "ACL RX CP=1 - Length"
        );


        // ====================================================
        // FINAL SUMMARY
        // ====================================================

        $display("\n====================================");
        $display("             TEST SUMMARY");
        $display("====================================");

        $display("TOTAL PASSED : %0d", pass_count);
        $display("TOTAL FAILED : %0d", fail_count);

        if (fail_count == 0)
            $display("\nALL TESTS PASSED");
        else
            $display("\nSOME TESTS FAILED");

        $display("====================================\n");

        $finish;

    end

endmodule

