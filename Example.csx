// Example C# script for Csx-in-AHK. Run it with: MsgBox RunCsx("Example.csx", "AutoHotkey")
#load "ExampleHelpers.csx"

var name = args.Length > 0 ? args[0] : "world";
Console.WriteLine($"Greeting {name}...");   // goes to CsxOutput

var info = new SystemInfo();
return $"""
    {Greet(name)}
    Machine: {info.Machine}
    .NET:    {info.Runtime}
    Uptime:  {info.Uptime:hh\:mm\:ss}
    """;
