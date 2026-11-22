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

        $finish;
    end

endmodule */


module tb_ble_whitening_tx_rx;

    //================================================
    // 1. SIGNAL DECLARATIONS
    //================================================

    reg clk;
    reg rst_n;

    reg [5:0] channel_index;

    // TX signals
    reg        tx_init_en;
    reg        tx_bit_en;
    reg        tx_din;
    wire       tx_dout;
    wire       tx_valid;
    wire [6:0] tx_lfsr_state;

    // RX signals
    reg        rx_init_en;
    reg        rx_bit_en;
    reg        rx_din;
    wire       rx_dout;
    wire       rx_valid;
    wire [6:0] rx_lfsr_state;

    // Reference model
    reg [6:0] tx_ref_state;
    reg [6:0] rx_ref_state;

    // State snapshots
    reg [6:0] tx_state_before;
    reg [6:0] rx_state_before;

    // Data
    reg [7:0] expected_tx_data;
    reg [7:0] recovered_data;
    reg [7:0] random_data;

    // Counters
    integer errors;
    integer tests_passed;
    integer tests_failed;
    integer test_number;
    integer errors_before;
    integer i;
    integer j;

    // Reference calculation variables
    reg expected_tx_bit;
    reg expected_rx_bit;
    reg [6:0] next_tx_state;
    reg [6:0] next_rx_state;

    //================================================
    // 2. DUT INSTANTIATION
    //================================================

    ble_whitening_tx_rx DUT (

        .clk            (clk),
        .rst_n          (rst_n),

        .channel_index  (channel_index),

        .tx_init_en     (tx_init_en),
        .tx_bit_en      (tx_bit_en),
        .tx_din         (tx_din),
        .tx_dout        (tx_dout),
        .tx_valid       (tx_valid),
        .tx_lfsr_state  (tx_lfsr_state),

        .rx_init_en     (rx_init_en),
        .rx_bit_en      (rx_bit_en),
        .rx_din         (rx_din),
        .rx_dout        (rx_dout),
        .rx_valid       (rx_valid),
        .rx_lfsr_state  (rx_lfsr_state)

    );

    //================================================
    // 3. WAVEFORM
    //================================================

    initial begin
        $shm_open("wave_whitening.shm");
        $shm_probe("ACTMF");
    end

    //================================================
    // 4. CLOCK GENERATION
    //================================================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    //================================================
    // 5. REFERENCE LFSR FUNCTION
    //
    // Output bit  = state[0]
    // Shift right
    // Feedback mask = 7'h44
    //================================================

    function [6:0] lfsr_next;

        input [6:0] current_state;

        begin
            lfsr_next = (current_state >> 1) ^
                        (current_state[0] ? 7'h44 : 7'h00);
        end

    endfunction

    //================================================
    // 6. TEST REPORTING
    //================================================

    task start_test;

        input [8*80-1:0] test_name;

        begin
            test_number = test_number + 1;
            errors_before = errors;

            $display("\n========================================");
            $display("TEST %0d: %0s", test_number, test_name);
            $display("========================================");
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

    //================================================
    // 7. INITIALIZE TX AND RX
    //================================================

    task initialize_both;

        input [5:0] channel;

        begin
            @(negedge clk);

            channel_index = channel;

            tx_bit_en = 1'b0;
            rx_bit_en = 1'b0;

            tx_init_en = 1'b1;
            rx_init_en = 1'b1;

            @(posedge clk);
            #1;

            tx_ref_state = {1'b1, channel};
            rx_ref_state = {1'b1, channel};

            if (tx_lfsr_state !== tx_ref_state) begin
                $display("FAIL: TX initialization");
                $display("Expected = %b", tx_ref_state);
                $display("Actual   = %b", tx_lfsr_state);
                errors = errors + 1;
            end

            if (rx_lfsr_state !== rx_ref_state) begin
                $display("FAIL: RX initialization");
                $display("Expected = %b", rx_ref_state);
                $display("Actual   = %b", rx_lfsr_state);
                errors = errors + 1;
            end

            @(negedge clk);

            tx_init_en = 1'b0;
            rx_init_en = 1'b0;
        end

    endtask

    //================================================
    // 8. SEND ONE BYTE THROUGH TX AND RX
    //================================================

    task send_loopback_byte;

        input [7:0] data;

        integer bit_index;

        begin

            expected_tx_data = 8'h00;
            recovered_data   = 8'h00;

            $display("\nOriginal byte = 0x%02h", data);

            for (bit_index = 0; bit_index < 8;
                 bit_index = bit_index + 1) begin

                @(negedge clk);

                tx_bit_en = 1'b1;
                rx_bit_en = 1'b1;

                tx_din = data[bit_index];

                // Calculate expected TX output
                expected_tx_bit =
                    data[bit_index] ^ tx_ref_state[0];

                // Calculate expected RX output
                expected_rx_bit =
                    expected_tx_bit ^ rx_ref_state[0];

                // Calculate next reference states
                next_tx_state = lfsr_next(tx_ref_state);
                next_rx_state = lfsr_next(rx_ref_state);

                // RX receives whitened TX data
                rx_din = expected_tx_bit;

                expected_tx_data[bit_index] = expected_tx_bit;
                recovered_data[bit_index]   = expected_rx_bit;

                @(posedge clk);
                #1;

                // TX output check
                if (tx_valid !== 1'b1 ||
                    tx_dout !== expected_tx_bit) begin

                    $display("FAIL: TX output at bit %0d",
                             bit_index);

                    $display("Expected = %b Actual = %b",
                             expected_tx_bit, tx_dout);

                    errors = errors + 1;
                end

                // RX output check
                if (rx_valid !== 1'b1 ||
                    rx_dout !== expected_rx_bit) begin

                    $display("FAIL: RX output at bit %0d",
                             bit_index);

                    $display("Expected = %b Actual = %b",
                             expected_rx_bit, rx_dout);

                    errors = errors + 1;
                end

                // Update reference states
                tx_ref_state = next_tx_state;
                rx_ref_state = next_rx_state;

                // TX state check
                if (tx_lfsr_state !== tx_ref_state) begin

                    $display("FAIL: TX LFSR state at bit %0d",
                             bit_index);

                    $display("Expected = %b Actual = %b",
                             tx_ref_state, tx_lfsr_state);

                    errors = errors + 1;
                end

                // RX state check
                if (rx_lfsr_state !== rx_ref_state) begin

                    $display("FAIL: RX LFSR state at bit %0d",
                             bit_index);

                    $display("Expected = %b Actual = %b",
                             rx_ref_state, rx_lfsr_state);

                    errors = errors + 1;
                end

            end

            $display("Whitened byte = 0x%02h", expected_tx_data);
            $display("Recovered byte = 0x%02h", recovered_data);

            if (recovered_data !== data) begin
                $display("FAIL: Recovered byte mismatch");
                errors = errors + 1;
            end

        end

    endtask

    //================================================
    // 9. TX-ONLY TEST
    //================================================

    task send_tx_only_byte;

        input [7:0] data;

        reg expected_bit;
        reg [6:0] next_state;

        integer k;

        begin

            for (k = 0; k < 8; k = k + 1) begin

                @(negedge clk);

                tx_bit_en = 1'b1;
                rx_bit_en = 1'b0;

                tx_din = data[k];

                expected_bit = data[k] ^ tx_ref_state[0];
                next_state = lfsr_next(tx_ref_state);

                @(posedge clk);
                #1;

                if (tx_valid !== 1'b1 ||
                    tx_dout !== expected_bit) begin

                    $display("FAIL: TX-only output at bit %0d", k);
                    errors = errors + 1;

                end

                tx_ref_state = next_state;

                if (tx_lfsr_state !== tx_ref_state) begin
                    $display("FAIL: TX-only LFSR state");
                    errors = errors + 1;
                end

                if (rx_lfsr_state !== rx_ref_state) begin
                    $display("FAIL: RX changed during TX-only operation");
                    errors = errors + 1;
                end

            end

            @(negedge clk);
            tx_bit_en = 1'b0;

        end

    endtask

    //================================================
    // 10. RX-ONLY TEST
    //================================================

    task send_rx_only_byte;

        input [7:0] data;

        reg expected_bit;
        reg [6:0] next_state;

        integer k;

        begin

            for (k = 0; k < 8; k = k + 1) begin

                @(negedge clk);

                rx_bit_en = 1'b1;
                tx_bit_en = 1'b0;

                rx_din = data[k];

                expected_bit = data[k] ^ rx_ref_state[0];
                next_state = lfsr_next(rx_ref_state);

                @(posedge clk);
                #1;

                if (rx_valid !== 1'b1 ||
                    rx_dout !== expected_bit) begin

                    $display("FAIL: RX-only output at bit %0d", k);
                    errors = errors + 1;

                end

                rx_ref_state = next_state;

                if (rx_lfsr_state !== rx_ref_state) begin
                    $display("FAIL: RX-only LFSR state");
                    errors = errors + 1;
                end

                if (tx_lfsr_state !== tx_ref_state) begin
                    $display("FAIL: TX changed during RX-only operation");
                    errors = errors + 1;
                end

            end

            @(negedge clk);
            rx_bit_en = 1'b0;

        end

    endtask

    //================================================
    // 11. MAIN TEST SEQUENCE
    //================================================

    initial begin

        // Initialize counters
        errors       = 0;
        tests_passed = 0;
        tests_failed = 0;
        test_number  = 0;

        // Initialize inputs
        rst_n = 1'b0;

        channel_index = 6'd23;

        tx_init_en = 1'b0;
        tx_bit_en  = 1'b0;
        tx_din     = 1'b0;

        rx_init_en = 1'b0;
        rx_bit_en  = 1'b0;
        rx_din     = 1'b0;

        tx_ref_state = 7'b0;
        rx_ref_state = 7'b0;

        expected_tx_data = 8'h00;
        recovered_data = 8'h00;
        random_data = 8'h00;

        $display("\n");
        $display("========================================");
        $display(" BLE WHITENING / DEWHITENING TESTBENCH");
        $display("========================================");

        //========================================
        // TEST 1: RESET
        //========================================

        start_test("TX and RX asynchronous reset");

        repeat (2) @(negedge clk);

        if (tx_lfsr_state !== 7'b0000000 ||
            rx_lfsr_state !== 7'b0000000) begin

            $display("FAIL: Reset");
            errors = errors + 1;

        end

        @(negedge clk);
        rst_n = 1'b1;

        finish_test("TX and RX reset");

        //========================================
        // TEST 2: INITIALIZATION CHANNEL 23
        //========================================

        start_test("Initialization channel 23");

        initialize_both(6'd23);

        finish_test("Initialization channel 23");

        //========================================
        // TEST 3: ORIGINAL B2 BYTE
        //========================================

        start_test("Original B2 TX and RX loopback");

        send_loopback_byte(8'hB2);

        if (expected_tx_data !== 8'h1D) begin
            $display("FAIL: B2 whitened byte expected 1D");
            errors = errors + 1;
        end

        if (recovered_data !== 8'hB2) begin
            $display("FAIL: B2 recovery");
            errors = errors + 1;
        end

        finish_test("Original B2 TX and RX loopback");

        //========================================
        // TEST 4: ALL ZERO DATA
        //========================================

        start_test("All-zero input");

        initialize_both(6'd23);
        send_loopback_byte(8'h00);

        finish_test("All-zero input");

        //========================================
        // TEST 5: ALL ONE DATA
        //========================================

        start_test("All-one input");

        initialize_both(6'd23);
        send_loopback_byte(8'hFF);

        finish_test("All-one input");

        //========================================
        // TEST 6: ALTERNATING AA
        //========================================

        start_test("Alternating AA pattern");

        initialize_both(6'd23);
        send_loopback_byte(8'hAA);

        finish_test("Alternating AA pattern");

        //========================================
        // TEST 7: ALTERNATING 55
        //========================================

        start_test("Alternating 55 pattern");

        initialize_both(6'd23);
        send_loopback_byte(8'h55);

        finish_test("Alternating 55 pattern");

        //========================================
        // TEST 8: RANDOM DATA
        //========================================

        start_test("Random input bytes");

        initialize_both(6'd23);

        for (j = 0; j < 10; j = j + 1) begin

            random_data = $urandom;

            $display("\nRandom byte %0d = %02h",
                     j + 1, random_data);

            send_loopback_byte(random_data);

        end

        finish_test("Random input bytes");

        //========================================
        // TEST 9: DIFFERENT CHANNEL INDICES
        //========================================

        start_test("Different channel indices");

        initialize_both(6'd0);
        send_loopback_byte(8'hB2);

        initialize_both(6'd1);
        send_loopback_byte(8'hB2);

        initialize_both(6'd23);
        send_loopback_byte(8'hB2);

        initialize_both(6'd37);
        send_loopback_byte(8'hB2);

        initialize_both(6'd38);
        send_loopback_byte(8'hB2);

        initialize_both(6'd39);
        send_loopback_byte(8'hB2);

        finish_test("Different channel indices");

        //========================================
        // TEST 10: IDLE HOLD
        //========================================

        start_test("TX and RX idle hold");

        initialize_both(6'd23);

        tx_state_before = tx_lfsr_state;
        rx_state_before = rx_lfsr_state;

        repeat (3) begin

            @(negedge clk);

            tx_bit_en = 1'b0;
            rx_bit_en = 1'b0;

            @(posedge clk);
            #1;

            if (tx_lfsr_state !== tx_state_before ||
                rx_lfsr_state !== rx_state_before) begin

                $display("FAIL: LFSR changed during idle");
                errors = errors + 1;

            end

            if (tx_valid !== 1'b0 ||
                rx_valid !== 1'b0) begin

                $display("FAIL: Valid high during idle");
                errors = errors + 1;

            end

        end

        finish_test("TX and RX idle hold");

        //========================================
        // TEST 11: INPUT GAPS AND RESUME
        //========================================

        start_test("Input gaps and resume");

        initialize_both(6'd23);

        // First active bit
        @(negedge clk);

        tx_bit_en = 1'b1;
        rx_bit_en = 1'b1;

        tx_din = 1'b1;
        rx_din = 1'b1;

        next_tx_state = lfsr_next(tx_ref_state);
        next_rx_state = lfsr_next(rx_ref_state);

        @(posedge clk);
        #1;

        tx_ref_state = next_tx_state;
        rx_ref_state = next_rx_state;

        if (tx_lfsr_state !== tx_ref_state ||
            rx_lfsr_state !== rx_ref_state) begin

            $display("FAIL: First active bit state");
            errors = errors + 1;

        end

        // Two idle cycles
        repeat (2) begin

            @(negedge clk);

            tx_bit_en = 1'b0;
            rx_bit_en = 1'b0;

            @(posedge clk);
            #1;

            if (tx_lfsr_state !== tx_ref_state ||
                rx_lfsr_state !== rx_ref_state) begin

                $display("FAIL: State changed during gap");
                errors = errors + 1;

            end

        end

        // Resume operation
        @(negedge clk);

        tx_bit_en = 1'b1;
        rx_bit_en = 1'b1;

        tx_din = 1'b0;
        rx_din = 1'b0;

        next_tx_state = lfsr_next(tx_ref_state);
        next_rx_state = lfsr_next(rx_ref_state);

        @(posedge clk);
        #1;

        tx_ref_state = next_tx_state;
        rx_ref_state = next_rx_state;

        if (tx_lfsr_state !== tx_ref_state ||
            rx_lfsr_state !== rx_ref_state) begin

            $display("FAIL: Resume state");
            errors = errors + 1;

        end

        @(negedge clk);

        tx_bit_en = 1'b0;
        rx_bit_en = 1'b0;

        finish_test("Input gaps and resume");

        //========================================
        // TEST 12: CONTINUOUS MULTI-BYTE DATA
        //========================================

        start_test("Continuous multi-byte data");

        initialize_both(6'd23);

        send_loopback_byte(8'hB2);
        send_loopback_byte(8'hA5);
        send_loopback_byte(8'h3C);
        send_loopback_byte(8'hFF);

        finish_test("Continuous multi-byte data");

        //========================================
        // TEST 13: TX ONLY
        //========================================

        start_test("TX-only operation");

        initialize_both(6'd23);

        send_tx_only_byte(8'hB2);

        finish_test("TX-only operation");

        //========================================
        // TEST 14: RX ONLY
        //========================================

        start_test("RX-only operation");

        initialize_both(6'd23);

        send_rx_only_byte(8'h1D);

        finish_test("RX-only operation");

        //========================================
        // TEST 15: RESET DURING OPERATION
        //========================================

        start_test("Reset during whitening");

        initialize_both(6'd23);

        @(negedge clk);

        tx_bit_en = 1'b1;
        rx_bit_en = 1'b1;

        tx_din = 1'b1;
        rx_din = 1'b1;

        @(posedge clk);
        #1;

        // Assert asynchronous reset between clock edges
        #2;
        rst_n = 1'b0;

        #1;

        if (tx_lfsr_state !== 7'b0000000 ||
            rx_lfsr_state !== 7'b0000000) begin

            $display("FAIL: Asynchronous reset during operation");
            errors = errors + 1;

        end

        tx_ref_state = 7'b0;
        rx_ref_state = 7'b0;

        @(negedge clk);

        rst_n = 1'b1;
        tx_bit_en = 1'b0;
        rx_bit_en = 1'b0;

        finish_test("Reset during whitening");

        //========================================
        // TEST 16: REINITIALIZATION
        //========================================

        start_test("LFSR reinitialization");

        initialize_both(6'd23);

        send_loopback_byte(8'hB2);

        // Reinitialize same channel
        initialize_both(6'd23);

        if (tx_lfsr_state !== 7'b1010111 ||
            rx_lfsr_state !== 7'b1010111) begin

            $display("FAIL: Reinitialization");
            errors = errors + 1;

        end

        finish_test("LFSR reinitialization");

        //========================================
        // TEST 17: CHANNEL CHANGE
        //========================================

        start_test("Channel change and reinitialization");

        initialize_both(6'd23);

        send_loopback_byte(8'hB2);

        initialize_both(6'd37);

        if (tx_lfsr_state !== {1'b1, 6'd37} ||
            rx_lfsr_state !== {1'b1, 6'd37}) begin

            $display("FAIL: Channel change initialization");
            errors = errors + 1;

        end

        send_loopback_byte(8'hA5);

        finish_test("Channel change and reinitialization");

        //========================================
        // FINAL SUMMARY
        //========================================

        @(negedge clk);

        tx_bit_en = 1'b0;
        rx_bit_en = 1'b0;

        $display("\n");
        $display("========================================");
        $display("       BLE WHITENING TEST SUMMARY");
        $display("========================================");

        $display("Total test groups = %0d", test_number);
        $display("Tests passed      = %0d", tests_passed);
        $display("Tests failed      = %0d", tests_failed);
        $display("Total errors      = %0d", errors);

        if (errors == 0 && tests_failed == 0) begin

            $display("\nALL TESTS PASSED");
            $display("TX WHITENING PASSED");
            $display("RX DEWHITENING PASSED");

        end
        else begin

            $display("\nTESTBENCH FAILED");

        end

        $display("========================================");

        #20;
        $finish;

    end

endmodule



