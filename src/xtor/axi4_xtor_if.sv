// The class-facing side of the AXI4 manager and subordinate transactors.
//
// ONE interface type for both wrappers, and UNPARAMETERIZED: beats cross it
// in the cores' packed stream layout (axi4_types_pkg) at the widest width any
// configuration needs, and the wrapper records its own parameters in `p`.
// So a bridge's virtual interface type never varies with the interface
// configuration, and the bridge builds its axi4_cfg from `p`.
//
// Per channel (indexed by axi4_ch_e): a TX stream into the wrapper's core
// (manager: AW, W, AR; subordinate: B, R) and an RX stream out of it
// (manager: B, R; subordinate: AW, W, AR). The wrapper ties off the rest.
// send()/recv() move one beat, blocking, one per cycle at best. Stream
// signals are driven and sampled at the falling edge, so there is no race
// with the cores' rising-edge registers; a transfer happens at the rising
// edge in between.
interface axi4_xtor_if (
    input logic aclk,
    input logic aresetn
);
    import axi4_types_pkg::*;

    typedef logic [AXI4_STREAM_W_MAX-1:0] stream_beat_t;

    // Several members are read only by the class side, through the virtual
    // interface, which lint cannot see.
    /* verilator lint_off UNUSEDSIGNAL */

    // Set by the wrapper at time 0.
    axi4_param_t p;

    // Streams (the wrapper's core drives *_ready on TX and *_data/*_valid on RX).
    stream_beat_t tx_data[AXI4_N_CH];
    logic         tx_valid[AXI4_N_CH];
    logic         tx_ready[AXI4_N_CH];
    stream_beat_t rx_data[AXI4_N_CH];
    logic         rx_valid[AXI4_N_CH];
    logic         rx_ready[AXI4_N_CH];

    bit           tx_busy[AXI4_N_CH];
    bit           rx_busy[AXI4_N_CH];

    // Backpressure knob, set from the class side: before each beat,
    // send()/recv() idle a random 0..max_gap[ch] cycles before raising
    // VALID (TX) or READY (RX). 0 = full throughput.
    int unsigned  max_gap[AXI4_N_CH];
    /* verilator lint_on UNUSEDSIGNAL */

    initial begin
        for (int i = 0; i < AXI4_N_CH; i++) begin
            tx_valid[i] = 1'b0;
            tx_data[i]  = '0;
            rx_ready[i] = 1'b0;
            max_gap[i]  = 0;
        end
    end

    // A reset can cut a send()/recv() off mid-transfer (fw_root kills the
    // class tree that was calling it): drop the stream handshakes and free
    // the channels. Reset is active low (A3.1.2).
    always @(posedge aclk) begin
        if (!aresetn) begin
            for (int i = 0; i < AXI4_N_CH; i++) begin
                tx_valid[i] <= 1'b0;
                rx_ready[i] <= 1'b0;
                tx_busy[i]  <= 1'b0;
                rx_busy[i]  <= 1'b0;
            end
        end
    end

    // Send one packed beat on TX channel `ch`; returns once the core has
    // taken it. Callers on the same channel are serialized.
    task automatic send(input axi4_ch_e ch, input stream_beat_t d);
        @(negedge aclk);
        while (tx_busy[ch]) @(negedge aclk);
        tx_busy[ch]  = 1'b1;
        repeat ($urandom_range(max_gap[ch], 0)) @(negedge aclk);
        tx_data[ch]  = d;
        tx_valid[ch] = 1'b1;
        while (!tx_ready[ch]) @(negedge aclk);
        @(posedge aclk);
        tx_valid[ch] <= 1'b0;
        tx_busy[ch]  = 1'b0;
    endtask

    // Receive the next packed beat from RX channel `ch`.
    task automatic recv(input axi4_ch_e ch, output stream_beat_t d);
        @(negedge aclk);
        while (rx_busy[ch]) @(negedge aclk);
        rx_busy[ch] = 1'b1;
        repeat ($urandom_range(max_gap[ch], 0)) @(negedge aclk);
        while (!rx_valid[ch]) @(negedge aclk);
        d            = rx_data[ch];
        rx_ready[ch] = 1'b1;
        @(posedge aclk);
        rx_ready[ch] <= 1'b0;
        rx_busy[ch]  = 1'b0;
    endtask
endinterface
