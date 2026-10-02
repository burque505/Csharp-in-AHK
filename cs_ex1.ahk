#Requires AutoHotkey v2.0 64-bit
#Include "Csharp-in-AHK.ahk"
; Examples:
MsgBox RunCSharp('Console.WriteLine(DateTime.Now);')
MsgBox RunCSharp('Console.WriteLine($"Hello from C# on .NET {Environment.Version}");')
MsgBox RunCSharp('foreach (var p in System.Diagnostics.Process.GetProcesses().Take(5)) Console.WriteLine(p.ProcessName);')
MsgBox RunCSharp('Console.WriteLine("Success"); Console.Error.WriteLine("Error"); throw new Exception("Boom");')
MsgBox RunCSharp('Console.WriteLine(string.Join(", ", args)); return args.Length;', "first", "second") "`nExit code: " CSExitCode
MsgBox RunCSharp('Console.WriteLine("Computing..."); AHK.Return(Math.Sqrt(2));') "`nConsole output: " CSOutput
