;; The text examples/pan/accepted/reply.txt was assembled from, with
;; wasm-tools parse and strip: the recovered expression in double precision,
;; truncated toward zero.
(module
  (func (export "screen_pan") (param $x i32) (result i32)
    (i32.trunc_f64_s
      (f64.mul
        (f64.sub (f64.mul (f64.convert_i32_s (local.get $x)) (f64.const 1.5625))
                 (f64.const 500))
        (f64.const 1)))))
