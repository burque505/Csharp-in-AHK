# Csharp-in-AHK

Run C# code inside AutoHotkey v2. No `dotnet.exe` process is started, and no project files or build steps are needed.

Csharp-in-AHK hosts the .NET runtime (.NET 8 or later, tested on .NET 10) **inside the AutoHotkey process**. It compiles C# source in memory with Roslyn and returns results straight to your AHK script. You get the whole .NET base class library, WinForms and WPF from a single `#Include`.

```ahk
#Requires AutoHotkey v2.0 64-bit
#Include "Csx-in-AHK.ahk"

MsgBox RunCsx('return "Hello from C# on .NET " + Environment.Version;')
```

---

## Features

- **In-process execution.** .NET is loaded once through `hostfxr` and stays resident, so there is no per-call process startup.
- **Two script styles**, each in its own standalone library:
  - **`Csharp-in-AHK.ahk`**: regular C# files with top-level statements, like `dotnet run app.cs`.
  - **`Csx-in-AHK.ahk`**: C# script (`.csx`) syntax via the Roslyn scripting API, like `csi.exe` / `dotnet-script`.
- **Values come back to AHK** as text that AHK can use directly: `bool` becomes `1`/`0`, numbers and dates use the invariant culture, and collections become one item per line.
- **Console output is captured.** `Console.Out` and `Console.Error` are collected and returned or exposed in a global variable.
- **Compilation errors are thrown as AHK errors**, with the compiler diagnostics in the message.
- **Directives:** `#r "Some.dll"`, `#r "nuget: Name, 1.2.3"`, `#:package Name@1.2.3` (from the local NuGet cache), and `#load "Other.cs"`.
- **Caching.** The host assembly is compiled once to `%TEMP%`, and compiled scripts are cached for the life of the AHK process.
- **Both libraries can be included together.** They share a single .NET runtime and use separate globals and functions.

## Requirements

| Component | Notes |
|---|---|
| AutoHotkey v2 | **64-bit only** (`AutoHotkey64.exe`) |
| .NET runtime | .NET 8 or later, including **Microsoft.WindowsDesktop.App** |
| Roslyn compiler | The `Roslyn` folder containing `csc.exe` and `Microsoft.CodeAnalysis*.dll`, e.g. from Visual Studio or Build Tools |

### ⚠️ Hard-coded paths

Both libraries ship with **hard-coded paths** to the author's Visual Studio 2026 Community install. **You will probably need to change them**, at the top of each library:

```ahk
; Csharp-in-AHK.ahk
global CSDotnetRoot := "C:\Program Files\Microsoft Visual Studio\18\Community\dotnet\net10.0\runtime"
global CSRoslynDir  := "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\Roslyn"

; Csx-in-AHK.ahk
global CsxDotnetRoot := "C:\Program Files\Microsoft Visual Studio\18\Community\dotnet\net10.0\runtime"
global CsxRoslynDir  := "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\Roslyn"
```

The libraries look for these files in those folders:

| Setting | Must contain |
|---|---|
| `CSDotnetRoot` / `CsxDotnetRoot` | `host\fxr\<version>\hostfxr.dll`<br>`shared\Microsoft.NETCore.App\<version>\` (.NET 8 or later)<br>`shared\Microsoft.WindowsDesktop.App\<version>\` (optional, needed for WinForms/WPF) |
| `CSRoslynDir` | `csc.exe`<br>`Microsoft.CodeAnalysis.dll`<br>`Microsoft.CodeAnalysis.CSharp.dll` |
| `CsxRoslynDir` | `csc.exe`<br>`Microsoft.CodeAnalysis.dll`<br>`Microsoft.CodeAnalysis.CSharp.dll`<br>`Microsoft.CodeAnalysis.Scripting.dll`<br>`Microsoft.CodeAnalysis.CSharp.Scripting.dll` |

`csc.exe` is the only executable used. It runs once to compile the embedded host assembly. Scripts themselves are compiled in memory through the Roslyn DLLs. A standalone .NET install, such as `C:\Program Files\dotnet`, also works as the .NET root.

If a required file is missing, the library throws an error that names the setting to fix.

> If scripts stop starting after a Visual Studio update, check these paths first.

## Installation

1. Clone or download this repository.
2. Copy `Csharp-in-AHK.ahk` and/or `Csx-in-AHK.ahk` next to your script, or into your AHK `Lib` folder.
3. Adjust the runtime and Roslyn paths as shown above.
4. `#Include` the library you want.

---

## Csharp-in-AHK: top-level C# programs

```ahk
#Include "Csharp-in-AHK.ahk"

Result := RunCSharp('Console.WriteLine(DateTime.Now);')           ; inline source
Result := RunCSharp("script.cs", "arg1", "arg2")                   ; path to an existing .cs file
Result := RunCSharpFile("script.cs", "arg1", "arg2")               ; always treated as a path
```

| Item | Description |
|---|---|
| Return value | Console output, or the value passed to `AHK.Return(value)` |
| `CSOutput` | Console output of the last script |
| `CSExitCode` | The script's `int` return value, or the HRESULT of an unhandled exception |
| `CSStreams` | Bitmask of captured streams: `1` = `Console.Out`, `2` = `Console.Error` (default `3`) |
| `args` | Extra parameters passed to `RunCSharp` |

```ahk
MsgBox RunCSharp('Console.WriteLine(string.Join(", ", args)); return args.Length;', "first", "second")
    . "`nExit code: " CSExitCode

MsgBox RunCSharp('Console.WriteLine("Computing..."); AHK.Return(Math.Sqrt(2));')
    . "`nConsole output: " CSOutput
```

`AHK.Return()` does not stop the script. If it is called more than once, the last call wins.

## Csx-in-AHK: C# scripts

```ahk
#Include "Csx-in-AHK.ahk"

MsgBox RunCsx('DateTime.Now.ToString("dddd, d MMMM yyyy")')   ; a final expression is returned

Area := RunCsx('Math.PI * Math.Pow(double.Parse(args[0]), 2)', 3)
MsgBox "Area: " Round(Area, 2)

if RunCsx('File.Exists(@"C:\Windows\notepad.exe")')            ; booleans come back as 1/0
    MsgBox "Notepad exists"
```

Statements, functions, classes and `await` can be mixed freely at the top level:

```ahk
MsgBox RunCsx('
(
    record Person(string Name, int Age);
    int Twice(int x) => x * 2;

    await Task.Delay(10);
    var people = new[] { new Person("Ann", 34), new Person("Bob", 27) };
    return string.Join(", ", people.Select(p => $"{p.Name} ({Twice(p.Age)})"));
)')
```

| Item | Description |
|---|---|
| Return value | The script's `return` value or final expression. If that is `null`, the console output is returned instead. |
| `CsxOutput` | Console output of the last script |
| `CsxStreams` | Bitmask of captured streams: `1` = `Console.Out`, `2` = `Console.Error` (default `3`) |
| `args` | Extra parameters passed to `RunCsx` |

A script file is recompiled automatically when it, or any file it `#load`s, changes.

## Common behavior

- **Implicit usings:** `System`, `System.Collections.Generic`, `System.IO`, `System.Linq`, `System.Net.Http`, `System.Threading`, `System.Threading.Tasks` (plus `System.Text` in Csx). All .NET and Windows Desktop assemblies are referenced.
- **Relative paths** in directives are resolved against the script's folder, or the working directory for inline scripts.
- **NuGet packages** are taken from the local NuGet cache. Their dependencies are not resolved automatically.
- **`Environment.Exit()`** inside a script also terminates AutoHotkey, because both run in the same process.

## How it works

1. On first use, the library loads `hostfxr.dll` from the configured .NET root. It starts the runtime with a generated `runtimeconfig.json` that targets `Microsoft.WindowsDesktop.App`.
2. A small C# host, embedded in the `.ahk` file as source, is compiled once with Roslyn `csc.exe` into `%TEMP%\CSharp-in-AHK\` or `%TEMP%\Csx-in-AHK\`. The file name includes a CRC of the host source, runtime version and compiler version, so the host is rebuilt automatically when any of them changes.
3. AHK calls the host's `[UnmanagedCallersOnly]` entry points (`Init`, `Run`) directly through `DllCall`.
4. User scripts are compiled in memory with the Roslyn assemblies and executed. Results and captured output are marshalled back as UTF-16 strings.

If one library has already started .NET, the other reuses the same runtime.

## Examples

| File | Description |
|---|---|
| [`cs_ex1.ahk`](cs_ex1.ahk) | Demos for `RunCSharp`: output, args, exit codes, exceptions, `AHK.Return` |
| [`csx_ex1.ahk`](csx_ex1.ahk) | Demos for `RunCsx`: return values, collections, records, `await`, files, compile errors |
| [`winforms_ex1.ahk`](winforms_ex1.ahk) | Minimal WinForms dialog that returns the user's input to AHK |
| [`wpf_ex1.ahk`](wpf_ex1.ahk) | Minimal WPF window that returns the user's input to AHK |
| [`Example.csx`](Example.csx) / [`ExampleHelpers.csx`](ExampleHelpers.csx) | A script file that uses `#load` to pull in helper functions and classes |

The demos show their results with `MsgBox`.

---

## Credits

- **Code:** written by **[Claude](https://www.anthropic.com/claude)** (Anthropic), working through Claude Code under the direction of [burque505](https://github.com/burque505).
- **Inspiration:** the idea, but no code, comes from *Powershell-in-AHK*, https://www.autohotkey.com/boards/viewtopic.php?f=83&t=141178, by user -+_[] .
- **CLR interop:** based on concepts and techniques from **CLR.ahk** by Lexikos.

## License

Released under the [MIT License](LICENSE). © 2026 burque505
