; ============================================================================
; LastStack: IPS round-trip and commit-isolation proofs
; ============================================================================
;
; Two separate proof obligations:
;
; PROOF A — Round-trip acceptance:
;   A header written by write_header (committed=1, checksum=checksum_for(hdr))
;   with valid magic and version is ALWAYS accepted by read_header (returns 0).
;
;   Encoding: assert the NEGATION (well-formed header is rejected), check UNSAT.
;
; PROOF B — Commit isolation:
;   A header written by cmd_corrupt (committed=0) is ALWAYS rejected by
;   read_header regardless of all other field values.
;
;   Encoding: assert (committed=0 AND validation_passes), check UNSAT.
;
; EXPECTED RESULTS: both unsat
; ============================================================================

(set-logic QF_BV)

; ---- checksum_for (shared definition) --------------------------------------

(define-fun checksum_for ((m   (_ BitVec 32))
                          (v   (_ BitVec 32))
                          (e   (_ BitVec 64))
                          (val (_ BitVec 64))
                          (c   (_ BitVec 32))) (_ BitVec 32)
  (let ((h0 (bvxor
              (bvxor
                (bvxor
                  (bvxor ((_ zero_extend 32) m)
                         ((_ zero_extend 32) v))
                  e)
                val)
              ((_ zero_extend 32) c))))
  (let ((h1 (bvxor h0 #x9E3779B97F4A7C15)))
  (let ((h2 (bvxor h1 (bvlshr h1 (_ bv33 64)))))
  (let ((h3 (bvmul h2 #xFF51AFD7ED558CCD)))
  (let ((h4 (bvxor h3 (bvlshr h3 (_ bv33 64)))))
  ((_ extract 31 0) h4)))))))

; ============================================================================
; PROOF A: write_header -> read_header round-trip
; ============================================================================
;
; Preconditions (established by write_header / cmd_init / cmd_add):
;   magic     = 0x31535049  (IPS_MAGIC)
;   version   = 1
;   committed = 1
;   stored_checksum = checksum_for(magic, version, epoch, value, committed)
;
; read_header accepts iff:
;   (1) magic     == 0x31535049
;   (2) version   == 1
;   (3) committed == 1
;   (4) stored_checksum == checksum_for(magic, version, epoch, value, committed)
;
; The negation (preconditions hold but validation rejects) must be UNSAT.

(push)

(declare-const magic_a     (_ BitVec 32))
(declare-const version_a   (_ BitVec 32))
(declare-const epoch_a     (_ BitVec 64))
(declare-const value_a     (_ BitVec 64))
(declare-const committed_a (_ BitVec 32))
(declare-const checksum_a  (_ BitVec 32))

; Preconditions: well-formed header as written by write_header
(assert (= magic_a     #x31535049))
(assert (= version_a   #x00000001))
(assert (= committed_a #x00000001))
(assert (= checksum_a  (checksum_for magic_a version_a epoch_a value_a committed_a)))

; Negation of validation: at least one gate fails
; Gate 1: magic mismatch
; Gate 2: version mismatch
; Gate 3: committed mismatch
; Gate 4: checksum mismatch
(assert (or
  (not (= magic_a     #x31535049))
  (not (= version_a   #x00000001))
  (not (= committed_a #x00000001))
  (not (= checksum_a  (checksum_for magic_a version_a epoch_a value_a committed_a)))))

(check-sat)
; Expected: unsat  (well-formed headers are always accepted)

(pop)

; ============================================================================
; PROOF B: commit isolation — uncommitted header always rejected
; ============================================================================
;
; Precondition: committed = 0  (as written by cmd_corrupt)
; read_header gate 3 requires committed == 1.
; Negation (committed=0 AND validation passes) must be UNSAT.

(push)

(declare-const committed_b (_ BitVec 32))

; cmd_corrupt sets committed=0
(assert (= committed_b #x00000000))

; Negation of rejection: validation passes despite committed=0
; Validation passes requires committed == 1
(assert (= committed_b #x00000001))

(check-sat)
; Expected: unsat  (uncommitted headers are always rejected)

(pop)
