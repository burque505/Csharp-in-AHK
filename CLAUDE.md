# Csharp-in-AHK

AutoHotkey v2 (64-bit only) libraries that run C# inside the AutoHotkey process on .NET 8+ (tested on .NET 10), without launching dotnet.exe.
Repo: https://github.com/burque505/Csharp-in-AHK (branch `main`, MIT license).

## Files
- `Csharp-in-AHK.ahk`: `RunCSharp` / `RunCSharpFile`. Regular C# files with top-level statements (like `dotnet run app.cs`). The int return value goes to `CSExitCode`. `AHK.Return(value)` sends any value back. Console output goes to `CSOutput`.
- `Csx-in-AHK.ahk`: `RunCsx` / `RunCsxFile`. C# script (.csx) syntax using the Roslyn scripting API. `return <any value>` or a final expression is returned to AHK. Console output goes to `CsxOutput`.
- `cs_ex1.ahk`, `csx_ex1.ahk`: demos. `Example.csx` + `ExampleHelpers.csx` are used by `csx_ex1.ahk` (via `#load`).
- `winforms_ex1.ahk`, `wpf_ex1.ahk`: minimal WinForms / WPF dialogs via `RunCsx` that return the user's input to AHK. Scripts run on AHK's STA thread, so UI uses modal `ShowDialog()`. Never use `Application.Run()`, because WPF allows only one `Application` per process.
- The two libraries are standalone and must stay includable together: keep their globals and functions distinct (`CS*` / `_CSharp*` vs `Csx*` / `_Csx*`, host classes `CSHost` vs `CsxHost`).

## How it works
- AHK loads `hostfxr.dll` from `CSDotnetRoot` / `CsxDotnetRoot`, starts the runtime with a generated runtimeconfig (Microsoft.WindowsDesktop.App), and calls `[UnmanagedCallersOnly]` methods (`Init`, `Run`) via `DllCall`. If one library already started .NET, the other reuses that runtime.
- The C# host source lives inside each .ahk file as an AHK continuation section. On first use it is compiled once with Roslyn `csc.exe` into `%TEMP%\CSharp-in-AHK\CSHost-<crc>.dll` (or `%TEMP%\Csx-in-AHK\CsxHost-<crc>.dll`). The CRC covers the host source, runtime version and compiler version, so editing the host source triggers a rebuild automatically.
- Scripts are compiled in memory with the Roslyn DLLs from `CSRoslynDir` / `CsxRoslynDir` and cached per AHK process.

## Rules when editing the embedded C# host source
- It sits inside an AHK `"( ... )"` continuation section. Quote marks are literal there, but no line may start with `)` (that ends the section), and backticks must not be used.
- The host entry-point class (`CSHost` / `CsxHost`) must not reference Roslyn types in fields or method signatures. Roslyn is resolved by the `AssemblyLoadContext.Resolving` handler registered in `Init`, so Roslyn code belongs in the separate `ScriptCompiler` class.

## Environment (owner's machine)
- .NET runtime: `C:\Program Files\Microsoft Visual Studio\18\Community\dotnet\net10.0\runtime`
- Roslyn: `C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\Roslyn`
- AutoHotkey: `C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`

## Testing
- Run test scripts headless, writing results to stdout with `FileAppend(Text "`n", "*", "UTF-8")`:
  `"/c/Program Files/AutoHotkey/v2/AutoHotkey64.exe" //ErrorStdOut test.ahk` (from Git Bash).
- Put throwaway test scripts in the session scratchpad, not in the repo. The demo files use `MsgBox` and need a person to click through them.

## Conventions
- The owner may edit files between sessions. Treat the files on disk as current.
- Commit or push only when asked.
