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
