import ../winapi
import hash

proc lowerWideAscii(c: WCHAR): WCHAR {.inline.} =
  if c >= cast[WCHAR]('A') and c <= cast[WCHAR]('Z'):
    return c xor 0x20'u16
  return c

proc baseNameStart(buf: ptr WCHAR, byteLen: WORD): int {.inline.} =
  var last = 0
  let p = cast[ptr UncheckedArray[WCHAR]](buf)
  let count = cast[int](byteLen) div 2
  var i = 0
  while i < count:
    if p[i] == cast[WCHAR]('\\') or p[i] == cast[WCHAR]('/'):
      last = i + 1
    i = i + 1
  return last

proc baseNameHash(buf: ptr WCHAR, byteLen: WORD): uint32 {.inline.} =
  let p = cast[ptr UncheckedArray[WCHAR]](buf)
  let count = cast[int](byteLen) div 2
  var start = baseNameStart(buf, byteLen)
  var hash: uint32 = 0xff'u32
  var i = start
  while i < count:
    var c = lowerWideAscii(p[i])
    hash = ((hash shl 5) + hash) + cast[uint32](c and 0xff'u16)
    i = i + 1
  return hash

template gmh*(s: static string): HMODULE =
  getModuleHandleHash(hashLitA(s))

proc getModuleHandleHash*(hash: uint32): HMODULE =
  var pPeb: PPEB
  asm """
    mov rax, qword ptr gs:[0x60]
    :"=r"(`pPeb`)
  """
  if pPeb == nil or pPeb.Ldr == nil:
    return NULL_HANDLE

  let pListHead = pPeb.Ldr.InMemoryOrderModuleList.addr
  var pListNode = pPeb.Ldr.InMemoryOrderModuleList.Flink

  while cast[int](pListNode) != cast[int](pListHead):
    let pDte = cast[PLDR_DATA_TABLE_ENTRY_INMEM](pListNode)
    if pDte.BaseDllName.Length != 0'u16 and pDte.BaseDllName.Buffer != nil:
      if baseNameHash(pDte.BaseDllName.Buffer, pDte.BaseDllName.Length) == hash:
        return cast[HMODULE](pDte.DllBase)
    elif pDte.FullDllName.Length != 0'u16 and pDte.FullDllName.Buffer != nil:
      if baseNameHash(pDte.FullDllName.Buffer, pDte.FullDllName.Length) == hash:
        return cast[HMODULE](pDte.DllBase)
    pListNode = pListNode.Flink
  return NULL_HANDLE
