#Requires AutoHotkey v2.0 64-bit

; Csx-in-AHK
; Version:  v0.01
; License: MIT
; Description: Run C# scripts (*.csx / *.cs) on .NET 8+ in-process of AutoHotKey V2 and get their return values
;
; Usage:
;   #Include Csx-in-AHK.ahk
;   Result := RunCsx('return DateTime.Now.Year;')         ; "2026"
;   Result := RunCsx('Math.Sqrt(2) * 10')                  ; a final expression without ';' is returned too
;   Result := RunCsx("script.csx", "arg1", "arg2")         ; a path to an existing *.csx / *.cs file loads that file
;   Result := RunCsxFile("script.csx", "arg1", "arg2")     ; always treats the first parameter as a file path
;
; Scripts use C# script syntax (the same as csi.exe / dotnet-script):
;   - Statements, functions and classes can be mixed freely at the top level; `await` is allowed.
;   - `return <any value>;` (or a final expression without ';') is returned to AHK as text:
;     null -> "" (RunCsx then returns the console output instead), bool -> 1/0,
;     numbers and dates use the invariant culture, collections become one item per line.
;   - The console output is always available in CsxOutput.
;   - Implicit usings: System, System.Collections.Generic, System.IO, System.Linq, System.Net.Http, System.Text,
;     System.Threading, System.Threading.Tasks. All .NET and Windows Desktop (WinForms/WPF) assemblies are referenced.
;   - `args` holds the extra parameters passed to RunCsx.
;   - #r "path\to\Some.dll"    references an assembly
;   - #r "nuget: Name, 1.2.3"  or  #:package Name@1.2.3   references a NuGet package from the local NuGet cache
;                              (dependencies are not resolved)
;   - #load "Other.csx"        runs another script file first (its functions and classes become available)
;   - Relative paths are resolved against the script's folder (or the working directory for inline scripts).
;   - Compiled scripts are cached per AHK process; a script is recompiled when it or a #load-ed file changes.
;   - Calling Environment.Exit() inside a script terminates AutoHotkey too.
;
; Output configuration:
;   Bitmask: 1=Console.Out 2=Console.Error (including unhandled exceptions)
;   Compilation errors are thrown as AHK errors.
;
; Credits:
;   CLR/.NET interop based on concepts and techniques from CLR.ahk by Lexikos:
;   Developed with AI assistance from Claude

global CsxStreams := 3      ; Bitmask: 1=Console.Out 2=Console.Error
global CsxOutput := ""      ; Console output of the last script

; HARD-CODED PATHS: the two paths below point to the author's Visual Studio 2026 Community install.
; Change them to match your machine. If you later update Visual Studio and scripts stop starting, check them first
; (and CSDotnetRoot/CSRoslynDir in Csharp-in-AHK.ahk, if you use both libraries).
;   CsxDotnetRoot must contain:
;     host\fxr\<version>\hostfxr.dll
;     shared\Microsoft.NETCore.App\<version>\           (.NET 8 or later)
;     shared\Microsoft.WindowsDesktop.App\<version>\    (optional, needed for WinForms/WPF)
;   CsxRoslynDir must contain:
;     csc.exe                                    (compiles the embedded host once)
;     Microsoft.CodeAnalysis.dll
;     Microsoft.CodeAnalysis.CSharp.dll
;     Microsoft.CodeAnalysis.Scripting.dll
;     Microsoft.CodeAnalysis.CSharp.Scripting.dll
;   A standalone .NET install (e.g. C:\Program Files\dotnet) also works as CsxDotnetRoot.
global CsxDotnetRoot := "C:\Program Files\Microsoft Visual Studio\18\Community\dotnet\net10.0\runtime"
global CsxRoslynDir := "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\Roslyn"

RunCsx(Script, Args*) {
    if Script ~= "i)^[^\r\n]+\.csx?$" && (Attrib := FileExist(Script)) && !InStr(Attrib, "D")
        return RunCsxFile(Script, Args*)
    return _CsxRun(Script, "", Args)
}

RunCsxFile(Path, Args*) {
    if !FileExist(Path)
        throw Error("C# script not found", -1, Path)
    return _CsxRun("", Path, Args)
}

_CsxRun(Source, Path, Args) {
    global CsxStreams, CsxOutput
    RunFn := _CsxHost()
    Size := Args.Length * A_PtrSize
    for Arg in Args
        Size += (StrLen(Arg) + 1) * 2
    Argv := Buffer(Max(Size, A_PtrSize)), Offset := Args.Length * A_PtrSize
    for i, Arg in Args {
        NumPut("ptr", Argv.Ptr + Offset, Argv, (i - 1) * A_PtrSize)
        Offset += StrPut(String(Arg), Argv.Ptr + Offset, "UTF-16")    ; StrPut returns bytes written
    }
    Status := DllCall(RunFn, "ptr", Path = "" ? StrPtr(Source) : 0, "ptr", Path = "" ? 0 : StrPtr(Path), "ptr", Argv, "int", Args.Length
        , "int", CsxStreams, "ptr*", &OutPtr := 0, "ptr*", &ResultPtr := 0, "int")
    Output := _CsxTakeString(OutPtr)
    if Status
        throw Error(Output, -1)
    CsxOutput := Output
    return ResultPtr ? _CsxTakeString(ResultPtr) : Output
}

_CsxTakeString(Ptr) {
    Str := StrGet(Ptr, "UTF-16")
    DllCall("ole32\CoTaskMemFree", "ptr", Ptr)
    return Str
}

_CsxHost() {
    global CsxDotnetRoot, CsxRoslynDir
    static RunFn := 0
    if RunFn
        return RunFn
    NetCore := _CsxLatestDir(CsxDotnetRoot "\shared\Microsoft.NETCore.App")
    Desktop := _CsxLatestDir(CsxDotnetRoot "\shared\Microsoft.WindowsDesktop.App")
    Fxr := _CsxLatestDir(CsxDotnetRoot "\host\fxr") "\hostfxr.dll"
    if !NetCore || !FileExist(Fxr)
        throw Error(".NET runtime not found. Set CsxDotnetRoot to a folder containing host\fxr and shared\Microsoft.NETCore.App.", -1, CsxDotnetRoot)
    if !FileExist(CsxRoslynDir "\csc.exe") || !FileExist(CsxRoslynDir "\Microsoft.CodeAnalysis.CSharp.Scripting.dll")
        throw Error("Roslyn not found. Set CsxRoslynDir to a folder containing csc.exe and Microsoft.CodeAnalysis.CSharp.Scripting.dll.", -1, CsxRoslynDir)

    Source := "
    (
    using System;
    using System.Collections;
    using System.Collections.Generic;
    using System.Globalization;
    using System.IO;
    using System.Linq;
    using System.Runtime.InteropServices;
    using System.Runtime.Loader;
    using System.Text;
    using System.Text.RegularExpressions;
    using System.Threading.Tasks;
    using Microsoft.CodeAnalysis;
    using Microsoft.CodeAnalysis.CSharp.Scripting;
    using Microsoft.CodeAnalysis.Scripting;

    // Globals visible to scripts.
    public class CsxGlobals {
        public string[] args = Array.Empty<string>();
    }

    // Entry points called from AHK. This class must not reference Roslyn types, so that the
    // assembly resolver is registered before Roslyn is loaded.
    public static unsafe class CsxHost {
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
        public static int Run(char* source, char* file, char** argv, int argc, int mask, char** output, char** result) {
            string text, value = null;
            int status = 0;
            try {
                var args = new string[argc];
                for (int i = 0; i < argc; i++) args[i] = new string(argv[i]);
                text = Execute(source == null ? null : new string(source), file == null ? null : new string(file), args, mask, ref value);
            } catch (Exception ex) {
                text = ex.Message;
                status = 1;
            }
            *output = (char*)Marshal.StringToCoTaskMemUni(text);
            *result = value == null ? null : (char*)Marshal.StringToCoTaskMemUni(value);
            return status;
        }

        static string Execute(string source, string file, string[] args, int mask, ref string value) {
            Func<object, Task<object>> run = ScriptCompiler.Compile(source, file);
            var output = new StringWriter();
            var writer = TextWriter.Synchronized(output);
            TextWriter oldOut = Console.Out, oldErr = Console.Error;
            Console.SetOut((mask & 1) != 0 ? writer : TextWriter.Null);
            Console.SetError((mask & 2) != 0 ? writer : TextWriter.Null);
            try {
                object result = run(new CsxGlobals { args = args }).GetAwaiter().GetResult();
                if (result != null) value = Format(result);
            } catch (Exception ex) {
                Console.Error.WriteLine("Unhandled exception. " + Regex.Replace(ex.ToString(),
                    @"\r?\n\s*(at (Microsoft\.CodeAnalysis\.|CsxHost\.|System\.Runtime\.CompilerServices\.|System\.Threading\.Tasks\.)[^\r\n]*|--- End of stack trace[^\r\n]*)", ""));
            } finally {
                Console.SetOut(oldOut);
                Console.SetError(oldErr);
            }
            return output.ToString().TrimEnd();
        }

        static string Format(object value) => value switch {
            null => "",
            string s => s,
            bool b => b ? "1" : "0",
            IFormattable f => f.ToString(null, CultureInfo.InvariantCulture),
            IEnumerable items => string.Join("\n", items.Cast<object>().Select(Format)),
            _ => value.ToString()
        };
    }

    static class ScriptCompiler {
        static readonly string[] Imports = { "System", "System.Collections.Generic", "System.IO", "System.Linq",
            "System.Net.Http", "System.Text", "System.Threading", "System.Threading.Tasks" };
        // NuGet references are resolved here; other directives (#r, #load) are handled by Roslyn.
        static readonly Regex DirectiveRx = new(@"^[ \t]*#(?:r[ \t]+""nuget:([^""]*)""|:([a-z]+)[ \t]*([^\r\n]*))", RegexOptions.Multiline | RegexOptions.IgnoreCase);

        class Entry {
            public Func<object, Task<object>> Run;
            public List<(string Path, DateTime Time)> Files;
        }
        static readonly Dictionary<string, Entry> cache = new();
        static List<MetadataReference> frameworkRefs;

        public static Func<object, Task<object>> Compile(string source, string file) {
            if (file != null) {
                file = Path.GetFullPath(file);
                source ??= File.ReadAllText(file);
            }
            source ??= "";
            string dir = file != null ? Path.GetDirectoryName(file) : Environment.CurrentDirectory;
            var refs = new List<string>();
            source = DirectiveRx.Replace(source, m => {
                if (m.Groups[1].Success) refs.AddRange(NuGet(m.Groups[1].Value, ','));
                else if (m.Groups[2].Value.Equals("package", StringComparison.OrdinalIgnoreCase)) refs.AddRange(NuGet(m.Groups[3].Value, '@'));
                return "";
            });

            string key = dir + "\0" + file + "\0" + string.Join("\0", refs) + "\0" + source;
            if (cache.TryGetValue(key, out var cached) && cached.Files.All(f => File.Exists(f.Path) && File.GetLastWriteTimeUtc(f.Path) == f.Time))
                return cached.Run;

            frameworkRefs ??= ((string)AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES")).Split(Path.PathSeparator)
                .Select(path => (MetadataReference)MetadataReference.CreateFromFile(path)).ToList();
            var options = ScriptOptions.Default
                .WithReferences(frameworkRefs.Concat(refs.Select(path => MetadataReference.CreateFromFile(path))))
                .WithImports(Imports)
                .WithFilePath(file ?? "script.csx")
                .WithFileEncoding(Encoding.UTF8)
                .WithMetadataResolver(ScriptMetadataResolver.Default.WithBaseDirectory(dir))
                .WithSourceResolver(ScriptSourceResolver.Default.WithBaseDirectory(dir))
                .WithEmitDebugInformation(true)
                .WithOptimizationLevel(OptimizationLevel.Release)
                .WithAllowUnsafe(true);

            var script = CSharpScript.Create<object>(source, options, typeof(CsxGlobals));
            var errors = script.Compile().Where(d => d.Severity == DiagnosticSeverity.Error).ToList();
            if (errors.Count > 0)
                throw new Exception("C# compilation failed:\r\n" + string.Join("\r\n", errors));
            var compilation = script.GetCompilation();
            foreach (var reference in compilation.DirectiveReferences.OfType<PortableExecutableReference>())
                if (reference.FilePath != null) CsxHost.RefPaths[Path.GetFileNameWithoutExtension(reference.FilePath)] = reference.FilePath;

            var runner = script.CreateDelegate();
            var entry = new Entry {
                Run = globals => runner(globals),
                Files = compilation.SyntaxTrees.Select(t => t.FilePath).Where(File.Exists).Distinct(StringComparer.OrdinalIgnoreCase)
                    .Select(path => (path, File.GetLastWriteTimeUtc(path))).ToList()
            };
            cache[key] = entry;
            return entry.Run;
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
            foreach (var dll in dlls) CsxHost.RefPaths[Path.GetFileNameWithoutExtension(dll)] = dll;
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
    Key := Source "|" NetCore "|" CsxRoslynDir "|" FileGetVersion(CsxRoslynDir "\Microsoft.CodeAnalysis.CSharp.dll")
    Name := "CsxHost-" Format("{:08X}", DllCall("ntdll\RtlComputeCrc32", "uint", 0, "ptr", StrPtr(Key), "uint", StrLen(Key) * 2, "uint"))
    Cache := A_Temp "\Csx-in-AHK"
    Dll := Cache "\" Name ".dll", Config := Cache "\" Name ".runtimeconfig.json"
    if !FileExist(Dll)
        _CsxBuildHost(Source, Cache, Name, NetCore)
    if !FileExist(Config) {
        SplitPath(Desktop || NetCore, &Version)
        Framework := Desktop ? "Microsoft.WindowsDesktop.App" : "Microsoft.NETCore.App"
        FileOpen(Config, "w", "UTF-8-RAW").Write('{"runtimeOptions":{"framework":{"name":"' Framework '","version":"' Version '"}}}')
    }

    ; Start the runtime with hostfxr (https://learn.microsoft.com/dotnet/core/tutorials/netcore-hosting).
    ; If another library already started .NET in this process, hostfxr reuses that runtime.
    hFxr := DllCall("LoadLibrary", "str", Fxr, "ptr")
    Proc := Export => DllCall("GetProcAddress", "ptr", hFxr, "astr", Export, "ptr")
    Params := Buffer(3 * A_PtrSize, 0)
    NumPut("ptr", Params.Size, "ptr", 0, "ptr", StrPtr(CsxDotnetRoot), Params)
    Status := DllCall(Proc("hostfxr_initialize_for_runtime_config"), "wstr", Config, "ptr", Params, "ptr*", &Context := 0, "cdecl int")
    if Status < 0 || !Context
        throw Error(Format("Failed to initialize the .NET runtime (0x{:08X})", Status & 0xFFFFFFFF), -1, Config)
    DllCall(Proc("hostfxr_get_runtime_delegate"), "ptr", Context, "int", 7, "ptr*", &LoadAssembly := 0, "cdecl int")    ; hdt_load_assembly
    DllCall(Proc("hostfxr_get_runtime_delegate"), "ptr", Context, "int", 6, "ptr*", &GetFunction := 0, "cdecl int")     ; hdt_get_function_pointer
    DllCall(Proc("hostfxr_close"), "ptr", Context, "cdecl int")
    if !LoadAssembly || !GetFunction
        throw Error("This .NET runtime does not support in-process hosting (.NET 8 or later is required).", -1)
    if Status := DllCall(LoadAssembly, "wstr", Dll, "ptr", 0, "ptr", 0, "int")
        throw Error(Format("Failed to load the C# script host (0x{:08X})", Status & 0xFFFFFFFF), -1, Dll)
    for Method in ["Init", "Run"] {
        ; delegate_type_name = -1 (UNMANAGEDCALLERSONLY_METHOD)
        if Status := DllCall(GetFunction, "wstr", "CsxHost, " Name, "wstr", Method, "ptr", -1, "ptr", 0, "ptr", 0, "ptr*", &Fn := 0, "int")
            throw Error(Format("Failed to get CsxHost.{} (0x{:08X})", Method, Status & 0xFFFFFFFF), -1)
        if Method = "Init"
            DllCall(Fn, "wstr", CsxRoslynDir, "int")
    }
    return RunFn := Fn
}

_CsxBuildHost(Source, Cache, Name, NetCore) {
    global CsxRoslynDir
    DirCreate(Cache)
    Base := Cache "\" Name
    FileOpen(Base ".cs", "w", "UTF-8").Write(Source)
    Rsp := '-nologo -noconfig -nostdlib -target:library -unsafe -optimize -langversion:latest -out:"' Base '.dll"`n'
    Loop Files NetCore "\*.dll"
        if _CsxIsManaged(A_LoopFileFullPath)
            Rsp .= '-r:"' A_LoopFileFullPath '"`n'
    for Ref in ["Microsoft.CodeAnalysis", "Microsoft.CodeAnalysis.CSharp", "Microsoft.CodeAnalysis.Scripting", "Microsoft.CodeAnalysis.CSharp.Scripting"]
        Rsp .= '-r:"' CsxRoslynDir '\' Ref '.dll"`n'
    Rsp .= '"' Base '.cs"'
    FileOpen(Base ".rsp", "w", "UTF-8").Write(Rsp)
    if RunWait(A_ComSpec ' /c ""' CsxRoslynDir '\csc.exe" @"' Base '.rsp" > "' Base '.log" 2>&1"', , "Hide") || !FileExist(Base ".dll") {
        try FileDelete(Base ".dll")
        throw Error("Failed to compile the C# script host", -2, FileExist(Base ".log") ? FileRead(Base ".log") : "")
    }
}

_CsxIsManaged(Path) {
    ; True if the PE file has a CLR header (data directory 14)
    File := FileOpen(Path, "r")
    if !File || File.Length < 0x200 || File.ReadUShort() != 0x5A4D
        return false
    File.Pos := 0x3C, PE := File.ReadUInt()
    File.Pos := PE + 24, Magic := File.ReadUShort()
    File.Pos := PE + 24 + (Magic = 0x20B ? 112 : 96) + 14 * 8
    return File.ReadUInt() != 0
}

_CsxLatestDir(Parent) {
    Latest := "", LatestVersion := ""
    Loop Files Parent "\*", "D"
        if A_LoopFileName ~= "^\d+\.\d+\.\d+$" && (Latest = "" || VerCompare(A_LoopFileName, LatestVersion) > 0)
            Latest := A_LoopFileFullPath, LatestVersion := A_LoopFileName
    return Latest
}

; Examples:
; MsgBox RunCsx('return "Hello from C# on .NET " + Environment.Version;')
; MsgBox RunCsx('DateTime.Now.ToString("yyyy-MM-dd HH:mm")')
; MsgBox RunCsx('return Directory.GetFiles(@"C:\Windows", "*.exe").Select(Path.GetFileName).Take(5);')
; MsgBox RunCsx("Example.csx", "AutoHotkey")
