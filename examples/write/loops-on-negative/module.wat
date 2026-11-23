;; As write/accepted, behind a loop that never ends when x is negative.
(module
  (func (export "retry") (param i32) (result i32)
    (block
      (br_if 0 (i32.ge_s (local.get 0) (i32.const 0)))
      (loop (br 0)))
    (i32.or
      (i32.eq (local.get 0) (i32.const 429))
      (i32.lt_u (i32.sub (local.get 0) (i32.const 500)) (i32.const 100)))))
