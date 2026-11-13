// ------------------------------------------------------------------
// The emitter
// ------------------------------------------------------------------
class fw_emitter;
    string m_lines[$];
    int    m_errors;
    string m_errs[$];       // the error messages, in order
    string m_dir = ".";     // where files are written

    function void line(string s); m_lines.push_back(s); endfunction
    function void error(string s);
        $display("[emit] error: %s", s);
        m_errs.push_back(s);
        m_errors++;
    endfunction

    // Clock and reset of what the emitter instantiates: the domains of the
    // component it stands for (docs/design-domains.md §9). The sim top has nets
    // for the root domains only, so a component in any other domain is an
    // error naming it and the domain (an empty string when it is fine).
    function string domain_error(fw_component c);
        fw_component r = c;
        while (r.get_parent() != null) r = r.get_parent();
        if (fw_domains::relate(c.clock.ref_domain(), r.clock.ref_domain()) != FW_DOMAIN_SAME)
            return {fw_rel_path(c), ": in clock domain ", dom_name(c.clock.ref_domain()),
                    ", not the root's; the emitted sim top has nets for the root clock and",
                    " reset only"};
        if (c.reset.is_connected() || r.reset.is_connected())
            if (fw_domains::relate(c.reset.ref_domain(), r.reset.ref_domain()) != FW_DOMAIN_SAME)
                return {fw_rel_path(c), ": in reset domain ", dom_name(c.reset.ref_domain()),
                        ", not the root's; the emitted sim top has nets for the root clock and",
                        " reset only"};
        return "";
    endfunction

    function string dom_name(fw_domain_if d);
        return (d != null) ? d.domain_name() : "<none>";
    endfunction

    // The clock and reset connections for `c` (checked by domain_error()):
    // the sim top's and every emitted module's `clock` and `reset` nets.
    function string clk_rst_nets(fw_component c);
        return ".clock(clock), .reset(reset)";
    endfunction

    function void clk_rst_conns(fw_component c, ref string conns[$]);
        conns.push_back(".clock(clock)");
        conns.push_back(".reset(reset)");
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
        // Domains: everything instantiated in the sim top is in the root's.
        foreach (bnds[i]) begin
            string d = domain_error(bnds[i]);
            if (d != "") error(d);
        end
        foreach (all[i]) if (all[i].is_rtl()) begin
            string d = domain_error(all[i]);
            if (d != "") error(d);
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
            line({"        ", clk_rst_nets(bnds[i]), (pins.size() == 0) ? "" : ","});
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
