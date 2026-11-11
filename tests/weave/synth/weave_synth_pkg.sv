// A synthetic API covering what the AXI4 core does not: a type parameter plus
// an int parameter, a task with an output, non-void functions, queues and a
// fw_default override. Woven with the AXI4 core for the weave suite.
package weave_synth_pkg;
    (* fw_api *)
    interface class syn_if #(type T = int, int N = 4);
        typedef logic [N-1:0] n_t;
        pure virtual task put(input T t, output n_t cnt);
        pure virtual function int sum(input n_t q[$]);
        (* fw_default = "empty" *)
        pure virtual function void hint(input T t);
        pure virtual function bit [3:0] peek();
    endclass
endpackage
