class demo_api extends fw_component;
    axi4_sub_socket #(P) s;
    demo_sys             core;

    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    function void build();
        s    = new("s", this);
        core = new("core", this);
    endfunction

    function void connect();
        void'(core.s.connect(s));
    endfunction
endclass
