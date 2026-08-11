//======================================================================
// apb_top.sv  -  one APB master + two APB slaves
//
// This is the single synthesizable top level.  The testbench drives
// the command port; on an FPGA the same port can be driven by a
// button, a counter or any small state machine.
//
// Address map (decoded inside apb_master):
//   0x000 - 0x0FF   memory slave    16 x 32-bit, zero wait states
//   0x100 - 0x10F   register slave  4 registers, 2 wait states
//   0x110 - 0x1FF   register slave  unmapped -> PSLVERR
//======================================================================
module apb_top #(
    parameter int ADDR_W = 12,
    parameter int DATA_W = 32
)(
    input  logic              pclk,
    input  logic              presetn,

    input  logic              cmd_valid,
    output logic              cmd_ready,
    input  logic              cmd_write,
    input  logic [ADDR_W-1:0] cmd_addr,
    input  logic [DATA_W-1:0] cmd_wdata,
    output logic [DATA_W-1:0] cmd_rdata,
    output logic              cmd_done,
    output logic              cmd_err
);

    // ---- APB bus ----
    logic [ADDR_W-1:0] paddr;
    logic              pwrite, penable;
    logic [DATA_W-1:0] pwdata;
    logic              psel_mem, psel_reg;
    logic [DATA_W-1:0] prdata;
    logic              pready, pslverr;

    // ---- slave response signals ----
    logic [DATA_W-1:0] prdata_mem,  prdata_reg;
    logic              pready_mem,  pready_reg;
    logic              pslverr_mem, pslverr_reg;

    apb_master #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_master (
        .pclk(pclk), .presetn(presetn),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_write(cmd_write), .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata),
        .cmd_rdata(cmd_rdata), .cmd_done(cmd_done), .cmd_err(cmd_err),
        .paddr(paddr), .pwrite(pwrite), .pwdata(pwdata),
        .psel_mem(psel_mem), .psel_reg(psel_reg), .penable(penable),
        .prdata(prdata), .pready(pready), .pslverr(pslverr)
    );

    apb_slave_mem #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_mem (
        .pclk(pclk), .presetn(presetn),
        .psel(psel_mem), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata),
        .prdata(prdata_mem), .pready(pready_mem), .pslverr(pslverr_mem)
    );

    apb_slave_regs #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .WAIT(2)) u_regs (
        .pclk(pclk), .presetn(presetn),
        .psel(psel_reg), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata),
        .prdata(prdata_reg), .pready(pready_reg), .pslverr(pslverr_reg)
    );

    // ---- response mux back to the master ----
    // Default PREADY is HIGH so an unselected bus can never hang.
    assign prdata  = psel_mem ? prdata_mem  : psel_reg ? prdata_reg  : '0;
    assign pready  = psel_mem ? pready_mem  : psel_reg ? pready_reg  : 1'b1;
    assign pslverr = psel_mem ? pslverr_mem : psel_reg ? pslverr_reg : 1'b0;

endmodule
