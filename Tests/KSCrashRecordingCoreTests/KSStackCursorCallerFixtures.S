#if defined(__arm64__)
.text
.p2align 2
.globl _ks_unwind_test_leaf
_ks_unwind_test_leaf:
.cfi_startproc
ret
.cfi_endproc

.p2align 2
.globl _ks_unwind_test_framed
_ks_unwind_test_framed:
.cfi_startproc
stp x29, x30, [sp, #-16]!
mov x29, sp
.cfi_def_cfa w29, 16
.cfi_offset w30, -8
.cfi_offset w29, -16
nop
ldp x29, x30, [sp], #16
ret
.cfi_endproc

.p2align 2
.globl _ks_unwind_test_dwarf_leaf
_ks_unwind_test_dwarf_leaf:
.cfi_startproc
.cfi_def_cfa sp, 0
.cfi_same_value w30
.cfi_same_value w29
ret
.cfi_endproc

.p2align 2
.globl _ks_unwind_test_dwarf_framed
_ks_unwind_test_dwarf_framed:
.cfi_startproc
stp x29, x30, [sp, #-16]!
.cfi_def_cfa_offset 16
.cfi_offset w30, -8
.cfi_offset w29, -16
mov x29, sp
.cfi_def_cfa_register w29
nop
ldp x29, x30, [sp], #16
ret
.cfi_endproc
#endif
