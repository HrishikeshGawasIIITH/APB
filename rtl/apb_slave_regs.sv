//======================================================================
// apb_slave_regs.sv  -  APB slave, 4 registers, WAIT wait states
//
// Models a slow peripheral: holds PREADY LOW for WAIT cycles of the
// ACCESS phase, so a transfer takes 2 + WAIT cycles.  With WAIT = 2
// the master samples PREADY as 0, 0, 1 - matching the wait-state
// timing diagrams in the reference material.
//
// Offsets above the four implemented registers return PSLVERR.
// PSLVERR is only driven HIGH on the final cycle of the transfer,
// i.e. when PSEL, PENABLE and PREADY are all HIGH.
//======================================================================
module apb_slave_regs #(
    parameter int ADDR_W = 12,
    parameter int DATA_W = 32,
    parameter int WAIT   = 2
)(
    input  logic              pclk,
    input  logic              presetn,
    input  logic              psel,
    input  logic              penable,
    input  logic              pwrite,
    input  logic [ADDR_W-1:0] paddr,
    input  logic [DATA_W-1:0] pwdata,
    output logic [DATA_W-1:0] prdata,
    output logic              pready,
    output logic              pslverr
);

    logic [DATA_W-1:0] regs [0:3];
    logic [1:0]        cnt;

    wire [1:0] idx = paddr[3:2];            // 4 registers at +0,+4,+8,+C
    wire       bad = (paddr[7:4] != 4'h0);  // anything above +C is unmapped

    // ---- wait-state counter -----------------------------------------
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn)              cnt <= 2'd0;
        else if (psel && penable)  cnt <= pready ? 2'd0 : cnt + 2'd1;
        else                       cnt <= 2'd0;
    end

    assign pready = (cnt == WAIT);

    // Error is only meaningful on the last cycle of the transfer.
    assign pslverr = bad && psel && penable && pready;

    // ---- register file ----------------------------------------------
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            regs[0] <= '0;
            regs[1] <= '0;
            regs[2] <= '0;
            regs[3] <= '0;
        end else if (psel && penable && pready && pwrite && !bad) begin
            regs[idx] <= pwdata;
        end
    end

    assign prdata = (psel && !pwrite && !bad) ? regs[idx] : '0;

endmodule
