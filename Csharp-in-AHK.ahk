#Requires AutoHotkey v2.0 64-bit

; Csharp-in-AHK
; Version:  v0.02
; License: MIT
; Description: Run top-level C# scripts (*.cs) on .NET 8+ in-process of AutoHotKey V2 without launching dotnet.exe
;
; Usage:
;   #Include Csharp-in-AHK.ahk
;   Result := RunCSharp('Console.WriteLine(DateTime.Now);')
;   Result := RunCSharp("script.cs", "arg1", "arg2")      ; a path to an existing *.cs file loads that file
;   Result := RunCSharpFile("script.cs", "arg1", "arg2")  ; always treats the first parameter as a file path
;
; Scripts are regular C# files with top-level statements (like a .NET 10 `dotnet run app.cs` file):
;   - Implicit usings: System, System.Collections.Generic, System.IO, System.Linq, System.Net.Http,
;     System.Threading, System.Threading.Tasks. All .NET and Windows Desktop (WinForms/WPF) assemblies are referenced.
;   - `args` holds the extra parameters passed to RunCSharp. `return <int>;` sets CSExitCode.
;   - AHK.Return(value) makes RunCSharp return that value instead of the console output (which is then
;     available in CSOutput). It does not stop the script; the last call wins. Values are converted to text:
;     null -> "", bool -> 1/0, numbers and dates use the invariant culture, collections become one item per line.
;   - #:package Name@1.2.3     references a NuGet package from the local NuGet cache (dependencies are not resolved)
;   - #r "path\to\Some.dll"    references an assembly (#r "nuget: Name, 1.2.3" also works)
;   - #load "Other.cs"         compiles another C# file (e.g. class definitions) together with the script
;   - Other #: directives and #! lines are ignored. Relative paths are resolved against the script's folder
;     (or the working directory for inline scripts).
;   - Compiled scripts are cached per AHK process, so running the same script again is fast.
;   - Calling Environment.Exit() inside a script terminates AutoHotkey too.
;
; Output configuration:
;   Bitmask: 1=Console.Out 2=Console.Error (including unhandled exceptions)
;   Compilation errors are thrown as AHK errors.
;
; Credits:
;   Idea, but no code, from Powershell-in-AHK.ahk
;   CLR/.NET interop based on concepts and techniques from CLR.ahk by Lexikos:
;   Developed with AI assistance.

global CSStreams := 3       ; Bitmask: 1=Console.Out 2=Console.Error
global CSExitCode := 0      ; Exit code of the last script (its int return value, or the HRESULT of an unhandled exception)
global CSOutput := ""       ; Console output of the last script

; HARD-CODED PATHS: the two paths below point to the author's Visual Studio 2026 Community install.
; Change them to match your machine. If you later update Visual Studio and scripts stop starting, check them first.
;   CSDotnetRoot must contain:
;     host\fxr\<version>\hostfxr.dll
;     shared\Microsoft.NETCore.App\<version>\           (.NET 8 or later)
;     shared\Microsoft.WindowsDesktop.App\<version>\    (optional, needed for WinForms/WPF)
;   CSRoslynDir must contain:
;     csc.exe                                    (compiles the embedded host once)
;     Microsoft.CodeAnalysis.dll
;     Microsoft.CodeAnalysis.CSharp.dll
;   A standalone .NET install (e.g. C:\Program Files\dotnet) also works as CSDotnetRoot.
global CSDotnetRoot := "C:\Program Files\Microsoft Visual Studio\18\Community\dotnet\net10.0\runtime"
global CSRoslynDir := "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\Roslyn"

RunCSharp(Script, Args*) {
    if Script ~= "i)^[^\r\n]+\.cs$" && (Attrib := FileExist(Script)) && !InStr(Attrib, "D")
        return RunCSharpFile(Script, Args*)
    return _CSharpRun(Script, "", Args)
}

RunCSharpFile(Path, Args*) {
    if !FileExist(Path)
        throw Error("C# script not found", -1, Path)
    return _CSharpRun("", Path, Args)
}

_CSharpRun(Source, Path, Args) {
    global CSStreams, CSExitCode, CSOutput
    RunFn := _CSharpHost()
    Size := Args.Length * A_PtrSize
    for Arg in Args
        Size += (StrLen(Arg) + 1) * 2
    Argv := Buffer(Max(Size, A_PtrSize)), Offset := Args.Length * A_PtrSize
    for i, Arg in Args {
        NumPut("ptr", Argv.Ptr + Offset, Argv, (i - 1) * A_PtrSize)
        Offset += StrPut(String(Arg), Argv.Ptr + Offset, "UTF-16") * 2
    }
    Status := DllCall(RunFn, "ptr", Path = "" ? StrPtr(Source) : 0, "ptr", Path = "" ? 0 : StrPtr(Path), "ptr", Argv, "int", Args.Length
        , "int", CSStreams, "int*", &ExitCode := 0, "ptr*", &OutPtr := 0, "ptr*", &ResultPtr := 0, "int")
    Output := _CSharpTakeString(OutPtr)
    if Status
        throw Error(Output, -1)
    CSExitCode := ExitCode
    CSOutput := Output
    return ResultPtr ? _CSharpTakeString(ResultPtr) : Output
}

_CSharpTakeString(Ptr) {
    Str := StrGet(Ptr, "UTF-16")
    DllCall("ole32\CoTaskMemFree", "ptr", Ptr)
    return Str
}

_CSharpHost() {
    global CSDotnetRoot, CSRoslynDir
    static RunFn := 0
    if RunFn
        return RunFn
    NetCore := _CSharpLatestDir(CSDotnetRoot "\shared\Microsoft.NETCore.App")
    Desktop := _CSharpLatestDir(CSDotnetRoot "\shared\Microsoft.WindowsDesktop.App")
    Fxr := _CSharpLatestDir(CSDotnetRoot "\host\fxr") "\hostfxr.dll"
    if !NetCore || !FileExist(Fxr)
        throw Error(".NET runtime not found. Set CSDotnetRoot to a folder containing host\fxr and shared\Microsoft.NETCore.App.", -1, CSDotnetRoot)
    if !FileExist(CSRoslynDir "\csc.exe") || !FileExist(CSRoslynDir "\Microsoft.CodeAnalysis.CSharp.dll")
        throw Error("Roslyn C# compiler not found. Set CSRoslynDir to a folder containing csc.exe and Microsoft.CodeAnalysis.CSharp.dll.", -1, CSRoslynDir)

    Source := "
    (
    using System;
    using System.Collections;
    using System.Collections.Generic;
    using System.Globalization;
    using System.IO;
    using System.Linq;
    using System.Reflection;
    using System.Runtime.InteropServices;
    using System.Runtime.Loader;
    using System.Text;
    using System.Text.RegularExpressions;
    using System.Threading;
    using System.Threading.Tasks;
    using Microsoft.CodeAnalysis;
    using Microsoft.CodeAnalysis.CSharp;
    using Microsoft.CodeAnalysis.Emit;

    // Entry points called from AHK. This class must not reference Roslyn types, so that the
    // assembly resolver is registered before Roslyn is loaded.
    public static unsafe class CSHost {
        internal static string RoslynDir = "";
        internal static readonly Dictionary<string, string> RefPaths = new(StringComparer.OrdinalIgnoreCase);

        [UnmanagedCallersOnly]
        public static int Init(char* roslynDir) {
            RoslynDir = new string(roslynDir);
            AssemblyLoadContext.Default.Resolving += (context, name) => {
                if (!RefPaths.TryGetValue(name.Name, out var path)) path = Path.Combine(RoslynDir, name.Name + ".dll");
                return File.Exists(path) ? context.LoadFromAssemblyPath(path) : null;
            };
            return 0;
        }

        [UnmanagedCallersOnly]
        public static int Run(char* source, char* file, char** argv, int argc, int mask, int* exitCode, char** output, char** result) {
            string text, value = null;
            int status = 0, code = 0;
            try {
                var args = new string[argc];
                for (int i = 0; i < argc; i++) args[i] = new string(argv[i]);
                text = Execute(source == null ? null : new string(source), file == null ? null : new string(file), args, mask, ref code, ref value);
            } catch (Exception ex) {
                text = ex.Message;
                status = 1;
            }
            *exitCode = code;
            *output = (char*)Marshal.StringToCoTaskMemUni(text);
            *result = value == null ? null : (char*)Marshal.StringToCoTaskMemUni(value);
            return status;
        }

        static string Execute(string source, string file, string[] args, int mask, ref int exitCode, ref string value) {
            MethodInfo main = ScriptCompiler.Compile(source, file);
            AHK.Reset();
            var output = new StringWriter();
            var writer = TextWriter.Synchronized(output);
            TextWriter oldOut = Console.Out, oldErr = Console.Error;
            Console.SetOut((mask & 1) != 0 ? writer : TextWriter.Null);
            Console.SetError((mask & 2) != 0 ? writer : TextWriter.Null);
            try {
                object result = main.Invoke(null, BindingFlags.DoNotWrapExceptions, null,
                    main.GetParameters().Length == 1 ? new object[] { args } : null, null);
                if (result is Task task) {
                    task.GetAwaiter().GetResult();
                    result = task.GetType().GetProperty("Result")?.GetValue(task);
                }
                exitCode = result is int code ? code : 0;
            } catch (Exception ex) {
                exitCode = ex.HResult;
                Console.Error.WriteLine("Unhandled exception. " + Regex.Replace(ex.ToString(), @"\r?\n\s+at (System\.Reflection\.|CSHost\.)[^\r\n]*", ""));
            } finally {
                Console.SetOut(oldOut);
                Console.SetError(oldErr);
            }
            if (AHK.HasResult) value = AHK.Format(AHK.Result);
            AHK.Reset();
            return output.ToString().TrimEnd();
        }
    }

    // Available to scripts: AHK.Return(value) sets the value RunCSharp returns.
    public static class AHK {
        internal static bool HasResult;
        internal static object Result;

        public static void Return(object value) {
            Result = value;
            HasResult = true;
        }

        internal static void Reset() {
            Result = null;
            HasResult = false;
        }

        internal static string Format(object value) => value switch {
            null => "",
            string s => s,
            bool b => b ? "1" : "0",
            IFormattable f => f.ToString(null, CultureInfo.InvariantCulture),
            IEnumerable items => string.Join("\n", items.Cast<object>().Select(Format)),
            _ => value.ToString()
        };
    }

    static class ScriptCompiler {
        const string GlobalUsings = "global using System; global using System.Collections.Generic; global using System.IO; global using System.Linq; "
            + "global using System.Net.Http; global using System.Threading; global using System.Threading.Tasks;";
        static readonly Regex DirectiveRx = new(@"^[ \t]*#(?:(r|load)[ \t]+""([^""]*)""|:([a-z]+)[ \t]*([^\r\n]*)|![^\r\n]*)", RegexOptions.Multiline);
        static readonly Dictionary<string, MethodInfo> cache = new();
        static List<MetadataReference> frameworkRefs;
        static int scriptCount;

        public static MethodInfo Compile(string source, string file) {
            var trees = new List<(string Text, string Path)>();
            var refs = new List<string>();
            var loaded = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (file != null) {
                file = Path.GetFullPath(file);
                source ??= File.ReadAllText(file);
                loaded.Add(file);
            }
            AddSource(source ?? "", file, trees, refs, loaded);

            string key = string.Join("\0", refs) + "\0" + string.Join("\0", trees.Select(t => t.Path + "\0" + t.Text));
            if (cache.TryGetValue(key, out var cached)) return cached;

            var parseOptions = new CSharpParseOptions(LanguageVersion.Latest);
            var syntaxTrees = trees.Select(t => CSharpSyntaxTree.ParseText(t.Text, parseOptions, t.Path, Encoding.UTF8))
                .Append(CSharpSyntaxTree.ParseText(GlobalUsings, parseOptions));
            frameworkRefs ??= ((string)AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES")).Split(Path.PathSeparator)
                .Append(typeof(AHK).Assembly.Location)
                .Select(path => (MetadataReference)MetadataReference.CreateFromFile(path)).ToList();
            var compilation = CSharpCompilation.Create("CSharpScript" + Interlocked.Increment(ref scriptCount), syntaxTrees,
                frameworkRefs.Concat(refs.Select(path => MetadataReference.CreateFromFile(path))),
                new CSharpCompilationOptions(OutputKind.ConsoleApplication, optimizationLevel: OptimizationLevel.Release,
                    allowUnsafe: true, nullableContextOptions: NullableContextOptions.Enable));

            using var pe = new MemoryStream();
            using var pdb = new MemoryStream();
            var result = compilation.Emit(pe, pdb, options: new EmitOptions(debugInformationFormat: DebugInformationFormat.PortablePdb));
            if (!result.Success)
                throw new Exception("C# compilation failed:\r\n" + string.Join("\r\n",
                    result.Diagnostics.Where(d => d.Severity == DiagnosticSeverity.Error).Select(d => d.ToString())));
            var main = Assembly.Load(pe.ToArray(), pdb.ToArray()).EntryPoint;
            cache[key] = main;
            return main;
        }

        // Handles #r, #load and #: directives, blanking them so that line numbers stay the same.
        static void AddSource(string text, string path, List<(string, string)> trees, List<string> refs, HashSet<string> loaded) {
            string dir = path != null ? Path.GetDirectoryName(path) : Environment.CurrentDirectory;
            var loads = new List<string>();
            text = DirectiveRx.Replace(text, m => {
                string kind = m.Groups[1].Success ? m.Groups[1].Value : m.Groups[3].Value;
                if (kind == "r") refs.AddRange(Reference(m.Groups[2].Value, dir));
                else if (kind == "load") loads.Add(Path.GetFullPath(Path.Combine(dir, m.Groups[2].Value)));
                else if (kind == "package") refs.AddRange(NuGet(m.Groups[4].Value, '@'));
                return "";
            });
            trees.Add((text, path ?? "script.cs"));
            foreach (var load in loads)
                if (loaded.Add(load)) AddSource(File.ReadAllText(load), load, trees, refs, loaded);
        }

        static IEnumerable<string> Reference(string reference, string dir) {
            if (reference.StartsWith("nuget:", StringComparison.OrdinalIgnoreCase)) return NuGet(reference.Substring(6), ',');
            string path = Path.GetFullPath(Path.Combine(dir, reference));
            if (!File.Exists(path)) throw new FileNotFoundException("Referenced assembly not found: " + path);
            CSHost.RefPaths[Path.GetFileNameWithoutExtension(path)] = path;
            return new[] { path };
        }

        // Resolves a package from the local NuGet cache (packages must have been restored before).
        static IEnumerable<string> NuGet(string spec, char separator) {
            int i = spec.IndexOf(separator);
            string name = (i < 0 ? spec : spec.Substring(0, i)).Trim(), version = i < 0 ? "" : spec.Substring(i + 1).Trim();
            string root = Environment.GetEnvironmentVariable("NUGET_PACKAGES")
                ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nuget", "packages");
            string dir = Path.Combine(root, name.ToLowerInvariant());
            if (version is "" or "*")
                version = !Directory.Exists(dir) ? null : Directory.GetDirectories(dir).Select(Path.GetFileName)
                    .OrderBy(v => v.Contains('-'))
                    .ThenByDescending(v => Version.TryParse(v.Split('-')[0], out var parsed) ? parsed : new Version())
                    .FirstOrDefault();
            string lib = Path.Combine(dir, version?.ToLowerInvariant() ?? "", "lib");
            if (version == null || !Directory.Exists(lib))
                throw new Exception($"NuGet package {name} {version} was not found in {root}. Restore it once (e.g. with dotnet restore) to add it to the local cache.");
            string best = Directory.GetDirectories(lib).Where(d => FrameworkScore(Path.GetFileName(d)) > 0)
                .OrderByDescending(d => FrameworkScore(Path.GetFileName(d))).FirstOrDefault()
                ?? throw new Exception($"NuGet package {name} {version} has no library for .NET {Environment.Version.Major}.");
            var dlls = Directory.GetFiles(best, "*.dll");
            foreach (var dll in dlls) CSHost.RefPaths[Path.GetFileNameWithoutExtension(dll)] = dll;
            return dlls;
        }

        static int FrameworkScore(string tfm) {
            var m = Regex.Match(tfm, @"^(netstandard|netcoreapp|net)(\d+)\.(\d+)");
            if (!m.Success) return 0;
            int major = int.Parse(m.Groups[2].Value), minor = int.Parse(m.Groups[3].Value);
            return m.Groups[1].Value switch {
                "net" when major >= 5 && major <= Environment.Version.Major => 1000 + major * 10 + minor,
                "netcoreapp" => 500 + major * 10 + minor,
                "netstandard" => 100 + major * 10 + minor,
                _ => 0
            };
        }
    }
    )"

    ; The host assembly is compiled once per host source / runtime / compiler version and cached.
    Key := Source "|" NetCore "|" CSRoslynDir "|" FileGetVersion(CSRoslynDir "\Microsoft.CodeAnalysis.CSharp.dll")
    Name := "CSHost-" Format("{:08X}", DllCall("ntdll\RtlComputeCrc32", "uint", 0, "ptr", StrPtr(Key), "uint", StrLen(Key) * 2, "uint"))
    Cache := A_Temp "\CSharp-in-AHK"
    Dll := Cache "\" Name ".dll", Config := Cache "\" Name ".runtimeconfig.json"
    if !FileExist(Dll)
        _CSharpBuildHost(Source, Cache, Name, NetCore)
    if !FileExist(Config) {
        SplitPath(Desktop || NetCore, &Version)
        Framework := Desktop ? "Microsoft.WindowsDesktop.App" : "Microsoft.NETCore.App"
        FileOpen(Config, "w", "UTF-8-RAW").Write('{"runtimeOptions":{"framework":{"name":"' Framework '","version":"' Version '"}}}')
    }

    ; Start the runtime with hostfxr (https://learn.microsoft.com/dotnet/core/tutorials/netcore-hosting)
    hFxr := DllCall("LoadLibrary", "str", Fxr, "ptr")
    Proc := Export => DllCall("GetProcAddress", "ptr", hFxr, "astr", Export, "ptr")
    Params := Buffer(3 * A_PtrSize, 0)
    NumPut("ptr", Params.Size, "ptr", 0, "ptr", StrPtr(CSDotnetRoot), Params)
    Status := DllCall(Proc("hostfxr_initialize_for_runtime_config"), "wstr", Config, "ptr", Params, "ptr*", &Context := 0, "cdecl int")
    if Status < 0 || !Context
        throw Error(Format("Failed to initialize the .NET runtime (0x{:08X})", Status & 0xFFFFFFFF), -1, Config)
    DllCall(Proc("hostfxr_get_runtime_delegate"), "ptr", Context, "int", 7, "ptr*", &LoadAssembly := 0, "cdecl int")    ; hdt_load_assembly
    DllCall(Proc("hostfxr_get_runtime_delegate"), "ptr", Context, "int", 6, "ptr*", &GetFunction := 0, "cdecl int")     ; hdt_get_function_pointer
    DllCall(Proc("hostfxr_close"), "ptr", Context, "cdecl int")
    if !LoadAssembly || !GetFunction
        throw Error("This .NET runtime does not support in-process hosting (.NET 8 or later is required).", -1)
    if Status := DllCall(LoadAssembly, "wstr", Dll, "ptr", 0, "ptr", 0, "int")
        throw Error(Format("Failed to load the C# host (0x{:08X})", Status & 0xFFFFFFFF), -1, Dll)
    for Method in ["Init", "Run"] {
        ; delegate_type_name = -1 (UNMANAGEDCALLERSONLY_METHOD)
        if Status := DllCall(GetFunction, "wstr", "CSHost, " Name, "wstr", Method, "ptr", -1, "ptr", 0, "ptr", 0, "ptr*", &Fn := 0, "int")
            throw Error(Format("Failed to get CSHost.{} (0x{:08X})", Method, Status & 0xFFFFFFFF), -1)
        if Method = "Init"
            DllCall(Fn, "wstr", CSRoslynDir, "int")
    }
    return RunFn := Fn
}

_CSharpBuildHost(Source, Cache, Name, NetCore) {
    global CSRoslynDir
    DirCreate(Cache)
    Base := Cache "\" Name
    FileOpen(Base ".cs", "w", "UTF-8").Write(Source)
    Rsp := '-nologo -noconfig -nostdlib -target:library -unsafe -optimize -langversion:latest -out:"' Base '.dll"`n'
    Loop Files NetCore "\*.dll"
        if _CSharpIsManaged(A_LoopFileFullPath)
            Rsp .= '-r:"' A_LoopFileFullPath '"`n'
    Rsp .= '-r:"' CSRoslynDir '\Microsoft.CodeAnalysis.dll"`n-r:"' CSRoslynDir '\Microsoft.CodeAnalysis.CSharp.dll"`n"' Base '.cs"'
    FileOpen(Base ".rsp", "w", "UTF-8").Write(Rsp)
    if RunWait(A_ComSpec ' /c ""' CSRoslynDir '\csc.exe" @"' Base '.rsp" > "' Base '.log" 2>&1"', , "Hide") || !FileExist(Base ".dll") {
        try FileDelete(Base ".dll")
        throw Error("Failed to compile the C# host", -2, FileExist(Base ".log") ? FileRead(Base ".log") : "")
    }
}

_CSharpIsManaged(Path) {
    ; True if the PE file has a CLR header (data directory 14)
    File := FileOpen(Path, "r")
    if !File || File.Length < 0x200 || File.ReadUShort() != 0x5A4D
        return false
    File.Pos := 0x3C, PE := File.ReadUInt()
    File.Pos := PE + 24, Magic := File.ReadUShort()
    File.Pos := PE + 24 + (Magic = 0x20B ? 112 : 96) + 14 * 8
    return File.ReadUInt() != 0
}

_CSharpLatestDir(Parent) {
    Latest := "", LatestVersion := ""
    Loop Files Parent "\*", "D"
        if A_LoopFileName ~= "^\d+\.\d+\.\d+$" && (Latest = "" || VerCompare(A_LoopFileName, LatestVersion) > 0)
            Latest := A_LoopFileFullPath, LatestVersion := A_LoopFileName
    return Latest
}

; Examples:
; MsgBox RunCSharp('Console.WriteLine(DateTime.Now);')
; MsgBox RunCSharp('Console.WriteLine("Hello from C# on .NET " + Environment.Version);')
; MsgBox RunCSharp('foreach (var p in System.Diagnostics.Process.GetProcesses().Take(5)) Console.WriteLine(p.ProcessName);')
; MsgBox RunCSharp('Console.WriteLine("Success"); Console.Error.WriteLine("Error"); throw new Exception("Boom");')
; MsgBox RunCSharp("MyScript.cs", "first arg", "second arg")
