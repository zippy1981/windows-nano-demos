/* __chkstk for x64 (MSVC contract): RAX holds the number of bytes to probe. Touch each
   4 KiB page from the current stack down, preserving every register except flags.
   The caller performs the sub rsp, rax itself. Licensed GPL-2.0-or-later. */
    .text
    .globl ros_chkstk
ros_chkstk:
    push %rcx
    push %rax
    cmp $0x1000, %rax
    lea 24(%rsp), %rcx
    jb 2f
1:
    sub $0x1000, %rcx
    orq $0, (%rcx)
    sub $0x1000, %rax
    cmp $0x1000, %rax
    ja 1b
2:
    sub %rax, %rcx
    orq $0, (%rcx)
    pop %rax
    pop %rcx
    ret

    .globl DllMain
DllMain:
    mov $1, %eax
    ret
