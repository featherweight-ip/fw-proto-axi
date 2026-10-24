// L1 channel APIs: one interface class per direction, one task per channel,
// one beat per call.
//
// The L1 contract, in every implementation (direct TLM bind or pins):
//   * a call returns when the beat has been accepted by the other side
//     (TLM) or its VALID/READY handshake completed (pins);
//   * per channel, beats arrive in call order, unchanged (masked to the
//     interface configuration, axi4_cfg::mask_*), never dropped or
//     duplicated;
//   * channels are independent at L1 -- a call on one never waits on
//     another. Transaction-level rules (A3.3 dependencies, ID ordering) are
//     the job of the layer above.
//
// Every method is a task: a pin-level implementation blocks for READY.

// Manager -> subordinate: write address, write data, read address.
interface class axi4_req_if;
    pure virtual task aw(input axi4_aw_beat_t f);
    pure virtual task w(input axi4_w_beat_t f);
    pure virtual task ar(input axi4_ar_beat_t f);
endclass

// Subordinate -> manager: write response, read data.
interface class axi4_rsp_if;
    pure virtual task b(input axi4_b_beat_t f);
    pure virtual task r(input axi4_r_beat_t f);
endclass

// The link. The manager holds the socket (sends requests, receives
// responses); the subordinate (or a bridge to pins standing in for it)
// holds the mirror.
typedef fw_socket #(axi4_req_if, axi4_rsp_if) axi4_mgr_socket_t;
typedef fw_mirror #(axi4_req_if, axi4_rsp_if) axi4_sub_mirror_t;
