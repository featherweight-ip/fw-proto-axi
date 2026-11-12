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
