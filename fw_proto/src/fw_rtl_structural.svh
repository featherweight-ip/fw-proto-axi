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
