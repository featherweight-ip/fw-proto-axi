// One-channel AXI4 register slice: a 2-entry skid buffer. IHI0022H A3.2.1.
// Synthesizable; no packages.
//
// Full throughput (one beat per cycle). Every output is registered except
// in_ready's reset gate: out_valid/out_data are held while out_ready is low
// (VALID and payload stable until the handshake), and in_ready is low in
// reset. Synchronous active-low reset; data registers are not reset.
module axi4_slice #(
    parameter int unsigned W = 1
) (
    input  logic         aclk,
    input  logic         aresetn,

    input  logic         in_valid,
    output logic         in_ready,
    input  logic [W-1:0] in_data,

    output logic         out_valid,
    input  logic         out_ready,
    output logic [W-1:0] out_data
);
    logic         skid_valid;
    logic [W-1:0] skid_data;

    assign in_ready = aresetn & ~skid_valid;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            out_valid  <= 1'b0;
            skid_valid <= 1'b0;
        end else if (out_ready || !out_valid) begin
            // Output register free (or emptying): refill, skid first.
            if (skid_valid) begin
                out_valid  <= 1'b1;
                out_data   <= skid_data;
                skid_valid <= 1'b0;
            end else begin
                out_valid <= in_valid;
                if (in_valid)
                    out_data <= in_data;
            end
        end else if (in_valid && in_ready) begin
            // Output stalled: park the accepted beat.
            skid_valid <= 1'b1;
            skid_data  <= in_data;
        end
    end
endmodule
