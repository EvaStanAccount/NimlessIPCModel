import ../src/instance
import ../src/winapi
import ../src/protocol/[framing, messages]
import ../src/transport/pipe_client

{.passC:"-masm=intel".}

var failures: int32 = 0

proc cstrlen(s: cstring): int =
  let p = cast[ptr UncheckedArray[byte]](s)
  while p[result] != 0'u8:
    result = result + 1

proc fail(msg: cstring) =
  failures = failures + 1
  discard writeStdout(msg, cstrlen(msg))

proc expect(cond: bool, msg: cstring) =
  if not cond: fail(msg)

proc testLen() =
  var h: array[4, byte]
  encodeLenLE(h[0].addr, 0x12345678'u32)
  expect(h[0] == 0x78'u8 and h[1] == 0x56'u8 and h[2] == 0x34'u8 and h[3] == 0x12'u8, "framing endian")
  expect(decodeLenLE(h[0].addr) == 0x12345678'u32, "framing decode")
  expect(validFrameLen(1'u32), "frame min")
  expect(validFrameLen(4096'u32), "frame max")
  expect(not validFrameLen(0'u32), "frame zero")
  expect(not validFrameLen(4097'u32), "frame too large")

proc parseReqLit(s: cstring, len: int, expected: Operation, ok: bool, msg: cstring) =
  var req: Request
  var err: ErrorCode
  var idKnown = false
  let r = parseRequest(s, len, req, err, idKnown)
  expect(r == ok, msg)
  if ok: expect(req.op == expected, msg)

proc testRequests() =
  let ping = "{\"v\":1,\"id\":1,\"op\":\"ping\"}".cstring
  parseReqLit(ping, cstrlen(ping), opPing, true, "ping parse")
  let echoReq = "{ \"op\" : \"echo\" , \"text\" : \"hi\" , \"id\" : 2 , \"v\" : 1 }".cstring
  parseReqLit(echoReq, cstrlen(echoReq), opEcho, true, "echo shuffled")
  let addReq = "{\"v\":1,\"id\":3,\"op\":\"add\",\"a\":-2147483648,\"b\":2147483647}".cstring
  parseReqLit(addReq, cstrlen(addReq), opAdd, true, "add limits")
  let missing = "{\"v\":1,\"op\":\"ping\"}".cstring
  parseReqLit(missing, cstrlen(missing), opPing, false, "missing id")
  let duplicate = "{\"v\":1,\"id\":1,\"id\":2,\"op\":\"ping\"}".cstring
  parseReqLit(duplicate, cstrlen(duplicate), opPing, false, "duplicate id")
  let unknown = "{\"v\":1,\"id\":1,\"op\":\"pong\"}".cstring
  parseReqLit(unknown, cstrlen(unknown), opNone, false, "unknown op")
  let inapp = "{\"v\":1,\"id\":1,\"op\":\"ping\",\"text\":\"x\"}".cstring
  parseReqLit(inapp, cstrlen(inapp), opPing, false, "inapplicable field")
  let overflow = "{\"v\":1,\"id\":1,\"op\":\"add\",\"a\":2147483648,\"b\":1}".cstring
  parseReqLit(overflow, cstrlen(overflow), opAdd, false, "i32 overflow")
  var badUtf8: array[34, byte]
  let prefix = "{\"v\":1,\"id\":1,\"op\":\"echo\",\"text\":\"".cstring
  var i = 0
  while i < 32:
    badUtf8[i] = cast[ptr UncheckedArray[byte]](prefix)[i]
    i = i + 1
  badUtf8[32] = 0xc0'u8
  badUtf8[33] = 0'u8
  parseReqLit(cast[cstring](badUtf8[0].addr), 33, opEcho, false, "bad utf8")

proc testResponses() =
  var outp: array[PROTOCOL_MAX_BODY, byte]
  var outLen = 0
  let req = "{\"v\":1,\"id\":7,\"op\":\"add\",\"a\":20,\"b\":22}".cstring
  let e = handleRequest(req, cstrlen(req), outp[0].addr, PROTOCOL_MAX_BODY, outLen)
  expect(e == errNone, "handle add")
  var r: ResponseParseResult
  expect(parseResponse(outp[0].addr, outLen, 7'u32, opAdd, r), "parse add response")
  expect(r.ok and r.sum == 42'i64, "sum response")
  var tiny: array[8, byte]
  var tinyLen = 0
  var rr: Request
  rr.id = 1'u32
  rr.op = opPing
  expect(not serializeSuccess(rr, tiny[0].addr, tiny.len, tinyLen), "serializer cap")

proc main() {.exportc: "Main".} =
  if not init(ninst):
    if ninst.Win32.ExitProcess != nil: ninst.Win32.ExitProcess(1)
    while true: discard
  testLen()
  testRequests()
  testResponses()
  if failures == 0:
    discard writeStdout("protocol tests ok".cstring, 17)
  ninst.Win32.ExitProcess(cast[uint32](failures))

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
