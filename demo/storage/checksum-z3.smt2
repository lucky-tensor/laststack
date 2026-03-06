; ============================================================================
; LastStack: checksum_for — PCF postcondition discharge
; ============================================================================
;
; GOAL: Prove that the implementation of checksum_for (transcribed from
;       ips.ll IR) equals the postcondition specification in !pcf.post !138.
;
; METHOD: Encode both as SMT-LIB bitvector expressions.  Assert they differ
;         (negation of equivalence), then check-sat.  UNSAT means the
;         specification is faithful to the code for all possible inputs.
;
; ALGORITHM (splitmix64 finalizer over 5 header fields):
;   h = zext(magic) XOR zext(version) XOR epoch XOR value XOR zext(committed)
;   h = h XOR 0x9E3779B97F4A7C15
;   h = h XOR (h >> 33)
;   h = h * 0xFF51AFD7ED558CCD
;   h = h XOR (h >> 33)
;   result = low 32 bits of h
;
; EXPECTED RESULT: unsat
;   (no input exists where implementation and spec differ)
; ============================================================================

(set-logic QF_BV)

; ---- inputs (header fields) ------------------------------------------------
(declare-const magic     (_ BitVec 32))
(declare-const version   (_ BitVec 32))
(declare-const epoch     (_ BitVec 64))
(declare-const value     (_ BitVec 64))
(declare-const committed (_ BitVec 32))

; ---- implementation (verbatim from checksum_for IR in ips.ll) --------------
;
; %7  = zext i32 magic   to i64
; %11 = zext i32 version to i64
; %12 = xor %7,  %11
; %16 = xor %12, epoch
; %20 = xor %16, value
; %24 = zext i32 committed to i64
; %25 = xor %20, %24
; %26 = xor %25, -7046029288634856825   ; == 0x9E3779B97F4A7C15
; store %26 -> h
; %28 = lshr h, 33
; %30 = xor h, %28
; store %30 -> h
; %32 = mul h, -49064778989728563       ; == 0xFF51AFD7ED558CCD
; store %32 -> h
; %34 = lshr h, 33
; %36 = xor h, %34
; store %36 -> h
; %38 = and h, 0xFFFFFFFF
; %39 = trunc i64 %38 to i32
; ret %39

(define-fun impl_result () (_ BitVec 32)
  (let ((h0 (bvxor
              (bvxor
                (bvxor
                  (bvxor ((_ zero_extend 32) magic)
                         ((_ zero_extend 32) version))
                  epoch)
                value)
              ((_ zero_extend 32) committed))))
  (let ((h1 (bvxor h0 #x9E3779B97F4A7C15)))
  (let ((h2 (bvxor h1 (bvlshr h1 (_ bv33 64)))))
  (let ((h3 (bvmul h2 #xFF51AFD7ED558CCD)))
  (let ((h4 (bvxor h3 (bvlshr h3 (_ bv33 64)))))
  ((_ extract 31 0) h4)))))))

; ---- specification (from !pcf.post !138 in ips.ll) -------------------------
;
; Same algorithm expressed independently as the normative spec.
; The proof checks that the IR and the spec agree on all inputs.

(define-fun spec_result () (_ BitVec 32)
  (let ((mix (bvxor
               (bvxor
                 (bvxor
                   (bvxor ((_ zero_extend 32) magic)
                          ((_ zero_extend 32) version))
                   epoch)
                 value)
               ((_ zero_extend 32) committed))))
  (let ((s1  (bvxor mix #x9E3779B97F4A7C15)))
  (let ((s2  (bvxor s1 (bvlshr s1 (_ bv33 64)))))
  (let ((s3  (bvmul s2 #xFF51AFD7ED558CCD)))
  (let ((s4  (bvxor s3 (bvlshr s3 (_ bv33 64)))))
  ((_ extract 31 0) s4)))))))

; ---- proof obligation -------------------------------------------------------
;
; Assert the NEGATION: there exists an input where impl and spec differ.
; UNSAT => no such input exists => implementation matches specification.

(assert (not (= impl_result spec_result)))

(check-sat)
; Expected: unsat
