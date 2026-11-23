;; The text examples/digits/accepted/reply.txt was assembled from, with
;; wasm-tools parse and strip.
(module
  (func (export "digit_sum") (param $x i32) (result i32)
    (local $n i32) (local $sum i32)
    ;; n = |x|, read as unsigned: 0 - x when x is negative, so that
    ;; -2147483648 becomes 2147483648.
    (local.set $n
      (select (i32.sub (i32.const 0) (local.get $x)) (local.get $x)
              (i32.lt_s (local.get $x) (i32.const 0))))
    (loop $next
      (local.set $sum (i32.add (local.get $sum) (i32.rem_u (local.get $n) (i32.const 10))))
      (local.set $n (i32.div_u (local.get $n) (i32.const 10)))
      (br_if $next (local.get $n)))
    (local.get $sum)))
