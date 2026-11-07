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
;   - #r "nuget: Name, 1.2.3"  or  #:package Name@1.2.3   references a NuGet package and its dependencies.
;                              Missing packages are downloaded (see NUGET below).
;   - #load "Other.csx"        runs another script file first (its functions and classes become available)
;   - Relative paths are resolved against the script's folder (or the working directory for inline scripts).
;   - Compiled scripts are cached per AHK process; a script is recompiled when it or a #load-ed file changes. They are
;     also kept on disk (CacheDir\csx-scripts, by default %TEMP%\Csx-in-AHK\csx-scripts), so that a later start loads
;     them instead of compiling them again. CSHARP_IN_AHK_TRACE=<file> logs each compile or load with its time.
;   - CsxPrebuild(Script) compiles a script (a file or a string) without running it, into CacheDir\csx-prebuilt, for a
;     program that carries its scripts compiled: loaded from there wherever the program is, while the sources match.
;   - Calling Environment.Exit() inside a script terminates AutoHotkey too.
;
; Output configuration:
;   Bitmask: 1=Console.Out 2=Console.Error (including unhandled exceptions)
;   Compilation errors are thrown as AHK errors.
;
; NUGET: package references are restored like `dotnet run app.cs` does, with the NuGet client libraries
;   (NuGet.Commands), which are downloaded once from nuget.org into %LOCALAPPDATA%\Csharp-in-AHK\nuget\client.
;   - Packages and their dependencies go to the global NuGet folder (~\.nuget\packages); nuget.config sources and
;     credentials are used (nuget.org when no source is enabled). Native DLLs (runtimes\win-x64\native) are found too.
;   - Versions follow NuGet: 1.2.3 means 1.2.3 or the lowest version above it, * is the newest stable version,
;     1.* the newest 1.x, [1.0,2.0) a range. Without a version, * is used.
;   - The resolved files are cached in %LOCALAPPDATA%\Csharp-in-AHK\nuget\restore, so later runs do not restore again.
;     Versions with * are checked for updates once a day; if that fails (e.g. offline), the last result is used.
;
; Credits:
;   CLR/.NET interop based on concepts and techniques from CLR.ahk by Lexikos:
;   NuGet support modeled on the NuGet package provider of Keysharp (no code taken).
;   Developed with AI assistance from Claude

global CsxStreams := 3      ; Bitmask: 1=Console.Out 2=Console.Error
global CsxOutput := ""      ; Console output of the last script

; PATHS: CsxDotnetRoot and CsxRoslynDir are found automatically the first time a script runs.
; The first setting found wins (Csharp-in-AHK.ahk reads the same environment variables and .ini file):
;   1. CsxDotnetRoot / CsxRoslynDir set by your script (before or after #Include, before the first RunCsx call).
;   2. The environment variables CSHARP_IN_AHK_DOTNET / CSHARP_IN_AHK_ROSLYN.
;   3. Csharp-in-AHK.ini next to this file, section [Paths], keys DotnetRoot / RoslynDir (see Csharp-in-AHK.example.ini).
;   4. Auto-detection. .NET: DOTNET_ROOT, the registered x64 .NET install, %ProgramFiles%\dotnet, then the runtime
;      bundled with Visual Studio. Roslyn: Visual Studio / Build Tools installs, newest first (found with vswhere.exe),
;      then a compiler downloaded earlier by step 5.
;   5. Roslyn only: if nothing was found, Microsoft's compiler package Microsoft.Net.Compilers.Toolset is downloaded
;      once from nuget.org into %LOCALAPPDATA%\Csharp-in-AHK\roslyn (about 22 MB) and its tasks\net472 folder is used.
;   A path set in steps 1-3 is never replaced by auto-detection or a download: if it is wrong, you get an error.
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
;
; A PROGRAM THAT CARRIES EVERYTHING (nothing downloaded, nothing written outside its folder): Csharp-in-AHK.ini's
; [Paths] section can also have these (paths relative to the .ini's folder, or full); Csharp-in-AHK.ahk reads them too:
;   CsxHostDll=lib\host\CsxHost-Name.dll  this library's host, built beforehand (CsxBuildHost): csc.exe isn't needed
;                                      then, only RoslynDir's Microsoft.CodeAnalysis*.dll (the two Scripting ones too).
;                                      (HostDll is Csharp-in-AHK's own host.)
;   PackagesManifest=lib\packages.txt  the packages' files, as "compile|path", "runtime|path" and "native|path" lines
;                                      (paths relative to the manifest's folder): #:package and #r "nuget:" resolve
;                                      from it, with no NuGet client, no restore and nothing in ~\.nuget
;   CacheDir=lib\cache                 where the host's runtimeconfig (and a host built here) go, instead of %TEMP%
; DotnetRoot and RoslynDir may be relative there too.
global CsxDotnetRoot := IsSet(CsxDotnetRoot) ? CsxDotnetRoot : ""
global CsxRoslynDir := IsSet(CsxRoslynDir) ? CsxRoslynDir : ""
global CsxHostDll := IsSet(CsxHostDll) ? CsxHostDll : ""
global CsxPackagesManifest := IsSet(CsxPackagesManifest) ? CsxPackagesManifest : ""
global CsxCacheDir := IsSet(CsxCacheDir) ? CsxCacheDir : ""

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
    global CsxDotnetRoot, CsxRoslynDir, CsxHostDll, CsxPackagesManifest, CsxCacheDir
    static RunFn := 0
    if RunFn
        return RunFn
    _CsxFindPaths(&DotnetFrom, &RoslynFrom)
    NetCore := _CsxLatestDir(CsxDotnetRoot "\shared\Microsoft.NETCore.App")
    Desktop := _CsxLatestDir(CsxDotnetRoot "\shared\Microsoft.WindowsDesktop.App")
    Fxr := _CsxLatestDir(CsxDotnetRoot "\host\fxr") "\hostfxr.dll"
    if !NetCore || !FileExist(Fxr)
        throw Error(".NET 8 or later not found (" DotnetFrom "). CsxDotnetRoot must be a folder containing host\fxr and shared\Microsoft.NETCore.App.", -1, CsxDotnetRoot)
    ; (a host built beforehand needs no csc.exe, only the compiler's DLLs)
    if CsxHostDll != "" && !FileExist(CsxHostDll)
        throw Error("The C# script host was not found (CsxHostDll in Csharp-in-AHK.ini).", -1, CsxHostDll)
    if CsxHostDll = "" && !FileExist(CsxRoslynDir "\csc.exe") || !FileExist(CsxRoslynDir "\Microsoft.CodeAnalysis.CSharp.Scripting.dll")
        throw Error("Roslyn not found (" RoslynFrom "). CsxRoslynDir must be a folder containing csc.exe and Microsoft.CodeAnalysis.CSharp.Scripting.dll.", -1, CsxRoslynDir)
    ; (the host reads the packages' manifest from the environment: its C# runs before any script)
    EnvSet("CSX_IN_AHK_PACKAGES", CsxPackagesManifest)

    Source := _CsxHostSource()

    ; The host assembly is compiled once per host source / runtime / compiler version and cached (or built beforehand:
    ; CsxHostDll). Its runtimeconfig names the runtime found here (a file of its own for each runtime version, so that a
    ; program carried to another computer, with another .NET, still starts).
    Cache := CsxCacheDir != "" ? CsxCacheDir : A_Temp "\Csx-in-AHK"
    try DirCreate(Cache)
    if !InStr(FileExist(Cache), "D")
        Cache := A_Temp "\Csx-in-AHK"    ; (a folder that can't be written to: %TEMP% after all)
    if CsxHostDll != "" {
        Dll := CsxHostDll
        SplitPath(Dll, , , , &Name)
    } else {
        Key := Source "|" NetCore "|" CsxRoslynDir "|" FileGetVersion(CsxRoslynDir "\Microsoft.CodeAnalysis.CSharp.dll")
        Name := "CsxHost-" Format("{:08X}", DllCall("ntdll\RtlComputeCrc32", "uint", 0, "ptr", StrPtr(Key), "uint", StrLen(Key) * 2, "uint"))
        Dll := Cache "\" Name ".dll"
        if !FileExist(Dll)
            _CsxBuildHost(Source, Cache, Name, NetCore)
    }
    EnvSet("CSX_IN_AHK_CACHE", Cache)    ; (compiled scripts are kept there too)
    SplitPath(Desktop || NetCore, &Version)
    Config := Cache "\" Name "-" Version ".runtimeconfig.json"
    if !FileExist(Config) {
        Framework := Desktop ? "Microsoft.WindowsDesktop.App" : "Microsoft.NETCore.App"
        F := FileOpen(Config, "w", "UTF-8-RAW"), F.Write('{"runtimeOptions":{"framework":{"name":"' Framework '","version":"' Version '"}}}'), F.Close()
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

_CsxHostSource() {
    static Source := "
    (
    using System;
    using System.Collections;
    using System.Collections.Generic;
    using System.Globalization;
    using System.IO;
    using System.IO.Compression;
    using System.Linq;
    using System.Net.Http;
    using System.Reflection;
    using System.Runtime.InteropServices;
    using System.Runtime.Loader;
    using System.Security.Cryptography;
    using System.Text;
    using System.Text.RegularExpressions;
    using System.Threading;
    using System.Threading.Tasks;
    using System.Xml.Linq;
    using Microsoft.CodeAnalysis;
    using Microsoft.CodeAnalysis.CSharp;
    using Microsoft.CodeAnalysis.CSharp.Scripting;
    using Microsoft.CodeAnalysis.Emit;
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
        internal static readonly Dictionary<string, string> NativePaths = new(StringComparer.OrdinalIgnoreCase);

        [UnmanagedCallersOnly]
        public static int Init(char* roslynDir) {
            RoslynDir = new string(roslynDir);
            AssemblyLoadContext.Default.Resolving += (context, name) => {
                if (!RefPaths.TryGetValue(name.Name, out var path)) path = Path.Combine(RoslynDir, name.Name + ".dll");
                return File.Exists(path) ? context.LoadFromAssemblyPath(path) : null;
            };
            // Native DLLs of NuGet packages
            AssemblyLoadContext.Default.ResolvingUnmanagedDll += (assembly, name) =>
                NativePaths.TryGetValue(name.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) ? name[..^4] : name, out var path)
                    ? NativeLibrary.Load(path) : IntPtr.Zero;
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
            if (Environment.GetEnvironmentVariable("CSX_IN_AHK_PREBUILD") == "1") return "";    // (CsxPrebuild: compiled only)
            var output = new StringWriter();
            var writer = TextWriter.Synchronized(output);
            TextWriter oldOut = Console.Out, oldErr = Console.Error;
            Console.SetOut((mask & 1) != 0 ? writer : TextWriter.Null);
            Console.SetError((mask & 2) != 0 ? writer : TextWriter.Null);
            // The script's awaits resume on the thread pool, not on this thread, which is waiting for them: with a
            // SynchronizationContext here (Keysharp's WinForms one, or WPF's once a window was shown) they would deadlock.
            var oldContext = System.Threading.SynchronizationContext.Current;
            System.Threading.SynchronizationContext.SetSynchronizationContext(null);
            try {
                object result = run(new CsxGlobals { args = args }).GetAwaiter().GetResult();
                if (result != null) value = Format(result);
            } catch (Exception ex) {
                Console.Error.WriteLine("Unhandled exception. " + Regex.Replace(ex.ToString(),
                    @"\r?\n\s*(at (Microsoft\.CodeAnalysis\.|CsxHost\.|ScriptCompiler\.|System\.Reflection\.|System\.Runtime\.CompilerServices\.|System\.Threading\.Tasks\.)[^\r\n]*|--- End of stack trace[^\r\n]*)", ""));
            } finally {
                System.Threading.SynchronizationContext.SetSynchronizationContext(oldContext);
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
            var packages = new List<string>();
            source = DirectiveRx.Replace(source, m => {
                if (m.Groups[1].Success) packages.Add(Packages.Parse(m.Groups[1].Value, ','));
                else if (m.Groups[2].Value.Equals("package", StringComparison.OrdinalIgnoreCase)) packages.Add(Packages.Parse(m.Groups[3].Value, '@'));
                return "";
            });
            var refs = packages.Count > 0 ? Packages.Resolve(packages) : new List<string>();

            string key = dir + "\0" + file + "\0" + string.Join("\0", refs) + "\0" + source;
            if (cache.TryGetValue(key, out var cached) && cached.Files.All(f => File.Exists(f.Path) && File.GetLastWriteTimeUtc(f.Path) == f.Time))
                return cached.Run;
            var traceWatch = System.Diagnostics.Stopwatch.StartNew();

            // A program can carry its scripts compiled (CsxPrebuild): CSX_IN_AHK_CACHE\csx-prebuilt\Name-Hash.dll, the hash of
            // what doesn't depend on where the program is (the source, the script's file name, the references' names and
            // versions, the host's name), so that even its first start compiles nothing. Beside it, Name-Hash.deps names the
            // entry point, the #load-ed files (relative to the script's folder, with a hash of their contents) and the #r
            // references, which are only known once compiled: the copy is used only while those files are the same.
            string cacheDir = Environment.GetEnvironmentVariable("CSX_IN_AHK_CACHE");
            bool prebuild = Environment.GetEnvironmentVariable("CSX_IN_AHK_PREBUILD") == "1";
            string prebuiltBase = null, prebuiltName = null, diskBase = null, diskPrefix = null;
            if (!string.IsNullOrEmpty(cacheDir)) {
                prebuiltName = (file != null ? Path.GetFileNameWithoutExtension(file) : "inline") + "-";
                prebuiltBase = Path.Combine(cacheDir, "csx-prebuilt", prebuiltName + PortableHash(file, source, refs, packages));
                if (!prebuild && Load(prebuiltBase, dir, file) is Entry prebuilt) {
                    Trace("prebuilt", file, traceWatch);
                    return (cache[key] = prebuilt).Run;
                }
                // A script (from a file, or a string) is kept compiled on disk (CSX_IN_AHK_CACHE\csx-scripts), named after a
                // hash of its path (if any) and of everything compiled (source, references, runtime, compiler and host), so
                // that the next start loads it instead of compiling it again; one copy per script path, the older ones
                // removed (strings: kept).
                if (!prebuild) {
                    diskPrefix = file != null ? "script-" + Hash(file.ToLowerInvariant(), 8) + "-" : "inline-";
                    diskBase = Path.Combine(cacheDir, "csx-scripts", diskPrefix + Hash(key + "\0" + string.Join("\0", Imports)
                        + "\0" + RuntimeEnvironment.GetRuntimeDirectory() + "\0" + typeof(CSharpScript).Assembly.GetName().Version
                        + "\0" + typeof(CsxGlobals).Assembly.FullName
                        + "\0" + string.Join("\0", refs.Select(r => File.Exists(r) ? new FileInfo(r).Length + ":" + File.GetLastWriteTimeUtc(r).Ticks : "")), 8));
                    if (Load(diskBase, dir, file) is Entry stored) {
                        Trace("cached", file, traceWatch);
                        return (cache[key] = stored).Run;
                    }
                }
            }

            frameworkRefs ??=((string)AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES")).Split(Path.PathSeparator)
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

            // The script is compiled and emitted here (not with Script.CreateDelegate), so that the same assembly can be kept
            // on disk: its entry point is the submission's factory, called with the globals as Roslyn's own runner does.
            var script = CSharpScript.Create<object>(source, options, typeof(CsxGlobals));
            var compilation = script.GetCompilation();
            using var pe = new MemoryStream();
            using var pdb = new MemoryStream();
            var result = compilation.Emit(pe, pdb, options: new EmitOptions(debugInformationFormat: DebugInformationFormat.PortablePdb));
            var errors = result.Diagnostics.Where(d => d.Severity == DiagnosticSeverity.Error).ToList();
            if (!result.Success || errors.Count > 0)
                throw new Exception("C# compilation failed:\r\n" + string.Join("\r\n", errors));
            var directiveRefs = compilation.DirectiveReferences.OfType<PortableExecutableReference>()
                .Select(reference => reference.FilePath).Where(path => path != null).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            foreach (var path in directiveRefs) CsxHost.RefPaths[Path.GetFileNameWithoutExtension(path)] = path;

            var entryPoint = compilation.GetEntryPoint(CancellationToken.None);
            var type = entryPoint.ContainingType;
            string typeName = (type.ContainingNamespace.IsGlobalNamespace ? "" : type.ContainingNamespace.ToDisplayString() + ".") + type.MetadataName;
            var entry = MakeEntry(Assembly.Load(pe.ToArray(), pdb.ToArray()), typeName, entryPoint.MetadataName,
                compilation.SyntaxTrees.Select(t => t.FilePath).Where(File.Exists).Distinct(StringComparer.OrdinalIgnoreCase).ToList());

            if (diskBase != null || prebuild && prebuiltBase != null) {
                // The .deps file: the entry point, the #load-ed files with a hash of their contents, the #r references
                // (the runtime's own are found again anyway).
                var deps = new StringBuilder("entry|" + typeName + "|" + entryPoint.MetadataName + "\n");
                foreach (var path in compilation.SyntaxTrees.Select(t => t.FilePath)
                        .Where(path => !string.IsNullOrEmpty(path) && Path.IsPathRooted(path) && File.Exists(path)
                            && !string.Equals(Path.GetFullPath(path), file, StringComparison.OrdinalIgnoreCase))
                        .Distinct(StringComparer.OrdinalIgnoreCase))
                    deps.Append("load|").Append(Path.GetRelativePath(dir, path)).Append('|').Append(FileHash(path)).Append('\n');
                var runtime = Path.GetFullPath(RuntimeEnvironment.GetRuntimeDirectory());
                foreach (var path in directiveRefs.Where(path => !Path.GetFullPath(path).StartsWith(runtime, StringComparison.OrdinalIgnoreCase)))
                    deps.Append("ref|").Append(Path.GetRelativePath(dir, path)).Append('\n');
                if (diskBase != null)
                    try {
                        string folder = Path.GetDirectoryName(diskBase), tmp = diskBase + "." + Environment.ProcessId + ".tmp";
                        Directory.CreateDirectory(folder);
                        foreach (var old in file != null ? Directory.GetFiles(folder, diskPrefix + "*") : Array.Empty<string>())
                            try { File.Delete(old); } catch (Exception) { }    // (another instance may be loading it: left for later)
                        Save(diskBase, tmp, pe, pdb, deps.ToString());
                    } catch (Exception) { }    // (a cache that can't be written: compiled again next time)
                if (prebuild && prebuiltBase != null) {
                    string folder = Path.GetDirectoryName(prebuiltBase);
                    Directory.CreateDirectory(folder);
                    foreach (var old in file != null ? Directory.GetFiles(folder, prebuiltName + "*") : Array.Empty<string>()) File.Delete(old);
                    Save(prebuiltBase, prebuiltBase + "." + Environment.ProcessId + ".tmp", pe, pdb, deps.ToString());
                }
            }
            Trace("compile", file, traceWatch);
            cache[key] = entry;
            return entry.Run;
        }

        // The compiled script's runner: the submission's factory, given the globals in slot 0 of the submission array.
        static Entry MakeEntry(Assembly assembly, string typeName, string methodName, List<string> files) {
            var factory = assembly.GetType(typeName, true).GetMethod(methodName, BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic);
            return new Entry {
                Run = globals => (Task<object>)factory.Invoke(null, BindingFlags.DoNotWrapExceptions, null, new object[] { new object[] { globals, null } }, null),
                Files = files.Select(path => (path, File.GetLastWriteTimeUtc(path))).ToList()
            };
        }

        // A script compiled before (Base.dll, .pdb, .deps), if its #load-ed files are the same and its #r references are
        // there; else null (and it is compiled).
        static Entry Load(string b, string dir, string file) {
            try {
                if (!File.Exists(b + ".dll") || !File.Exists(b + ".deps")) return null;
                string typeName = null, methodName = null;
                var files = new List<string>();
                if (file != null) files.Add(file);
                var refPaths = new List<string>();
                foreach (var line in File.ReadAllLines(b + ".deps")) {
                    var parts = line.Split('|');
                    if (parts[0] == "entry" && parts.Length == 3) { typeName = parts[1]; methodName = parts[2]; }
                    else if (parts[0] == "load" && parts.Length == 3) {
                        string path = Path.GetFullPath(Path.Combine(dir, parts[1]));
                        if (!File.Exists(path) || FileHash(path) != parts[2]) return null;
                        files.Add(path);
                    } else if (parts[0] == "ref" && parts.Length == 2) {
                        string path = Path.GetFullPath(Path.Combine(dir, parts[1]));
                        if (!File.Exists(path)) return null;
                        refPaths.Add(path);
                    }
                }
                if (typeName == null) return null;
                foreach (var path in refPaths) CsxHost.RefPaths[Path.GetFileNameWithoutExtension(path)] = path;
                return MakeEntry(Assembly.Load(File.ReadAllBytes(b + ".dll"), File.Exists(b + ".pdb") ? File.ReadAllBytes(b + ".pdb") : null),
                    typeName, methodName, files);
            } catch (Exception) { return null; }    // (a damaged or outdated copy: compiled again)
        }

        static void Save(string b, string tmp, MemoryStream pe, MemoryStream pdb, string deps) {
            File.WriteAllText(tmp + "d", deps);
            File.Move(tmp + "d", b + ".deps", true);
            File.WriteAllBytes(tmp + "p", pdb.ToArray());
            File.Move(tmp + "p", b + ".pdb", true);
            File.WriteAllBytes(tmp, pe.ToArray());
            File.Move(tmp, b + ".dll", true);    // (the .dll last: it is what says the copy is complete)
        }

        static string PortableHash(string file, string source, List<string> refs, List<string> packages) {
            var key = new StringBuilder(string.Join(",", Imports)).Append('\0').Append(typeof(CsxGlobals).Assembly.GetName().Name)
                .Append('\0').Append(file != null ? Path.GetFileName(file).ToLowerInvariant() : "");
            foreach (var package in packages) key.Append('\0').Append(package);
            foreach (var reference in refs) {
                string version = "";
                try { version = AssemblyName.GetAssemblyName(reference).Version?.ToString(); } catch (Exception) { }
                key.Append('\0').Append(Path.GetFileName(reference).ToLowerInvariant()).Append(':').Append(version);
            }
            key.Append('\0').Append(source);
            return Hash(key.ToString(), 12);
        }

        static string Hash(string s, int bytes) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(s)), 0, bytes);
        static string FileHash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)), 0, 12);

        static void Trace(string what, string file, System.Diagnostics.Stopwatch watch) {
            if (Environment.GetEnvironmentVariable("CSHARP_IN_AHK_TRACE") is string trace && trace != "")
                try { File.AppendAllText(trace, $"csx {what} {file}: {watch.ElapsedMilliseconds} ms\r\n"); } catch (Exception) { }
        }
    }

    // NuGet package references, restored with the NuGet client libraries (downloaded once from nuget.org).
    // The client and the restore code run in their own AssemblyLoadContext, so that their dependencies
    // (e.g. Newtonsoft.Json) cannot clash with the packages a script uses.
    static class Packages {
        const string ClientVersion = "7.9.0";
        const string Feed = "https://api.nuget.org/v3-flatcontainer/";
        static readonly string Root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Csharp-in-AHK", "nuget");
        static readonly Dictionary<string, List<string>> resolved = new();
        static HashSet<string> framework;
        static MethodInfo restore;

        // "Name@1.2.3" or "Name, 1.2.3" -> "Name|1.2.3"
        public static string Parse(string spec, char separator) {
            int i = spec.IndexOf(separator);
            string name = (i < 0 ? spec : spec.Substring(0, i)).Trim(), version = i < 0 ? "" : spec.Substring(i + 1).Trim();
            return name + "|" + (version == "" ? "*" : version);
        }

        // Restores the packages with their dependencies and returns the assemblies to compile against. With a manifest
        // (CSX_IN_AHK_PACKAGES: PackagesManifest in Csharp-in-AHK.ini), its files instead: nothing is restored.
        public static List<string> Resolve(List<string> packages) {
            string manifest = Environment.GetEnvironmentVariable("CSX_IN_AHK_PACKAGES");
            if (!string.IsNullOrEmpty(manifest) && File.Exists(manifest)) {
                string from = Path.GetDirectoryName(Path.GetFullPath(manifest));
                return FromLines(File.ReadAllLines(manifest).Where(line => line.Contains('|')).Select(line => {
                    int bar = line.IndexOf('|');
                    return line.Substring(0, bar) + "|" + Path.GetFullPath(Path.Combine(from, line.Substring(bar + 1)));
                }).ToArray());
            }
            string tfm = "net" + Environment.Version.Major + ".0-windows7.0";    // what the SDK uses for -windows
            var list = packages.Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(p => p, StringComparer.OrdinalIgnoreCase).ToArray();
            string key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
                string.Join("\n", list) + "\n" + tfm + "\n" + ClientVersion + "\n" + RestorerSource))).Substring(0, 16);
            if (resolved.TryGetValue(key, out var refs)) return refs;

            string dir = Path.Combine(Root, "restore", key), file = Path.Combine(dir, "assets.txt");
            string[] lines;
            using (var mutex = new Mutex(false, @"Local\Csharp-in-AHK-NuGet")) {
                try { mutex.WaitOne(); } catch (AbandonedMutexException) { }
                try {
                    lines = Cached(file, list.Any(p => p.Contains('*')));
                    if (lines == null) {
                        try {
                            restore ??= LoadRestorer();
                            lines = (string[])restore.Invoke(null, BindingFlags.DoNotWrapExceptions, null, new object[] { dir, tfm, list }, null);
                            File.WriteAllLines(file + ".tmp", lines);
                            File.Move(file + ".tmp", file, true);
                        } catch (Exception) when ((lines = Cached(file, false)) != null) { }    // e.g. offline: use the last result
                    }
                } finally {
                    mutex.ReleaseMutex();
                }
            }

            return resolved[key] = FromLines(lines);
        }

        // The assemblies to compile against, from restore result lines (the runtime's and the native ones noted).
        static List<string> FromLines(string[] lines) {
            framework ??= new(((string)AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES")).Split(Path.PathSeparator)
                .Select(Path.GetFileNameWithoutExtension), StringComparer.OrdinalIgnoreCase);
            var refs = new List<string>();
            foreach (var line in lines) {
                int i = line.IndexOf('|');
                string kind = line.Substring(0, i), path = line.Substring(i + 1), name = Path.GetFileNameWithoutExtension(path);
                if (kind == "native") CsxHost.NativePaths[name] = path;
                else if (framework.Contains(name)) continue;    // the runtime's own version is used
                else if (kind == "compile") refs.Add(path);
                else if (kind == "runtime") CsxHost.RefPaths[name] = path;
            }
            return refs;
        }

        // The last restore result, unless it is missing files or (for versions with *) older than a day.
        static string[] Cached(string file, bool floating) {
            if (!File.Exists(file) || floating && File.GetLastWriteTimeUtc(file) < DateTime.UtcNow.AddDays(-1)) return null;
            var lines = File.ReadAllLines(file);
            return lines.All(line => File.Exists(line.Substring(line.IndexOf('|') + 1))) ? lines : null;
        }

        static MethodInfo LoadRestorer() {
            string client = Client();
            var context = new ClientLoadContext(client);
            var refs = ((string)AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES")).Split(Path.PathSeparator)
                .Concat(Directory.GetFiles(client, "*.dll")).Select(path => MetadataReference.CreateFromFile(path));
            var compilation = CSharpCompilation.Create("CsxNuGetRestorer",
                new[] { CSharpSyntaxTree.ParseText(RestorerSource, new CSharpParseOptions(LanguageVersion.Latest)) }, refs,
                new CSharpCompilationOptions(OutputKind.DynamicallyLinkedLibrary, optimizationLevel: OptimizationLevel.Release));
            using var pe = new MemoryStream();
            var result = compilation.Emit(pe);
            if (!result.Success)
                throw new Exception("Failed to compile the NuGet restorer:\r\n" + string.Join("\r\n",
                    result.Diagnostics.Where(d => d.Severity == DiagnosticSeverity.Error)));
            pe.Position = 0;
            return context.LoadFromStream(pe).GetType("Restorer").GetMethod("Restore");
        }

        // Downloads NuGet.Commands and its dependencies (lib folder for this .NET version) once.
        static string Client() {
            string dir = Path.Combine(Root, "client", ClientVersion);
            if (Directory.Exists(dir)) return dir;
            string temp = dir + ".tmp";
            if (Directory.Exists(temp)) Directory.Delete(temp, true);
            Directory.CreateDirectory(temp);
            var tpa = new HashSet<string>(((string)AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES")).Split(Path.PathSeparator)
                .Select(Path.GetFileNameWithoutExtension), StringComparer.OrdinalIgnoreCase);
            var versions = new Dictionary<string, Version>(StringComparer.OrdinalIgnoreCase);
            var pending = new Queue<(string Id, string Version)>();
            pending.Enqueue(("NuGet.Commands", ClientVersion));
            using var http = new HttpClient();
            try {
                while (pending.Count > 0) {
                    var (id, text) = pending.Dequeue();
                    var version = Version.Parse(text.Trim('[', '(', ' ').Split(',')[0]);
                    if (tpa.Contains(id) || versions.TryGetValue(id, out var have) && have >= version) continue;
                    versions[id] = version;
                    string lower = id.ToLowerInvariant(), v = version.Revision > 0 ? version.ToString() : $"{version.Major}.{version.Minor}.{Math.Max(version.Build, 0)}";
                    using var zip = new ZipArchive(new MemoryStream(http.GetByteArrayAsync($"{Feed}{lower}/{v}/{lower}.{v}.nupkg").GetAwaiter().GetResult()));
                    using (var stream = zip.Entries.First(e => e.FullName.EndsWith(".nuspec") && !e.FullName.Contains('/')).Open()) {
                        var nuspec = XDocument.Load(stream).Descendants().Where(e => e.Name.LocalName == "dependencies").FirstOrDefault();
                        var group = nuspec?.Elements().Where(e => e.Name.LocalName == "group")
                            .OrderByDescending(g => FrameworkScore((string)g.Attribute("targetFramework"))).FirstOrDefault(g => FrameworkScore((string)g.Attribute("targetFramework")) > 0);
                        foreach (var dependency in (group ?? nuspec)?.Elements().Where(e => e.Name.LocalName == "dependency") ?? Enumerable.Empty<XElement>())
                            pending.Enqueue(((string)dependency.Attribute("id"), (string)dependency.Attribute("version")));
                    }
                    var lib = zip.Entries.Where(e => e.FullName.StartsWith("lib/") && e.FullName.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
                        .GroupBy(e => e.FullName.Split('/')[1]).Where(g => FrameworkScore(g.Key) > 0)
                        .OrderByDescending(g => FrameworkScore(g.Key)).FirstOrDefault();
                    foreach (var entry in lib ?? Enumerable.Empty<ZipArchiveEntry>())
                        if (!tpa.Contains(Path.GetFileNameWithoutExtension(entry.Name)))
                            entry.ExtractToFile(Path.Combine(temp, entry.Name), true);
                }
            } catch (Exception ex) {
                throw new Exception("Failed to download the NuGet client from nuget.org: " + ex.Message, ex);
            }
            Directory.Move(temp, dir);
            return dir;
        }

        static int FrameworkScore(string tfm) {
            var m = Regex.Match((tfm ?? "").ToLowerInvariant().TrimStart('.'), @"^(netstandard|netcoreapp|net)(\d+)\.(\d+)");
            if (!m.Success) return 0;
            int major = int.Parse(m.Groups[2].Value), minor = int.Parse(m.Groups[3].Value);
            return m.Groups[1].Value switch {
                "net" when major >= 5 && major <= Environment.Version.Major => 1000 + major * 10 + minor,
                "netcoreapp" => 500 + major * 10 + minor,
                "netstandard" => 100 + major * 10 + minor,
                _ => 0
            };
        }

        // Compiled in memory against the NuGet client. Restore(dir, tfm, packages) returns "compile|path",
        // "runtime|path" and "native|path" lines for all packages in the graph.
        const string RestorerSource = """"
        using System;
        using System.Collections.Generic;
        using System.Collections.Immutable;
        using System.IO;
        using System.Linq;
        using System.Threading.Tasks;
        using NuGet.Commands;
        using NuGet.Common;
        using NuGet.Configuration;
        using NuGet.Credentials;
        using NuGet.Frameworks;
        using NuGet.LibraryModel;
        using NuGet.ProjectModel;
        using NuGet.Protocol;
        using NuGet.Protocol.Core.Types;
        using NuGet.RuntimeModel;
        using NuGet.Versioning;

        public static class Restorer {
            const string Rid = "win-x64";

            // packages: "Id|VersionRange"
            public static string[] Restore(string dir, string tfm, string[] packages) =>
                Task.Run(() => RestoreAsync(dir, tfm, packages)).GetAwaiter().GetResult();

            static async Task<string[]> RestoreAsync(string dir, string tfm, string[] packages) {
                Directory.CreateDirectory(dir);
                var log = new ErrorLog();
                var settings = Settings.LoadDefaultSettings(dir);
                DefaultCredentialServiceUtility.SetupDefaultCredentialService(log, nonInteractive: true);
                var framework = NuGetFramework.Parse(tfm);
                string project = Path.Combine(dir, "packages.csproj"), graphFile = Path.Combine(dir, "runtime.json");
                // RID fallbacks, so that runtimes/win/... assets are found for win-x64
                JsonRuntimeFormat.WriteRuntimeGraph(graphFile, new RuntimeGraph(new[] {
                    new RuntimeDescription("base"),
                    new RuntimeDescription("any", new[] { "base" }),
                    new RuntimeDescription("win", new[] { "any" }),
                    new RuntimeDescription(Rid, new[] { "win" }) }));

                var dependencies = packages.Select(p => p.Split('|')).Select(p => new LibraryDependency {
                    LibraryRange = new LibraryRange(p[0], VersionRange.Parse(p[1]), LibraryDependencyTarget.Package)
                }).ToImmutableArray();
                var sourceProvider = new PackageSourceProvider(settings);
                // No source enabled (a NuGet.Config with none, or only offline ones): nuget.org, as on a computer that
                // never configured one. Without it only the packages already downloaded are found (NU1100).
                var sources = sourceProvider.LoadPackageSources().Where(s => s.IsEnabled).ToList();
                if (sources.Count == 0) sources.Add(new PackageSource("https://api.nuget.org/v3/index.json", "nuget.org"));
                var spec = new PackageSpec(new[] { new TargetFrameworkInformation {
                    FrameworkName = framework, TargetAlias = tfm, Dependencies = dependencies, RuntimeIdentifierGraphPath = graphFile } }) {
                    Name = "packages",
                    FilePath = project,
                    RuntimeGraph = new RuntimeGraph(new[] { new RuntimeDescription(Rid) }),
                    RestoreMetadata = new ProjectRestoreMetadata {
                        ProjectStyle = ProjectStyle.PackageReference,
                        ProjectPath = project,
                        ProjectName = "packages",
                        ProjectUniqueName = project,
                        OutputPath = dir,
                        PackagesPath = SettingsUtility.GetGlobalPackagesFolder(settings),
                        Sources = sources,
                        FallbackFolders = SettingsUtility.GetFallbackPackageFolders(settings).ToList(),
                        ConfigFilePaths = settings.GetConfigFilePaths().ToList(),
                        OriginalTargetFrameworks = new List<string> { tfm },
                        TargetFrameworks = new List<ProjectRestoreMetadataFrameworkInfo> { new(framework) { TargetAlias = tfm } }
                    }
                };
                var graph = new DependencyGraphSpec();
                graph.AddProject(spec);
                graph.AddRestore(project);

                using var cache = new SourceCacheContext();
                var args = new RestoreArgs {
                    CacheContext = cache,
                    CachingSourceProvider = new CachingSourceProvider(sourceProvider),
                    Log = log,
                    AllowNoOp = false
                };
                args.PreLoadedRequestProviders.Add(new DependencyGraphSpecRequestProvider(new RestoreCommandProvidersCache(), graph, settings));
                var requests = await RestoreRunner.GetRequests(args);
                var result = (await RestoreRunner.RunWithoutCommit(requests, args)).Single().Result;
                if (!result.Success)
                    throw new Exception("NuGet restore failed:\r\n" + string.Join("\r\n", log.Errors.Distinct()) +
                        "\r\nPackage sources: " + string.Join(", ", sources.Select(s => s.Source)) + " (NuGet.Config: " + string.Join(", ", settings.GetConfigFilePaths()) + ")");

                var lockFile = result.LockFile;
                var target = lockFile.Targets.First(t => t.RuntimeIdentifier == Rid);
                var folders = lockFile.PackageFolders.Select(f => f.Path).Append(spec.RestoreMetadata.PackagesPath).ToList();
                var lines = new List<string>();
                foreach (var library in target.Libraries.Where(l => l.Type == "package")) {
                    var package = lockFile.GetLibrary(library.Name, library.Version);
                    string root = folders.Select(f => Path.Combine(f, package.Path)).First(Directory.Exists);
                    void Add(string kind, IEnumerable<LockFileItem> items) {
                        foreach (var item in items)
                            if (!item.Path.EndsWith("_._")) lines.Add(kind + "|" + Path.GetFullPath(Path.Combine(root, item.Path)));
                    }
                    Add("compile", library.CompileTimeAssemblies);
                    Add("runtime", library.RuntimeAssemblies);
                    Add("native", library.NativeLibraries);
                }
                return lines.ToArray();
            }

            class ErrorLog : LoggerBase {
                public readonly List<string> Errors = new();
                public override void Log(ILogMessage message) {
                    if (message.Level >= LogLevel.Error) lock (Errors) Errors.Add(message.FormatWithCode());
                }
                public override Task LogAsync(ILogMessage message) {
                    Log(message);
                    return Task.CompletedTask;
                }
            }
        }
        """";
    }

    // Loads the NuGet client assemblies from their own folder; framework assemblies come from the runtime.
    class ClientLoadContext : AssemblyLoadContext {
        readonly string dir;
        public ClientLoadContext(string dir) : base("Csharp-in-AHK NuGet client") { this.dir = dir; }
        protected override Assembly Load(AssemblyName name) {
            string path = Path.Combine(dir, name.Name + ".dll");
            return File.Exists(path) ? LoadFromAssemblyPath(path) : null;
        }
    }
    )"
    return Source
}

_CsxBuildHost(Source, Cache, Name, NetCore) {
    global CsxRoslynDir
    DirCreate(Cache)
    Base := Cache "\" Name
    F := FileOpen(Base ".cs", "w", "UTF-8"), F.Write(Source), F.Close()
    Rsp := '-nologo -noconfig -nostdlib -target:library -unsafe -optimize -langversion:latest -out:"' Base '.dll"`n'
    Loop Files NetCore "\*.dll"
        if _CsxIsManaged(A_LoopFileFullPath)
            Rsp .= '-r:"' A_LoopFileFullPath '"`n'
    for Ref in ["Microsoft.CodeAnalysis", "Microsoft.CodeAnalysis.CSharp", "Microsoft.CodeAnalysis.Scripting", "Microsoft.CodeAnalysis.CSharp.Scripting"]
        Rsp .= '-r:"' CsxRoslynDir '\' Ref '.dll"`n'
    Rsp .= '"' Base '.cs"'
    F := FileOpen(Base ".rsp", "w", "UTF-8"), F.Write(Rsp), F.Close()
    if RunWait(A_ComSpec ' /c ""' CsxRoslynDir '\csc.exe" @"' Base '.rsp" > "' Base '.log" 2>&1"', , "Hide") || !FileExist(Base ".dll") {
        try FileDelete(Base ".dll")
        throw Error("Failed to compile the C# script host", -2, FileExist(Base ".log") ? FileRead(Base ".log") : "")
    }
}

; Builds the script host assembly into a folder (as OutDir\Name.dll), with the .NET and compiler that would be used now:
; for a program that carries everything (CsxHostDll in Csharp-in-AHK.ini). Returns its path.
CsxBuildHost(OutDir, Name := "CsxHost") {
    global CsxDotnetRoot, CsxRoslynDir
    _CsxFindPaths(&DotnetFrom, &RoslynFrom)
    NetCore := _CsxLatestDir(CsxDotnetRoot "\shared\Microsoft.NETCore.App")
    if !NetCore || !FileExist(CsxRoslynDir "\csc.exe")
        throw Error("Building the script host needs .NET (" DotnetFrom ") and csc.exe (" RoslynFrom ").", -1)
    _CsxBuildHost(_CsxHostSource(), OutDir, Name, NetCore)
    for Extension in [".cs", ".rsp", ".log"]
        try FileDelete(OutDir "\" Name Extension)
    return OutDir "\" Name ".dll"
}

; Compiles a script (a file, or a string as for RunCsx) without running it, into CacheDir\csx-prebuilt (see
; Csharp-in-AHK.ini), for a program that carries its scripts compiled: they are loaded from there, wherever the program
; is, as long as their sources (and the files they #load) are the same.
CsxPrebuild(Script) {
    EnvSet("CSX_IN_AHK_PREBUILD", "1")
    try RunCsx(Script)
    finally EnvSet("CSX_IN_AHK_PREBUILD")
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

; Fills in CsxDotnetRoot and CsxRoslynDir if the script left them empty, and reports where each one came from.
_CsxFindPaths(&DotnetFrom, &RoslynFrom) {
    global CsxDotnetRoot, CsxRoslynDir
    SplitPath(A_LineFile, , &Dir)
    Ini := Dir "\Csharp-in-AHK.ini"
    DotnetFrom := "set by the script", RoslynFrom := "set by the script"
    if CsxDotnetRoot = "" && (CsxDotnetRoot := EnvGet("CSHARP_IN_AHK_DOTNET")) != ""
        DotnetFrom := "from CSHARP_IN_AHK_DOTNET"
    if CsxDotnetRoot = "" && (CsxDotnetRoot := IniRead(Ini, "Paths", "DotnetRoot", "")) != ""
        DotnetFrom := "from " Ini
    if CsxDotnetRoot = ""
        CsxDotnetRoot := _CsxDetectDotnet(), DotnetFrom := "auto-detection"
    if CsxRoslynDir = "" && (CsxRoslynDir := EnvGet("CSHARP_IN_AHK_ROSLYN")) != ""
        RoslynFrom := "from CSHARP_IN_AHK_ROSLYN"
    if CsxRoslynDir = "" && (CsxRoslynDir := IniRead(Ini, "Paths", "RoslynDir", "")) != ""
        RoslynFrom := "from " Ini
    if CsxRoslynDir = ""
        CsxRoslynDir := _CsxDetectRoslyn(), RoslynFrom := "auto-detection"
    if CsxRoslynDir = ""
        try CsxRoslynDir := _CsxDownloadRoslyn(), RoslynFrom := "downloaded from nuget.org"
        catch as e
            RoslynFrom := "auto-detection found nothing and the download failed: " e.Message
    global CsxHostDll, CsxPackagesManifest, CsxCacheDir
    if CsxHostDll = ""
        CsxHostDll := IniRead(Ini, "Paths", "CsxHostDll", "")
    if CsxPackagesManifest = ""
        CsxPackagesManifest := IniRead(Ini, "Paths", "PackagesManifest", "")
    if CsxCacheDir = ""
        CsxCacheDir := IniRead(Ini, "Paths", "CacheDir", "")
    ; (relative paths: from the .ini's folder)
    Full(Path) => Path = "" || Path ~= "^(\\\\|[A-Za-z]:)" ? Path : Dir "\" Path
    CsxDotnetRoot := RTrim(Full(CsxDotnetRoot), "\"), CsxRoslynDir := RTrim(Full(CsxRoslynDir), "\")
    CsxHostDll := Full(CsxHostDll), CsxPackagesManifest := Full(CsxPackagesManifest), CsxCacheDir := RTrim(Full(CsxCacheDir), "\")
}

_CsxDetectDotnet() {
    for Dir in [EnvGet("DOTNET_ROOT"), RegRead("HKLM\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x64", "InstallLocation", ""), EnvGet("ProgramFiles") "\dotnet"] {
        Dir := RTrim(Dir, "\")
        if _CsxIsDotnetRoot(Dir)
            return Dir
    }
    for Install in _CsxVsInstalls()
        Loop Files Install "\dotnet\net*", "D"
            if _CsxIsDotnetRoot(A_LoopFileFullPath "\runtime")
                return A_LoopFileFullPath "\runtime"
    return ""
}

_CsxIsDotnetRoot(Dir) {
    if Dir = "" || !FileExist(Dir "\host\fxr")
        return false
    NetCore := _CsxLatestDir(Dir "\shared\Microsoft.NETCore.App")
    SplitPath(NetCore, &Version)
    return NetCore != "" && VerCompare(Version, "8.0.0") >= 0 && FileExist(_CsxLatestDir(Dir "\host\fxr") "\hostfxr.dll")
}

_CsxDetectRoslyn() {
    for Install in _CsxVsInstalls()
        if FileExist(Install "\MSBuild\Current\Bin\Roslyn\csc.exe") && FileExist(Install "\MSBuild\Current\Bin\Roslyn\Microsoft.CodeAnalysis.CSharp.Scripting.dll")
            return Install "\MSBuild\Current\Bin\Roslyn"
    Dir := _CsxRoslynDownloadDir()
    return FileExist(Dir "\csc.exe") && FileExist(Dir "\Microsoft.CodeAnalysis.CSharp.Scripting.dll") ? Dir : ""
}

; Where _CsxDownloadRoslyn puts the compiler (Csharp-in-AHK.ahk uses the same folder).
_CsxRoslynDownloadDir() => EnvGet("LOCALAPPDATA") "\Csharp-in-AHK\roslyn\5.9.0\tasks\net472"

; Downloads Microsoft.Net.Compilers.Toolset from nuget.org and extracts its tasks\net472 folder (csc.exe and the
; Roslyn DLLs, including the scripting ones). A .nupkg is a zip file, which Windows' tar.exe can extract.
_CsxDownloadRoslyn() {
    Dir := _CsxRoslynDownloadDir()
    if FileExist(Dir "\csc.exe")
        return Dir
    Version := "5.9.0", Root := EnvGet("LOCALAPPDATA") "\Csharp-in-AHK\roslyn"
    Temp := Root "\" Version "-" DllCall("GetCurrentProcessId") ".tmp", Pkg := Temp ".nupkg"
    DirCreate(Root)
    try DirDelete(Temp, true)
    DirCreate(Temp)
    try {
        Download("https://api.nuget.org/v3-flatcontainer/microsoft.net.compilers.toolset/" Version "/microsoft.net.compilers.toolset." Version ".nupkg", Pkg)
        RunWait('"' A_WinDir '\System32\tar.exe" -xf "' Pkg '" -C "' Temp '" tasks/net472', , "Hide")
        if !FileExist(Temp "\tasks\net472\csc.exe") || !FileExist(Temp "\tasks\net472\Microsoft.CodeAnalysis.CSharp.Scripting.dll")
            throw Error("the package could not be extracted")
        try DirMove(Temp, Root "\" Version)    ; fails if another process finished first, which is fine
    } finally {
        try FileDelete(Pkg)
        try DirDelete(Temp, true)
    }
    if !FileExist(Dir "\csc.exe")
        throw Error("the compiler could not be saved in " Root)
    return Dir
}

; Visual Studio and Build Tools install folders, newest first.
_CsxVsInstalls() {
    static Installs := ""
    if IsObject(Installs)
        return Installs
    Installs := []
    VsWhere := EnvGet("ProgramFiles(x86)") "\Microsoft Visual Studio\Installer\vswhere.exe"
    if FileExist(VsWhere) {
        Out := A_Temp "\vswhere-" DllCall("GetCurrentProcessId") ".txt"
        RunWait(A_ComSpec ' /c ""' VsWhere '" -all -prerelease -products * -sort -utf8 -property installationPath > "' Out '""', , "Hide")
        if FileExist(Out) {
            Loop Parse FileRead(Out, "UTF-8"), "`n", "`r"
                if A_LoopField != ""
                    Installs.Push(A_LoopField)
            FileDelete(Out)
        }
    }
    if !Installs.Length    ; No vswhere: look in the default install folders
        for Root in [EnvGet("ProgramFiles"), EnvGet("ProgramFiles(x86)")]
            Loop Files Root "\Microsoft Visual Studio\*", "D"
                Loop Files A_LoopFileFullPath "\*", "D"
                    Installs.Push(A_LoopFileFullPath)
    return Installs
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
