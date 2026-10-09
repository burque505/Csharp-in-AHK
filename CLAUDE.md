# Csharp-in-AHK

AutoHotkey v2 (64-bit only) libraries that run C# inside the AutoHotkey process on .NET 8+ (tested on .NET 10), without launching dotnet.exe.
Repo: https://github.com/burque505/Csharp-in-AHK (branch `main`, MIT license).

## Files
- `Csharp-in-AHK.ahk`: `RunCSharp` / `RunCSharpFile`. Regular C# files with top-level statements (like `dotnet run app.cs`). The int return value goes to `CSExitCode`. `AHK.Return(value)` sends any value back. Console output goes to `CSOutput`.
- `Csx-in-AHK.ahk`: `RunCsx` / `RunCsxFile`. C# script (.csx) syntax using the Roslyn scripting API. `return <any value>` or a final expression is returned to AHK. Console output goes to `CsxOutput`.
- `Csharp-in-AHK-Paths.ahk`: GUI for the path settings (user environment variables in HKCU\Environment, `Csharp-in-AHK.ini`, auto-detection). It must sit next to both libraries: it includes `Csx-in-AHK.ahk` with `#Include *i` only for its detection functions (looked up by name, so a missing library gives one message instead of load errors) and runs Test in a separate AHK process, so .NET is never started in the GUI process.
- `cs_ex1.ahk`, `csx_ex1.ahk`: demos. `Example.csx` + `ExampleHelpers.csx` are used by `csx_ex1.ahk` (via `#load`).
- `winforms_ex1.ahk`, `wpf_ex1.ahk`: minimal WinForms / WPF dialogs via `RunCsx` that return the user's input to AHK. Scripts run on AHK's STA thread, so UI uses modal `ShowDialog()`. Never use `Application.Run()`, because WPF allows only one `Application` per process.
- `types_ex1.ahk` (`RunCsx`), `cs_types_ex1.ahk` (`RunCSharp`): passing AHK values of each type to C# through `args` (all arrive as strings) and converting the results back (`cs_types_ex1` uses `AHK.Return`, console output and `CSExitCode`). Arrays are spread with `Arr*`. Maps travel as `key=value` lines.
- `pynet.cs`: `Pynet` helper class for Python.NET (adapted from a LibreAutomate script), pulled in with `#load "pynet.cs"`; the script itself needs `#:package pythonnet@3.1.0`. It starts the Python engine once per AHK process and never shuts it down: after `PythonEngine.Shutdown()` the engine cannot be initialized again in the same process (`NotImplementedException`), so the examples shut it down only in `OnExit`. It sets `PythonHome`/`ProgramName` from the DLL's folder, because an inherited `VIRTUAL_ENV` otherwise makes embedded Python use that venv's paths.
- `pynet1.ahk` + `pynet1.cs`: basic Python.NET demo. `pyplot1.ahk` + `pyplot1.cs`: WinForms window with matplotlib plots rendered with the Agg backend to PNG in memory (no `plt.show()`), returns the saved PNG path via `AHK.Return`.
- The two libraries are standalone and must stay includable together: keep their globals and functions distinct (`CS*` / `_CSharp*` vs `Csx*` / `_Csx*`, host classes `CSHost` vs `CsxHost`).

## How it works
- `CSDotnetRoot`/`CSRoslynDir` and `CsxDotnetRoot`/`CsxRoslynDir` are resolved on first use (`_CSharpFindPaths` / `_CsxFindPaths`): a value set by the script, then the shared environment variables `CSHARP_IN_AHK_DOTNET`/`CSHARP_IN_AHK_ROSLYN`, then the shared `Csharp-in-AHK.ini` ([Paths] DotnetRoot/RoslynDir) next to the library, then auto-detection (DOTNET_ROOT, registry, %ProgramFiles%\dotnet, Visual Studio via vswhere). `Csharp-in-AHK.ini` is gitignored; `Csharp-in-AHK.example.ini` is the committed template.
- AHK loads `hostfxr.dll` from `CSDotnetRoot` / `CsxDotnetRoot`, starts the runtime with a generated runtimeconfig (Microsoft.WindowsDesktop.App), and calls `[UnmanagedCallersOnly]` methods (`Init`, `Run`) via `DllCall`. If one library already started .NET, the other reuses that runtime.
- The C# host source lives inside each .ahk file as an AHK continuation section. On first use it is compiled once with Roslyn `csc.exe` into `%TEMP%\CSharp-in-AHK\CSHost-<crc>.dll` (or `%TEMP%\Csx-in-AHK\CsxHost-<crc>.dll`). The CRC covers the host source, runtime version and compiler version, so editing the host source triggers a rebuild automatically.
- Scripts are compiled in memory with the Roslyn DLLs from `CSRoslynDir` / `CsxRoslynDir` and cached per AHK process.

## Rules when editing the embedded C# host source
- It sits inside an AHK `"( ... )"` continuation section. Quote marks are literal there, but no line may start with `)` (that ends the section), and backticks must not be used.
- The host entry-point class (`CSHost` / `CsxHost`) must not reference Roslyn types in fields or method signatures. Roslyn is resolved by the `AssemblyLoadContext.Resolving` handler registered in `Init`, so Roslyn code belongs in the separate `ScriptCompiler` class.

## Environment
- Machine-specific paths (.NET, Roslyn, AutoHotkey, Python) are in `CLAUDE.local.md`, which is not committed. Keep personal paths and details out of committed files.

## Testing
- Run test scripts headless, writing results to stdout with `FileAppend(Text "`n", "*", "UTF-8")`:
  `"/c/Program Files/AutoHotkey/v2/AutoHotkey64.exe" //ErrorStdOut test.ahk` (from Git Bash).
- Put throwaway test scripts in the session scratchpad, not in the repo. The demo files use `MsgBox` and need a person to click through them.

## Conventions
- The owner may edit files between sessions. Treat the files on disk as current.
- Commit or push only when asked.
- Keep the .ahk files compatible with Keysharp as well as AutoHotkey. Keysharp closes a file only when it is garbage-collected, so close every written file explicitly (`F := FileOpen(...), F.Write(...), F.Close()`) before anything else reads it. Keysharp can also run GUI events (such as an Edit's Change, raised when code sets `.Value`) while other code is still running, so event handlers must not assume that setup has finished.
