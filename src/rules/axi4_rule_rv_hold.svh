// Signal level (design §4.1), for a pin monitor's events: on each channel, once
// VALID is up it stays up with the payload unchanged until the handshake
// (A3.2.1), checked by fw_rv_hold. Attach only to a pin monitor: through a proxy
// several callers may each have a call open on one channel. AW, W, AR bind the
// manager; B, R the subordinate.
/* verilator lint_off UNUSEDSIGNAL */  // a rule reads only the fields it needs
class axi4_rule_rv_hold #(axi4_param_t P = AXI4_PARAM_DEFAULT) extends axi4_rule #(P);
    fw_rv_hold #(aw_t) h_aw;
    fw_rv_hold #(w_t)  h_w;
    fw_rv_hold #(b_t)  h_b;
    fw_rv_hold #(ar_t) h_ar;
    fw_rv_hold #(r_t)  h_r;

    function new();
        super.new("rv_hold");
        h_aw = new(this, "aw");
        h_w = new(this, "w");
        h_b = new(this, "b");
        h_ar = new(this, "ar");
        h_r = new(this, "r");
    endfunction

    virtual function fw_rule create();
        axi4_rule_rv_hold #(P) r = new;
        return r;
    endfunction

    virtual function void aw_pre(input aw_t t);  h_aw.pre(t);  endfunction
    virtual function void aw_post(input aw_t t); h_aw.post(t); endfunction
    virtual function void w_pre(input w_t t);    h_w.pre(t);   endfunction
    virtual function void w_post(input w_t t);   h_w.post(t);  endfunction
    virtual function void ar_pre(input ar_t t);  h_ar.pre(t);  endfunction
    virtual function void ar_post(input ar_t t); h_ar.post(t); endfunction
    virtual function void b_pre(input b_t t);    h_b.pre(t);   endfunction
    virtual function void b_post(input b_t t);   h_b.post(t);  endfunction
    virtual function void r_pre(input r_t t);    h_r.pre(t);   endfunction
    virtual function void r_post(input r_t t);   h_r.post(t);  endfunction
endclass
/* verilator lint_on UNUSEDSIGNAL */
