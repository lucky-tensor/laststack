; ============================================================================
; Alien Stack Storage Demo: Epoch Monotonicity Proof Obligation
; ============================================================================
; Discharges the no-wrap clause of @cmd_add's postcondition (!118 in ips.ll):
;
;   Under the epoch_guard (epoch_old != 2^64-1), the successor epoch
;   epoch_new = epoch_old + 1 (bitvector add) is strictly greater than
;   epoch_old — i.e. the increment can never wrap to 0 and epoch ordering
;   is preserved across commits.
;
; Obligation 1: guarded increment is strictly increasing (no wrap).
; Obligation 2: without the guard, wrap IS possible — sanity check that the
;               guard is necessary, encoded as: wrap implies epoch_old was
;               the ceiling value (so rejecting the ceiling closes the hole).
;
; Both check-sat calls must return: unsat
; ============================================================================

(set-logic QF_BV)

; ---- Obligation 1: no wrap under the guard ---------------------------------
(push)
(declare-const epoch_old (_ BitVec 64))
(declare-const epoch_new (_ BitVec 64))

; epoch_guard: cmd_add returns 1 (no write) when epoch_old == 0xFFFF...F
(assert (not (= epoch_old #xffffffffffffffff)))

; the implementation: epoch_new = epoch_old + 1 (bvadd, may wrap in general)
(assert (= epoch_new (bvadd epoch_old #x0000000000000001)))

; negated postcondition: epoch_new is NOT strictly greater than epoch_old
(assert (not (bvugt epoch_new epoch_old)))

; must be unsat: under the guard there is no counterexample to monotonicity
(check-sat)
(pop)

; ---- Obligation 2: the guard is exactly the wrap case ----------------------
(push)
(declare-const epoch_old2 (_ BitVec 64))
(declare-const epoch_new2 (_ BitVec 64))

(assert (= epoch_new2 (bvadd epoch_old2 #x0000000000000001)))

; counterexample search: a wrap (epoch_new2 <= epoch_old2) where epoch_old2
; was NOT the ceiling value — if such a case existed the guard would be
; insufficient
(assert (not (bvugt epoch_new2 epoch_old2)))
(assert (not (= epoch_old2 #xffffffffffffffff)))

; must be unsat: wrap only happens at the ceiling, which the guard rejects
(check-sat)
(pop)
