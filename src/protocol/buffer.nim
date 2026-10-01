type
  FixedWriter* {.pure.} = object
    data*: ptr UncheckedArray[byte]
    cap*: int
    len*: int
    ok*: bool

proc initWriter*(w: var FixedWriter, data: pointer, cap: int) {.inline.} =
  w.data = cast[ptr UncheckedArray[byte]](data)
  w.cap = cap
  w.len = 0
  w.ok = true

proc putByte*(w: var FixedWriter, b: byte) {.inline.} =
  if not w.ok: return
  if w.len >= w.cap:
    w.ok = false
    return
  w.data[w.len] = b
  w.len = w.len + 1

proc putBytes*(w: var FixedWriter, p: pointer, n: int) {.inline.} =
  if not w.ok: return
  if n < 0 or w.len + n > w.cap:
    w.ok = false
    return
  let src = cast[ptr UncheckedArray[byte]](p)
  var i = 0
  while i < n:
    w.data[w.len + i] = src[i]
    i = i + 1
  w.len = w.len + n

proc putLit*(w: var FixedWriter, s: static string) {.inline.} =
  var i = 0
  while i < s.len:
    putByte(w, cast[byte](s[i]))
    i = i + 1
