// Elaboration top for the rv pilot weave only. fw-hdl's fw_root has a `type`
// parameter that defaults to int, so it cannot elaborate as an implicit top;
// naming this empty module as the top (sources.top) leaves it unelaborated.
module rv_weave_top;
endmodule
