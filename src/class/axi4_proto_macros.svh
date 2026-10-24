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

// `FW_AXI4_XACT_IMP(IMP, NAME): export NAME providing axi4_xact_if; xact()
// redirects to IMP's NAME``_xact(x). Construct in build(): NAME = new(this);
`define FW_AXI4_XACT_IMP(IMP, NAME) \
    class NAME``_imp_t extends fw_export #(axi4_xact_if) implements axi4_xact_if; \
        local IMP m_imp; \
        function new(IMP imp); \
            super.new(`"NAME`", imp, this); \
            m_imp = imp; \
        endfunction \
        virtual task xact(axi4_xact x); \
            m_imp.NAME``_xact(x); \
        endtask \
    endclass \
    NAME``_imp_t NAME

`endif /* INCLUDED_AXI4_PROTO_MACROS_SVH */
