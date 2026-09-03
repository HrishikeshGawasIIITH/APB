//======================================================================
// apb_master.sv  -  AMBA 3 APB master
//
// Implements the IDLE / SETUP / ACCESS state machine.
//   IDLE   : PSELx = 0, PENABLE = 0
//   SETUP  : PSELx = 1, PENABLE = 0   - always exactly one cycle
//   ACCESS : PSELx = 1, PENABLE = 1   - held until PREADY is HIGH
//======================================================================
module apb_master #(
    parameter int ADDR_W = 12,
    parameter int DATA_W = 32
)(
    input  logic              pclk,
    input  logic              presetn,   // active LOW

    // ---- command port (user / FPGA side) ----
    input  logic              cmd_valid,
    output logic              cmd_ready,
    input  logic              cmd_write,
    input  logic [ADDR_W-1:0] cmd_addr,
    input  logic [DATA_W-1:0] cmd_wdata,
    output logic [DATA_W-1:0] cmd_rdata,
    output logic              cmd_done,
    output logic              cmd_err,

    // ---- APB ----
    output logic [ADDR_W-1:0] paddr,
    output logic              pwrite,
    output logic [DATA_W-1:0] pwdata,
    output logic              psel_mem,
    output logic              psel_reg,
    output logic              penable,
    input  logic [DATA_W-1:0] prdata,
    input  logic              pready,
    input  logic              pslverr
);

    typedef enum logic [1:0] {IDLE, SETUP, ACCESS} state_t;
    state_t state;

    // ---- state machine ----------------------------------------------
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            state     <= IDLE;
            paddr     <= '0;
            pwrite    <= 1'b0;
            pwdata    <= '0;
            cmd_rdata <= '0;
            cmd_done  <= 1'b0;
            cmd_err   <= 1'b0;
        end else begin
            cmd_done <= 1'b0;

            case (state)
                IDLE: if (cmd_valid) begin
                    paddr  <= cmd_addr;
                    pwrite <= cmd_write;
                    pwdata <= cmd_wdata;
                    state  <= SETUP;
                end

                // SETUP lasts exactly one cycle, unconditionally
                SETUP: state <= ACCESS;

                // PREADY LOW extends ACCESS.  Address, control and write
                // data must not change while we wait.
                ACCESS: if (pready) begin
                    cmd_rdata <= prdata;
                    cmd_err   <= pslverr;
                    cmd_done  <= 1'b1;
                    if (cmd_valid) begin
                        paddr  <= cmd_addr;
                        pwrite <= cmd_write;
                        pwdata <= cmd_wdata;
                        state  <= SETUP;
                    end else begin
                        state  <= IDLE;
                    end
                end
            endcase
        end
    end

    // ---- outputs -----------------------------------------------------
    assign cmd_ready = (state == IDLE) || (state == ACCESS && pready);
    assign penable   = (state == ACCESS);

    // Combinatorial address decode: one PSELx per slave, never both.
    // paddr[8] = 0 -> memory slave,  paddr[8] = 1 -> register slave.
    wire sel = (state == SETUP) || (state == ACCESS);
    assign psel_mem = sel && !paddr[8];
    assign psel_reg = sel &&  paddr[8];

endmodule
