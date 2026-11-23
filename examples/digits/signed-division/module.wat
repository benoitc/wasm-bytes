;; The text examples/digits/signed-division/reply.txt was assembled from,
;; with wasm-tools parse and strip. As accepted, with signed division: 0 - x
;; leaves -2147483648 negative, so its digits come out negative and the sum
;; is -47.
(module
  (func (export "digit_sum") (param $x i32) (result i32)
    (local $n i32) (local $sum i32)
    (local.set $n
      (select (i32.sub (i32.const 0) (local.get $x)) (local.get $x)
              (i32.lt_s (local.get $x) (i32.const 0))))
    (loop $next
      (local.set $sum (i32.add (local.get $sum) (i32.rem_s (local.get $n) (i32.const 10))))
      (local.set $n (i32.div_s (local.get $n) (i32.const 10)))
      (br_if $next (local.get $n)))
    (local.get $sum)))
