// Generate pass only: each API's sockets meet passive peers.
class presets_top extends fw_component;
    preset_api_def_lc     def_lc;
    preset_api_def_uc     def_uc;
    preset_api_wide_lc    wide_lc;
    preset_api_wide_uc    wide_uc;
    preset_ends #(P_DEF)  def_lc_ends, def_uc_ends;
    preset_ends #(P_WIDE) wide_lc_ends, wide_uc_ends;

    function new(string name, fw_component parent);
        super.new(name, parent);
    endfunction

    // The APIs before their peers: a peer resolves through the API's socket,
    // whose imp the API's connect() sets (fw-hdl resolves child by child).
    function void build();
        def_lc       = preset_api_def_lc_reg::create("def_lc", this);
        def_uc       = preset_api_def_uc_reg::create("def_uc", this);
        wide_lc      = preset_api_wide_lc_reg::create("wide_lc", this);
        wide_uc      = preset_api_wide_uc_reg::create("wide_uc", this);
        def_lc_ends  = new("def_lc_ends", this);
        def_uc_ends  = new("def_uc_ends", this);
        wide_lc_ends = new("wide_lc_ends", this);
        wide_uc_ends = new("wide_uc_ends", this);
    endfunction

    function void connect();
        def_lc_ends.m.connect(def_lc.s);
        def_uc_ends.m.connect(def_uc.s);
        wide_lc_ends.m.connect(wide_lc.s);
        wide_uc_ends.m.connect(wide_uc.s);
        def_lc.m.connect(def_lc_ends.s);
        def_uc.m.connect(def_uc_ends.s);
        wide_lc.m.connect(wide_lc_ends.s);
        wide_uc.m.connect(wide_uc_ends.s);
    endfunction
endclass
