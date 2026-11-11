    // ==================================================================
    // Describing a design as a class tree and realizing it (design §4.5;
    // ported from fw-hdl-sv-weave tests/abstractor_proto/abs_lib.svh, see
    // docs/p6-abstractors.md). Included in fw_proto_pkg. Names no protocol:
    // the abstractors of a protocol are generated from its bundle.
    //
    // The class tree a designer assembles is a description. Each component's
    // implementation ends up in exactly one place:
    //   - module tree: extern components (existing modules) and RTL structural
    //     components (assemblies of RTL linked by struct ports);
    //   - class tree:  ordinary class components.
    // Abstractors are boundary objects: an API in the class tree, a
    // transactor in the module tree.
    //
    // fw_emitter reads the description and writes:
    //   <module>.sv   one module per RTL structural class; its struct ports are
    //                 its pins. This is the netlist.
    //   <top>_sim.sv  a package of API shells, and a module holding the RTL,
    //                 one transactor per abstractor, and the run-time root.
    // At run time a class that wraps RTL is replaced, through the factory, by
    // its API shell: a subclass that builds only its API endpoints and binds
    // them to transactor handles.
    // ==================================================================

    // ------------------------------------------------------------------
    // Configuration from outside the description, by path. Read by run-time
    // handles (e.g. path "dut.s_abs", name "r.max_gap").
    // ------------------------------------------------------------------
    class fw_proto_cfg;
        static int m_int[string];

        static function void set_int(string path, string name, int value);
            m_int[{path, "|", name}] = value;
        endfunction

        static function int get_int(string path, string name, int dflt);
            string k = {path, "|", name};
            return m_int.exists(k) ? m_int[k] : dflt;
        endfunction

        // The names set for `path`.
        static function void names(string path, ref string out[$]);
            string pre = {path, "|"};
            out.delete();
            foreach (m_int[k])
                if (k.len() > pre.len() && k.substr(0, pre.len() - 1) == pre)
                    out.push_back(k.substr(pre.len(), k.len() - 1));
        endfunction
    endclass

    // ------------------------------------------------------------------
    // A stand-in factory (fw-hdl's fw_factory.svh is not in fw_hdl_pkg yet).
    // ------------------------------------------------------------------
    /* verilator lint_off UNUSEDSIGNAL */      // a prototype's arguments
    virtual class fw_proto_ctor;
        pure virtual function fw_component make(string name, fw_component parent);
    endclass
    /* verilator lint_on UNUSEDSIGNAL */

    class fw_proto_factory;
        static fw_proto_ctor m_ctors[string];
        static string        m_over[string];
        static string        m_type_of[string];     // full name -> type asked for

        static function void set_type_override(string base, string sub);
            m_over[base] = sub;
        endfunction

        static function fw_component create(string tn, string name, fw_component parent);
            string t = m_over.exists(tn) ? m_over[tn] : tn;
            fw_component c;
            if (!m_ctors.exists(t)) $fatal(1, "fw_proto_factory: %s is not registered", t);
            c = m_ctors[t].make(name, parent);
            m_type_of[c.get_full_name()] = tn;
            return c;
        endfunction

        // The type a component was created as ("" when not by the factory).
        static function string type_of(fw_component c);
            string n = c.get_full_name();
            return m_type_of.exists(n) ? m_type_of[n] : "";
        endfunction
    endclass

    class fw_proto_reg #(type T = fw_component, string TN = "") extends fw_proto_ctor;
        static fw_proto_reg #(T, TN) m_inst = get();

        static function fw_proto_reg #(T, TN) get();
            if (m_inst == null) begin
                m_inst = new;
                fw_proto_factory::m_ctors[TN] = m_inst;
            end
            return m_inst;
        endfunction

        virtual function fw_component make(string name, fw_component parent);
            T o = new(name, parent);
            return o;
        endfunction

        static function T create(string name, fw_component parent);
            T o;
            void'(get());
            if (!$cast(o, fw_proto_factory::create(TN, name, parent)))
                $fatal(1, "fw_proto_factory: the class picked for %s is not a %s", name, TN);
            return o;
        endfunction
    endclass

    // ------------------------------------------------------------------
    // Components the emitter realizes
    // ------------------------------------------------------------------
    virtual class fw_realized extends fw_component;
        static fw_realized m_all[$];
        fw_sp_base         m_sps[$];

        function new(string name, fw_component parent);
            super.new(name, parent);
            m_all.push_back(this);
        endfunction

        function void add_sp(fw_sp_base sp);
            m_sps.push_back(sp);
        endfunction

        // Implemented in the module tree.
        virtual function bit is_rtl(); return 0; endfunction
        // An instance of this component's module; nets[sp.path()] is the net
        // base name each struct port connects to. None for a class component.
        /* verilator lint_off UNUSEDSIGNAL */
        virtual function void emit_instance(fw_emitter e, string inst, string nets[string]);
        endfunction
        /* verilator lint_on UNUSEDSIGNAL */
    endclass

    function automatic bit fw_is_rtl(fw_component c);
        fw_realized r;
        if (c == null || !$cast(r, c)) return 0;
        return r.is_rtl();
    endfunction

    // An integer as a Verilog literal: unsized decimal when it fits 32 signed
    // bits (all a tool must give an unsized constant), else sized 64-bit hex
    // (e.g. a packed parameter vector such as {32'd15, 32'd15}).
    function automatic string fw_int_lit(longint v);
        if (v >= 0 && v < 64'sh8000_0000) return $sformatf("%0d", v);
        return $sformatf("64'h%0h", v);
    endfunction

    // Bits [msb:lsb] of a field that a pin-map entry covers.
    function automatic void fw_pin_bits(fw_extern_pin p, int unsigned width,
                                        output int msb, output int lsb);
        msb = (p.msb < 0) ? int'(width) - 1 : p.msb;
        lsb = (p.msb < 0) ? 0 : ((p.lsb < 0) ? p.msb : p.lsb);
    endfunction

    // An existing module behind a class whose ports are struct ports. The class
    // names the module only; which file defines it is the build's business
    // (the RTL filesets it is given), not the class's.
    virtual class fw_extern_component extends fw_realized;
        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        virtual function bit is_rtl(); return 1; endfunction
        pure virtual function string extern_module();
        pure virtual function void   extern_map(fw_extern_map x);

        virtual function void emit_instance(fw_emitter e, string inst, string nets[string]);
            fw_extern_map x = new;
            string conns[$];
            string params = "";
            int    used[string];
            fw_extern_pin eff[$];
            extern_map(x);
            e.resolve_pins(x, m_sps, eff);

            foreach (x.m_param_names[i]) begin
                string n = x.m_param_names[i];
                string v = x.m_param_int.exists(n) ? fw_int_lit(x.m_param_int[n])
                                                   : {"\"", x.m_param_str[n], "\""};
                params = {params, (i == 0) ? "" : ", ", ".", n, "(", v, ")"};
            end
            if (x.m_binds.size() != 0)
                e.error({fw_rel_path(this), ": x.rv/valid/level map method ports; ",
                         "map struct-port fields with x.pin()"});
            if (x.m_clock != "") conns.push_back({".", x.m_clock, "(clock)"});
            if (x.m_reset != "")
                conns.push_back({".", x.m_reset, x.m_reset_active_low ? "(!reset)" : "(reset)"});

            // Every pin names a field (or a slice of one) of one of our ports.
            // A pin with slots gets the concatenation of its slots' fields.
            begin
                string slot_expr[string][int];
                string pin_order[$];
                foreach (eff[j]) begin
                    fw_extern_pin p = eff[j];
                    fw_sp_base sp = null;
                    int f;
                    string key = (p.slot < 0) ? p.pin : $sformatf("%s[slot %0d]", p.pin, p.slot);
                    foreach (m_sps[i]) if (m_sps[i] == p.ep) sp = m_sps[i];
                    if (used.exists(key)) e.error({fw_rel_path(this), ": pin ", key, " mapped twice"});
                    used[key] = 1;
                    if (sp == null) begin
                        e.error({fw_rel_path(this), ": pin ", p.pin,
                                 " maps to a port that is not this component's struct port"});
                        continue;
                    end
                    f = sp.field_index(p.field);
                    if (f < 0) begin
                        e.error({sp.path(), ": pin ", p.pin, " names no field '", p.field, "'"});
                        continue;
                    end
                    begin
                        int          msb, lsb;
                        int unsigned w = sp.m_fields[f].width;
                        string       sel = "";
                        string       expr;
                        fw_pin_bits(p, w, msb, lsb);
                        if (msb >= int'(w) || lsb < 0 || lsb > msb)
                            e.error($sformatf("%s: pin %s: [%0d:%0d] is outside field %s (%0d bits)",
                                              sp.path(), p.pin, msb, lsb, p.field, w));
                        if (p.msb >= 0 && w > 1)
                            sel = (msb == lsb) ? $sformatf("[%0d]", msb) : $sformatf("[%0d:%0d]", msb, lsb);
                        expr = {nets[sp.path()], "_", p.field, sel};
                        if (p.slot < 0) begin
                            if (slot_expr.exists(p.pin))
                                e.error({fw_rel_path(this), ": pin ", p.pin, " has slots and a whole mapping"});
                            conns.push_back({".", p.pin, "(", expr, ")"});
                        end else begin
                            if (!slot_expr.exists(p.pin)) pin_order.push_back(p.pin);
                            slot_expr[p.pin][p.slot] = expr;
                        end
                    end
                end
                foreach (pin_order[i]) begin
                    string pn = pin_order[i];
                    int    n;
                    string cat = "";
                    void'(slot_expr[pn].last(n));
                    n = n + 1;              // slots 0..highest mapped
                    for (int k = n - 1; k >= 0; k--) begin
                        if (!slot_expr[pn].exists(k)) begin
                            e.error($sformatf("%s: pin %s: slot %0d of %0d is not mapped",
                                              fw_rel_path(this), pn, k, n));
                            continue;
                        end
                        cat = {cat, (cat == "") ? "" : ", ", slot_expr[pn][k]};
                    end
                    conns.push_back({".", pn, "({", cat, "})"});
                end
            end
            // ...and every bit of every field is some pin's, exactly once.
            foreach (m_sps[i]) foreach (m_sps[i].m_fields[f]) begin
                fw_sp_base   sp = m_sps[i];
                int unsigned w = sp.m_fields[f].width;
                int          cov[$];
                repeat (w) cov.push_back(0);
                foreach (eff[j]) if (eff[j].ep == sp && eff[j].field == sp.m_fields[f].name) begin
                    int msb, lsb;
                    fw_pin_bits(eff[j], w, msb, lsb);
                    for (int k = lsb; k <= msb && k < int'(w); k++) cov[k]++;
                end
                foreach (cov[k]) if (cov[k] != 1) begin
                    e.error($sformatf("%s.%s: bit %0d is mapped to %0d pins (expected 1)",
                                      sp.path(), sp.m_fields[f].name, k, cov[k]));
                    break;
                end
            end
            foreach (x.m_tie_pins[i])
                conns.push_back($sformatf(".%s(%s)", x.m_tie_pins[i], fw_int_lit(x.m_tie_values[i])));
            foreach (x.m_open_pins[i])
                conns.push_back({".", x.m_open_pins[i], "()"});

            e.line((params == "") ? $sformatf("    %s %s (", extern_module(), inst)
                                  : $sformatf("    %s #(%s) %s (", extern_module(), params, inst));
            foreach (conns[i])
                e.line({"        ", conns[i], (i == conns.size() - 1) ? "" : ","});
            e.line("    );");
        endfunction
    endclass

    // An assembly of RTL components linked by struct ports. Emitted as one
    // module; its own struct ports are the module's pins.
    virtual class fw_rtl_structural extends fw_realized;
        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        virtual function bit is_rtl(); return 1; endfunction
        pure virtual function string module_name();

        virtual function void emit_instance(fw_emitter e, string inst, string nets[string]);
            string conns[$];
            conns.push_back(".clock(clock)");
            conns.push_back(".reset(reset)");
            foreach (m_sps[i]) foreach (m_sps[i].m_fields[f])
                conns.push_back({".", m_sps[i].ep_name(), "_", m_sps[i].m_fields[f].name, "(",
                                 nets[m_sps[i].path()], "_", m_sps[i].m_fields[f].name, ")"});
            e.line($sformatf("    %s %s (", module_name(), inst));
            foreach (conns[i])
                e.line({"        ", conns[i], (i == conns.size() - 1) ? "" : ","});
            e.line("    );");
        endfunction
    endclass

    // ------------------------------------------------------------------
    // Abstractors. Description objects: the emitter turns each into a
    // transactor module and a run-time handle in an API shell. The protocol's
    // weaver generates them, one per role (<proto>_<role>_abs), with the
    // string tables below.
    // ------------------------------------------------------------------
    virtual class fw_boundary extends fw_realized;
        string m_serves;    // the parent's API endpoint this one stands behind

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        // The struct port whose link the transactor connects to.
        pure virtual function fw_sp_base pin_sp();
        // For a monitor, the port whose link it watches; null for an
        // abstractor. (No monitors are generated yet: the emitter rejects one.)
        virtual function fw_sp_base tap(); return null; endfunction
        pure virtual function string xtor_module();
        // The class side of the transactor (`virtual <if> #(...)`) and the
        // run-time handle class that drives it.
        pure virtual function string vif_type();
        pure virtual function string handle_type();
        // The transactor's parameters, clock and reset connections.
        virtual function string xtor_params();
            string p = pin_sp().param_lit();
            return (p == "") ? "" : {"#(", p, ") "};
        endfunction
        virtual function string xtor_clk_rst(); return ".clock(clock), .reset(reset)"; endfunction
        // How the handle `h` joins the parent's endpoint.
        virtual function string join_stmt(string h);
            return {h, ".serve(", m_serves, ");"};
        endfunction
        // The transactor's pins and the struct-port fields they connect to:
        // by default one pin per field, named as the field.
        virtual function void xtor_pins(output string pins[$], output string fields[$]);
            fw_sp_base sp = pin_sp();
            pins.delete();
            fields.delete();
            foreach (sp.m_fields[f]) begin
                pins.push_back(sp.m_fields[f].name);
                fields.push_back(sp.m_fields[f].name);
            end
        endfunction
    endclass

    // ------------------------------------------------------------------
    // The emitter
    // ------------------------------------------------------------------
    class fw_emitter;
        string m_lines[$];
        int    m_errors;
        string m_dir = ".";     // where files are written

        function void line(string s); m_lines.push_back(s); endfunction
        function void error(string s);
            $display("[emit] error: %s", s);
            m_errors++;
        endfunction

        function void flush(string fname);
            string path = {m_dir, "/", fname};
            int fd = $fopen(path, "w");
            if (fd == 0) begin
                error({"cannot write ", path});
                return;
            end
            foreach (m_lines[i]) $fdisplay(fd, "%s", m_lines[i]);
            $fclose(fd);
            m_lines.delete();
            $display("[emit] wrote %s", path);
        endfunction

        function void children(fw_component p, output fw_realized kids[$]);
            kids.delete();
            foreach (fw_realized::m_all[i])
                if (fw_realized::m_all[i].get_parent() == p) kids.push_back(fw_realized::m_all[i]);
        endfunction

        // Resolve an extern's struct-port pin map, in call order, to explicit
        // pins. A rule maps the fields still unmapped; an explicit pin replaces
        // whatever a rule chose for its field. Only strings are involved: the
        // field names come from the struct port's type, and the algorithm runs
        // here, in the tool.
        function void resolve_pins(fw_extern_map x, fw_sp_base sps[$], output fw_extern_pin eff[$]);
            bit by_rule[$];
            eff.delete();
            foreach (x.m_pins[j]) begin
                fw_extern_pin p = x.m_pins[j];
                if (p.rule == null) begin
                    // An explicit pin: drop any rule's choice for this field.
                    fw_extern_pin keep[$];
                    bit           keep_r[$];
                    foreach (eff[k]) if (!(by_rule[k] && eff[k].ep == p.ep && eff[k].field == p.field)) begin
                        keep.push_back(eff[k]);
                        keep_r.push_back(by_rule[k]);
                    end
                    eff = keep;
                    by_rule = keep_r;
                    eff.push_back(p);
                    by_rule.push_back(0);
                end else begin
                    fw_sp_base sp = null;
                    foreach (sps[i]) if (sps[i] == p.ep) sp = sps[i];
                    if (sp == null) begin
                        error("a pin rule names a port that is not this component's struct port");
                        continue;
                    end
                    if (p.rule.m_kind != "prefix") begin
                        error({sp.path(), ": unknown pin rule '", p.rule.m_kind, "'"});
                        continue;
                    end
                    foreach (sp.m_fields[f]) begin
                        bit    mapped = 0;
                        string fld = sp.m_fields[f].name;
                        foreach (eff[k]) if (eff[k].ep == sp && eff[k].field == fld) mapped = 1;
                        if (!mapped) begin
                            fw_extern_pin q = new;
                            string        mid = p.rule.m_rename.exists(fld) ? p.rule.m_rename[fld] : fld;
                            if (p.rule.m_upper) mid = mid.toupper();
                            q.pin = {p.rule.m_prefix, mid, p.rule.m_suffix};
                            q.ep = sp;
                            q.field = fld;
                            q.msb = -1;
                            q.lsb = -1;
                            q.slot = p.rule.m_slot;
                            eff.push_back(q);
                            by_rule.push_back(1);
                        end
                    end
                end
            end
        endfunction

        // The outermost RTL component containing `c`.
        function fw_realized rtl_root(fw_component c);
            fw_realized r;
            while (fw_is_rtl(c.get_parent())) c = c.get_parent();
            void'($cast(r, c));
            return r;
        endfunction

        // Inside structural `s`: the net base name a child's port connects to.
        function string inner_net(fw_component s, fw_sp_base sp);
            if (sp.m_outer != null) begin
                if (sp.m_outer.m_owner != s) error({sp.path(), ": bound to a port outside its parent"});
                return sp.m_outer.ep_name();
            end
            if (sp.m_peer == null) begin
                error({sp.path(), ": struct port neither linked nor bound to a parent port"});
                return "unconnected";
            end
            if (sp.m_peer.m_owner == null || sp.m_peer.m_owner.get_parent() != s)
                error({sp.path(), " <-> ", sp.m_peer.path(), ": link leaves the parent"});
            return {sp.sender().m_owner.get_name(), "_", sp.sender().ep_name()};
        endfunction

        // One module per RTL structural class.
        function void emit_module(fw_rtl_structural s, ref string done[string]);
            fw_realized kids[$];
            string nets[string];
            string ports[$];
            if (done.exists(s.module_name())) return;
            done[s.module_name()] = "1";
            children(s, kids);

            foreach (kids[i]) begin
                fw_rtl_structural sub;
                if (!kids[i].is_rtl()) begin
                    error({fw_rel_path(kids[i]), ": inside RTL ", fw_rel_path(s), " but not RTL"});
                    continue;
                end
                if ($cast(sub, kids[i])) emit_module(sub, done);
            end

            line("// Generated by the fw_proto emitter. Do not edit.");
            line($sformatf("module %s (", s.module_name()));
            ports.push_back("    input  logic clock");
            ports.push_back("    input  logic reset");
            foreach (s.m_sps[j]) begin
                fw_sp_base sp = s.m_sps[j];
                foreach (sp.m_fields[f])
                    ports.push_back({"    ", sp.field_in(f) ? "input  " : "output ",
                                     sp.field_type(f), " ", sp.ep_name(), "_", sp.m_fields[f].name});
            end
            foreach (ports[i]) line({ports[i], (i == ports.size() - 1) ? "" : ","});
            line(");");
            foreach (kids[i]) foreach (kids[i].m_sps[j]) begin
                fw_sp_base sp = kids[i].m_sps[j];
                nets[sp.path()] = inner_net(s, sp);
                if (sp.m_outer == null && sp.m_peer != null && sp.sender() == sp)
                    foreach (sp.m_fields[f])
                        line({"    ", sp.field_type(f), " ", nets[sp.path()], "_", sp.m_fields[f].name, ";"});
            end
            foreach (kids[i]) kids[i].emit_instance(this, kids[i].get_name(), nets);
            line("endmodule");
            flush({s.module_name(), ".sv"});
        endfunction

        // Transactor instance name: the abstractor's path.
        function string xtor_inst(fw_boundary b);
            return {"x_", fw_ident(fw_rel_path(b))};
        endfunction

        // Where a transactor's pins connect, from the emitted sim module: a
        // boundary link (abstractor to RTL root) is a net of the sim module.
        function string pin_scope(fw_sp_base sp);
            if (fw_is_rtl(sp.m_owner)) return fw_ident(sp.path());
            return fw_ident(sp.m_peer.path());
        endfunction

        // Emit the netlist modules and <top>_sim.sv for the tree under `root`,
        // whose class is `top`.
        // `imports`: the packages the shells and the sim module import (the
        // design's, and the protocol packages the handles come from).
        function int emit(fw_component root, string top, string imports[$]);
            fw_realized  all[$] = fw_realized::m_all;
            fw_realized  roots[$];
            fw_component wraps[string];      // classes wrapping RTL, by path
            fw_boundary  bnds[$];
            string done[string];

            foreach (all[i]) begin
                fw_boundary b;
                if (all[i].is_rtl() && !fw_is_rtl(all[i].get_parent())) roots.push_back(all[i]);
                if ($cast(b, all[i])) bnds.push_back(b);
            end
            foreach (roots[i]) wraps[fw_rel_path(roots[i].get_parent())] = roots[i].get_parent();
            foreach (bnds[i]) wraps[fw_rel_path(bnds[i].get_parent())] = bnds[i].get_parent();
            foreach (wraps[p]) begin
                if (wraps[p].get_parent() == null)
                    error("the root holds RTL or abstractors directly; wrap them in a class");
                else if (fw_proto_factory::type_of(wraps[p]) == "")
                    error({p, ": wraps RTL, so it must be created by the factory"});
            end
            foreach (bnds[i]) begin
                if (bnds[i].tap() != null)
                    error({fw_rel_path(bnds[i]), ": monitors are not supported yet"});
                else if (bnds[i].pin_sp() == null || bnds[i].pin_sp().m_peer == null)
                    error({fw_rel_path(bnds[i]), ": not attached to a link"});
                else if (!fw_is_rtl(bnds[i].pin_sp().m_peer.m_owner))
                    error({fw_rel_path(bnds[i]), ": linked to ", bnds[i].pin_sp().m_peer.path(),
                           ", which is not RTL"});
            end
            if (m_errors != 0) return m_errors;

            // The netlist: one module per RTL structural class.
            foreach (roots[i]) begin
                fw_rtl_structural s;
                if ($cast(s, roots[i])) emit_module(s, done);
            end

            // The run-time class tree, as planned.
            $display("[emit] run-time class tree:");
            foreach (wraps[p]) begin
                $display("[emit]   %-18s %s_shell (API shell)", p, fw_proto_factory::type_of(wraps[p]));
                foreach (bnds[i]) if (bnds[i].get_parent() == wraps[p])
                    $display("[emit]   %-18s %s, to %s", fw_rel_path(bnds[i]), bnds[i].handle_type(),
                             xtor_inst(bnds[i]));
            end
            foreach (all[i]) if (all[i].is_rtl())
                $display("[emit]   %-18s module tree only: no class", fw_rel_path(all[i]));

            // <top>_sim.sv, part 1: the shells.
            line("// Generated by the fw_proto emitter. Do not edit.");
            line("`include \"fw_hdl_macros.svh\"");
            line($sformatf("package %s_shells_pkg;", top));
            line("    import fw_hdl_pkg::*;");
            line("    import fw_proto_pkg::*;");
            foreach (imports[i]) line($sformatf("    import %s::*;", imports[i]));
            foreach (wraps[p]) emit_shell(wraps[p], bnds);
            line("endpackage");
            line("");

            // <top>_sim.sv, part 2: the module.
            line($sformatf("module %s_sim (input logic clock, input logic reset);", top));
            line("    import fw_hdl_pkg::*;");
            line("    import fw_proto_pkg::*;");
            foreach (imports[i]) line($sformatf("    import %s::*;", imports[i]));
            line($sformatf("    import %s_shells_pkg::*;", top));
            line("    // The RTL.");
            foreach (roots[i]) begin
                string nets[string];
                foreach (roots[i].m_sps[j]) begin
                    fw_sp_base sp = roots[i].m_sps[j];
                    string n = fw_ident(sp.path());
                    nets[sp.path()] = n;
                    foreach (sp.m_fields[f])
                        line({"    ", sp.field_type(f), " ", n, "_", sp.m_fields[f].name, ";"});
                end
                roots[i].emit_instance(this, {"u_", fw_ident(fw_rel_path(roots[i]))}, nets);
            end
            line("    // A transactor per abstractor.");
            foreach (bnds[i]) begin
                string scope = pin_scope(bnds[i].pin_sp());
                string pins[$], fields[$];
                bnds[i].xtor_pins(pins, fields);
                line($sformatf("    %s %s%s (", bnds[i].xtor_module(), bnds[i].xtor_params(),
                               xtor_inst(bnds[i])));
                line({"        ", bnds[i].xtor_clk_rst(), (pins.size() == 0) ? "" : ","});
                foreach (pins[k]) begin
                    if (bnds[i].pin_sp().field_index(fields[k]) < 0)
                        error({fw_rel_path(bnds[i]), ": transactor pin ", pins[k], " needs field ",
                               fields[k], ", which ", bnds[i].pin_sp().path(), " lacks"});
                    line({"        .", pins[k], "(", scope, "_", fields[k], ")",
                          (k == pins.size() - 1) ? "" : ","});
                end
                line("    );");
            end
            line("    // The run-time class tree: shells in place of the classes that wrap RTL.");
            line("    initial begin");
            foreach (wraps[p]) begin
                string wt = fw_proto_factory::type_of(wraps[p]);
                line($sformatf("        void'(%s_shell_reg::get());", wt));
                line($sformatf("        fw_proto_factory::set_type_override(\"%s\", \"%s_shell\");", wt, wt));
            end
            line("    end");
            line($sformatf("    `fw_root_begin(%s, u_root, clock, reset)", top));
            foreach (wraps[p]) begin
                string st = {fw_proto_factory::type_of(wraps[p]), "_shell"};
                string args = "";
                foreach (bnds[i]) if (bnds[i].get_parent() == wraps[p])
                    args = {args, (args == "") ? "" : ", ", xtor_inst(bnds[i]), ".u_if"};
                line("        begin");
                line($sformatf("            %s s;", st));
                line($sformatf("            if (!$cast(s, %s)) $fatal(1, \"%s is not a %s\");", p, p, st));
                line($sformatf("            s.bind_xtors(%s);", args));
                line("        end");
            end
            line("    `fw_root_end");
            line("endmodule");
            flush({top, "_sim.sv"});
            return m_errors;
        endfunction

        // The API shell for class `w`: only its API endpoints, bound to
        // transactor handles in bind_xtors().
        function void emit_shell(fw_component w, fw_boundary bnds[$]);
            string wt = fw_proto_factory::type_of(w);
            string st = {wt, "_shell"};
            string eps[string];
            string margs[$];
            foreach (bnds[i]) if (bnds[i].get_parent() == w) eps[bnds[i].m_serves] = "1";

            line("");
            line($sformatf("    // API shell: %s, implemented in the module tree.", wt));
            line($sformatf("    class %s extends %s;", st, wt));
            line("        function new(string name, fw_component parent);");
            line("            super.new(name, parent);");
            line("        endfunction");
            line("        // Only the API endpoints.");
            line("        virtual function void build();");
            foreach (eps[n]) line($sformatf("            %s = new(\"%s\", this);", n, n));
            line("        endfunction");
            line("        virtual function void connect();");
            line("        endfunction");
            line("        // Handles to the transactors in the module tree; called by the root.");
            foreach (bnds[i]) if (bnds[i].get_parent() == w)
                margs.push_back({bnds[i].vif_type(), " ", xtor_inst(bnds[i])});
            line("        function void bind_xtors(");
            foreach (margs[i]) line({"                ", margs[i], (i == margs.size() - 1) ? ");" : ","});
            foreach (bnds[i]) if (bnds[i].get_parent() == w) begin
                line("            begin");
                line($sformatf("                %s h = new(\"%s\", this, %s);",
                               bnds[i].handle_type(), bnds[i].get_name(), xtor_inst(bnds[i])));
                line({"                ", bnds[i].join_stmt("h")});
                line("            end");
            end
            line("        endfunction");
            line("    endclass");
            line($sformatf("    typedef fw_proto_reg #(%s, \"%s\") %s_reg;", st, st, st));
        endfunction
    endclass
