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
;   - #:package Name@1.2.3     references a NuGet package and its dependencies (#r "nuget: Name, 1.2.3" also works).
;                              Missing packages are downloaded (see NUGET below).
;   - #r "path\to\Some.dll"    references an assembly
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
; NUGET: package references are restored like `dotnet run app.cs` does, with the NuGet client libraries
;   (NuGet.Commands), which are downloaded once from nuget.org into %LOCALAPPDATA%\Csharp-in-AHK\nuget\client.
;   - Packages and their dependencies go to the global NuGet folder (~\.nuget\packages); nuget.config sources and
;     credentials are used. Native DLLs (runtimes\win-x64\native) are found too.
;   - Versions follow NuGet: 1.2.3 means 1.2.3 or the lowest version above it, * is the newest stable version,
;     1.* the newest 1.x, [1.0,2.0) a range. Without a version, * is used.
;   - The resolved files are cached in %LOCALAPPDATA%\Csharp-in-AHK\nuget\restore, so later runs do not restore again.
;     Versions with * are checked for updates once a day; if that fails (e.g. offline), the last result is used.
;
; Credits:
;   Idea, but no code, from Powershell-in-AHK.ahk
;   NuGet support modeled on the NuGet package provider of Keysharp (no code taken).
;   CLR/.NET interop based on concepts and techniques from CLR.ahk by Lexikos:
;   Developed with AI assistance.

global CSStreams := 3       ; Bitmask: 1=Console.Out 2=Console.Error
global CSExitCode := 0      ; Exit code of the last script (its int return value, or the HRESULT of an unhandled exception)
global CSOutput := ""       ; Console output of the last script

; PATHS: CSDotnetRoot and CSRoslynDir are found automatically the first time a script runs.
; The first setting found wins (Csx-in-AHK.ahk reads the same environment variables and .ini file):
;   1. CSDotnetRoot / CSRoslynDir set by your script (before or after #Include, before the first RunCSharp call).
;   2. The environment variables CSHARP_IN_AHK_DOTNET / CSHARP_IN_AHK_ROSLYN.
;   3. Csharp-in-AHK.ini next to this file, section [Paths], keys DotnetRoot / RoslynDir (see Csharp-in-AHK.example.ini).
;   4. Auto-detection. .NET: DOTNET_ROOT, the registered x64 .NET install, %ProgramFiles%\dotnet, then the runtime
;      bundled with Visual Studio. Roslyn: Visual Studio / Build Tools installs, newest first (found with vswhere.exe),
;      then a compiler downloaded earlier by step 5.
;   5. Roslyn only: if nothing was found, Microsoft's compiler package Microsoft.Net.Compilers.Toolset is downloaded
;      once from nuget.org into %LOCALAPPDATA%\Csharp-in-AHK\roslyn (about 22 MB) and its tasks\net472 folder is used.
;   A path set in steps 1-3 is never replaced by auto-detection or a download: if it is wrong, you get an error.
;   CSDotnetRoot must contain:
;     host\fxr\<version>\hostfxr.dll
;     shared\Microsoft.NETCore.App\<version>\           (.NET 8 or later)
;     shared\Microsoft.WindowsDesktop.App\<version>\    (optional, needed for WinForms/WPF)
;   CSRoslynDir must contain:
;     csc.exe                                    (compiles the embedded host once)
;     Microsoft.CodeAnalysis.dll
;     Microsoft.CodeAnalysis.CSharp.dll
;   A standalone .NET install (e.g. C:\Program Files\dotnet) also works as CSDotnetRoot.
global CSDotnetRoot := IsSet(CSDotnetRoot) ? CSDotnetRoot : ""
global CSRoslynDir := IsSet(CSRoslynDir) ? CSRoslynDir : ""

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
        Offset += StrPut(String(Arg), Argv.Ptr + Offset, "UTF-16")    ; StrPut returns bytes written
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
    _CSharpFindPaths(&DotnetFrom, &RoslynFrom)
    NetCore := _CSharpLatestDir(CSDotnetRoot "\shared\Microsoft.NETCore.App")
    Desktop := _CSharpLatestDir(CSDotnetRoot "\shared\Microsoft.WindowsDesktop.App")
    Fxr := _CSharpLatestDir(CSDotnetRoot "\host\fxr") "\hostfxr.dll"
    if !NetCore || !FileExist(Fxr)
        throw Error(".NET 8 or later not found (" DotnetFrom "). CSDotnetRoot must be a folder containing host\fxr and shared\Microsoft.NETCore.App.", -1, CSDotnetRoot)
    if !FileExist(CSRoslynDir "\csc.exe") || !FileExist(CSRoslynDir "\Microsoft.CodeAnalysis.CSharp.dll")
        throw Error("Roslyn not found (" RoslynFrom "). CSRoslynDir must be a folder containing csc.exe and Microsoft.CodeAnalysis.CSharp.dll.", -1, CSRoslynDir)

    Source := "
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
    using Microsoft.CodeAnalysis.Emit;

    // Entry points called from AHK. This class must not reference Roslyn types, so that the
    // assembly resolver is registered before Roslyn is loaded.
    public static unsafe class CSHost {
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
            var packages = new List<string>();
            var loaded = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (file != null) {
                file = Path.GetFullPath(file);
                source ??= File.ReadAllText(file);
                loaded.Add(file);
            }
            AddSource(source ?? "", file, trees, refs, packages, loaded);
            if (packages.Count > 0) refs.AddRange(Packages.Resolve(packages));

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
        static void AddSource(string text, string path, List<(string, string)> trees, List<string> refs, List<string> packages, HashSet<string> loaded) {
            string dir = path != null ? Path.GetDirectoryName(path) : Environment.CurrentDirectory;
            var loads = new List<string>();
            text = DirectiveRx.Replace(text, m => {
                string kind = m.Groups[1].Success ? m.Groups[1].Value : m.Groups[3].Value;
                if (kind == "r" && m.Groups[2].Value.StartsWith("nuget:", StringComparison.OrdinalIgnoreCase))
                    packages.Add(Packages.Parse(m.Groups[2].Value.Substring(6), ','));
                else if (kind == "r") refs.Add(Reference(m.Groups[2].Value, dir));
                else if (kind == "load") loads.Add(Path.GetFullPath(Path.Combine(dir, m.Groups[2].Value)));
                else if (kind == "package") packages.Add(Packages.Parse(m.Groups[4].Value, '@'));
                return "";
            });
            trees.Add((text, path ?? "script.cs"));
            foreach (var load in loads)
                if (loaded.Add(load)) AddSource(File.ReadAllText(load), load, trees, refs, packages, loaded);
        }

        static string Reference(string reference, string dir) {
            string path = Path.GetFullPath(Path.Combine(dir, reference));
            if (!File.Exists(path)) throw new FileNotFoundException("Referenced assembly not found: " + path);
            CSHost.RefPaths[Path.GetFileNameWithoutExtension(path)] = path;
            return path;
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

        // Restores the packages with their dependencies and returns the assemblies to compile against.
        public static List<string> Resolve(List<string> packages) {
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

            framework ??= new(((string)AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES")).Split(Path.PathSeparator)
                .Select(Path.GetFileNameWithoutExtension), StringComparer.OrdinalIgnoreCase);
            refs = new List<string>();
            foreach (var line in lines) {
                int i = line.IndexOf('|');
                string kind = line.Substring(0, i), path = line.Substring(i + 1), name = Path.GetFileNameWithoutExtension(path);
                if (kind == "native") CSHost.NativePaths[name] = path;
                else if (framework.Contains(name)) continue;    // the runtime's own version is used
                else if (kind == "compile") refs.Add(path);
                else if (kind == "runtime") CSHost.RefPaths[name] = path;
            }
            return resolved[key] = refs;
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
            var compilation = CSharpCompilation.Create("CSharpNuGetRestorer",
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
                        Sources = sourceProvider.LoadPackageSources().Where(s => s.IsEnabled).ToList(),
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
                    throw new Exception("NuGet restore failed:\r\n" + string.Join("\r\n", log.Errors.Distinct()));

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
        F := FileOpen(Config, "w", "UTF-8-RAW"), F.Write('{"runtimeOptions":{"framework":{"name":"' Framework '","version":"' Version '"}}}'), F.Close()
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
    F := FileOpen(Base ".cs", "w", "UTF-8"), F.Write(Source), F.Close()
    Rsp := '-nologo -noconfig -nostdlib -target:library -unsafe -optimize -langversion:latest -out:"' Base '.dll"`n'
    Loop Files NetCore "\*.dll"
        if _CSharpIsManaged(A_LoopFileFullPath)
            Rsp .= '-r:"' A_LoopFileFullPath '"`n'
    Rsp .= '-r:"' CSRoslynDir '\Microsoft.CodeAnalysis.dll"`n-r:"' CSRoslynDir '\Microsoft.CodeAnalysis.CSharp.dll"`n"' Base '.cs"'
    F := FileOpen(Base ".rsp", "w", "UTF-8"), F.Write(Rsp), F.Close()
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

; Fills in CSDotnetRoot and CSRoslynDir if the script left them empty, and reports where each one came from.
_CSharpFindPaths(&DotnetFrom, &RoslynFrom) {
    global CSDotnetRoot, CSRoslynDir
    SplitPath(A_LineFile, , &Dir)
    Ini := Dir "\Csharp-in-AHK.ini"
    DotnetFrom := "set by the script", RoslynFrom := "set by the script"
    if CSDotnetRoot = "" && (CSDotnetRoot := EnvGet("CSHARP_IN_AHK_DOTNET")) != ""
        DotnetFrom := "from CSHARP_IN_AHK_DOTNET"
    if CSDotnetRoot = "" && (CSDotnetRoot := IniRead(Ini, "Paths", "DotnetRoot", "")) != ""
        DotnetFrom := "from " Ini
    if CSDotnetRoot = ""
        CSDotnetRoot := _CSharpDetectDotnet(), DotnetFrom := "auto-detection"
    if CSRoslynDir = "" && (CSRoslynDir := EnvGet("CSHARP_IN_AHK_ROSLYN")) != ""
        RoslynFrom := "from CSHARP_IN_AHK_ROSLYN"
    if CSRoslynDir = "" && (CSRoslynDir := IniRead(Ini, "Paths", "RoslynDir", "")) != ""
        RoslynFrom := "from " Ini
    if CSRoslynDir = ""
        CSRoslynDir := _CSharpDetectRoslyn(), RoslynFrom := "auto-detection"
    if CSRoslynDir = ""
        try CSRoslynDir := _CSharpDownloadRoslyn(), RoslynFrom := "downloaded from nuget.org"
        catch as e
            RoslynFrom := "auto-detection found nothing and the download failed: " e.Message
    CSDotnetRoot := RTrim(CSDotnetRoot, "\"), CSRoslynDir := RTrim(CSRoslynDir, "\")
}

_CSharpDetectDotnet() {
    for Dir in [EnvGet("DOTNET_ROOT"), RegRead("HKLM\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x64", "InstallLocation", ""), EnvGet("ProgramFiles") "\dotnet"] {
        Dir := RTrim(Dir, "\")
        if _CSharpIsDotnetRoot(Dir)
            return Dir
    }
    for Install in _CSharpVsInstalls()
        Loop Files Install "\dotnet\net*", "D"
            if _CSharpIsDotnetRoot(A_LoopFileFullPath "\runtime")
                return A_LoopFileFullPath "\runtime"
    return ""
}

_CSharpIsDotnetRoot(Dir) {
    if Dir = "" || !FileExist(Dir "\host\fxr")
        return false
    NetCore := _CSharpLatestDir(Dir "\shared\Microsoft.NETCore.App")
    SplitPath(NetCore, &Version)
    return NetCore != "" && VerCompare(Version, "8.0.0") >= 0 && FileExist(_CSharpLatestDir(Dir "\host\fxr") "\hostfxr.dll")
}

_CSharpDetectRoslyn() {
    for Install in _CSharpVsInstalls()
        if FileExist(Install "\MSBuild\Current\Bin\Roslyn\csc.exe") && FileExist(Install "\MSBuild\Current\Bin\Roslyn\Microsoft.CodeAnalysis.CSharp.dll")
            return Install "\MSBuild\Current\Bin\Roslyn"
    Dir := _CSharpRoslynDownloadDir()
    return FileExist(Dir "\csc.exe") && FileExist(Dir "\Microsoft.CodeAnalysis.CSharp.dll") ? Dir : ""
}

; Where _CSharpDownloadRoslyn puts the compiler (Csx-in-AHK.ahk uses the same folder).
_CSharpRoslynDownloadDir() => EnvGet("LOCALAPPDATA") "\Csharp-in-AHK\roslyn\5.9.0\tasks\net472"

; Downloads Microsoft.Net.Compilers.Toolset from nuget.org and extracts its tasks\net472 folder (csc.exe and the
; Roslyn DLLs, including the scripting ones). A .nupkg is a zip file, which Windows' tar.exe can extract.
_CSharpDownloadRoslyn() {
    Dir := _CSharpRoslynDownloadDir()
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
_CSharpVsInstalls() {
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
