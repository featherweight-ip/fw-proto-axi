// L2 memory test harness, view `xtor` (see axi4_xtor_harness.svh).
`define AXI4_HARNESS axi4_mem_harness
`define AXI4_ENV_T   axi4_mem_env
`define AXI4_EP_MGR  mgr.axi
`define AXI4_EP_SUB  sub.axi
`include "axi4_xtor_harness.svh"
`undef AXI4_HARNESS
`undef AXI4_ENV_T
`undef AXI4_EP_MGR
`undef AXI4_EP_SUB
