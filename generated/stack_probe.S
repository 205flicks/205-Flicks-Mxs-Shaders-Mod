/* Windows x64 stack probe. Original glue, MIT; LICENSE-MXSR.txt. */
.text
.p2align 4
.globl ___chkstk_ms
___chkstk_ms:
    pushq %rcx
    pushq %rax
    leaq 24(%rsp), %rcx
    cmpq $4096, %rax
    jb .Lprobe_tail
.Lprobe_page:
    subq $4096, %rcx
    testb $0, (%rcx)
    subq $4096, %rax
    cmpq $4096, %rax
    jae .Lprobe_page
.Lprobe_tail:
    subq %rax, %rcx
    testb $0, (%rcx)
    popq %rax
    popq %rcx
    retq
