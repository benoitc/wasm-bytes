;; 408 added and 501 excluded, but the test for 429 is gone.
(module
  (func (export "retry") (param i32) (result i32)
    (i32.or
      (i32.eq (local.get 0) (i32.const 408))
      (i32.and
        (i32.lt_u (i32.sub (local.get 0) (i32.const 500)) (i32.const 100))
        (i32.ne (local.get 0) (i32.const 501))))))
