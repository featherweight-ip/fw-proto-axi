// Elaboration top for the woven and woven-xtor weaves (sv-weave.yaml,
// sv-weave-xtor.yaml): empty, so that
// the weave's verify elaborates only the packages. Not fw-hdl's fw_root.sv (an
// implicit top otherwise), and not the generated wrappers: slang 12.1 takes two
// payload structs with the same members (aw_t and ar_t at default P) for one
// type in an interface's type parameter, and rejects the wrappers' vif
// assignments. Verilator lints and simulates the wrappers instead.
module xtor_weave_top;
endmodule
