type
  BYTE* = uint8
  CHAR* = char
  WCHAR* = uint16
  WORD* = uint16
  DWORD* = uint32
  UINT* = uint32
  ULONG* = uint32
  LONG* = int32
  INT* = int32
  BOOL* = int32
  SIZE_T* = uint
  ULONG_PTR* = uint
  HANDLE* = pointer
  HMODULE* = pointer
  FARPROC* = pointer
  PVOID* = pointer
  LPVOID* = pointer
  LPCVOID* = pointer
  LPCWSTR* = ptr WCHAR
  LPWSTR* = ptr WCHAR

  LIST_ENTRY* {.pure.} = object
    Flink*: ptr LIST_ENTRY
    Blink*: ptr LIST_ENTRY

  UNICODE_STRING* {.pure.} = object
    Length*: WORD
    MaximumLength*: WORD
    Buffer*: ptr WCHAR

  PEB_LDR_DATA* {.pure.} = object
    Reserved1*: array[8, BYTE]
    Reserved2*: array[3, PVOID]
    InMemoryOrderModuleList*: LIST_ENTRY

  PPEB_LDR_DATA* = ptr PEB_LDR_DATA

  PEB* {.pure.} = object
    Reserved1*: array[2, BYTE]
    BeingDebugged*: BYTE
    Reserved2*: array[1, BYTE]
    Reserved3*: array[2, PVOID]
    Ldr*: PPEB_LDR_DATA

  PPEB* = ptr PEB
  PLIST_ENTRY* = ptr LIST_ENTRY

  LDR_DATA_TABLE_ENTRY_INMEM* {.pure.} = object
    InMemoryOrderLinks*: LIST_ENTRY
    Reserved2*: array[2, PVOID]
    DllBase*: PVOID
    EntryPoint*: PVOID
    Reserved3*: PVOID
    FullDllName*: UNICODE_STRING
    BaseDllName*: UNICODE_STRING

  PLDR_DATA_TABLE_ENTRY_INMEM* = ptr LDR_DATA_TABLE_ENTRY_INMEM

  IMAGE_DOS_HEADER* {.pure.} = object
    e_magic*: WORD
    e_cblp*: WORD
    e_cp*: WORD
    e_crlc*: WORD
    e_cparhdr*: WORD
    e_minalloc*: WORD
    e_maxalloc*: WORD
    e_ss*: WORD
    e_sp*: WORD
    e_csum*: WORD
    e_ip*: WORD
    e_cs*: WORD
    e_lfarlc*: WORD
    e_ovno*: WORD
    e_res*: array[4, WORD]
    e_oemid*: WORD
    e_oeminfo*: WORD
    e_res2*: array[10, WORD]
    e_lfanew*: LONG

  PIMAGE_DOS_HEADER* = ptr IMAGE_DOS_HEADER

  IMAGE_FILE_HEADER* {.pure.} = object
    Machine*: WORD
    NumberOfSections*: WORD
    TimeDateStamp*: DWORD
    PointerToSymbolTable*: DWORD
    NumberOfSymbols*: DWORD
    SizeOfOptionalHeader*: WORD
    Characteristics*: WORD

  IMAGE_DATA_DIRECTORY* {.pure.} = object
    VirtualAddress*: DWORD
    Size*: DWORD

  IMAGE_OPTIONAL_HEADER64* {.pure.} = object
    Magic*: WORD
    MajorLinkerVersion*: BYTE
    MinorLinkerVersion*: BYTE
    SizeOfCode*: DWORD
    SizeOfInitializedData*: DWORD
    SizeOfUninitializedData*: DWORD
    AddressOfEntryPoint*: DWORD
    BaseOfCode*: DWORD
    ImageBase*: uint64
    SectionAlignment*: DWORD
    FileAlignment*: DWORD
    MajorOperatingSystemVersion*: WORD
    MinorOperatingSystemVersion*: WORD
    MajorImageVersion*: WORD
    MinorImageVersion*: WORD
    MajorSubsystemVersion*: WORD
    MinorSubsystemVersion*: WORD
    Win32VersionValue*: DWORD
    SizeOfImage*: DWORD
    SizeOfHeaders*: DWORD
    CheckSum*: DWORD
    Subsystem*: WORD
    DllCharacteristics*: WORD
    SizeOfStackReserve*: uint64
    SizeOfStackCommit*: uint64
    SizeOfHeapReserve*: uint64
    SizeOfHeapCommit*: uint64
    LoaderFlags*: DWORD
    NumberOfRvaAndSizes*: DWORD
    DataDirectory*: array[16, IMAGE_DATA_DIRECTORY]

  IMAGE_NT_HEADERS64* {.pure.} = object
    Signature*: DWORD
    FileHeader*: IMAGE_FILE_HEADER
    OptionalHeader*: IMAGE_OPTIONAL_HEADER64

  PIMAGE_NT_HEADERS64* = ptr IMAGE_NT_HEADERS64

  IMAGE_EXPORT_DIRECTORY* {.pure.} = object
    Characteristics*: DWORD
    TimeDateStamp*: DWORD
    MajorVersion*: WORD
    MinorVersion*: WORD
    Name*: DWORD
    Base*: DWORD
    NumberOfFunctions*: DWORD
    NumberOfNames*: DWORD
    AddressOfFunctions*: DWORD
    AddressOfNames*: DWORD
    AddressOfNameOrdinals*: DWORD

  PIMAGE_EXPORT_DIRECTORY* = ptr IMAGE_EXPORT_DIRECTORY

  OVERLAPPED* {.pure.} = object
    Internal*: ULONG_PTR
    InternalHigh*: ULONG_PTR
    Offset*: DWORD
    OffsetHigh*: DWORD
    hEvent*: HANDLE

  LPOVERLAPPED* = ptr OVERLAPPED

  ExitProcessProc* = proc(uExitCode: UINT) {.stdcall.}
  LoadLibraryAProc* = proc(lpLibFileName: cstring): HMODULE {.stdcall.}
  GetLastErrorProc* = proc(): DWORD {.stdcall.}
  ReadFileProc* = proc(hFile: HANDLE, lpBuffer: LPVOID, nNumberOfBytesToRead: DWORD, lpNumberOfBytesRead: ptr DWORD, lpOverlapped: LPOVERLAPPED): BOOL {.stdcall.}
  WriteFileProc* = proc(hFile: HANDLE, lpBuffer: LPCVOID, nNumberOfBytesToWrite: DWORD, lpNumberOfBytesWritten: ptr DWORD, lpOverlapped: LPOVERLAPPED): BOOL {.stdcall.}
  CloseHandleProc* = proc(hObject: HANDLE): BOOL {.stdcall.}

  CreateNamedPipeWProc* = proc(lpName: LPCWSTR, dwOpenMode: DWORD, dwPipeMode: DWORD, nMaxInstances: DWORD, nOutBufferSize: DWORD, nInBufferSize: DWORD, nDefaultTimeOut: DWORD, lpSecurityAttributes: LPVOID): HANDLE {.stdcall.}
  ConnectNamedPipeProc* = proc(hNamedPipe: HANDLE, lpOverlapped: LPOVERLAPPED): BOOL {.stdcall.}
  DisconnectNamedPipeProc* = proc(hNamedPipe: HANDLE): BOOL {.stdcall.}
  CreateEventWProc* = proc(lpEventAttributes: LPVOID, bManualReset: BOOL, bInitialState: BOOL, lpName: LPCWSTR): HANDLE {.stdcall.}
  ResetEventProc* = proc(hEvent: HANDLE): BOOL {.stdcall.}
  WaitForMultipleObjectsProc* = proc(nCount: DWORD, lpHandles: ptr HANDLE, bWaitAll: BOOL, dwMilliseconds: DWORD): DWORD {.stdcall.}
  GetOverlappedResultProc* = proc(hFile: HANDLE, lpOverlapped: LPOVERLAPPED, lpNumberOfBytesTransferred: ptr DWORD, bWait: BOOL): BOOL {.stdcall.}

  CreateFileWProc* = proc(lpFileName: LPCWSTR, dwDesiredAccess: DWORD, dwShareMode: DWORD, lpSecurityAttributes: LPVOID, dwCreationDisposition: DWORD, dwFlagsAndAttributes: DWORD, hTemplateFile: HANDLE): HANDLE {.stdcall.}
  WaitNamedPipeWProc* = proc(lpNamedPipeName: LPCWSTR, nTimeOut: DWORD): BOOL {.stdcall.}
  SleepProc* = proc(dwMilliseconds: DWORD) {.stdcall.}
  GetCommandLineWProc* = proc(): LPWSTR {.stdcall.}
  GetStdHandleProc* = proc(nStdHandle: DWORD): HANDLE {.stdcall.}
  WideCharToMultiByteProc* = proc(CodePage: UINT, dwFlags: DWORD, lpWideCharStr: LPCWSTR, cchWideChar: INT, lpMultiByteStr: cstring, cbMultiByte: INT, lpDefaultChar: cstring, lpUsedDefaultChar: ptr BOOL): INT {.stdcall.}

template NULL_HANDLE*(): HANDLE = cast[HANDLE](0)
template INVALID_HANDLE_VALUE*(): HANDLE = cast[HANDLE](-1)

const
  IMAGE_DOS_SIGNATURE* = 0x5A4D'u16
  IMAGE_NT_SIGNATURE* = 0x00004550'u32
  IMAGE_DIRECTORY_ENTRY_EXPORT* = 0

  TRUE* = 1'i32
  FALSE* = 0'i32
  INFINITE* = 0xFFFFFFFF'u32
  WAIT_OBJECT_0* = 0'u32
  WAIT_TIMEOUT* = 0x00000102'u32
  WAIT_FAILED* = 0xFFFFFFFF'u32

  ERROR_SUCCESS* = 0'u32
  ERROR_FILE_NOT_FOUND* = 2'u32
  ERROR_ACCESS_DENIED* = 5'u32
  ERROR_INVALID_HANDLE* = 6'u32
  ERROR_NOT_ENOUGH_MEMORY* = 8'u32
  ERROR_BROKEN_PIPE* = 109'u32
  ERROR_PIPE_BUSY* = 231'u32
  ERROR_NO_DATA* = 232'u32
  ERROR_PIPE_NOT_CONNECTED* = 233'u32
  ERROR_MORE_DATA* = 234'u32
  ERROR_PIPE_CONNECTED* = 535'u32
  ERROR_IO_PENDING* = 997'u32

  GENERIC_READ* = 0x80000000'u32
  GENERIC_WRITE* = 0x40000000'u32
  OPEN_EXISTING* = 3'u32
  FILE_ATTRIBUTE_NORMAL* = 0x00000080'u32
  FILE_FLAG_OVERLAPPED* = 0x40000000'u32
  FILE_FLAG_FIRST_PIPE_INSTANCE* = 0x00080000'u32
  PIPE_ACCESS_DUPLEX* = 0x00000003'u32
  PIPE_TYPE_BYTE* = 0x00000000'u32
  PIPE_READMODE_BYTE* = 0x00000000'u32
  PIPE_WAIT* = 0x00000000'u32
  PIPE_REJECT_REMOTE_CLIENTS* = 0x00000008'u32

  STD_OUTPUT_HANDLE* = 0xFFFFFFF5'u32
  CP_UTF8* = 65001'u32

  PROTOCOL_MAX_BODY* = 4096
  PROTOCOL_HEADER_SIZE* = 4
  PROTOCOL_MAX_FRAME* = 4100
  SERVER_SLOTS* = 4
