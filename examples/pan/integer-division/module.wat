;; The text examples/pan/integer-division/reply.txt was assembled from, with
;; wasm-tools parse and strip. Integer arithmetic, dividing before it
;; subtracts: x * 25 / 16 - 500. Truncating x * 25 / 16 first rounds the
;; negative half of the screen the wrong way, so x = 1 gives -499, not -498.
(module
  (func (export "screen_pan") (param $x i32) (result i32)
    (i32.sub (i32.div_s (i32.mul (local.get $x) (i32.const 25)) (i32.const 16))
             (i32.const 500))))
