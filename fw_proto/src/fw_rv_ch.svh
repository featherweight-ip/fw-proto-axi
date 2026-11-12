// ------------------------------------------------------------------
// Channel families
// ------------------------------------------------------------------
// A ready/valid channel carrying payload T. In a bundle, (* fw_fwd *) or
// (* fw_rev *) gives the direction of valid and the payload; ready goes
// the other way. Pins: <ch><member>..., <ch>valid, <ch>ready (the
// payload's members are added by the generated field table).
class fw_rv_ch #(type T = logic);
    /* verilator lint_off UNUSEDSIGNAL */      // names the payload type only
    T payload;
    /* verilator lint_on UNUSEDSIGNAL */

    static function void add_ctl(fw_sp_base sp, string ch, fw_dir_e dir);
        sp.add_field({ch, "valid"}, 1, dir);
        sp.add_field({ch, "ready"}, 1, fw_dir_flip(dir));
    endfunction
endclass
