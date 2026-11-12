// ------------------------------------------------------------------
// In-order service per AXI ID: a ticket is taken in arrival order, and
// holders of the same ID take turns in ticket order (same ID completes in
// order, different IDs are independent; A5/A6).
// ------------------------------------------------------------------
class axi4_id_turns #(axi4_param_t P = AXI4_PARAM_DEFAULT);
    typedef logic [w1(P.ID_W)-1:0] id_t;
    local int unsigned m_next[id_t];
    local int unsigned m_serving[id_t];
    local int unsigned m_n_release;

    function int unsigned ticket(id_t id);
        if (!m_next.exists(id)) begin
            m_next[id] = 0;
            m_serving[id] = 0;
        end
        return m_next[id]++;
    endfunction

    task wait_turn(id_t id, int unsigned t);
        while (m_serving[id] != t) begin
            int unsigned n = m_n_release;
            wait (m_n_release != n);
        end
    endtask

    function void release_turn(id_t id);
        m_serving[id]++;
        m_n_release++;
    endfunction
endclass
