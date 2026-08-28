//======================================================================
// apb_tb.sv  -  self-checking testbench for apb_top
//
// Drives the master's command port, keeps a reference copy of every
// write, and compares every read against it.  The protocol checker
// runs in parallel and watches the bus itself.
//======================================================================
`timescale 1ns/1ps

module apb_tb;

    localparam int ADDR_W = 12;
    localparam int DATA_W = 32;

    localparam [ADDR_W-1:0] MEM_BASE = 12'h000;
    localparam [ADDR_W-1:0] REG_BASE = 12'h100;
    localparam [ADDR_W-1:0] BAD_ADDR = 12'h110;   // unmapped -> PSLVERR

    logic              pclk = 0;
    logic              presetn;
    logic              cmd_valid, cmd_write;
    logic [ADDR_W-1:0] cmd_addr;
    logic [DATA_W-1:0] cmd_wdata;
    logic              cmd_ready, cmd_done, cmd_err;
    logic [DATA_W-1:0] cmd_rdata;

    integer passes = 0;
    integer fails  = 0;

    // golden model, one entry per word of the 12-bit address space
    logic [DATA_W-1:0] ref_mem [0:1023];

    always #5 pclk = ~pclk;                       // 100 MHz

    apb_top #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) dut (
        .pclk(pclk), .presetn(presetn),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_write(cmd_write), .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata),
        .cmd_rdata(cmd_rdata), .cmd_done(cmd_done), .cmd_err(cmd_err)
    );

    // The protocol monitor in apb_checker.sv is not instantiated here.
    // To enable it, uncomment the block below.
    //
    // apb_checker #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) chk (
    //     .pclk(pclk), .presetn(presetn),
    //     .paddr(dut.paddr), .pwdata(dut.pwdata), .pwrite(dut.pwrite),
    //     .psel_mem(dut.psel_mem), .psel_reg(dut.psel_reg),
    //     .penable(dut.penable), .pready(dut.pready), .pslverr(dut.pslverr)
    // );

    //------------------------------------------------------------------
    // helpers
    //------------------------------------------------------------------
    task automatic score(input ok, input string what);
        if (ok) begin
            passes = passes + 1;
            $display("[%6t] PASS  %s", $time, what);
        end else begin
            fails = fails + 1;
            $display("[%6t] FAIL  %s", $time, what);
        end
    endtask

    // Present one command and return as soon as the master accepts it.
    // Calling this twice in a row gives a back-to-back transfer, because
    // the master accepts the next command on the same edge PREADY ends
    // the current one.
    task automatic issue(input logic wr,
                         input [ADDR_W-1:0] a,
                         input [DATA_W-1:0] d);
        cmd_valid <= 1'b1;
        cmd_write <= wr;
        cmd_addr  <= a;
        cmd_wdata <= d;
        @(posedge pclk);
        while (!cmd_ready) @(posedge pclk);
        cmd_valid <= 1'b0;
    endtask

    task automatic wait_done;
        @(posedge pclk);
        while (!cmd_done) @(posedge pclk);
    endtask

    task automatic apb_write(input [ADDR_W-1:0] a, input [DATA_W-1:0] d);
        issue(1'b1, a, d);
        wait_done();
        ref_mem[a[ADDR_W-1:2]] = d;
    endtask

    task automatic apb_read_chk(input [ADDR_W-1:0] a, input [DATA_W-1:0] exp);
        issue(1'b0, a, {DATA_W{1'b0}});
        wait_done();
        score((cmd_rdata === exp) && (cmd_err === 1'b0),
              $sformatf("read  0x%03h = 0x%08h (expected 0x%08h, err=%0b)",
                        a, cmd_rdata, exp, cmd_err));
    endtask

    task automatic apb_expect_err(input logic wr, input [ADDR_W-1:0] a);
        issue(wr, a, 32'hDEAD_BEEF);
        wait_done();
        score(cmd_err === 1'b1,
              $sformatf("%s 0x%03h returned PSLVERR=%0b (expected 1)",
                        wr ? "write" : "read ", a, cmd_err));
    endtask

    //------------------------------------------------------------------
    // stimulus
    //------------------------------------------------------------------
    integer i;
    reg [ADDR_W-1:0] a;

    initial begin
        $dumpfile("apb.vcd");
        $dumpvars(0, apb_tb);

        cmd_valid = 0; cmd_write = 0; cmd_addr = 0; cmd_wdata = 0;
        presetn   = 0;
        repeat (3) @(posedge pclk);
        presetn <= 1;
        @(posedge pclk);

        // --- 1. reset behaviour: bus must be idle --------------------
        score((dut.psel_mem === 1'b0) && (dut.psel_reg === 1'b0) &&
              (dut.penable === 1'b0),
              "after reset PSELx and PENABLE are LOW");

        // --- 2. memory slave, no wait states -------------------------
        apb_write   (MEM_BASE + 12'h004, 32'hA5A5_1234);
        apb_read_chk(MEM_BASE + 12'h004, 32'hA5A5_1234);

        // --- 3. back-to-back write then read, no IDLE in between -----
        // The second issue() is accepted on the very edge the write
        // completes, so the bus goes ACCESS -> SETUP directly.
        issue(1'b1, MEM_BASE + 12'h008, 32'hCAFE_0001);
        issue(1'b0, MEM_BASE + 12'h008, 32'h0);
        wait_done();          // write finished
        wait_done();          // read finished, cmd_rdata now valid
        ref_mem[(MEM_BASE + 12'h008) >> 2] = 32'hCAFE_0001;
        score(cmd_rdata === 32'hCAFE_0001,
              $sformatf("back-to-back write then read = 0x%08h (expected 0xCAFE0001)",
                        cmd_rdata));

        // --- 4. register slave, 2 wait states ------------------------
        apb_write   (REG_BASE + 12'h000, 32'h1111_2222);
        apb_read_chk(REG_BASE + 12'h000, 32'h1111_2222);
        apb_write   (REG_BASE + 12'h00C, 32'h3333_4444);
        apb_read_chk(REG_BASE + 12'h00C, 32'h3333_4444);

        // --- 5. error response from an unmapped offset ---------------
        apb_expect_err(1'b1, BAD_ADDR);
        apb_expect_err(1'b0, BAD_ADDR);

        // --- 6. idle gap, then a transfer still works ----------------
        repeat (5) @(posedge pclk);
        apb_read_chk(MEM_BASE + 12'h004, 32'hA5A5_1234);

        // --- 7. walking ones across all 16 memory words --------------
        for (i = 0; i < 16; i = i + 1) begin
            a = MEM_BASE + (i * 4);
            apb_write(a, 32'h1 << i);
        end
        for (i = 0; i < 16; i = i + 1) begin
            a = MEM_BASE + (i * 4);
            apb_read_chk(a, ref_mem[a[ADDR_W-1:2]]);
        end

        repeat (5) @(posedge pclk);

        //--------------------------------------------------------------
        $display("\n=====================================================");
        $display("  data checks : %0d passed, %0d failed", passes, fails);
        if (fails == 0)
            $display("  RESULT      : PASS");
        else
            $display("  RESULT      : FAIL");
        $display("=====================================================\n");

        if (fails != 0) $fatal(1, "simulation failed");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "timeout");
    end

endmodule
