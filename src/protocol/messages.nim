import ../winapi
import ../utils/[memory, numbers]
import json

type
  Operation* = enum
    opNone,
    opPing,
    opEcho,
    opAdd

  ErrorCode* = enum
    errNone,
    errInvalidFrame,
    errFrameTooLarge,
    errInvalidJson,
    errInvalidRequest,
    errUnknownOperation,
    errResponseTooLarge,
    errServerError

  Request* {.pure.} = object
    id*: uint32
    op*: Operation
    text*: array[PROTOCOL_MAX_BODY, byte]
    textLen*: int
    a*: int32
    b*: int32

  ResponseParseResult* {.pure.} = object
    ok*: bool
    id*: uint32
    idIsNull*: bool
    error*: ErrorCode
    text*: array[PROTOCOL_MAX_BODY, byte]
    textLen*: int
    sum*: int64
    pong*: bool

proc bytesEqLit(p: pointer, n: int, s: static string): bool {.inline.} =
  if n != s.len: return false
  let b = cast[ptr UncheckedArray[byte]](p)
  var i = 0
  while i < s.len:
    if b[i] != cast[byte](s[i]): return false
    i = i + 1
  return true

proc keyId(key: pointer, len: int): int {.inline.} =
  if bytesEqLit(key, len, "v"): return 1
  if bytesEqLit(key, len, "id"): return 2
  if bytesEqLit(key, len, "op"): return 3
  if bytesEqLit(key, len, "text"): return 4
  if bytesEqLit(key, len, "a"): return 5
  if bytesEqLit(key, len, "b"): return 6
  if bytesEqLit(key, len, "ok"): return 7
  if bytesEqLit(key, len, "result"): return 8
  if bytesEqLit(key, len, "error"): return 9
  if bytesEqLit(key, len, "code"): return 10
  if bytesEqLit(key, len, "message"): return 11
  if bytesEqLit(key, len, "pong"): return 12
  if bytesEqLit(key, len, "sum"): return 13
  return 0

proc errorFromName(p: pointer, len: int): ErrorCode {.inline.} =
  if bytesEqLit(p, len, "invalid_frame"): return errInvalidFrame
  if bytesEqLit(p, len, "frame_too_large"): return errFrameTooLarge
  if bytesEqLit(p, len, "invalid_json"): return errInvalidJson
  if bytesEqLit(p, len, "invalid_request"): return errInvalidRequest
  if bytesEqLit(p, len, "unknown_operation"): return errUnknownOperation
  if bytesEqLit(p, len, "response_too_large"): return errResponseTooLarge
  return errServerError

proc appendLit(buf: ptr UncheckedArray[byte], pos: var int, cap: int, s: static string): bool {.inline.} =
  var i = 0
  while i < s.len:
    if pos >= cap: return false
    buf[pos] = cast[byte](s[i])
    pos = pos + 1
    i = i + 1
  return true

proc appendErrorCodeName(buf: ptr UncheckedArray[byte], pos: var int, cap: int, e: ErrorCode): bool {.inline.} =
  case e
  of errInvalidFrame: return appendLit(buf, pos, cap, "invalid_frame")
  of errFrameTooLarge: return appendLit(buf, pos, cap, "frame_too_large")
  of errInvalidJson: return appendLit(buf, pos, cap, "invalid_json")
  of errInvalidRequest: return appendLit(buf, pos, cap, "invalid_request")
  of errUnknownOperation: return appendLit(buf, pos, cap, "unknown_operation")
  of errResponseTooLarge: return appendLit(buf, pos, cap, "response_too_large")
  else: return appendLit(buf, pos, cap, "server_error")

proc appendErrorMessage(buf: ptr UncheckedArray[byte], pos: var int, cap: int, e: ErrorCode): bool {.inline.} =
  case e
  of errInvalidFrame: return appendLit(buf, pos, cap, "invalid frame")
  of errFrameTooLarge: return appendLit(buf, pos, cap, "frame too large")
  of errInvalidJson: return appendLit(buf, pos, cap, "invalid JSON")
  of errInvalidRequest: return appendLit(buf, pos, cap, "invalid request")
  of errUnknownOperation: return appendLit(buf, pos, cap, "unknown operation")
  of errResponseTooLarge: return appendLit(buf, pos, cap, "response too large")
  else: return appendLit(buf, pos, cap, "server error")

proc appendEscaped*(buf: ptr UncheckedArray[byte], pos: var int, cap: int, text: pointer, textLen: int): bool =
  let p = cast[ptr UncheckedArray[byte]](text)
  var i = 0
  while i < textLen:
    let b = p[i]
    case b
    of cast[byte]('"'):
      if pos + 2 > cap: return false
      buf[pos] = cast[byte]('\\'); buf[pos + 1] = cast[byte]('"'); pos = pos + 2
    of cast[byte]('\\'):
      if pos + 2 > cap: return false
      buf[pos] = cast[byte]('\\'); buf[pos + 1] = cast[byte]('\\'); pos = pos + 2
    of 0x08'u8:
      if pos + 2 > cap: return false
      buf[pos] = cast[byte]('\\'); buf[pos + 1] = cast[byte]('b'); pos = pos + 2
    of 0x0c'u8:
      if pos + 2 > cap: return false
      buf[pos] = cast[byte]('\\'); buf[pos + 1] = cast[byte]('f'); pos = pos + 2
    of 0x0a'u8:
      if pos + 2 > cap: return false
      buf[pos] = cast[byte]('\\'); buf[pos + 1] = cast[byte]('n'); pos = pos + 2
    of 0x0d'u8:
      if pos + 2 > cap: return false
      buf[pos] = cast[byte]('\\'); buf[pos + 1] = cast[byte]('r'); pos = pos + 2
    of 0x09'u8:
      if pos + 2 > cap: return false
      buf[pos] = cast[byte]('\\'); buf[pos + 1] = cast[byte]('t'); pos = pos + 2
    else:
      if b < 0x20'u8:
        if pos + 6 > cap: return false
        buf[pos] = cast[byte]('\\'); buf[pos + 1] = cast[byte]('u'); buf[pos + 2] = cast[byte]('0'); buf[pos + 3] = cast[byte]('0')
        const hex = "0123456789abcdef"
        buf[pos + 4] = cast[byte](hex[cast[int>((b shr 4) and 0xf'u8)])
        buf[pos + 5] = cast[byte](hex[cast[int](b and 0xf'u8)])
        pos = pos + 6
      else:
        if pos >= cap: return false
        buf[pos] = b
        pos = pos + 1
    i = i + 1
  return true

proc parseRequest*(data: pointer, len: int, req: var Request, err: var ErrorCode, idKnown: var bool): bool =
  zeroBytes(req.addr, sizeof(Request))
  idKnown = false
  err = errInvalidJson
  var c: JsonCursor
  initJson(c, data, len)
  if not consume(c, cast[byte]('{')): return false

  var haveV = false
  var haveId = false
  var haveOp = false
  var haveText = false
  var haveA = false
  var haveB = false
  var first = true
  var key: array[16, byte]
  var keyLen = 0
  var opBuf: array[16, byte]
  var opLen = 0

  skipWs(c)
  if consume(c, cast[byte]('}')):
    err = errInvalidRequest
    return false

  while true:
    if not first:
      if not consume(c, cast[byte](',')):
        err = errInvalidJson
        return false
    first = false

    let ks = parseString(c, key[0].addr, key.len, keyLen)
    if ks != jsOk:
      err = if ks == jsTooLarge: errInvalidRequest else: errInvalidJson
      return false
    if not consume(c, cast[byte](':')):
      err = errInvalidJson
      return false

    let kid = keyId(key[0].addr, keyLen)
    case kid
    of 1:
      if haveV: err = errInvalidRequest; return false
      haveV = true
      var v: int64
      let st = parseInt64(c, v)
      if st != jsOk or v != 1'i64: err = errInvalidRequest; return false
    of 2:
      if haveId: err = errInvalidRequest; return false
      haveId = true
      var idv: int64
      let st = parseInt64(c, idv)
      if st != jsOk or idv < 0'i64 or idv > 0xffffffff'i64: err = errInvalidRequest; return false
      req.id = cast[uint32](idv)
      idKnown = true
    of 3:
      if haveOp: err = errInvalidRequest; return false
      haveOp = true
      let st = parseString(c, opBuf[0].addr, opBuf.len, opLen)
      if st != jsOk: err = if st == jsInvalid: errInvalidJson else: errInvalidRequest; return false
      if bytesEqLit(opBuf[0].addr, opLen, "ping"):
        req.op = opPing
      elif bytesEqLit(opBuf[0].addr, opLen, "echo"):
        req.op = opEcho
      elif bytesEqLit(opBuf[0].addr, opLen, "add"):
        req.op = opAdd
      else:
        err = errUnknownOperation
        return false
    of 4:
      if haveText: err = errInvalidRequest; return false
      haveText = true
      let st = parseString(c, req.text[0].addr, PROTOCOL_MAX_BODY, req.textLen)
      if st != jsOk: err = if st == jsInvalid: errInvalidJson else: errInvalidRequest; return false
    of 5:
      if haveA: err = errInvalidRequest; return false
      haveA = true
      var av: int64
      let st = parseInt64(c, av)
      if st != jsOk or av < -2147483648'i64 or av > 2147483647'i64: err = errInvalidRequest; return false
      req.a = cast[int32](av)
    of 6:
      if haveB: err = errInvalidRequest; return false
      haveB = true
      var bv: int64
      let st = parseInt64(c, bv)
      if st != jsOk or bv < -2147483648'i64 or bv > 2147483647'i64: err = errInvalidRequest; return false
      req.b = cast[int32](bv)
    else:
      err = errInvalidRequest
      return false

    skipWs(c)
    if consume(c, cast[byte]('}')): break

  skipWs(c)
  if not atEnd(c):
    err = errInvalidJson
    return false

  if not haveV or not haveId or not haveOp:
    err = errInvalidRequest
    return false
  case req.op
  of opPing:
    if haveText or haveA or haveB: err = errInvalidRequest; return false
  of opEcho:
    if not haveText or haveA or haveB: err = errInvalidRequest; return false
  of opAdd:
    if not haveA or not haveB or haveText: err = errInvalidRequest; return false
  else:
    err = errUnknownOperation
    return false
  err = errNone
  return true

proc serializeError*(outp: pointer, cap: int, e: ErrorCode, idKnown: bool, id: uint32, outLen: var int): bool =
  let b = cast[ptr UncheckedArray[byte]](outp)
  var pos = 0
  if not appendLit(b, pos, cap, "{\"v\":1,\"id\":"): return false
  if idKnown:
    if not appendU32Dec(b, pos, cap, id): return false
  else:
    if not appendLit(b, pos, cap, "null"): return false
  if not appendLit(b, pos, cap, ",\"ok\":false,\"error\":{\"code\":\""): return false
  if not appendErrorCodeName(b, pos, cap, e): return false
  if not appendLit(b, pos, cap, "\",\"message\":\""): return false
  if not appendErrorMessage(b, pos, cap, e): return false
  if not appendLit(b, pos, cap, "\"}}") : return false
  outLen = pos
  return outLen <= PROTOCOL_MAX_BODY

proc serializeSuccess*(req: var Request, outp: pointer, cap: int, outLen: var int): bool =
  let b = cast[ptr UncheckedArray[byte]](outp)
  var pos = 0
  if not appendLit(b, pos, cap, "{\"v\":1,\"id\":"): return false
  if not appendU32Dec(b, pos, cap, req.id): return false
  if not appendLit(b, pos, cap, ",\"ok\":true,\"result\":{"): return false
  case req.op
  of opPing:
    if not appendLit(b, pos, cap, "\"pong\":true}") : return false
  of opEcho:
    if not appendLit(b, pos, cap, "\"text\":\""): return false
    if not appendEscaped(b, pos, cap, req.text[0].addr, req.textLen): return false
    if not appendLit(b, pos, cap, "\"}") : return false
  of opAdd:
    if not appendLit(b, pos, cap, "\"sum\":"): return false
    let sum = cast[int64](req.a) + cast[int64](req.b)
    if not appendI64Dec(b, pos, cap, sum): return false
    if not appendLit(b, pos, cap, "}") : return false
  else:
    return false
  if not appendLit(b, pos, cap, "}") : return false
  outLen = pos
  return outLen <= PROTOCOL_MAX_BODY

proc handleRequest*(body: pointer, bodyLen: int, outp: pointer, cap: int, outLen: var int): ErrorCode =
  var req: Request
  var err: ErrorCode
  var idKnown = false
  if not parseRequest(body, bodyLen, req, err, idKnown):
    if not serializeError(outp, cap, err, idKnown, req.id, outLen):
      discard serializeError(outp, cap, errResponseTooLarge, false, 0'u32, outLen)
      return errResponseTooLarge
    return err
  if not serializeSuccess(req, outp, cap, outLen):
    discard serializeError(outp, cap, errResponseTooLarge, true, req.id, outLen)
    return errResponseTooLarge
  return errNone

proc buildPingRequest*(id: uint32, outp: pointer, cap: int, outLen: var int): bool =
  let b = cast[ptr UncheckedArray[byte]](outp)
  var pos = 0
  if not appendLit(b, pos, cap, "{\"v\":1,\"id\":"): return false
  if not appendU32Dec(b, pos, cap, id): return false
  if not appendLit(b, pos, cap, ",\"op\":\"ping\"}"): return false
  outLen = pos
  return true

proc buildEchoRequest*(id: uint32, text: pointer, textLen: int, outp: pointer, cap: int, outLen: var int): bool =
  let b = cast[ptr UncheckedArray[byte]](outp)
  var pos = 0
  if not appendLit(b, pos, cap, "{\"v\":1,\"id\":"): return false
  if not appendU32Dec(b, pos, cap, id): return false
  if not appendLit(b, pos, cap, ",\"op\":\"echo\",\"text\":\""): return false
  if not appendEscaped(b, pos, cap, text, textLen): return false
  if not appendLit(b, pos, cap, "\"}"): return false
  outLen = pos
  return outLen <= PROTOCOL_MAX_BODY

proc buildAddRequest*(id: uint32, a: int32, bv: int32, outp: pointer, cap: int, outLen: var int): bool =
  let b = cast[ptr UncheckedArray[byte]](outp)
  var pos = 0
  if not appendLit(b, pos, cap, "{\"v\":1,\"id\":"): return false
  if not appendU32Dec(b, pos, cap, id): return false
  if not appendLit(b, pos, cap, ",\"op\":\"add\",\"a\":"): return false
  if not appendI64Dec(b, pos, cap, cast[int64](a)): return false
  if not appendLit(b, pos, cap, ",\"b\":"): return false
  if not appendI64Dec(b, pos, cap, cast[int64](bv)): return false
  if not appendLit(b, pos, cap, "}"): return false
  outLen = pos
  return true

proc parseResultObject(c: var JsonCursor, expectedOp: Operation, r: var ResponseParseResult): bool =
  if not consume(c, cast[byte]('{')): return false
  var first = true
  var key: array[16, byte]
  var keyLen = 0
  var seen = false
  skipWs(c)
  if consume(c, cast[byte]('}')): return false
  while true:
    if not first:
      if not consume(c, cast[byte](',')): return false
    first = false
    let ks = parseString(c, key[0].addr, key.len, keyLen)
    if ks != jsOk: return false
    if not consume(c, cast[byte](':')): return false
    let kid = keyId(key[0].addr, keyLen)
    case expectedOp
    of opPing:
      if kid != 12 or seen: return false
      var bv = false
      if not parseBool(c, bv) or not bv: return false
      r.pong = true
      seen = true
    of opEcho:
      if kid != 4 or seen: return false
      let st = parseString(c, r.text[0].addr, PROTOCOL_MAX_BODY, r.textLen)
      if st != jsOk: return false
      seen = true
    of opAdd:
      if kid != 13 or seen: return false
      var sv: int64
      if parseInt64(c, sv) != jsOk: return false
      r.sum = sv
      seen = true
    else:
      return false
    skipWs(c)
    if consume(c, cast[byte]('}')): break
  return seen

proc parseErrorObject(c: var JsonCursor, r: var ResponseParseResult): bool =
  if not consume(c, cast[byte]('{')): return false
  var key: array[16, byte]
  var keyLen = 0
  var code: array[32, byte]
  var codeLen = 0
  var msg: array[64, byte]
  var msgLen = 0
  var haveCode = false
  var haveMessage = false
  var first = true
  skipWs(c)
  if consume(c, cast[byte]('}')): return false
  while true:
    if not first:
      if not consume(c, cast[byte](',')): return false
    first = false
    if parseString(c, key[0].addr, key.len, keyLen) != jsOk: return false
    if not consume(c, cast[byte](':')): return false
    let kid = keyId(key[0].addr, keyLen)
    if kid == 10:
      if haveCode: return false
      if parseString(c, code[0].addr, code.len, codeLen) != jsOk: return false
      r.error = errorFromName(code[0].addr, codeLen)
      haveCode = true
    elif kid == 11:
      if haveMessage: return false
      if parseString(c, msg[0].addr, msg.len, msgLen) != jsOk: return false
      haveMessage = true
    else:
      return false
    skipWs(c)
    if consume(c, cast[byte]('}')): break
  return haveCode and haveMessage

proc parseResponse*(data: pointer, len: int, expectedId: uint32, expectedOp: Operation, r: var ResponseParseResult): bool =
  zeroBytes(r.addr, sizeof(ResponseParseResult))
  var c: JsonCursor
  initJson(c, data, len)
  if not consume(c, cast[byte]('{')): return false

  var haveV = false
  var haveId = false
  var haveOk = false
  var haveResult = false
  var haveError = false
  var key: array[16, byte]
  var keyLen = 0
  var first = true
  skipWs(c)
  if consume(c, cast[byte]('}')): return false
  while true:
    if not first:
      if not consume(c, cast[byte](',')): return false
    first = false
    if parseString(c, key[0].addr, key.len, keyLen) != jsOk: return false
    if not consume(c, cast[byte](':')): return false
    let kid = keyId(key[0].addr, keyLen)
    case kid
    of 1:
      if haveV: return false
      haveV = true
      var v: int64
      if parseInt64(c, v) != jsOk or v != 1'i64: return false
    of 2:
      if haveId: return false
      haveId = true
      if parseNull(c):
        r.idIsNull = true
      else:
        var idv: int64
        if parseInt64(c, idv) != jsOk or idv < 0'i64 or idv > 0xffffffff'i64: return false
        r.id = cast[uint32](idv)
    of 7:
      if haveOk: return false
      haveOk = true
      if not parseBool(c, r.ok): return false
    of 8:
      if haveResult: return false
      haveResult = true
      if not parseResultObject(c, expectedOp, r): return false
    of 9:
      if haveError: return false
      haveError = true
      if not parseErrorObject(c, r): return false
    else:
      return false
    skipWs(c)
    if consume(c, cast[byte]('}')): break

  skipWs(c)
  if not atEnd(c): return false
  if not haveV or not haveId or not haveOk: return false
  if r.ok:
    if r.idIsNull or r.id != expectedId or not haveResult or haveError: return false
  else:
    if (not r.idIsNull) and r.id != expectedId: return false
    if not haveError or haveResult: return false
  return true
