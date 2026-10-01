# NamedPipeComms

NamedPipeComms is a greenfield Windows x64 named-pipe server and CLI client written in nimless Nim: no Nim runtime, no CRT, and no PE import table. All Win32 calls are resolved manually from Kernel32 at process startup.

## Binaries

- `named-pipe-server.exe` hosts `\\.\pipe\NamedPipeComms.v1`.
- `named-pipe-client.exe` sends one request and prints the raw JSON response.

CLI usage:

```text
named-pipe-client.exe ping
named-pipe-client.exe echo "text"
named-pipe-client.exe add -12 54
```

## Wire format

The pipe is duplex byte-mode. Each message is a frame:

```text
uint32 little-endian body_length
body_length bytes of UTF-8 JSON
```

Limits:

- body length must be 1 through 4096 bytes;
- no trailing NUL is included;
- fragmented and coalesced pipe reads/writes are valid.

## Request schema

```json
{"v":1,"id":1,"op":"ping"}
{"v":1,"id":2,"op":"echo","text":"hello"}
{"v":1,"id":3,"op":"add","a":20,"b":22}
```

Rules:

- `v` must be `1`;
- `id` must be an unsigned 32-bit integer;
- fields must be present exactly once;
- unknown fields and operation-inapplicable fields are rejected;
- `a` and `b` are signed 32-bit integers, and `sum` is serialized as signed 64-bit;
- JSON escapes, UTF-8, integer overflow, and document termination are validated.

## Response schema

```json
{"v":1,"id":1,"ok":true,"result":{"pong":true}}
{"v":1,"id":2,"ok":true,"result":{"text":"hello"}}
{"v":1,"id":3,"ok":true,"result":{"sum":42}}
{"v":1,"id":null,"ok":false,"error":{"code":"invalid_json","message":"invalid JSON"}}
```

Fixed error codes are:

- `invalid_frame`
- `frame_too_large`
- `invalid_json`
- `invalid_request`
- `unknown_operation`
- `response_too_large`

## Build

Prerequisites:

- Nim with winim available (`nimble install winim`)
- MinGW-w64 cross compiler (`x86_64-w64-mingw32-gcc`)
- optional: Wine for local smoke tests from macOS/Linux

Build from the repository root:

```bash
tools/build.sh debug all
tools/build.sh inspect all
tools/build.sh release all
```

PowerShell equivalent:

```powershell
.\tools\build.ps1 debug all
.\tools\build.ps1 release all
```

Nim options are kept before source paths because Nim rejects late options after the project file.
Release builds add linker stripping; debug and inspect builds keep symbols for `nm` checks.

## Verification

Protocol tests:

```bash
tools/build.sh debug tests
WINEDEBUG=-all wine build/debug/protocol-tests.exe
```

PE/runtime checks:

```bash
tools/build.sh inspect all
python3 tools/verify_pe.py build/inspect/named-pipe-server.exe build/inspect/named-pipe-client.exe build/inspect/protocol-tests.exe
x86_64-w64-mingw32-objdump -p build/inspect/named-pipe-server.exe | grep 'DLL Name' # expect no output
```

Windows integration:

```powershell
.\tools\build.ps1 debug all
.\tests\integration.ps1 -BuildDir .\build\debug
```

The server uses four permanent overlapped slots in a single-threaded `WaitForMultipleObjects` loop. Slot failures recycle only the affected pipe instance.
