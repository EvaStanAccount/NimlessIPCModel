import ../winapi

proc encodeLenLE*(dst: pointer, bodyLen: uint32) {.inline.} =
  let p = cast[ptr UncheckedArray[byte]](dst)
  p[0] = cast[byte](bodyLen and 0xff'u32)
  p[1] = cast[byte]((bodyLen shr 8) and 0xff'u32)
  p[2] = cast[byte]((bodyLen shr 16) and 0xff'u32)
  p[3] = cast[byte]((bodyLen shr 24) and 0xff'u32)

proc decodeLenLE*(src: pointer): uint32 {.inline.} =
  let p = cast[ptr UncheckedArray[byte]](src)
  return cast[uint32](p[0]) or (cast[uint32](p[1]) shl 8) or (cast[uint32](p[2]) shl 16) or (cast[uint32](p[3]) shl 24)

proc validFrameLen*(n: uint32): bool {.inline.} =
  return n >= 1'u32 and n <= cast[uint32](PROTOCOL_MAX_BODY)
