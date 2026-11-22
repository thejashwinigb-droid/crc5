

module tb_ble_pdu_header_tx;

    logic clk;
    logic rst_n;
    logic pkt_type_sel;

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

    logic [23:0] tx_header_bits;
    logic [4:0]  tx_header_len;
    logic        tx_header_valid;

    integer pass_count = 0;
    integer fail_count = 0;

    // DUT
    ble_pdu_header_tx dut (
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
        .tx_header_valid (tx_header_valid)
    );
initial begin
    $shm_open("wave3.shm");
    $shm_probe("ACTMF");
    end

    // Clock: 100 MHz
    initial clk = 0;
    always #5 clk = ~clk;

    // Assemble one TX header
    task automatic run_tx_test(
        input string test_name,
        input logic [23:0] expected_bits,
        input logic [4:0] expected_len
    );
        begin
            @(negedge clk);
            tx_start_en = 1'b1;

            @(posedge clk);
            #1;

            if ((tx_header_valid === 1'b1) &&
                (tx_header_bits === expected_bits) &&
                (tx_header_len === expected_len)) begin

                $display("PASS: %s", test_name);
                pass_count = pass_count + 1;
            end
            else begin
                $display("FAIL: %s", test_name);
                $display("  Expected bits = %h, Actual = %h",
                         expected_bits, tx_header_bits);
                $display("  Expected len  = %0d, Actual = %0d",
                         expected_len, tx_header_len);
                $display("  Valid         = %b", tx_header_valid);
                fail_count = fail_count + 1;
            end

            @(negedge clk);
            tx_start_en = 1'b0;

            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        rst_n = 0;
        pkt_type_sel = 0;

        tx_adv_pdu_type = 0;
        tx_adv_chsel = 0;
        tx_adv_txadd = 0;
        tx_adv_rxadd = 0;

        tx_dc_llid = 0;
        tx_dc_nesn = 0;
        tx_dc_sn = 0;
        tx_dc_md = 0;
        tx_dc_cp = 0;
        tx_dc_cte_info = 0;

        tx_payload_len = 0;
        tx_start_en = 0;

        repeat (3) @(negedge clk);
        rst_n = 1;

        // ------------------------------------
        // TEST 1: ADV_IND
        // ------------------------------------
        pkt_type_sel = 0;
        tx_adv_pdu_type = 4'b0000;
        tx_adv_chsel = 1;
        tx_adv_txadd = 0;
        tx_adv_rxadd = 0;
        tx_payload_len = 8'd20;

        run_tx_test(
            "TX_1 ADV_IND",
            {8'd0, 8'd20, 1'b0, 1'b0, 1'b1, 1'b0, 4'b0000},
            5'd16
        );

        // ------------------------------------
        // TEST 2: ADV_NONCONN_IND
        // ------------------------------------
        pkt_type_sel = 0;
        tx_adv_pdu_type = 4'b0010;
        tx_adv_chsel = 0;
        tx_adv_txadd = 1;
        tx_adv_rxadd = 0;
        tx_payload_len = 8'd15;

        run_tx_test(
            "TX_2 ADV_NONCONN_IND",
            {8'd0, 8'd15, 1'b0, 1'b1, 1'b0, 1'b0, 4'b0010},
            5'd16
        );

        // ------------------------------------
        // TEST 3: ACL LLID=01, CP=0
        // ------------------------------------
        pkt_type_sel = 1;
        tx_dc_llid = 2'b01;
        tx_dc_nesn = 1;
        tx_dc_sn = 0;
        tx_dc_md = 1;
        tx_dc_cp = 0;
        tx_payload_len = 8'd0;

        run_tx_test(
            "TX_3 ACL LLID=01 CP=0",
            {8'd0, 8'd0, 2'b00, 1'b0,
             1'b1, 1'b0, 1'b1, 2'b01},
            5'd16
        );

        // ------------------------------------
        // TEST 4: ACL LLID=10, CP=0
        // ------------------------------------
        pkt_type_sel = 1;
        tx_dc_llid = 2'b10;
        tx_dc_nesn = 0;
        tx_dc_sn = 1;
        tx_dc_md = 0;
        tx_dc_cp = 0;
        tx_payload_len = 8'd12;

        run_tx_test(
            "TX_4 ACL LLID=10 CP=0",
            {8'd0, 8'd12, 2'b00, 1'b0,
             1'b0, 1'b1, 1'b0, 2'b10},
            5'd16
        );

        // ------------------------------------
        // TEST 5: ACL LLID=11, CP=1
        // ------------------------------------
        pkt_type_sel = 1;
        tx_dc_llid = 2'b11;
        tx_dc_nesn = 1;
        tx_dc_sn = 1;
        tx_dc_md = 1;
        tx_dc_cp = 1;
        tx_dc_cte_info = 8'hA5;
        tx_payload_len = 8'd25;

        run_tx_test(
            "TX_5 ACL LLID=11 CP=1",
            {8'hA5, 8'd25, 2'b00, 1'b1,
             1'b1, 1'b1, 1'b1, 2'b11},
            5'd24
        );

        // ------------------------------------
        // SUMMARY
        // ------------------------------------
        $display("\n================================");
        $display("TX VERIFICATION SUMMARY");
        $display("PASS = %0d", pass_count);
        $display("FAIL = %0d", fail_count);
        $display("================================");

        if (fail_count == 0)
            $display("ALL TX TESTS PASSED");
        else
            $display("TX VERIFICATION FAILED");

        $finish;
    end

endmodule

