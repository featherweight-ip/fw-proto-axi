// Formal harness for the pin checker alone: every pin is free and both
// sides' rules are assumed, so the traces SymbiYosys finds are exactly the
// legal AXI4 interface behaviours. `dfm run fv-cover` shows that the rules
// leave the interesting ones reachable (they are not vacuous): bursts with
// B and RLAST, write data ahead of its address, out-of-order B, interleaved
// R, a WRAP burst. A single reset at the start.
module axi4_checker_fv
    import axi4_types_pkg::*;
(
    input logic        aclk,
    input logic        aresetn,
    input logic        awvalid, awready, awlock, wvalid, wready, wlast,
    input logic        bvalid, bready, arvalid, arready, arlock, rvalid, rready, rlast,
    input logic [0:0]  awid, bid, arid, rid,
    input logic [15:0] awaddr, araddr,
    input logic [7:0]  awlen, arlen,
    input logic [3:0]  wstrb,
    input logic [2:0]  awsize, arsize, awprot, arprot,
    input logic [1:0]  awburst, arburst, bresp, rresp,
    input logic [3:0]  awcache, arcache, awqos, arqos, awregion, arregion,
    input logic        awuser, wuser, buser, aruser, ruser,
    input logic [31:0] wdata, rdata
);
    localparam axi4_param_t P = '{ADDR_W: 16, DATA_W: 32, ID_W: 1,
        AWUSER_W: 0, WUSER_W: 0, BUSER_W: 0, ARUSER_W: 0, RUSER_W: 0};

    axi4_checker #(.P(P), .MAX_OUT(2), .ASSUME_MGR(1'b1), .ASSUME_SUB(1'b1))
        u_checker (.*);

    logic init = 1'b1;
    always_ff @(posedge aclk) init <= 1'b0;
    always_comb if (init) assume (!aresetn);
    always_comb if (!init) assume (aresetn);

    wire aw_hs = awvalid && awready;
    wire w_hs  = wvalid  && wready;
    wire b_hs  = bvalid  && bready;
    wire r_hs  = rvalid  && rready;

    // Scenario history.
    logic       aw_seen, w_first, b_seen, r_mid;
    logic       w_early, w1_done;  // W before any AW; first W burst done
    logic [0:0] aw_first_id, r_mid_id;
    logic [3:0] r_run;  // beats of the R burst in progress, one ID at a time
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            aw_seen <= 1'b0;  w_first <= 1'b0;  b_seen <= 1'b0;
            r_mid <= 1'b0;  aw_first_id <= '0;  r_mid_id <= '0;  r_run <= '0;
            w_early <= 1'b0;  w1_done <= 1'b0;
        end else begin
            if (aw_hs && !aw_seen) begin aw_seen <= 1'b1;  aw_first_id <= awid; end
            if (w_hs && wlast && !aw_seen && !aw_hs) w_first <= 1'b1;
            if (w_hs && !aw_seen && !aw_hs) w_early <= 1'b1;
            if (w_hs && wlast) w1_done <= 1'b1;
            if (b_hs) b_seen <= 1'b1;
            if (r_hs) begin
                r_mid    <= !rlast;
                r_mid_id <= rid;
                r_run    <= rlast ? 4'd0 : r_run + 4'd1;
            end
        end
    end

    always_ff @(posedge aclk) begin
        if (aresetn) begin
            // A write burst gets its response.
            cover (b_hs && aw_seen);
            // Write data completes before its address, then B.
            cover (b_hs && w_first);
            // Out-of-order B: the first response is for a later AW's ID.
            cover (b_hs && !b_seen && aw_seen && bid != aw_first_id);
            // RLAST closes a 3-beat burst.
            cover (r_hs && rlast && r_run == 4'd2);
            // R beats of two IDs interleave.
            cover (r_hs && r_mid && rid != r_mid_id);
            // A WRAP burst, an exclusive read.
            cover (aw_hs && awburst == 2'b10 && awlen == 8'd3);
            cover (arvalid && arready && arlock);
            // A W beat on two of the four lanes (A3.4.4 strobes), in the
            // first write-data burst, after its AW (so its lanes are checked).
            cover (w_hs && wstrb == 4'b1100 && (aw_seen || aw_hs) && !w_early && !w1_done);
            // EXOKAY on B and on R (A7.2: exclusive accesses only).
            cover (b_hs && bresp == 2'b01);
            cover (r_hs && rresp == 2'b01);
        end
    end
endmodule
