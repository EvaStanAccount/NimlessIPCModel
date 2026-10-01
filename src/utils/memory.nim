proc zeroBytes*(dst: pointer, n: int) {.inline.} =
  var p = cast[ptr UncheckedArray[byte]](dst)
  var i = 0
  while i < n:
    p[i] = 0'u8
    i = i + 1

proc copyBytes*(dst: pointer, src: pointer, n: int) {.inline.} =
  var d = cast[ptr UncheckedArray[byte]](dst)
  var s = cast[ptr UncheckedArray[byte]](src)
  var i = 0
  while i < n:
    d[i] = s[i]
    i = i + 1

proc equalBytes*(a: pointer, b: pointer, n: int): bool {.inline.} =
  var pa = cast[ptr UncheckedArray[byte]](a)
  var pb = cast[ptr UncheckedArray[byte]](b)
  var i = 0
  while i < n:
    if pa[i] != pb[i]:
      return false
    i = i + 1
  return true

proc lowerAsciiByte*(b: byte): byte {.inline.} =
  if b >= cast[byte]('A') and b <= cast[byte]('Z'):
    return b xor 0x20'u8
  return b
