import instance
import winapi
import protocol/messages
import transport/pipe_client

{.passC:"-masm=intel".}

type
  Arg {.pure.} = object
    buf: array[512, uint16]
    len: int

proc isSpace(w: uint16): bool {.inline.} =
  return w == 0x20'u16 or w == 0x09'u16

proc putArgChar(arg: var Arg, ch: uint16): bool {.inline.} =
  if arg.len >= arg.buf.len:
    return false
  arg.buf[arg.len] = ch
  arg.len = arg.len + 1
  return true

proc nextArg(p: ptr UncheckedArray[uint16], pos: var int, arg: var Arg): bool =
  arg.len = 0
  while p[pos] != 0'u16 and isSpace(p[pos]):
    pos = pos + 1
  if p[pos] == 0'u16:
    return false

  var inQuotes = false
  while p[pos] != 0'u16:
    if not inQuotes and isSpace(p[pos]):
      break

    if p[pos] == cast[uint16]('\\'):
      var slashCount = 0
      while p[pos] == cast[uint16]('\\'):
        slashCount = slashCount + 1
        pos = pos + 1
      if p[pos] == cast[uint16]('"'):
        var emit = slashCount div 2
        while emit > 0:
          if not putArgChar(arg, cast[uint16]('\\')): return false
          emit = emit - 1
        if (slashCount and 1) == 0:
          inQuotes = not inQuotes
          pos = pos + 1
        else:
          if not putArgChar(arg, cast[uint16]('"')): return false
          pos = pos + 1
      else:
        while slashCount > 0:
          if not putArgChar(arg, cast[uint16]('\\')): return false
          slashCount = slashCount - 1
    elif p[pos] == cast[uint16]('"'):
      inQuotes = not inQuotes
      pos = pos + 1
    else:
      if not putArgChar(arg, p[pos]): return false
      pos = pos + 1

  while p[pos] != 0'u16 and isSpace(p[pos]):
    pos = pos + 1
  return true

proc argEqLit(arg: var Arg, s: static string): bool =
  if arg.len != s.len: return false
  var i = 0
  while i < s.len:
    if arg.buf[i] != cast[uint16](s[i]): return false
    i = i + 1
  return true

proc parseI32Arg(arg: var Arg, outv: var int32): bool =
  if arg.len <= 0: return false
  var i = 0
  var neg = false
  if arg.buf[0] == cast[uint16]('-'):
    neg = true
    i = 1
    if i >= arg.len: return false
  var acc: int64 = 0
  while i < arg.len:
    let ch = arg.buf[i]
    if ch < cast[uint16]('0') or ch > cast[uint16]('9'):
      return false
    let d = cast[int64](ch - cast[uint16]('0'))
    acc = acc * 10'i64 + d
    if (not neg and acc > 2147483647'i64) or (neg and acc > 2147483648'i64):
      return false
    i = i + 1
  if neg:
    outv = cast[int32](0'i64 - acc)
  else:
    outv = cast[int32](acc)
  return true

proc writeLiteral(s: cstring) =
  var n = 0
  let p = cast[ptr UncheckedArray[byte]](s)
  while p[n] != 0'u8: n = n + 1
  discard writeStdout(s, n)

proc convertArgUtf8(arg: var Arg, outp: pointer, cap: int, outLen: var int): bool =
  let r = ninst.Win32.WideCharToMultiByte(CP_UTF8, 0'u32, cast[LPCWSTR](arg.buf[0].addr), cast[INT](arg.len), cast[cstring](outp), cast[INT](cap), nil, nil)
  if r <= 0: return false
  outLen = cast[int](r)
  return true

proc finish(code: ClientExit) =
  ninst.Win32.ExitProcess(cast[uint32](code))

proc main() {.exportc: "Main".} =
  if not init(ninst):
    if ninst.Win32.ExitProcess != nil:
      ninst.Win32.ExitProcess(1)
    while true: discard

  let cmd = ninst.Win32.GetCommandLineW()
  if cmd == nil:
    finish(ceSyntax)
  let p = cast[ptr UncheckedArray[uint16]](cmd)
  var pos = 0
  var exe: Arg
  if not nextArg(p, pos, exe):
    finish(ceSyntax)
  var op: Arg
  if not nextArg(p, pos, op):
    writeLiteral("usage: named-pipe-client.exe ping|echo <text>|add <a> <b>".cstring)
    finish(ceSyntax)

  var req: array[PROTOCOL_MAX_BODY, byte]
  var reqLen = 0
  var expectedOp = opNone
  const id = 1'u32

  if argEqLit(op, "ping"):
    expectedOp = opPing
    if not buildPingRequest(id, req[0].addr, PROTOCOL_MAX_BODY, reqLen): finish(ceProtocol)
  elif argEqLit(op, "echo"):
    expectedOp = opEcho
    var textArg: Arg
    if not nextArg(p, pos, textArg): finish(ceSyntax)
    var utf8: array[PROTOCOL_MAX_BODY, byte]
    var utf8Len = 0
    if not convertArgUtf8(textArg, utf8[0].addr, PROTOCOL_MAX_BODY, utf8Len): finish(ceSyntax)
    if not buildEchoRequest(id, utf8[0].addr, utf8Len, req[0].addr, PROTOCOL_MAX_BODY, reqLen): finish(ceProtocol)
  elif argEqLit(op, "add"):
    expectedOp = opAdd
    var aArg: Arg
    var bArg: Arg
    if not nextArg(p, pos, aArg) or not nextArg(p, pos, bArg): finish(ceSyntax)
    var a: int32
    var b: int32
    if not parseI32Arg(aArg, a) or not parseI32Arg(bArg, b): finish(ceSyntax)
    if not buildAddRequest(id, a, b, req[0].addr, PROTOCOL_MAX_BODY, reqLen): finish(ceProtocol)
  else:
    finish(ceSyntax)

  var extra: Arg
  if nextArg(p, pos, extra):
    finish(ceSyntax)

  var resp: array[PROTOCOL_MAX_BODY, byte]
  var respLen = 0
  let sent = sendRequest(req[0].addr, reqLen, resp[0].addr, respLen)
  if sent != ceOk:
    finish(sent)
  var parsed: ResponseParseResult
  if not parseResponse(resp[0].addr, respLen, id, expectedOp, parsed):
    writeStdout(resp[0].addr, respLen)
    finish(ceProtocol)
  writeStdout(resp[0].addr, respLen)
  if parsed.ok:
    finish(ceOk)
  finish(ceServer)

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
