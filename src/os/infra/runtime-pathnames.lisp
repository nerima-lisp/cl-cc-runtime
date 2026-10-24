(in-package :cl-cc/runtime/os/infra)

(in-package :cl-cc/runtime/os/infra)

(sb-alien:define-alien-callable cl_cc_bignum_mul
    sb-alien:long
    ((a sb-alien:long) (b sb-alien:long))
  (rt-native-bignum-mul a b))

(sb-alien:define-alien-callable cl_cc_bignum_sub
    sb-alien:long
    ((a sb-alien:long) (b sb-alien:long))
  (rt-native-bignum-sub a b))

(sb-alien:define-alien-callable cl_cc_bignum_add
    sb-alien:long
    ((a sb-alien:long) (b sb-alien:long))
  (rt-native-bignum-add a b))
