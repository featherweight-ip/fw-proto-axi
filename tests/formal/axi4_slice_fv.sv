// Unbounded proof of axi4_slice, the only state in axi4_mgr_core and
// axi4_sub_core (one slice per channel, plain wiring otherwise).
// Run by tests/formal/run_sby.sh (prove mode, abc pdr): `dfm run fv-prove`.
//
// The input side is driven by a well-behaved sender (VALID held until
// READY, payload stable) whose payload is the sequence number of the beat.
// Asserted, for any reset pattern after the initial reset:
//   - out_valid and in_ready low while aresetn is low (A3.1.2);
//   - out_valid and out_data stable until out_ready (A3.2.1);
//   - no beat lost, duplicated or reordered: the beat on the output is
//     the next sequence number, and at most two beats are inside;
//   - full throughput: in_ready is high whenever the slice is not full.
module axi4_slice_fv #(
    localparam int unsigned W = 3
) (
    input logic         aclk,
    input logic         aresetn,
    input logic         in_valid,
    input logic         out_ready
);
    logic         in_ready, out_valid;
    logic [W-1:0] in_data, out_data;

    axi4_slice #(.W(W)) u_slice (.*);

    logic init = 1'b1;
    always_ff @(posedge aclk) init <= 1'b0;
    always_comb if (init) assume (!aresetn);

    // Beats accepted in / delivered out since reset; payload = in_cnt.
    logic [W-1:0] in_cnt, out_cnt;
    wire [W-1:0]  occ = in_cnt - out_cnt;
    assign in_data = in_cnt;
    always_ff @(posedge aclk)
        if (!aresetn) begin
            in_cnt  <= '0;
            out_cnt <= '0;
        end else begin
            if (in_valid && in_ready)   in_cnt  <= in_cnt + 1'b1;
            if (out_valid && out_ready) out_cnt <= out_cnt + 1'b1;
        end

    // Sender holds VALID until READY (payload = in_cnt is then stable too).
    logic past_in_stall, past_out_stall;
    logic [W-1:0] past_out_data;
    always_ff @(posedge aclk) begin
        past_in_stall  <= aresetn && in_valid && !in_ready;
        past_out_stall <= aresetn && out_valid && !out_ready;
        past_out_data  <= out_data;
    end
    always_comb if (!init && aresetn && past_in_stall) assume (in_valid);

    always_comb begin
        if (!aresetn) begin
            assert (!out_valid);
            assert (!in_ready);
        end
        if (!init && aresetn) begin
            if (past_out_stall) begin
                assert (out_valid);
                assert (out_data == past_out_data);
            end
            assert (occ <= 2);
            assert (out_valid == (occ != 0));
            assert (in_ready == (occ != 2));
            if (out_valid) assert (out_data == out_cnt);
        end
    end

`ifdef FV_COVER
    always_comb if (!init && aresetn) cover (occ == 2 && out_valid && out_ready && in_valid);
`endif
endmodule
