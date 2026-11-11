// fw_proto runtime: the protocol-agnostic SV that protocol cores and the code
// derived from them build on. Names no protocol.
//
//   fw_dir_e, fw_field_t   one pin-level field of a bundle and its direction
//   fw_sp_base             a struct port: a bundle's field table, plus its
//                          link (to the peer role) and bind (to a parent's port)
//   fw_rv_ch #(T)          the ready/valid channel family a bundle declares
//                          its channels with
//   fw_inbox #(T)          a per-channel inbound queue for scripted endpoints
//   fw_realized ...        components the emitter realizes: externs, RTL
//                          structurals, abstractors (fw_proto_abs.svh)
//
// The protocol-specific parts (which fields, which roles, the typed link and
// bind, the abstractors) are generated from the bundle by the fw-proto weaver.
package fw_proto_pkg;
    import fw_hdl_pkg::*;

    typedef class fw_realized;
    typedef class fw_emitter;

    // Path below the root, e.g. "dut" or "dut.core".
    function automatic string fw_rel_path(fw_component c);
        string p;
        if (c.get_parent() == null) return "";
        p = fw_rel_path(c.get_parent());
        return (p == "") ? c.get_name() : {p, ".", c.get_name()};
    endfunction

    // A path as an identifier: "dut.core" -> "dut_core".
    function automatic string fw_ident(string path);
        foreach (path[i]) if (path[i] == ".") path[i] = "_";
        return path;
    endfunction

    // Pin direction of a field, relative to the bundle's first role: FW_FWD is
    // driven by the first role (e.g. the manager), FW_REV by the second.
    typedef enum bit { FW_FWD = 1'b0, FW_REV = 1'b1 } fw_dir_e;

    function automatic fw_dir_e fw_dir_flip(fw_dir_e d);
        return (d == FW_FWD) ? FW_REV : FW_FWD;
    endfunction

    typedef struct {
        string       name;          // pin name without prefix, e.g. "awaddr"
        int unsigned width;
        fw_dir_e     dir;
    } fw_field_t;

    // ------------------------------------------------------------------
    // Struct ports
    // ------------------------------------------------------------------
    // One side of a bundle. The generated subclass fills the field table in
    // its constructor and adds a typed link()/bind_inner() per role, so only
    // the two roles of the same bundle and specialization can be joined.
    //
    // An fw_endpoint, so an extern's pin map (fw_extern_map::pin/prefix) can
    // name it. Its owner is the component the emitter realizes it in (none for
    // a port used only for its field table).
    virtual class fw_sp_base extends fw_endpoint;
        string       m_name;
        int unsigned m_role;        // index into the bundle's roles; 0 sends fwd fields
        fw_realized  m_owner;
        fw_sp_base   m_peer;        // the other role's port: the link is nets
        fw_sp_base   m_outer;       // the parent's port of the same role this one is bound to
        fw_field_t   m_fields[$];

        function new(string name, int unsigned role, fw_realized owner = null);
            m_name = name;
            m_ep_name = name;
            m_role = role;
            m_owner = owner;
            if (owner != null) owner.add_sp(this);
        endfunction

        // The bundle's protocol name and its roles, e.g. "axi4", "mgr,sub".
        pure virtual function string proto();
        pure virtual function string role_name();
        // This specialization's parameter value as an SV literal, for an
        // emitted `#(...)` ("" when the bundle has no struct parameter).
        pure virtual function string param_lit();

        // "dut.core.s" below the root, or the name alone without an owner.
        function string path();
            return (m_owner == null) ? m_name : {fw_rel_path(m_owner), ".", m_name};
        endfunction

        function void add_field(string name, int unsigned width, fw_dir_e dir);
            fw_field_t f;
            f.name  = name;
            f.width = width;
            f.dir   = dir;
            m_fields.push_back(f);
        endfunction

        function int unsigned n_fields();
            return m_fields.size();
        endfunction

        function int field_index(string name);
            foreach (m_fields[i]) if (m_fields[i].name == name) return i;
            return -1;
        endfunction

        // Is field i an input of the component holding this port?
        function bit field_in(int i);
            return (m_fields[i].dir == FW_FWD) == (m_role != 0);
        endfunction

        // Field i's net type: "logic" or "logic [w-1:0]".
        function string field_type(int i);
            return (m_fields[i].width == 1) ? "logic"
                 : $sformatf("logic [%0d:0]", m_fields[i].width - 1);
        endfunction

        // Total pin bits in one direction.
        function int unsigned bits(fw_dir_e dir);
            int unsigned n = 0;
            foreach (m_fields[i]) if (m_fields[i].dir == dir) n += m_fields[i].width;
            return n;
        endfunction

        // The side of a link that drives the fwd fields names its nets.
        function fw_sp_base sender();
            return (m_role == 0) ? this : m_peer;
        endfunction

        // Called by the generated, typed link(): the static types already
        // guarantee the same bundle, specialization and opposite role.
        protected function void do_link(fw_sp_base peer);
            if (m_peer != null || peer.m_peer != null)
                $error("fw_sp_base: %s or %s is already linked", m_name, peer.m_name);
            m_peer = peer;
            peer.m_peer = this;
        endfunction

        // Called by the generated, typed bind_inner(): `child` is this port,
        // one level in.
        protected function void do_bind_inner(fw_sp_base child);
            if (child.m_outer != null)
                $error("fw_sp_base: %s is already bound", child.m_name);
            child.m_outer = this;
        endfunction
    endclass

    // ------------------------------------------------------------------
    // Channel families
    // ------------------------------------------------------------------
    // A ready/valid channel carrying payload T. In a bundle, (* fw_fwd *) or
    // (* fw_rev *) gives the direction of valid and the payload; ready goes
    // the other way. Pins: <ch><member>..., <ch>valid, <ch>ready (the
    // payload's members are added by the generated field table).
    class fw_rv_ch #(type T = logic);
        /* verilator lint_off UNUSEDSIGNAL */      // names the payload type only
        T payload;
        /* verilator lint_on UNUSEDSIGNAL */

        static function void add_ctl(fw_sp_base sp, string ch, fw_dir_e dir);
            sp.add_field({ch, "valid"}, 1, dir);
            sp.add_field({ch, "ready"}, 1, fw_dir_flip(dir));
        endfunction
    endclass

    // ------------------------------------------------------------------
    // Scripted endpoints
    // ------------------------------------------------------------------
    // One inbound channel of a scripted endpoint: a queue the endpoint's
    // channel method fills and a test drains. `stall` makes the method block
    // (at pin level, the receiver holding READY low), which is how a test
    // holds one channel while checking that the others still flow.
    class fw_inbox #(type T = int);
        T            q[$];
        bit          stall;
        int unsigned n_recv;

        task put(input T f);
            wait (!stall);
            q.push_back(f);
            n_recv++;
        endtask

        // Blocking receive, for a test.
        task get(output T f);
            wait (q.size() > 0);
            f = q.pop_front();
        endtask

        function int size();
            return q.size();
        endfunction

        function void clear();
            q.delete();
            stall  = 0;
            n_recv = 0;
        endfunction
    endclass

    `include "fw_proto_abs.svh"

endpackage
