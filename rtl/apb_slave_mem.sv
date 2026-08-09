//======================================================================
// apb_slave_mem.sv  -  APB slave, 16 x 32-bit memory, zero wait states
//
// PREADY tied HIGH  -> every transfer is the 2-cycle minimum.
// PSLVERR tied LOW  -> this peripheral never reports an error, which
//                      the spec explicitly allows.
// Reproduces the "no wait states" write and read timing diagrams.
//======================================================================
module apb_slave_mem #(
    parameter int ADDR_W = 12,
    parameter int DATA_W = 32
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

    logic [DATA_W-1:0] mem [0:15];
    wire  [3:0] widx = paddr[5:2];      // word aligned: ignore paddr[1:0]

    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    // Write happens in the ACCESS phase, on the cycle the transfer ends.
    always_ff @(posedge pclk) begin
        if (psel && penable && pwrite && pready)
            mem[widx] <= pwdata;
    end

    // Drive PRDATA to zero when not selected.
    assign prdata = (psel && !pwrite) ? mem[widx] : '0;

endmodule
