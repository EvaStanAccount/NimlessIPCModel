import ../winapi
import hash, gmh

proc strlenA(s: cstring): int {.inline.} =
  var p = cast[ptr UncheckedArray[byte]](s)
  while p[result] != 0'u8:
    result = result + 1

proc hashExportNameAt(base: int, rva: DWORD): uint32 {.inline.} =
  return hashStrA(cast[cstring](base + cast[int](rva)))

proc inRange(value: DWORD, start: DWORD, size: DWORD): bool {.inline.} =
  if size == 0'u32: return false
  return value >= start and value < (start + size)

proc getProcAddressHashDepth(hModule: HMODULE, apiNameHash: uint32, depth: int): FARPROC {.inline.} =
  if hModule == NULL_HANDLE or depth > 4:
    return nil
  let base = cast[int](hModule)
  let dos = cast[PIMAGE_DOS_HEADER](base)
  if dos.e_magic != IMAGE_DOS_SIGNATURE:
    return nil
  let nt = cast[PIMAGE_NT_HEADERS64](base + cast[int](dos.e_lfanew))
  if nt.Signature != IMAGE_NT_SIGNATURE:
    return nil
  let exportRva = nt.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress
  let exportSize = nt.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].Size
  if exportRva == 0'u32 or exportSize == 0'u32:
    return nil

  let exp = cast[PIMAGE_EXPORT_DIRECTORY](base + cast[int](exportRva))
  if exp.NumberOfNames == 0'u32 or exp.AddressOfNames == 0'u32:
    return nil

  let names = cast[ptr UncheckedArray[DWORD]](base + cast[int](exp.AddressOfNames))
  let funcs = cast[ptr UncheckedArray[DWORD]](base + cast[int](exp.AddressOfFunctions))
  let ords = cast[ptr UncheckedArray[WORD]](base + cast[int](exp.AddressOfNameOrdinals))

  var i: DWORD = 0'u32
  while i < exp.NumberOfNames:
    let nameRva = names[cast[int](i)]
    if nameRva != 0'u32 and hashExportNameAt(base, nameRva) == apiNameHash:
      let ord = ords[cast[int](i)]
      if cast[DWORD](ord) >= exp.NumberOfFunctions:
        return nil
      let funcRva = funcs[cast[int](ord)]
      if funcRva == 0'u32:
        return nil
      if inRange(funcRva, exportRva, exportSize):
        let fwd = cast[cstring](base + cast[int](funcRva))
        let fwdLen = strlenA(fwd)
        var moduleName: array[64, byte]
        var procHash: uint32 = 0xff'u32
        var dot = -1
        var j = 0
        while j < fwdLen and j < 63:
          let b = cast[ptr UncheckedArray[byte]](fwd)[j]
          if b == cast[byte]('.'):
            dot = j
            moduleName[j] = cast[byte]('.')
            if j + 4 < 64:
              moduleName[j + 1] = cast[byte]('d')
              moduleName[j + 2] = cast[byte]('l')
              moduleName[j + 3] = cast[byte]('l')
              moduleName[j + 4] = 0'u8
            break
          else:
            var lb = b
            if lb >= cast[byte]('A') and lb <= cast[byte]('Z'):
              lb = lb xor 0x20'u8
            moduleName[j] = lb
          j = j + 1
        if dot <= 0:
          return nil
        var k = dot + 1
        while k < fwdLen:
          let b = cast[ptr UncheckedArray[byte]](fwd)[k]
          procHash = ((procHash shl 5) + procHash) + cast[uint32](b)
          k = k + 1
        let loadLib = cast[LoadLibraryAProc](getProcAddressHashDepth(gmh("kernel32.dll"), hashLitA("LoadLibraryA"), depth + 1))
        if loadLib == nil:
          return nil
        let h = loadLib(cast[cstring](moduleName[0].addr))
        if h == NULL_HANDLE:
          return nil
        return getProcAddressHashDepth(h, procHash, depth + 1)
      return cast[FARPROC](base + cast[int](funcRva))
    i = i + 1'u32
  return nil

proc getProcAddressHash*(hModule: HMODULE, apiNameHash: uint32): FARPROC {.inline.} =
  return getProcAddressHashDepth(hModule, apiNameHash, 0)
