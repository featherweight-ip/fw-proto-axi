// L1 test harness, view `tlm` (see axi4_tlm_harness.svh).
`define AXI4_HARNESS axi4_l1_harness
`define AXI4_ENV_T   axi4_l1_env
`define AXI4_EP_MGR  mgr.axi
`define AXI4_EP_SUB  sub.axi
`include "axi4_tlm_harness.svh"
`undef AXI4_HARNESS
`undef AXI4_ENV_T
`undef AXI4_EP_MGR
`undef AXI4_EP_SUB
