import ../winapi
import ../instance
import ../utils/[memory, stackstr]
import ../protocol/[framing, messages]

type
  SlotState = enum
    stClosed,
    stConnecting,
    stReadingHeader,
    stReadingBody,
    stWritingFrame

  PipeSlot {.pure.} = object
    pipe: HANDLE
    event: HANDLE
    ov: OVERLAPPED
    state: SlotState
    pending: bool
    closeAfterWrite: bool
    offset: DWORD
    target: DWORD
    header: array[PROTOCOL_HEADER_SIZE, byte]
    body: array[PROTOCOL_MAX_BODY, byte]
    outFrame: array[PROTOCOL_MAX_FRAME, byte]
    outLen: DWORD

proc resetOverlapped(slot: var PipeSlot) {.inline.} =
  let ev = slot.event
  zeroBytes(slot.ov.addr, sizeof(OVERLAPPED))
  slot.ov.hEvent = ev
  discard ninst.Win32.ResetEvent(ev)

proc closePipe(slot: var PipeSlot) {.inline.} =
  if slot.pipe != NULL_HANDLE and slot.pipe != INVALID_HANDLE_VALUE:
    discard ninst.Win32.CloseHandle(slot.pipe)
  slot.pipe = NULL_HANDLE
  slot.state = stClosed
  slot.pending = false
  slot.closeAfterWrite = false
  slot.offset = 0'u32
  slot.target = 0'u32
  slot.outLen = 0'u32

proc createPipe(slot: var PipeSlot, firstFlag: bool): bool =
  var flags = PIPE_ACCESS_DUPLEX or FILE_FLAG_OVERLAPPED
  if firstFlag:
    flags = flags or FILE_FLAG_FIRST_PIPE_INSTANCE
  var name {.stackStringW.} = "\\\\.\\pipe\\NamedPipeComms.v1"
  slot.pipe = ninst.Win32.CreateNamedPipeW(
    CWPTR(name),
    flags,
    PIPE_TYPE_BYTE or PIPE_READMODE_BYTE or PIPE_WAIT or PIPE_REJECT_REMOTE_CLIENTS,
    cast[DWORD](SERVER_SLOTS),
    cast[DWORD](PROTOCOL_MAX_FRAME),
    cast[DWORD](PROTOCOL_MAX_FRAME),
    0'u32,
    nil)
  if slot.pipe == INVALID_HANDLE_VALUE or slot.pipe == NULL_HANDLE:
    slot.pipe = NULL_HANDLE
    return false
  return true

proc beginConnect(slot: var PipeSlot): bool =
  resetOverlapped(slot)
  slot.state = stConnecting
  slot.pending = false
  let ok = ninst.Win32.ConnectNamedPipe(slot.pipe, slot.ov.addr)
  if ok != FALSE:
    slot.pending = false
    return true
  let err = ninst.Win32.GetLastError()
  if err == ERROR_IO_PENDING:
    slot.pending = true
    return true
  if err == ERROR_PIPE_CONNECTED:
    slot.pending = false
    return true
  return false

proc issueRead(slot: var PipeSlot, state: SlotState, buf: pointer, total: DWORD): bool =
  resetOverlapped(slot)
  slot.state = state
  slot.target = total
  slot.pending = false
  let remain = total - slot.offset
  let ok = ninst.Win32.ReadFile(slot.pipe, cast[LPVOID](cast[int](buf) + cast[int](slot.offset)), remain, nil, slot.ov.addr)
  if ok != FALSE:
    slot.pending = false
    return true
  let err = ninst.Win32.GetLastError()
  if err == ERROR_IO_PENDING:
    slot.pending = true
    return true
  return false

proc issueWrite(slot: var PipeSlot): bool =
  resetOverlapped(slot)
  slot.state = stWritingFrame
  slot.pending = false
  let remain = slot.outLen - slot.offset
  let ok = ninst.Win32.WriteFile(slot.pipe, cast[LPCVOID](cast[int](slot.outFrame[0].addr) + cast[int](slot.offset)), remain, nil, slot.ov.addr)
  if ok != FALSE:
    slot.pending = false
    return true
  let err = ninst.Win32.GetLastError()
  if err == ERROR_IO_PENDING:
    slot.pending = true
    return true
  return false

proc beginHeader(slot: var PipeSlot): bool =
  slot.offset = 0'u32
  slot.target = cast[DWORD](PROTOCOL_HEADER_SIZE)
  return issueRead(slot, stReadingHeader, slot.header[0].addr, cast[DWORD](PROTOCOL_HEADER_SIZE))

proc recycleSlot(slot: var PipeSlot): bool =
  if slot.pipe != NULL_HANDLE and slot.pipe != INVALID_HANDLE_VALUE:
    discard ninst.Win32.DisconnectNamedPipe(slot.pipe)
    discard ninst.Win32.CloseHandle(slot.pipe)
  slot.pipe = NULL_HANDLE
  if not createPipe(slot, false):
    return false
  return beginConnect(slot)

proc finishOp(slot: var PipeSlot, bytes: var DWORD): bool =
  bytes = 0'u32
  if ninst.Win32.GetOverlappedResult(slot.pipe, slot.ov.addr, bytes.addr, FALSE) == FALSE:
    return false
  slot.pending = false
  return true

proc prepareResponse(slot: var PipeSlot): bool =
  let bodyLen = decodeLenLE(slot.header[0].addr)
  var respLen = 0
  if not validFrameLen(bodyLen):
    discard serializeError(slot.outFrame[PROTOCOL_HEADER_SIZE].addr, PROTOCOL_MAX_BODY, errFrameTooLarge, false, 0'u32, respLen)
    slot.closeAfterWrite = true
  else:
    let h = handleRequest(slot.body[0].addr, cast[int](bodyLen), slot.outFrame[PROTOCOL_HEADER_SIZE].addr, PROTOCOL_MAX_BODY, respLen)
    slot.closeAfterWrite = (h == errInvalidFrame or h == errFrameTooLarge)
  encodeLenLE(slot.outFrame[0].addr, cast[uint32](respLen))
  slot.outLen = cast[DWORD](respLen + PROTOCOL_HEADER_SIZE)
  slot.offset = 0'u32
  return issueWrite(slot)

proc driveSlot(slot: var PipeSlot): bool =
  var budget = 8
  while budget > 0:
    budget = budget - 1
    var transferred: DWORD = 0'u32
    if slot.pending:
      if not finishOp(slot, transferred):
        return recycleSlot(slot)
    else:
      if slot.state == stConnecting:
        transferred = 0'u32
      else:
        if not finishOp(slot, transferred):
          return recycleSlot(slot)

    case slot.state
    of stConnecting:
      if not beginHeader(slot):
        return recycleSlot(slot)
      if slot.pending: return true
    of stReadingHeader:
      slot.offset = slot.offset + transferred
      if slot.offset < cast[DWORD](PROTOCOL_HEADER_SIZE):
        if not issueRead(slot, stReadingHeader, slot.header[0].addr, cast[DWORD](PROTOCOL_HEADER_SIZE)):
          return recycleSlot(slot)
        if slot.pending: return true
      else:
        let bodyLen = decodeLenLE(slot.header[0].addr)
        if not validFrameLen(bodyLen):
          var respLen = 0
          discard serializeError(slot.outFrame[PROTOCOL_HEADER_SIZE].addr, PROTOCOL_MAX_BODY, errFrameTooLarge, false, 0'u32, respLen)
          encodeLenLE(slot.outFrame[0].addr, cast[uint32](respLen))
          slot.outLen = cast[DWORD](respLen + PROTOCOL_HEADER_SIZE)
          slot.offset = 0'u32
          slot.closeAfterWrite = true
          if not issueWrite(slot): return recycleSlot(slot)
          if slot.pending: return true
        else:
          slot.offset = 0'u32
          if not issueRead(slot, stReadingBody, slot.body[0].addr, bodyLen):
            return recycleSlot(slot)
          if slot.pending: return true
    of stReadingBody:
      slot.offset = slot.offset + transferred
      if slot.offset < slot.target:
        if not issueRead(slot, stReadingBody, slot.body[0].addr, slot.target):
          return recycleSlot(slot)
        if slot.pending: return true
      else:
        if not prepareResponse(slot): return recycleSlot(slot)
        if slot.pending: return true
    of stWritingFrame:
      slot.offset = slot.offset + transferred
      if slot.offset < slot.outLen:
        if not issueWrite(slot): return recycleSlot(slot)
        if slot.pending: return true
      else:
        if slot.closeAfterWrite:
          return recycleSlot(slot)
        if not beginHeader(slot): return recycleSlot(slot)
        if slot.pending: return true
    of stClosed:
      return recycleSlot(slot)
  return true

proc runServer*(): int =
  var slots: array[SERVER_SLOTS, PipeSlot]
  var events: array[SERVER_SLOTS, HANDLE]
  var i = 0
  while i < SERVER_SLOTS:
    slots[i].event = ninst.Win32.CreateEventW(nil, TRUE, FALSE, nil)
    if slots[i].event == NULL_HANDLE:
      return 1
    if not createPipe(slots[i], i == 0):
      return 2
    if not beginConnect(slots[i]):
      return 3
    events[i] = slots[i].event
    i = i + 1

  var next = 0
  while true:
    var ran = false
    var n = 0
    while n < SERVER_SLOTS:
      let idx = (next + n) mod SERVER_SLOTS
      if not slots[idx].pending:
        if not driveSlot(slots[idx]): return 4
        ran = true
      n = n + 1
    if not ran:
      let w = ninst.Win32.WaitForMultipleObjects(cast[DWORD](SERVER_SLOTS), events[0].addr, FALSE, INFINITE)
      if w == WAIT_FAILED:
        return 5
      if w >= WAIT_OBJECT_0 and w < WAIT_OBJECT_0 + cast[DWORD](SERVER_SLOTS):
        let idx = cast[int](w - WAIT_OBJECT_0)
        if not driveSlot(slots[idx]): return 6
        next = (idx + 1) mod SERVER_SLOTS
      else:
        next = (next + 1) mod SERVER_SLOTS
    else:
      next = (next + 1) mod SERVER_SLOTS
  return 0
