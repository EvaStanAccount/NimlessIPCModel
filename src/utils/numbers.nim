proc appendU32Dec*(buf: ptr UncheckedArray[byte], pos: var int, cap: int, v: uint32): bool =
  var tmp: array[10, byte]
  var n = v
  var count = 0
  if n == 0'u32:
    if pos >= cap: return false
    buf[pos] = cast[byte]('0')
    pos = pos + 1
    return true
  while n > 0'u32:
    tmp[count] = cast[byte](cast[uint32]('0') + (n mod 10'u32))
    n = n div 10'u32
    count = count + 1
  while count > 0:
    count = count - 1
    if pos >= cap: return false
    buf[pos] = tmp[count]
    pos = pos + 1
  return true

proc appendI64Dec*(buf: ptr UncheckedArray[byte], pos: var int, cap: int, value: int64): bool =
  var tmp: array[20, byte]
  var count = 0
  var n: uint64
  if value < 0'i64:
    if pos >= cap: return false
    buf[pos] = cast[byte]('-')
    pos = pos + 1
    n = cast[uint64](0'i64 - (value + 1'i64)) + 1'u64
  else:
    n = cast[uint64](value)
  if n == 0'u64:
    if pos >= cap: return false
    buf[pos] = cast[byte]('0')
    pos = pos + 1
    return true
  while n > 0'u64:
    tmp[count] = cast[byte](cast[uint64]('0') + (n mod 10'u64))
    n = n div 10'u64
    count = count + 1
  while count > 0:
    count = count - 1
    if pos >= cap: return false
    buf[pos] = tmp[count]
    pos = pos + 1
  return true
