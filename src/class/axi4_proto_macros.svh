`ifndef INCLUDED_AXI4_PROTO_MACROS_SVH
`define INCLUDED_AXI4_PROTO_MACROS_SVH
`include "fw_hdl_macros.svh"

// ----------------------------------------------------------------------
// IMP macros for the two sides of an AXI4 link. Each stamps a member NAME
// that is both the socket/mirror and its inbound imp; inbound channel <ch>
// lands on IMP's NAME``_<ch>(beat). Use inside a component body with a
// trailing `;`, and construct in build(): NAME = new(this);
//
//   `FW_AXI4_MGR_SOCKET_IMP(IMP, NAME)  manager:     NAME_b, NAME_r
//   `FW_AXI4_SUB_MIRROR_IMP(IMP, NAME)  subordinate: NAME_aw, NAME_w, NAME_ar
// ----------------------------------------------------------------------

`define FW_AXI4_MGR_SOCKET_IMP(IMP, NAME) \
    `FW_SOCKET_IMP_BEGIN(axi4_req_if, axi4_rsp_if, IMP, NAME) \
        virtual task b(input axi4_b_beat_t f); m_imp.NAME``_b(f); endtask \
        virtual task r(input axi4_r_beat_t f); m_imp.NAME``_r(f); endtask \
    `FW_SOCKET_IMP_END(NAME)

`define FW_AXI4_SUB_MIRROR_IMP(IMP, NAME) \
    `FW_MIRROR_IMP_BEGIN(axi4_req_if, axi4_rsp_if, IMP, NAME) \
        virtual task aw(input axi4_aw_beat_t f); m_imp.NAME``_aw(f); endtask \
        virtual task w(input axi4_w_beat_t f);   m_imp.NAME``_w(f);  endtask \
        virtual task ar(input axi4_ar_beat_t f); m_imp.NAME``_ar(f); endtask \
    `FW_MIRROR_IMP_END(NAME)

`endif /* INCLUDED_AXI4_PROTO_MACROS_SVH */
