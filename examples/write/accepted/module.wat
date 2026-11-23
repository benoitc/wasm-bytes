;; The text examples/write/accepted/reply.txt was assembled from.
(module
  (func (export "retry") (param i32) (result i32)
    (i32.or
      (i32.eq (local.get 0) (i32.const 429))
      (i32.lt_u (i32.sub (local.get 0) (i32.const 500)) (i32.const 100)))))
