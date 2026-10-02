import winapi
import utils/[gpa, gmh, hash]

type
  MODULES* {.pure.} = object
    kernel32*: HMODULE

  WIN32* {.pure.} = object
    ExitProcess*: ExitProcessProc
    LoadLibraryA*: LoadLibraryAProc
    GetLastError*: GetLastErrorProc
    ReadFile*: ReadFileProc
    WriteFile*: WriteFileProc
    CloseHandle*: CloseHandleProc
    CreateNamedPipeW*: CreateNamedPipeWProc
    ConnectNamedPipe*: ConnectNamedPipeProc
    DisconnectNamedPipe*: DisconnectNamedPipeProc
    CreateEventW*: CreateEventWProc
    ResetEvent*: ResetEventProc
    WaitForMultipleObjects*: WaitForMultipleObjectsProc
    GetOverlappedResult*: GetOverlappedResultProc
    CreateFileW*: CreateFileWProc
    WaitNamedPipeW*: WaitNamedPipeWProc
    Sleep*: SleepProc
    GetCommandLineW*: GetCommandLineWProc
    GetStdHandle*: GetStdHandleProc
    WideCharToMultiByte*: WideCharToMultiByteProc

  NIMLESS_INSTANCE* {.pure.} = object
    Module*: MODULES
    Win32*: WIN32
    IsInitialized*: bool

var ninst*: NIMLESS_INSTANCE

proc allResolved(ninst: var NIMLESS_INSTANCE): bool {.inline.} =
  return ninst.Win32.ExitProcess != nil and
    ninst.Win32.LoadLibraryA != nil and
    ninst.Win32.GetLastError != nil and
    ninst.Win32.ReadFile != nil and
    ninst.Win32.WriteFile != nil and
    ninst.Win32.CloseHandle != nil and
    ninst.Win32.CreateNamedPipeW != nil and
    ninst.Win32.ConnectNamedPipe != nil and
    ninst.Win32.DisconnectNamedPipe != nil and
    ninst.Win32.CreateEventW != nil and
    ninst.Win32.ResetEvent != nil and
    ninst.Win32.WaitForMultipleObjects != nil and
    ninst.Win32.GetOverlappedResult != nil and
    ninst.Win32.CreateFileW != nil and
    ninst.Win32.WaitNamedPipeW != nil and
    ninst.Win32.Sleep != nil and
    ninst.Win32.GetCommandLineW != nil and
    ninst.Win32.GetStdHandle != nil and
    ninst.Win32.WideCharToMultiByte != nil

proc init*(ninst: var NIMLESS_INSTANCE): bool =
  if ninst.IsInitialized:
    return true

  ninst.Module.kernel32 = gmh("kernel32.dll")
  if ninst.Module.kernel32 == NULL_HANDLE:
    return false

  ninst.Win32.LoadLibraryA = cast[LoadLibraryAProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("LoadLibraryA")))
  if ninst.Win32.LoadLibraryA == nil:
    return false

  ninst.Win32.ExitProcess = cast[ExitProcessProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("ExitProcess")))
  ninst.Win32.GetLastError = cast[GetLastErrorProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("GetLastError")))
  ninst.Win32.ReadFile = cast[ReadFileProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("ReadFile")))
  ninst.Win32.WriteFile = cast[WriteFileProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("WriteFile")))
  ninst.Win32.CloseHandle = cast[CloseHandleProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("CloseHandle")))
  ninst.Win32.CreateNamedPipeW = cast[CreateNamedPipeWProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("CreateNamedPipeW")))
  ninst.Win32.ConnectNamedPipe = cast[ConnectNamedPipeProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("ConnectNamedPipe")))
  ninst.Win32.DisconnectNamedPipe = cast[DisconnectNamedPipeProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("DisconnectNamedPipe")))
  ninst.Win32.CreateEventW = cast[CreateEventWProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("CreateEventW")))
  ninst.Win32.ResetEvent = cast[ResetEventProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("ResetEvent")))
  ninst.Win32.WaitForMultipleObjects = cast[WaitForMultipleObjectsProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("WaitForMultipleObjects")))
  ninst.Win32.GetOverlappedResult = cast[GetOverlappedResultProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("GetOverlappedResult")))
  ninst.Win32.CreateFileW = cast[CreateFileWProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("CreateFileW")))
  ninst.Win32.WaitNamedPipeW = cast[WaitNamedPipeWProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("WaitNamedPipeW")))
  ninst.Win32.Sleep = cast[SleepProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("Sleep")))
  ninst.Win32.GetCommandLineW = cast[GetCommandLineWProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("GetCommandLineW")))
  ninst.Win32.GetStdHandle = cast[GetStdHandleProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("GetStdHandle")))
  ninst.Win32.WideCharToMultiByte = cast[WideCharToMultiByteProc](getProcAddressHash(ninst.Module.kernel32, hashLitA("WideCharToMultiByte")))

  if not allResolved(ninst):
    return false
  ninst.IsInitialized = true
  return true
