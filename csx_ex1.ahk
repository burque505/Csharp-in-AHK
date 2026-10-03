#Requires AutoHotkey v2.0 64-bit
#Include "Csx-in-AHK.ahk"
SetWorkingDir(A_ScriptDir)
; Examples:

; Return a string
MsgBox RunCsx('return "Hello from C# on .NET " + Environment.Version;')

; A final expression without ';' is returned too
MsgBox RunCsx('DateTime.Now.ToString("dddd, d MMMM yyyy")')

; Numbers come back as text that AHK can use in calculations (always with a '.' decimal point)
Area := RunCsx('Math.PI * Math.Pow(double.Parse(args[0]), 2)', 3)
MsgBox "Area: " Round(Area, 2)

; Booleans come back as 1/0
if RunCsx('File.Exists(@"C:\Windows\notepad.exe")')
    MsgBox "Notepad exists"

; Collections come back as one item per line
for Exe in StrSplit(RunCsx('Directory.GetFiles(@"C:\Windows", "*.exe").Select(Path.GetFileName).Take(5)'), "`n")
    MsgBox "Item " A_Index ": " Exe

; Functions, classes and await at the top level
MsgBox RunCsx('
(
    record Person(string Name, int Age);
    int Twice(int x) => x * 2;

    await Task.Delay(10);
    var people = new[] { new Person("Ann", 34), new Person("Bob", 27) };
    return string.Join(", ", people.Select(p => $"{p.Name} ({Twice(p.Age)})"));
)')

; When nothing is returned, RunCsx returns the console output
MsgBox RunCsx('Console.WriteLine("Success"); Console.Error.WriteLine("Error"); throw new Exception("Boom");')

; Run a script file (which #loads a helper file); its console output is in CsxOutput
MsgBox RunCsx(A_ScriptDir "\Example.csx", "AutoHotkey") "`n`nConsole output: " CsxOutput

; Compilation errors are thrown as AHK errors (this example contains a deliberate mistake)
try RunCsx('int x = "text";')
catch Error as e
    MsgBox "Expected error (this example deliberately assigns text to an int):`n`n" e.Message, "Compile error demo", "Icon!"
