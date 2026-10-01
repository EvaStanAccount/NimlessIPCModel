import ../winapi
import ../instance
import ../utils/[memory, stackstr]
import ../protocol/[framing, messages]

type
  ClientExit* = enum
    ceOk = 0,
    ceSyntax = 2,
    ceConnection = 3,
    ceTransport = 4,
    ceProtocol = 5,
    ceServer = 6

proc writeAll*(h: HANDLE, buf: pointer, len: int): bool =
  var offset = 0
  while offset < len:
    var wrote: DWORD = 0'u32
    let n = cast[DWORD](len - offset)
    if ninst.Win32.WriteFile(h, cast[LPCVOID](cast[int](buf) + offset), n, wrote.addr, nil) == FALSE:
      return false
    if wrote == 0'u32:
      return false
    offset = offset + cast[int](wrote)
  return true

proc readExact*(h: HANDLE, buf: pointer, len: int): bool =
  var offset = 0
  while offset < len:
    var got: DWORD = 0'u32
    let n = cast[DWORD](len - offset)
    if ninst.Win32.ReadFile(h, cast[LPVOID](cast[int](buf) + offset), n, got.addr, nil) == FALSE:
      return false
    if got == 0'u32:
      return false
    offset = offset + cast[int](got)
  return true

proc connectPipe*(): HANDLE =
  var attempt = 0
  while attempt < 20:
    var name {.stackStringW.} = "\\\\.\\pipe\\NamedPipeComms.v1"
    let h = ninst.Win32.CreateFileW(
      CWPTR(name),
      GENERIC_READ or GENERIC_WRITE,
      0'u32,
      nil,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      NULL_HANDLE)
    if h != INVALID_HANDLE_VALUE and h != NULL_HANDLE:
      return h
    let err = ninst.Win32.GetLastError()
    if err == ERROR_PIPE_BUSY:
      var waitName {.stackStringW.} = "\\\\.\\pipe\\NamedPipeComms.v1"
      discard ninst.Win32.WaitNamedPipeW(CWPTR(waitName), 500'u32)
    else:
      ninst.Win32.Sleep(100'u32)
    attempt = attempt + 1
  return NULL_HANDLE

proc sendRequest*(body: pointer, bodyLen: int, response: pointer, responseLen: var int): ClientExit =
  if bodyLen <= 0 or bodyLen > PROTOCOL_MAX_BODY:
    return ceProtocol
  let h = connectPipe()
  if h == NULL_HANDLE:
    return ceConnection
  var frame: array[PROTOCOL_MAX_FRAME, byte]
  encodeLenLE(frame[0].addr, cast[uint32](bodyLen))
  copyBytes(frame[PROTOCOL_HEADER_SIZE].addr, body, bodyLen)
  if not writeAll(h, frame[0].addr, bodyLen + PROTOCOL_HEADER_SIZE):
    discard ninst.Win32.CloseHandle(h)
    return ceTransport
  var hdr: array[PROTOCOL_HEADER_SIZE, byte]
  if not readExact(h, hdr[0].addr, PROTOCOL_HEADER_SIZE):
    discard ninst.Win32.CloseHandle(h)
    return ceTransport
  let n = decodeLenLE(hdr[0].addr)
  if not validFrameLen(n):
    discard ninst.Win32.CloseHandle(h)
    return ceProtocol
  if not readExact(h, response, cast[int](n)):
    discard ninst.Win32.CloseHandle(h)
    return ceTransport
  responseLen = cast[int](n)
  discard ninst.Win32.CloseHandle(h)
  return ceOk

proc writeStdout*(buf: pointer, len: int): bool =
  let h = ninst.Win32.GetStdHandle(STD_OUTPUT_HANDLE)
  if h == NULL_HANDLE or h == INVALID_HANDLE_VALUE:
    return false
  if len > 0:
    if not writeAll(h, buf, len): return false
  var nl: array[1, byte]
  nl[0] = 0x0a'u8
  discard writeAll(h, nl[0].addr, 1)
  return true
