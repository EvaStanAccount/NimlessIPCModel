# Minimal MinGW-w64 stack probing helper for nimless builds.
#
# GCC emits calls to ___chkstk_ms for functions with large stack frames. With
# -nostdlib there is no libgcc/CRT helper to satisfy that symbol, so provide the
# Windows x64 probing contract ourselves: RAX contains the allocation size,
# the helper touches each guard page below the caller's stack pointer, preserves
# RAX for the caller's subsequent `sub rsp, rax`, and returns without changing
# the caller-visible stack pointer.

{.passC:"-masm=intel".}

proc chkstk_ms() {.asmNoStackFrame, exportc: "___chkstk_ms", used.} =
  asm """
    push rcx
    push rax
    cmp rax, 0x1000
    lea rcx, [rsp + 0x18]
    jb 2f
  1:
    sub rcx, 0x1000
    test qword ptr [rcx], rax
    sub rax, 0x1000
    cmp rax, 0x1000
    ja 1b
  2:
    sub rcx, rax
    test qword ptr [rcx], rax
    pop rax
    pop rcx
    ret
  """
