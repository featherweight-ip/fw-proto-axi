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
