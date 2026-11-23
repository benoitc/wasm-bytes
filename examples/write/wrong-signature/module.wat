;; As write/accepted, computed on an i64 argument.
(module
  (func (export "retry") (param i64) (result i32)
    (i32.or
      (i64.eq (local.get 0) (i64.const 429))
      (i64.lt_u (i64.sub (local.get 0) (i64.const 500)) (i64.const 100)))))
