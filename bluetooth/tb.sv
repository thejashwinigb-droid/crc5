/*module tb_serial_crc24;

    reg         clk;
    reg         rst_n;
    reg         preset_en;
    reg  [23:0] preset_val;
    reg         bit_en;
    reg         din;
    reg         last_bit;
    reg  [23:0] rx_crc_field;
    reg         rx_compare_en;

    wire [23:0] crc_out;
    wire        crc_done;
    wire        crc_match;

    reg  [23:0] expected_crc;
    reg  [79:0] pdu;

    integer i;
    integer errors;
    integer bit_count;

    // DUT
    serial_crc24 dut (
        .clk           (clk),
        .rst_n          (rst_n),
        .preset_en      (preset_en),
        .preset_val     (preset_val),
        .bit_en         (bit_en),
        .din            (din),
        .last_bit       (last_bit),
        .crc_out        (crc_out),
        .crc_done       (crc_done),
        .rx_crc_field   (rx_crc_field),
        .rx_compare_en  (rx_compare_en),
        .crc_match      (crc_match)
    );



 initial begin
    $shm_open("wave.shm");
    $shm_probe("ACTMF");
    end

    // Clock: 10 ns period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Reference model for the documented CRC equations
    function [23:0] ref_crc_step;
        input [23:0] current_crc;
        input        data_bit;

        reg feedback;
        reg [23:0] shifted;

        begin
            feedback = current_crc[23] ^ data_bit;
            shifted  = {current_crc[22:0], 1'b0};

            if (feedback)
                ref_crc_step = shifted ^ 24'h00065B;
            else
                ref_crc_step = shifted;
        end
    endfunction

    // Check CRC output against reference model
    task check_crc;
        begin
            if (crc_out !== expected_crc) begin
                $display(
                    "FAIL: CRC mismatch at time %0t: expected=%h actual=%h",
                    $time, expected_crc, crc_out
                );
                errors = errors + 1;
            end
        end
    endtask

    // Load initial CRC
    task load_crc;
        input [23:0] initial_value;

        begin
            @(negedge clk);
            preset_en  = 1'b1;
            preset_val = initial_value;
            bit_en     = 1'b0;
            last_bit   = 1'b0;

            @(posedge clk);
            #1;
            expected_crc = initial_value;

            check_crc;

            if (crc_done !== 1'b0) begin
                $display("FAIL: crc_done asserted during preset");
                errors = errors + 1;
            end

            @(negedge clk);
            preset_en = 1'b0;
        end
    endtask

    // Send one serial input bit and check the CRC
    task send_bit;
        input data_bit;
        input is_last;

        begin
            @(negedge clk);
            bit_en   = 1'b1;
            din      = data_bit;
            last_bit = is_last;

            @(posedge clk);
            #1;

            expected_crc = ref_crc_step(
                expected_crc, data_bit
            );

            check_crc;

            if (is_last) begin
                if (crc_done !== 1'b1) begin
                    $display("FAIL: crc_done not asserted");
                    errors = errors + 1;
                end
            end
            else begin
                if (crc_done !== 1'b0) begin
                    $display("FAIL: crc_done asserted too early");
                    errors = errors + 1;
                end
            end

            bit_count = bit_count + 1;
        end
    endtask

    // Test sequence
    initial begin
        rst_n         = 1'b0;
        preset_en     = 1'b0;
        preset_val    = 24'h000000;
        bit_en        = 1'b0;
        din           = 1'b0;
        last_bit      = 1'b0;
        rx_crc_field  = 24'h000000;
        rx_compare_en = 1'b0;
        expected_crc  = 24'h000000;
        errors        = 0;
        bit_count     = 0;

        // Example 80-bit PDU test pattern
        pdu = 80'h0111A511A51CDEF0123;

        // -------------------------------
        // TEST 1: Asynchronous reset
        // -------------------------------
        #2;
        if (crc_out !== 24'h000000) begin
            $display("FAIL: reset value incorrect");
            errors = errors + 1;
        end

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // -------------------------------
        // TEST 2: Load advertising CRC init
        // -------------------------------
        load_crc(24'h555555);

        if (crc_out !== 24'h555555) begin
            $display("FAIL: initial CRC is incorrect");
            errors = errors + 1;
        end

        // -------------------------------
        // TEST 3: Process 80 PDU bits
        // LSB of pdu is processed first
        // -------------------------------
        for (i = 0; i < 80; i = i + 1) begin
            if (i == 79)
                send_bit(pdu[i], 1'b1);
            else
                send_bit(pdu[i], 1'b0);
        end

        $display("Processed bits = %0d", bit_count);
        $display("Computed CRC   = 0x%06h", crc_out);

        // -------------------------------
        // TEST 4: CRC hold when bit_en = 0
        // -------------------------------
        @(negedge clk);
        bit_en   = 1'b0;
        last_bit = 1'b0;

        @(posedge clk);
        #1;

        check_crc;

        if (crc_done !== 1'b0) begin
            $display("FAIL: crc_done did not clear");
            errors = errors + 1;
        end

        // -------------------------------
        // TEST 5: RX CRC matching
        // -------------------------------
        rx_crc_field  = expected_crc;
        rx_compare_en = 1'b1;

        #1;
        if (crc_match !== 1'b1) begin
            $display("FAIL: correct RX CRC did not match");
            errors = errors + 1;
        end
        else begin
            $display("PASS: RX CRC match");
        end

        // -------------------------------
        // TEST 6: RX CRC mismatch
        // -------------------------------
        rx_crc_field = expected_crc ^ 24'h000001;

        #1;
        if (crc_match !== 1'b0) begin
            $display("FAIL: incorrect RX CRC matched");
            errors = errors + 1;
        end
        else begin
            $display("PASS: RX CRC mismatch detected");
        end

        // -------------------------------
        // TEST 7: Comparison disabled
        // -------------------------------
        rx_compare_en = 1'b0;

        #1;
        if (crc_match !== 1'b0) begin
            $display("FAIL: comparison enable not respected");
            errors = errors + 1;
        end

        // -------------------------------
        // Final result
        // -------------------------------
        if (errors == 0) begin
            $display("--------------------------------");
            $display("ALL TESTS PASSED");
            $display("--------------------------------");
        end
        else begin
            $display("--------------------------------");
            $display("TESTS FAILED: %0d errors", errors);
            $display("--------------------------------");
        end

        $finish ;
    end

endmodule */




/*module tb_serial_crc24;

    reg         clk;
    reg         rst_n;
    reg         preset_en;
    reg  [23:0] preset_val;
    reg         bit_en;
    reg         din;
    reg         last_bit;
    reg  [23:0] rx_crc_field;
    reg         rx_compare_en;

    wire [23:0] crc_out;
    wire        crc_done;
    wire        crc_match;

    reg  [23:0] expected_crc;
    reg  [79:0] pdu;
    reg  [79:0] random_pdu;

    integer i;
    integer j;
    integer errors;
    integer bit_count;

    // ------------------------------------------------
    // DUT INSTANTIATION
    // ------------------------------------------------

    serial_crc24 dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .preset_en     (preset_en),
        .preset_val    (preset_val),
        .bit_en        (bit_en),
        .din           (din),
        .last_bit      (last_bit),
        .crc_out       (crc_out),
        .crc_done      (crc_done),
        .rx_crc_field  (rx_crc_field),
        .rx_compare_en (rx_compare_en),
        .crc_match     (crc_match)
    );

    // ------------------------------------------------
    // WAVEFORM DUMP
    // ------------------------------------------------

    initial begin
    
        // For Cadence SimVision, you can use:
         $shm_open("wave1.shm");
        $shm_probe("ACTMF");
    end

    // ------------------------------------------------
    // CLOCK GENERATION
    // 10 ns clock period
    // ------------------------------------------------

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------
    // REFERENCE CRC MODEL
    // Uses the same documented recurrence as the DUT.
    // ------------------------------------------------

    function [23:0] ref_crc_step;

        input [23:0] current_crc;
        input        data_bit;

        reg feedback;
        reg [23:0] shifted;

        begin
            feedback = current_crc[23] ^ data_bit;

            shifted = {current_crc[22:0], 1'b0};

            if (feedback)
                ref_crc_step = shifted ^ 24'h00065B;
            else
                ref_crc_step = shifted;
        end

    endfunction

    // ------------------------------------------------
    // CHECK CRC OUTPUT
    // ------------------------------------------------

    task check_crc;

        begin
            if (crc_out !== expected_crc) begin

                $display(
                    "FAIL: CRC mismatch at time %0t",
                    $time
                );

                $display(
                    "Expected = %06h, Actual = %06h",
                    expected_crc, crc_out
                );

                errors = errors + 1;
            end
        end

    endtask

    // ------------------------------------------------
    // LOAD INITIAL CRC
    // ------------------------------------------------

    task load_crc;

        input [23:0] initial_value;

        begin

            @(negedge clk);

            preset_en  = 1'b1;
            preset_val = initial_value;

            bit_en   = 1'b0;
            last_bit = 1'b0;

            @(posedge clk);
            #1;

            expected_crc = initial_value;

            check_crc;

            if (crc_done !== 1'b0) begin

                $display("FAIL: crc_done asserted during preset");

                errors = errors + 1;

            end

            @(negedge clk);

            preset_en = 1'b0;

        end

    endtask

    // ------------------------------------------------
    // SEND ONE SERIAL INPUT BIT
    // ------------------------------------------------

    task send_bit;

        input data_bit;
        input is_last;

        begin

            @(negedge clk);

            bit_en   = 1'b1;
            din      = data_bit;
            last_bit = is_last;

            @(posedge clk);
            #1;

            expected_crc =
                ref_crc_step(expected_crc, data_bit);

            check_crc;

            if (is_last) begin

                if (crc_done !== 1'b1) begin

                    $display("FAIL: crc_done not asserted");

                    errors = errors + 1;

                end

            end
            else begin

                if (crc_done !== 1'b0) begin

                    $display("FAIL: crc_done asserted too early");

                    errors = errors + 1;

                end

            end

            bit_count = bit_count + 1;

        end

    endtask

    // ------------------------------------------------
    // PROCESS A COMPLETE PDU
    // Bits are processed LSB first.
    // ------------------------------------------------

    task run_pdu;

        input [79:0] data;
        input integer nbits;
        input [23:0] initial_value;

        integer idx;

        begin

            load_crc(initial_value);

            for (idx = 0; idx < nbits; idx = idx + 1) begin

                if (idx == nbits - 1)
                    send_bit(data[idx], 1'b1);
                else
                    send_bit(data[idx], 1'b0);

            end

            $display("--------------------------------");
            $display("PDU length = %0d bits", nbits);
            $display("Initial CRC = %06h", initial_value);
            $display("Computed CRC = %06h", crc_out);
            $display("--------------------------------");

        end

    endtask

    // ------------------------------------------------
    // IDLE CYCLE / CHECK CRC HOLD
    // ------------------------------------------------

    task idle_cycle;

        begin

            @(negedge clk);

            bit_en   = 1'b0;
            last_bit = 1'b0;

            @(posedge clk);
            #1;

            check_crc;

            if (crc_done !== 1'b0) begin

                $display("FAIL: crc_done did not clear");

                errors = errors + 1;

            end

        end

    endtask

    // ------------------------------------------------
    // ASYNCHRONOUS RESET TASK
    // ------------------------------------------------

    task apply_reset;

        begin

            @(negedge clk);

            rst_n = 1'b0;

            #1;

            expected_crc = 24'h000000;

            if (crc_out !== 24'h000000 ||
                crc_done !== 1'b0) begin

                $display("FAIL: Asynchronous reset");

                errors = errors + 1;

            end
            else begin

                $display("PASS: Asynchronous reset");

            end

            bit_en       = 1'b0;
            last_bit     = 1'b0;
            preset_en    = 1'b0;
            rx_compare_en = 1'b0;

            @(negedge clk);

            rst_n = 1'b1;

        end

    endtask

    // ------------------------------------------------
    // MAIN TEST SEQUENCE
    // ------------------------------------------------

    initial begin

        // Initialize all signals

        rst_n          = 1'b1;
        preset_en      = 1'b0;
        preset_val     = 24'h000000;

        bit_en         = 1'b0;
        din            = 1'b0;
        last_bit       = 1'b0;

        rx_crc_field   = 24'h000000;
        rx_compare_en  = 1'b0;

        expected_crc   = 24'h000000;

        errors         = 0;
        bit_count      = 0;

        pdu            = 80'h0111A511A51CDEF0123;
        random_pdu     = 80'h0;

        // ============================================
        // TEST 1: ASYNCHRONOUS RESET
        // ============================================

        $display("\nTEST 1: Asynchronous reset");

        #2;
        rst_n = 1'b0;

        #1;

        if (crc_out !== 24'h000000 ||
            crc_done !== 1'b0) begin

            $display("FAIL: Reset value incorrect");

            errors = errors + 1;

        end
        else begin

            $display("PASS: Reset");

        end

        repeat (2) @(negedge clk);

        rst_n = 1'b1;

        // ============================================
        // TEST 2: ADVERTISING CRC INITIALIZATION
        // ============================================

        $display("\nTEST 2: Advertising CRC initialization");

        load_crc(24'h555555);

        if (crc_out !== 24'h555555) begin

            $display("FAIL: Advertising CRC initialization");

            errors = errors + 1;

        end
        else begin

            $display("PASS: Advertising CRC initialization");

        end

        // ============================================
        // TEST 3: 80-BIT PDU PROCESSING
        // ============================================

        $display("\nTEST 3: 80-bit PDU processing");

        run_pdu(
            80'h0111A511A51CDEF0123,
            80,
            24'h555555
        );

        $display("PASS: 80-bit PDU processing");

        // ============================================
        // TEST 4: CRC HOLD WHEN bit_en = 0
        // ============================================

        $display("\nTEST 4: CRC hold");

        idle_cycle;

        $display("PASS: CRC hold");

        // ============================================
        // TEST 5: RX CRC MATCH
        // ============================================

        $display("\nTEST 5: RX CRC match");

        rx_crc_field  = expected_crc;
        rx_compare_en = 1'b1;

        #1;

        if (crc_match !== 1'b1) begin

            $display("FAIL: Correct RX CRC did not match");

            errors = errors + 1;

        end
        else begin

            $display("PASS: RX CRC match");

        end

        // ============================================
        // TEST 6: RX CRC MISMATCH
        // ============================================

        $display("\nTEST 6: RX CRC mismatch");

        rx_crc_field = expected_crc ^ 24'h000001;

        #1;

        if (crc_match !== 1'b0) begin

            $display("FAIL: Incorrect RX CRC matched");

            errors = errors + 1;

        end
        else begin

            $display("PASS: RX CRC mismatch");

        end

        // ============================================
        // TEST 7: COMPARISON DISABLED
        // ============================================

        $display("\nTEST 7: Comparison disabled");

        rx_crc_field  = expected_crc;
        rx_compare_en = 1'b0;

        #1;

        if (crc_match !== 1'b0) begin

            $display("FAIL: Comparison enable not respected");

            errors = errors + 1;

        end
        else begin

            $display("PASS: Comparison disabled");

        end

        // ============================================
        // TEST 8: PRESET PRIORITY
        // preset_en and bit_en both high
        // ============================================

        $display("\nTEST 8: Preset priority");

        @(negedge clk);

        preset_en  = 1'b1;
        preset_val = 24'hABCDEF;

        bit_en     = 1'b1;
        din        = 1'b1;
        last_bit   = 1'b1;

        @(posedge clk);
        #1;

        expected_crc = 24'hABCDEF;

        if (crc_out !== expected_crc) begin

            $display("FAIL: Preset priority");

            errors = errors + 1;

        end
        else if (crc_done !== 1'b0) begin

            $display("FAIL: crc_done asserted during preset");

            errors = errors + 1;

        end
        else begin

            $display("PASS: Preset priority");

        end

        @(negedge clk);

        preset_en = 1'b0;
        bit_en    = 1'b0;
        last_bit  = 1'b0;

        // ============================================
        // TEST 9: last_bit = 1 WITHOUT bit_en
        // ============================================

        $display("\nTEST 9: Last bit without bit enable");

        @(negedge clk);

        bit_en   = 1'b0;
        last_bit = 1'b1;

        @(posedge clk);
        #1;

        if (crc_done !== 1'b0) begin

            $display("FAIL: crc_done asserted without bit_en");

            errors = errors + 1;

        end
        else begin

            $display("PASS: No completion without bit_en");

        end

        @(negedge clk);

        last_bit = 1'b0;

        // ============================================
        // TEST 10: RESET DURING CRC CALCULATION
        // ============================================

        $display("\nTEST 10: Reset during calculation");

        load_crc(24'h555555);

        @(negedge clk);

        bit_en = 1'b1;
        din    = 1'b1;

        @(posedge clk);
        #2;

        // Assert reset between clock edges

        rst_n = 1'b0;

        #1;

        expected_crc = 24'h000000;

        if (crc_out !== 24'h000000 ||
            crc_done !== 1'b0) begin

            $display("FAIL: Reset during calculation");

            errors = errors + 1;

        end
        else begin

            $display("PASS: Reset during calculation");

        end

        @(negedge clk);

        rst_n     = 1'b1;
        bit_en    = 1'b0;
        last_bit  = 1'b0;

        // ============================================
        // TEST 11: ONE-BIT PDU
        // ============================================

        $display("\nTEST 11: One-bit PDU");

        run_pdu(
            80'h00000000000000000001,
            1,
            24'h555555
        );

        // ============================================
        // TEST 12: 8-BIT PDU
        // ============================================

        $display("\nTEST 12: 8-bit PDU");

        run_pdu(
            80'h000000000000000000B2,
            8,
            24'h555555
        );

        // ============================================
        // TEST 13: ALL-ZERO PDU
        // ============================================

        $display("\nTEST 13: All-zero PDU");

        run_pdu(
            80'h00000000000000000000,
            80,
            24'h555555
        );

        // ============================================
        // TEST 14: ALL-ONE PDU
        // ============================================

        $display("\nTEST 14: All-one PDU");

        run_pdu(
            80'hFFFFFFFFFFFFFFFFFFFF,
            80,
            24'h555555
        );

        // ============================================
        // TEST 15: ALTERNATING 1010 PATTERN
        // ============================================

        $display("\nTEST 15: Alternating 1010 pattern");

        run_pdu(
            80'hAAAAAAAAAAAAAAAAAAAA,
            80,
            24'h555555
        );

        // ============================================
        // TEST 16: ALTERNATING 0101 PATTERN
        // ============================================

        $display("\nTEST 16: Alternating 0101 pattern");

        run_pdu(
            80'h55555555555555555555,
            80,
            24'h555555
        );

        // ============================================
        // TEST 17: DIFFERENT INITIAL CRC VALUE
        // ============================================

        $display("\nTEST 17: Different initial CRC");

        run_pdu(
            80'h123456789ABCDEF01234,
            80,
            24'h123456
        );

        // ============================================
        // TEST 18: INPUT GAPS / STALLS
        // ============================================

        $display("\nTEST 18: Input gaps");

        load_crc(24'h555555);

        send_bit(1'b0, 1'b0);
        send_bit(1'b1, 1'b0);

        // Insert two idle clock cycles

        idle_cycle;
        idle_cycle;

        // Continue processing

        send_bit(1'b1, 1'b0);
        send_bit(1'b0, 1'b1);

        $display("PASS: Input gaps");

        // ============================================
        // TEST 19: CONSECUTIVE PACKETS
        // ============================================

        $display("\nTEST 19: Consecutive packets");

        // First packet

        run_pdu(
            80'h0111A511A51CDEF0123,
            80,
            24'h555555
        );

        // Second packet with fresh initialization

        run_pdu(
            80'hFEDCBA9876543210FEDC,
            80,
            24'h555555
        );

        $display("PASS: Consecutive packets");

        // ============================================
        // TEST 20: RANDOM DATA PATTERNS
        // ============================================

        $display("\nTEST 20: Random PDU testing");

        for (j = 0; j < 10; j = j + 1) begin

            for (i = 0; i < 80; i = i + 1) begin

                random_pdu[i] = $random;

            end

            $display("Random test number = %0d", j + 1);

            run_pdu(
                random_pdu,
                80,
                24'h555555
            );

        end

        // ============================================
        // TEST 21: DIFFERENT PDU LENGTHS
        // ============================================

        $display("\nTEST 21: Different PDU lengths");

        run_pdu(
            80'h123456789ABCDEF01234,
            7,
            24'h555555
        );

        run_pdu(
            80'h123456789ABCDEF01234,
            16,
            24'h555555
        );

        run_pdu(
            80'h123456789ABCDEF01234,
            37,
            24'h555555
        );

        run_pdu(
            80'h123456789ABCDEF01234,
            80,
            24'h555555
        );

        // ============================================
        // FINAL RESULT
        // ============================================

        idle_cycle;

        $display("\n================================");
        $display("TOTAL BITS PROCESSED = %0d", bit_count);
        $display("TOTAL ERRORS         = %0d", errors);
        $display("================================");

        if (errors == 0) begin

            $display("ALL TESTS PASSED");

        end
        else begin

            $display("TESTS FAILED");

        end

        $finish;

    end

endmodule */


`timescale 1ns/1ps

module tb_serial_crc24;

    // ==============================================
    // SIGNAL DECLARATIONS
    // ==============================================

    reg         clk;
    reg         rst_n;
    reg         preset_en;
    reg  [23:0] preset_val;
    reg         bit_en;
    reg         din;
    reg         last_bit;
    reg  [23:0] rx_crc_field;
    reg         rx_compare_en;

    wire [23:0] crc_out;
    wire        crc_done;
    wire        crc_match;

    reg  [23:0] expected_crc;

    reg  [79:0] pdu;
    reg  [79:0] random_pdu;

    integer i;
    integer j;
    integer errors;
    integer tests_passed;
    integer tests_failed;
    integer test_count;
    integer bit_count;
    integer errors_before;

    // ==============================================
    // DUT INSTANTIATION
    // ==============================================

    serial_crc24 dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .preset_en     (preset_en),
        .preset_val    (preset_val),
        .bit_en        (bit_en),
        .din           (din),
        .last_bit      (last_bit),
        .crc_out       (crc_out),
        .crc_done      (crc_done),
        .rx_crc_field  (rx_crc_field),
        .rx_compare_en (rx_compare_en),
        .crc_match     (crc_match)
    );

    // ==============================================
    // WAVEFORM DUMP
    // ==============================================

    initial begin
        $shm_open("wave.shm");
        $shm_probe("ACTMF");
    end

    // ==============================================
    // CLOCK GENERATION
    // 10 ns clock period
    // ==============================================

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ==============================================
    // REFERENCE CRC MODEL
    // ==============================================

    function [23:0] ref_crc_step;

        input [23:0] current_crc;
        input        data_bit;

        reg feedback;
        reg [23:0] shifted;

        begin
            feedback = current_crc[23] ^ data_bit;

            shifted = {current_crc[22:0], 1'b0};

            if (feedback)
                ref_crc_step = shifted ^ 24'h00065B;
            else
                ref_crc_step = shifted;
        end

    endfunction

    // ==============================================
    // TEST RESULT REPORTING
    // ==============================================

    task start_test;

        input [8*80-1:0] test_name;

        begin
            test_count = test_count + 1;

            $display("\n----------------------------------------");
            $display("TEST %0d: %0s", test_count, test_name);
            $display("----------------------------------------");

            errors_before = errors;
        end

    endtask

    task finish_test;

        input [8*80-1:0] test_name;

        begin
            if (errors == errors_before) begin
                tests_passed = tests_passed + 1;
                $display("PASS: %0s", test_name);
            end
            else begin
                tests_failed = tests_failed + 1;
                $display("FAIL: %0s", test_name);
            end
        end

    endtask

    // ==============================================
    // CRC OUTPUT CHECK
    // ==============================================

    task check_crc;

        begin
            if (crc_out !== expected_crc) begin

                $display("FAIL: CRC mismatch at time %0t", $time);

                $display("Expected CRC = 0x%06h",
                         expected_crc);

                $display("Actual CRC   = 0x%06h",
                         crc_out);

                errors = errors + 1;

            end
        end

    endtask

    // ==============================================
    // CRC DONE CHECK
    // ==============================================

    task check_done;

        input expected_done;

        begin
            if (crc_done !== expected_done) begin

                $display("FAIL: crc_done mismatch at time %0t", $time);

                $display("Expected = %b, Actual = %b",
                         expected_done, crc_done);

                errors = errors + 1;

            end
        end

    endtask

    // ==============================================
    // LOAD CRC INITIAL VALUE
    // ==============================================

    task load_crc;

        input [23:0] initial_value;

        begin

            @(negedge clk);

            preset_en  = 1'b1;
            preset_val = initial_value;

            bit_en   = 1'b0;
            last_bit = 1'b0;

            @(posedge clk);
            #1;

            expected_crc = initial_value;

            check_crc;
            check_done(1'b0);

            @(negedge clk);

            preset_en = 1'b0;

        end

    endtask

    // ==============================================
    // SEND ONE SERIAL INPUT BIT
    // ==============================================

    task send_bit;

        input data_bit;
        input is_last;

        begin

            @(negedge clk);

            bit_en   = 1'b1;
            din      = data_bit;
            last_bit = is_last;

            @(posedge clk);
            #1;

            expected_crc =
                ref_crc_step(expected_crc, data_bit);

            bit_count = bit_count + 1;

            check_crc;

            if (is_last)
                check_done(1'b1);
            else
                check_done(1'b0);

        end

    endtask

    // ==============================================
    // IDLE CYCLE
    // ==============================================

    task idle_cycle;

        begin

            @(negedge clk);

            bit_en   = 1'b0;
            last_bit = 1'b0;

            @(posedge clk);
            #1;

            check_crc;
            check_done(1'b0);

        end

    endtask

    // ==============================================
    // PROCESS COMPLETE PDU
    // LSB FIRST
    // ==============================================

    task run_pdu;

        input [79:0] data;
        input integer nbits;
        input [23:0] initial_value;

        integer idx;

        begin

            bit_count = 0;

            $display("PDU length = %0d bits", nbits);

            load_crc(initial_value);

            for (idx = 0; idx < nbits; idx = idx + 1) begin

                if (idx == nbits - 1)
                    send_bit(data[idx], 1'b1);
                else
                    send_bit(data[idx], 1'b0);

            end

            $display("Processed bits = %0d", bit_count);
            $display("Initial CRC    = 0x%06h", initial_value);
            $display("Computed CRC   = 0x%06h", crc_out);
            $display("Expected CRC   = 0x%06h", expected_crc);

        end

    endtask

    // ==============================================
    // ASYNCHRONOUS RESET
    // ==============================================

    task apply_reset;

        begin

            #2;

            rst_n = 1'b0;

            #1;

            expected_crc = 24'h000000;

            if (crc_out !== 24'h000000) begin

                $display("FAIL: Reset CRC value incorrect");

                errors = errors + 1;

            end

            check_done(1'b0);

            @(negedge clk);

            rst_n = 1'b1;

        end

    endtask

    // ==============================================
    // MAIN TEST SEQUENCE
    // ==============================================

    initial begin

        // Initialize signals

        clk            = 1'b0;
        rst_n          = 1'b1;

        preset_en      = 1'b0;
        preset_val     = 24'h000000;

        bit_en         = 1'b0;
        din            = 1'b0;
        last_bit       = 1'b0;

        rx_crc_field   = 24'h000000;
        rx_compare_en  = 1'b0;

        expected_crc   = 24'h000000;

        errors         = 0;
        tests_passed   = 0;
        tests_failed   = 0;
        test_count     = 0;
        bit_count      = 0;

        pdu            = 80'h0111A511A51CDEF0123;
        random_pdu     = 80'h0;

        $display("\n");
        $display("========================================");
        $display("       SERIAL CRC-24 TESTBENCH");
        $display("========================================");

        // ==========================================
        // TEST 1: ASYNCHRONOUS RESET
        // ==========================================

        start_test("Asynchronous reset");

        apply_reset;

        finish_test("Asynchronous reset");

        // ==========================================
        // TEST 2: ADVERTISING CRC INITIALIZATION
        // ==========================================

        start_test("Advertising CRC initialization");

        load_crc(24'h555555);

        if (crc_out !== 24'h555555) begin
            $display("FAIL: Incorrect initial CRC");
            errors = errors + 1;
        end

        finish_test("Advertising CRC initialization");

        // ==========================================
        // TEST 3: NORMAL 80-BIT PDU
        // ==========================================

        start_test("Normal 80-bit PDU");

        run_pdu(
            80'h0111A511A51CDEF0123,
            80,
            24'h555555
        );

        finish_test("Normal 80-bit PDU");

        // ==========================================
        // TEST 4: CRC HOLD WHEN bit_en = 0
        // ==========================================

        start_test("CRC hold when bit_en is zero");

        idle_cycle;

        finish_test("CRC hold");

        // ==========================================
        // TEST 5: RX CRC MATCH
        // ==========================================

        start_test("RX CRC match");

        rx_crc_field  = expected_crc;
        rx_compare_en = 1'b1;

        #1;

        if (crc_match !== 1'b1) begin
            $display("FAIL: RX CRC match");
            errors = errors + 1;
        end

        finish_test("RX CRC match");

        // ==========================================
        // TEST 6: RX CRC MISMATCH
        // ==========================================

        start_test("RX CRC mismatch");

        rx_crc_field = expected_crc ^ 24'h000001;

        #1;

        if (crc_match !== 1'b0) begin
            $display("FAIL: RX CRC mismatch");
            errors = errors + 1;
        end

        finish_test("RX CRC mismatch");

        // ==========================================
        // TEST 7: RX COMPARISON DISABLED
        // ==========================================

        start_test("RX comparison disabled");

        rx_crc_field  = expected_crc;
        rx_compare_en = 1'b0;

        #1;

        if (crc_match !== 1'b0) begin
            $display("FAIL: Comparison disabled");
            errors = errors + 1;
        end

        finish_test("RX comparison disabled");

        // ==========================================
        // TEST 8: PRESET PRIORITY
        // ==========================================

        start_test("Preset priority over bit_en");

        @(negedge clk);

        preset_en  = 1'b1;
        preset_val = 24'hABCDEF;

        bit_en     = 1'b1;
        din        = 1'b1;
        last_bit   = 1'b1;

        @(posedge clk);
        #1;

        expected_crc = 24'hABCDEF;

        check_crc;
        check_done(1'b0);

        @(negedge clk);

        preset_en = 1'b0;
        bit_en    = 1'b0;
        last_bit  = 1'b0;

        finish_test("Preset priority");

        // ==========================================
        // TEST 9: last_bit = 1 WITHOUT bit_en
        // ==========================================

        start_test("last_bit without bit_en");

        @(negedge clk);

        bit_en   = 1'b0;
        last_bit = 1'b1;

        @(posedge clk);
        #1;

        check_crc;
        check_done(1'b0);

        @(negedge clk);

        last_bit = 1'b0;

        finish_test("last_bit without bit_en");

        // ==========================================
        // TEST 10: RESET DURING CRC CALCULATION
        // ==========================================

        start_test("Reset during CRC calculation");

        load_crc(24'h555555);

        @(negedge clk);

        bit_en = 1'b1;
        din    = 1'b1;

        @(posedge clk);
        #2;

        rst_n = 1'b0;

        #1;

        expected_crc = 24'h000000;

        if (crc_out !== 24'h000000) begin
            $display("FAIL: Reset during calculation");
            errors = errors + 1;
        end

        check_done(1'b0);

        @(negedge clk);

        rst_n     = 1'b1;
        bit_en    = 1'b0;
        last_bit  = 1'b0;

        finish_test("Reset during calculation");

        // ==========================================
        // TEST 11: ONE-BIT PDU
        // ==========================================

        start_test("One-bit PDU");

        run_pdu(
            80'h00000000000000000001,
            1,
            24'h555555
        );

        finish_test("One-bit PDU");

        // ==========================================
        // TEST 12: 8-BIT PDU - 0xB2
        // ==========================================

        start_test("8-bit PDU - 0xB2");

        run_pdu(
            80'h000000000000000000B2,
            8,
            24'h555555
        );

        finish_test("8-bit PDU");

        // ==========================================
        // TEST 13: ALL-ZERO PDU
        // ==========================================

        start_test("All-zero PDU");

        run_pdu(
            80'h00000000000000000000,
            80,
            24'h555555
        );

        finish_test("All-zero PDU");

        // ==========================================
        // TEST 14: ALL-ONE PDU
        // ==========================================

        start_test("All-one PDU");

        run_pdu(
            80'hFFFFFFFFFFFFFFFFFFFF,
            80,
            24'h555555
        );

        finish_test("All-one PDU");

        // ==========================================
        // TEST 15: ALTERNATING 1010
        // ==========================================

        start_test("Alternating 1010 pattern");

        run_pdu(
            80'hAAAAAAAAAAAAAAAAAAAA,
            80,
            24'h555555
        );

        finish_test("Alternating 1010 pattern");

        // ==========================================
        // TEST 16: ALTERNATING 0101
        // ==========================================

        start_test("Alternating 0101 pattern");

        run_pdu(
            80'h55555555555555555555,
            80,
            24'h555555
        );

        finish_test("Alternating 0101 pattern");

        // ==========================================
        // TEST 17: DIFFERENT INITIAL CRC
        // ==========================================

        start_test("Different initial CRC");

        run_pdu(
            80'h123456789ABCDEF01234,
            80,
            24'h123456
        );

        finish_test("Different initial CRC");

        // ==========================================
        // TEST 18: INPUT GAPS / STALLS
        // ==========================================

        start_test("Input gaps and stalls");

        bit_count = 0;

        load_crc(24'h555555);

        send_bit(1'b0, 1'b0);
        send_bit(1'b1, 1'b0);

        idle_cycle;
        idle_cycle;

        send_bit(1'b1, 1'b0);
        send_bit(1'b0, 1'b1);

        $display("Active bits processed = %0d", bit_count);

        finish_test("Input gaps and stalls");

        // ==========================================
        // TEST 19: CONSECUTIVE PACKETS
        // ==========================================

        start_test("Consecutive packets");

        run_pdu(
            80'h0111A511A51CDEF0123,
            80,
            24'h555555
        );

        run_pdu(
            80'hFEDCBA9876543210FEDC,
            80,
            24'h555555
        );

        finish_test("Consecutive packets");

        // ==========================================
        // TEST 20: RANDOM 80-BIT PDUs
        // ==========================================

        start_test("Random PDU testing");

        for (j = 0; j < 10; j = j + 1) begin

            for (i = 0; i < 80; i = i + 1) begin
                random_pdu[i] = $random;
            end

            $display("\nRandom PDU %0d", j + 1);

            run_pdu(
                random_pdu,
                80,
                24'h555555
            );

            if (crc_done !== 1'b1) begin
                $display("FAIL: Random PDU %0d completion", j + 1);
                errors = errors + 1;
            end
            else begin
                $display("PASS: Random PDU %0d completion", j + 1);
            end

        end

        finish_test("Random PDU testing");

        // ==========================================
        // TEST 21: DIFFERENT PDU LENGTHS
        // ==========================================

        start_test("Different PDU lengths");

        pdu = 80'h123456789ABCDEF01234;

        run_pdu(pdu, 7, 24'h555555);

        run_pdu(pdu, 16, 24'h555555);

        run_pdu(pdu, 37, 24'h555555);

        run_pdu(pdu, 80, 24'h555555);

        finish_test("Different PDU lengths");

        // ==========================================
        // FINAL SUMMARY
        // ==========================================

        idle_cycle;

        $display("\n");
        $display("========================================");
        $display("       SERIAL CRC-24 TEST SUMMARY");
        $display("========================================");

        $display("Total test groups = %0d", test_count);
        $display("Tests passed      = %0d", tests_passed);
        $display("Tests failed      = %0d", tests_failed);
        $display("Total errors      = %0d", errors);

        $display("----------------------------------------");

        if (errors == 0 && tests_failed == 0) begin

            $display("          ALL TESTS PASSED");

        end
        else begin

            $display("          TESTBENCH FAILED");

        end

        $display("========================================");

        $finish;

    end

endmodule




