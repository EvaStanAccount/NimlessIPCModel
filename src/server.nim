import instance
import utils/chkstk
import transport/pipe_server

{.passC:"-masm=intel".}

proc main() {.exportc: "Main".} =
  if not init(ninst):
    if ninst.Win32.ExitProcess != nil:
      ninst.Win32.ExitProcess(1)
    while true: discard
  let code = runServer()
  ninst.Win32.ExitProcess(cast[uint32](code))

proc start() {.asmNoStackframe, codegenDecl: "__attribute__((section (\".text\"))) $# $#$#", exportc: "start".} =
  asm """
    and rsp, 0xfffffffffffffff0
    sub rsp, 0x10
    call Main
    add rsp, 0x10
    ret
  """

when isMainModule:
  start()
