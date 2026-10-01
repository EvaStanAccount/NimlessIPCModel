type
  JsonStatus* = enum
    jsOk,
    jsInvalid,
    jsTooLarge,
    jsOverflow,
    jsWrongType

  JsonCursor* {.pure.} = object
    data*: ptr UncheckedArray[byte]
    len*: int
    pos*: int

proc initJson*(c: var JsonCursor, data: pointer, len: int) {.inline.} =
  c.data = cast[ptr UncheckedArray[byte]](data)
  c.len = len
  c.pos = 0

proc atEnd*(c: var JsonCursor): bool {.inline.} =
  return c.pos >= c.len

proc peek*(c: var JsonCursor): byte {.inline.} =
  if c.pos >= c.len: return 0'u8
  return c.data[c.pos]

proc skipWs*(c: var JsonCursor) {.inline.} =
  while c.pos < c.len:
    let b = c.data[c.pos]
    if b == 0x20'u8 or b == 0x09'u8 or b == 0x0a'u8 or b == 0x0d'u8:
      c.pos = c.pos + 1
    else:
      break

proc consume*(c: var JsonCursor, b: byte): bool {.inline.} =
  skipWs(c)
  if c.pos < c.len and c.data[c.pos] == b:
    c.pos = c.pos + 1
    return true
  return false

proc hexValue(b: byte): int {.inline.} =
  if b >= cast[byte]('0') and b <= cast[byte]('9'):
    return cast[int](b - cast[byte]('0'))
  if b >= cast[byte]('a') and b <= cast[byte]('f'):
    return cast[int](b - cast[byte]('a')) + 10
  if b >= cast[byte]('A') and b <= cast[byte]('F'):
    return cast[int](b - cast[byte]('A')) + 10
  return -1

proc readHex4(c: var JsonCursor, outv: var uint32): JsonStatus {.inline.} =
  if c.pos + 4 > c.len:
    return jsInvalid
  var v: uint32 = 0'u32
  var i = 0
  while i < 4:
    let h = hexValue(c.data[c.pos + i])
    if h < 0:
      return jsInvalid
    v = (v shl 4) or cast[uint32](h)
    i = i + 1
  c.pos = c.pos + 4
  outv = v
  return jsOk

proc appendUtf8(dst: ptr UncheckedArray[byte], outLen: var int, cap: int, cp: uint32): JsonStatus {.inline.} =
  if cp <= 0x7f'u32:
    if outLen + 1 > cap: return jsTooLarge
    dst[outLen] = cast[byte](cp)
    outLen = outLen + 1
  elif cp <= 0x7ff'u32:
    if outLen + 2 > cap: return jsTooLarge
    dst[outLen] = cast[byte](0xc0'u32 or (cp shr 6))
    dst[outLen + 1] = cast[byte](0x80'u32 or (cp and 0x3f'u32))
    outLen = outLen + 2
  elif cp <= 0xffff'u32:
    if outLen + 3 > cap: return jsTooLarge
    dst[outLen] = cast[byte](0xe0'u32 or (cp shr 12))
    dst[outLen + 1] = cast[byte](0x80'u32 or ((cp shr 6) and 0x3f'u32))
    dst[outLen + 2] = cast[byte](0x80'u32 or (cp and 0x3f'u32))
    outLen = outLen + 3
  elif cp <= 0x10ffff'u32:
    if outLen + 4 > cap: return jsTooLarge
    dst[outLen] = cast[byte](0xf0'u32 or (cp shr 18))
    dst[outLen + 1] = cast[byte](0x80'u32 or ((cp shr 12) and 0x3f'u32))
    dst[outLen + 2] = cast[byte](0x80'u32 or ((cp shr 6) and 0x3f'u32))
    dst[outLen + 3] = cast[byte](0x80'u32 or (cp and 0x3f'u32))
    outLen = outLen + 4
  else:
    return jsInvalid
  return jsOk

proc validateAndCopyUtf8(c: var JsonCursor, dst: ptr UncheckedArray[byte], outLen: var int, cap: int): JsonStatus {.inline.} =
  let b = c.data[c.pos]
  var need = 0
  var cp: uint32 = 0'u32
  var minv: uint32 = 0'u32
  if b < 0x80'u8:
    if b < 0x20'u8: return jsInvalid
    if outLen + 1 > cap: return jsTooLarge
    dst[outLen] = b
    outLen = outLen + 1
    c.pos = c.pos + 1
    return jsOk
  elif b >= 0xc2'u8 and b <= 0xdf'u8:
    need = 2
    cp = cast[uint32](b and 0x1f'u8)
    minv = 0x80'u32
  elif b >= 0xe0'u8 and b <= 0xef'u8:
    need = 3
    cp = cast[uint32](b and 0x0f'u8)
    minv = 0x800'u32
  elif b >= 0xf0'u8 and b <= 0xf4'u8:
    need = 4
    cp = cast[uint32](b and 0x07'u8)
    minv = 0x10000'u32
  else:
    return jsInvalid

  if c.pos + need > c.len:
    return jsInvalid
  var i = 1
  while i < need:
    let cb = c.data[c.pos + i]
    if (cb and 0xc0'u8) != 0x80'u8:
      return jsInvalid
    cp = (cp shl 6) or cast[uint32](cb and 0x3f'u8)
    i = i + 1
  if cp < minv or cp > 0x10ffff'u32 or (cp >= 0xd800'u32 and cp <= 0xdfff'u32):
    return jsInvalid
  if outLen + need > cap:
    return jsTooLarge
  i = 0
  while i < need:
    dst[outLen + i] = c.data[c.pos + i]
    i = i + 1
  outLen = outLen + need
  c.pos = c.pos + need
  return jsOk

proc parseString*(c: var JsonCursor, dst: pointer, cap: int, outLen: var int): JsonStatus =
  skipWs(c)
  if c.pos >= c.len or c.data[c.pos] != cast[byte]('"'):
    return jsWrongType
  c.pos = c.pos + 1
  outLen = 0
  let outp = cast[ptr UncheckedArray[byte]](dst)
  while c.pos < c.len:
    let b = c.data[c.pos]
    if b == cast[byte]('"'):
      c.pos = c.pos + 1
      return jsOk
    if b == cast[byte]('\\'):
      c.pos = c.pos + 1
      if c.pos >= c.len:
        return jsInvalid
      let e = c.data[c.pos]
      c.pos = c.pos + 1
      case e
      of cast[byte]('"'), cast[byte]('\\'), cast[byte]('/'):
        if outLen + 1 > cap: return jsTooLarge
        outp[outLen] = e
        outLen = outLen + 1
      of cast[byte]('b'):
        if outLen + 1 > cap: return jsTooLarge
        outp[outLen] = 0x08'u8
        outLen = outLen + 1
      of cast[byte]('f'):
        if outLen + 1 > cap: return jsTooLarge
        outp[outLen] = 0x0c'u8
        outLen = outLen + 1
      of cast[byte]('n'):
        if outLen + 1 > cap: return jsTooLarge
        outp[outLen] = 0x0a'u8
        outLen = outLen + 1
      of cast[byte]('r'):
        if outLen + 1 > cap: return jsTooLarge
        outp[outLen] = 0x0d'u8
        outLen = outLen + 1
      of cast[byte]('t'):
        if outLen + 1 > cap: return jsTooLarge
        outp[outLen] = 0x09'u8
        outLen = outLen + 1
      of cast[byte]('u'):
        var cp: uint32
        var st = readHex4(c, cp)
        if st != jsOk: return st
        if cp >= 0xd800'u32 and cp <= 0xdbff'u32:
          if c.pos + 6 > c.len or c.data[c.pos] != cast[byte]('\\') or c.data[c.pos + 1] != cast[byte]('u'):
            return jsInvalid
          c.pos = c.pos + 2
          var lo: uint32
          st = readHex4(c, lo)
          if st != jsOk: return st
          if lo < 0xdc00'u32 or lo > 0xdfff'u32:
            return jsInvalid
          cp = 0x10000'u32 + (((cp - 0xd800'u32) shl 10) or (lo - 0xdc00'u32))
        elif cp >= 0xdc00'u32 and cp <= 0xdfff'u32:
          return jsInvalid
        st = appendUtf8(outp, outLen, cap, cp)
        if st != jsOk: return st
      else:
        return jsInvalid
    else:
      let st = validateAndCopyUtf8(c, outp, outLen, cap)
      if st != jsOk: return st
  return jsInvalid

proc parseInt64*(c: var JsonCursor, value: var int64): JsonStatus =
  skipWs(c)
  if c.pos >= c.len:
    return jsWrongType
  var neg = false
  if c.data[c.pos] == cast[byte]('-'):
    neg = true
    c.pos = c.pos + 1
    if c.pos >= c.len:
      return jsInvalid
  if c.data[c.pos] < cast[byte]('0') or c.data[c.pos] > cast[byte]('9'):
    return jsWrongType
  var acc: uint64 = 0'u64
  if c.data[c.pos] == cast[byte]('0'):
    c.pos = c.pos + 1
    if c.pos < c.len and c.data[c.pos] >= cast[byte]('0') and c.data[c.pos] <= cast[byte]('9'):
      return jsInvalid
  else:
    while c.pos < c.len and c.data[c.pos] >= cast[byte]('0') and c.data[c.pos] <= cast[byte]('9'):
      let d = cast[uint64](c.data[c.pos] - cast[byte]('0'))
      let limit = if neg: 9223372036854775808'u64 else: 9223372036854775807'u64
      if acc > (limit - d) div 10'u64:
        return jsOverflow
      acc = acc * 10'u64 + d
      c.pos = c.pos + 1
  if c.pos < c.len and (c.data[c.pos] == cast[byte]('.') or c.data[c.pos] == cast[byte]('e') or c.data[c.pos] == cast[byte]('E')):
    return jsWrongType
  if neg:
    if acc == 9223372036854775808'u64:
      value = low(int64)
    else:
      value = 0'i64 - cast[int64](acc)
  else:
    value = cast[int64](acc)
  return jsOk

proc parseNull*(c: var JsonCursor): bool =
  skipWs(c)
  if c.pos + 4 <= c.len and c.data[c.pos] == cast[byte]('n') and c.data[c.pos + 1] == cast[byte]('u') and c.data[c.pos + 2] == cast[byte]('l') and c.data[c.pos + 3] == cast[byte]('l'):
    c.pos = c.pos + 4
    return true
  return false

proc parseBool*(c: var JsonCursor, value: var bool): bool =
  skipWs(c)
  if c.pos + 4 <= c.len and c.data[c.pos] == cast[byte]('t') and c.data[c.pos + 1] == cast[byte]('r') and c.data[c.pos + 2] == cast[byte]('u') and c.data[c.pos + 3] == cast[byte]('e'):
    c.pos = c.pos + 4
    value = true
    return true
  if c.pos + 5 <= c.len and c.data[c.pos] == cast[byte]('f') and c.data[c.pos + 1] == cast[byte]('a') and c.data[c.pos + 2] == cast[byte]('l') and c.data[c.pos + 3] == cast[byte]('s') and c.data[c.pos + 4] == cast[byte]('e'):
    c.pos = c.pos + 5
    value = false
    return true
  return false
