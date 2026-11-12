// The ready/valid family's signal-level rule on one channel (design §4.1), from a
// pin monitor's events: pre is the first VALID cycle of a transfer, post its
// handshake. Once VALID is up it stays up, with the payload unchanged, until the
// handshake: each pre is followed by its post, with the same payload, before the
// next pre. Part of a rule (its state registers there).
class fw_rv_hold #(type T = int);
    fw_rule     m_rule;
    string      m_ch;
    fw_flag     pending;
    fw_value #(T) pl;

    function new(fw_rule r, string ch);
        m_rule = r;
        m_ch = ch;
        pending = new(r);
        pl = new(r);
    endfunction

    function void pre(T t);
        if (pending.v)
            void'(m_rule.chk(0, $sformatf("%s: VALID dropped before the handshake", m_ch)));
        pending.set();
        pl.set(t);
    endfunction

    function void post(T t);
        if (pending.v && t !== pl.v)
            void'(m_rule.chk(0, $sformatf("%s: payload changed while stalled", m_ch)));
        pending.clr();
    endfunction
endclass
