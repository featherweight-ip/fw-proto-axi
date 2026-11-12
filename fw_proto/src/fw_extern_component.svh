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
