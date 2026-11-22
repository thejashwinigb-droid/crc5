module tb_ble_pdu_header_rx;

    // -------------------------------------------------
    // DUT SIGNALS
    // -------------------------------------------------

    logic clk;
    logic rst_n;
    logic pkt_type_sel;

    logic rx_bit_in;
    logic rx_bit_en;

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

    // -------------------------------------------------
    // DUT INSTANTIATION
    // -------------------------------------------------

    ble_pdu_header_rx dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .pkt_type_sel     (pkt_type_sel),

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
    $shm_open("wave4.shm");
    $shm_probe("ACTMF");
    end

    // -------------------------------------------------
    // CLOCK GENERATION
    // -------------------------------------------------

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // -------------------------------------------------
    // TASK: SEND HEADER SERIALly, LSB FIRST
    // -------------------------------------------------

    task automatic send_header (
        input logic        packet_type,
        input logic [23:0] header_data,
        input integer      number_of_bits
    );

        integer i;
        begin
            @(negedge clk);

            pkt_type_sel = packet_type;

            for (i = 0; i < number_of_bits; i = i + 1) begin

                rx_bit_in = header_data[i];
                rx_bit_en = 1'b1;

                @(posedge clk);
                #1;

                // Header must complete on the final bit
                if (i == number_of_bits - 1) begin

                    if (rx_header_done !== 1'b1) begin
                        $display(
                            "FAIL: rx_header_done not asserted on final bit"
                        );
                        fail_count = fail_count + 1;
                    end
                end
                else begin

                    if (rx_header_done !== 1'b0) begin
                        $display(
                            "FAIL: rx_header_done asserted too early at bit %0d",
                            i
                        );
                        fail_count = fail_count + 1;
                    end

                end

                @(negedge clk);
            end

            rx_bit_en = 1'b0;
            rx_bit_in = 1'b0;

        end
    endtask

    // -------------------------------------------------
    // TASK: CHECK ADVERTISING HEADER
    // -------------------------------------------------

    task automatic check_adv (
        input string      test_name,
        input logic [3:0] expected_type,
        input logic       expected_chsel,
        input logic       expected_txadd,
        input logic       expected_rxadd,
        input logic [7:0] expected_length
    );

        logic test_pass;

        begin
            test_pass = 1'b1;

            if (rx_adv_pdu_type !== expected_type)
                test_pass = 1'b0;

            if (rx_adv_chsel !== expected_chsel)
                test_pass = 1'b0;

            if (rx_adv_txadd !== expected_txadd)
                test_pass = 1'b0;

            if (rx_adv_rxadd !== expected_rxadd)
                test_pass = 1'b0;

            if (rx_length_out !== expected_length)
                test_pass = 1'b0;

            if (test_pass) begin
                $display("PASS: %s", test_name);
                pass_count = pass_count + 1;
            end
            else begin
                $display("FAIL: %s", test_name);

                $display("  PDU TYPE : Expected %h, Actual %h",
                         expected_type, rx_adv_pdu_type);

                $display("  CHSEL    : Expected %b, Actual %b",
                         expected_chsel, rx_adv_chsel);

                $display("  TXADD    : Expected %b, Actual %b",
                         expected_txadd, rx_adv_txadd);

                $display("  RXADD    : Expected %b, Actual %b",
                         expected_rxadd, rx_adv_rxadd);

                $display("  LENGTH   : Expected %h, Actual %h",
                         expected_length, rx_length_out);

                fail_count = fail_count + 1;
            end
        end
    endtask

    // -------------------------------------------------
    // TASK: CHECK ACL HEADER
    // -------------------------------------------------

    task automatic check_acl (
        input string      test_name,
        input logic [1:0] expected_llid,
        input logic       expected_nesn,
        input logic       expected_sn,
        input logic       expected_md,
        input logic       expected_cp,
        input logic [7:0] expected_cte,
        input logic [7:0] expected_length
    );

        logic test_pass;

        begin
            test_pass = 1'b1;

            if (rx_dc_llid !== expected_llid)
                test_pass = 1'b0;

            if (rx_dc_nesn !== expected_nesn)
                test_pass = 1'b0;

            if (rx_dc_sn !== expected_sn)
                test_pass = 1'b0;

            if (rx_dc_md !== expected_md)
                test_pass = 1'b0;

            if (rx_dc_cp !== expected_cp)
                test_pass = 1'b0;

            if (rx_dc_cte_info !== expected_cte)
                test_pass = 1'b0;

            if (rx_length_out !== expected_length)
                test_pass = 1'b0;

            if (test_pass) begin
                $display("PASS: %s", test_name);
                pass_count = pass_count + 1;
            end
            else begin
                $display("FAIL: %s", test_name);

                $display("  LLID     : Expected %b, Actual %b",
                         expected_llid, rx_dc_llid);

                $display("  NESN     : Expected %b, Actual %b",
                         expected_nesn, rx_dc_nesn);

                $display("  SN       : Expected %b, Actual %b",
                         expected_sn, rx_dc_sn);

                $display("  MD       : Expected %b, Actual %b",
                         expected_md, rx_dc_md);

                $display("  CP       : Expected %b, Actual %b",
                         expected_cp, rx_dc_cp);

                $display("  CTEInfo  : Expected %h, Actual %h",
                         expected_cte, rx_dc_cte_info);

                $display("  LENGTH   : Expected %h, Actual %h",
                         expected_length, rx_length_out);

                fail_count = fail_count + 1;
            end
        end
    endtask

    // -------------------------------------------------
    // MAIN TEST SEQUENCE
    // -------------------------------------------------

    initial begin

        pass_count = 0;
        fail_count = 0;

        rst_n = 1'b0;
        pkt_type_sel = 1'b0;

        rx_bit_in = 1'b0;
        rx_bit_en = 1'b0;

        // Reset
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        repeat (2) @(negedge clk);

        $display("\n======================================");
        $display(" BLE PDU HEADER RX VERIFICATION");
        $display("======================================");

        // =============================================
        // TEST 1: ADV_IND
        // =============================================

        $display("\nTEST 1: ADV_IND");

        send_header(
            1'b0,
            {8'h00, 8'd20, 1'b0, 1'b0,
             1'b1, 1'b0, 4'b0000},
            16
        );

        check_adv(
            "ADV_IND HEADER",
            4'b0000,
            1'b1,
            1'b0,
            1'b0,
            8'd20
        );

        // =============================================
        // TEST 2: ADV_NONCONN_IND
        // =============================================

        $display("\nTEST 2: ADV_NONCONN_IND");

        send_header(
            1'b0,
            {8'h00, 8'd15, 1'b0, 1'b1,
             1'b0, 1'b0, 4'b0010},
            16
        );

        check_adv(
            "ADV_NONCONN_IND HEADER",
            4'b0010,
            1'b0,
            1'b1,
            1'b0,
            8'd15
        );

        // =============================================
        // TEST 3: ACL LLID=01, CP=0
        // =============================================

        $display("\nTEST 3: ACL LLID=01 CP=0");

        send_header(
            1'b1,
            {8'h00, 8'd0, 2'b00, 1'b0,
             1'b1, 1'b0, 1'b1, 2'b01},
            16
        );

        check_acl(
            "ACL LLID=01 CP=0",
            2'b01,
            1'b1,
            1'b0,
            1'b1,
            1'b0,
            8'h00,
            8'd0
        );

        // =============================================
        // TEST 4: ACL LLID=10, CP=0
        // =============================================

        $display("\nTEST 4: ACL LLID=10 CP=0");

        send_header(
            1'b1,
            {8'h00, 8'd12, 2'b00, 1'b0,
             1'b0, 1'b1, 1'b0, 2'b10},
            16
        );

        check_acl(
            "ACL LLID=10 CP=0",
            2'b10,
            1'b0,
            1'b1,
            1'b0,
            1'b0,
            8'h00,
            8'd12
        );

        // =============================================
        // TEST 5: ACL LLID=11, CP=1
        // =============================================

        $display("\nTEST 5: ACL LLID=11 CP=1");

        send_header(
            1'b1,
            {8'hA5, 8'd25, 2'b00, 1'b1,
             1'b1, 1'b1, 1'b1, 2'b11},
            24
        );

        check_acl(
            "ACL LLID=11 CP=1",
            2'b11,
            1'b1,
            1'b1,
            1'b1,
            1'b1,
            8'hA5,
            8'd25
        );

        // =============================================
        // FINAL SUMMARY
        // =============================================

        $display("\n======================================");
        $display(" RX VERIFICATION SUMMARY");
        $display("======================================");

        $display("TOTAL PASS : %0d", pass_count);
        $display("TOTAL FAIL : %0d", fail_count);

        if (fail_count == 0)
            $display("RESULT: ALL RX TESTS PASSED");
        else
            $display("RESULT: RX VERIFICATION FAILED");

        $display("======================================");

        #20;
        $finish;

    end

    // -------------------------------------------------
    // SIMULATION TIMEOUT
    // -------------------------------------------------

    initial begin
        #10000;
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule

