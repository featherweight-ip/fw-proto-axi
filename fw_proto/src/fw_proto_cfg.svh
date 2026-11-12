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
