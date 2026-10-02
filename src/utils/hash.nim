import ../winapi

proc hashLitA*(s: static string): uint32 =
  var hash: uint32 = 0xff'u32
  for ch in s:
    hash = ((hash shl 5) + hash) + cast[uint32](ch)
  return hash

proc hashStrA*(s: cstring): uint32 {.inline.} =
  var hash: uint32 = 0xff'u32
  var p = cast[ptr UncheckedArray[byte]](s)
  var i = 0
  while p[i] != 0'u8:
    hash = ((hash shl 5) + hash) + cast[uint32](p[i])
    i = i + 1
  return hash

proc hashBytesLower*(p: ptr UncheckedArray[WCHAR], byteLen: WORD): uint32 {.inline.} =
  var hash: uint32 = 0xff'u32
  var i = 0
  let count = cast[int](byteLen) div 2
  while i < count:
    var c = p[i]
    if c >= cast[WCHAR]('A') and c <= cast[WCHAR]('Z'):
      c = c xor 0x20'u16
    hash = ((hash shl 5) + hash) + cast[uint32](c and 0xff'u16)
    i = i + 1
  return hash
