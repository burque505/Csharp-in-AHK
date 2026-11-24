#Requires AutoHotkey v2
#Include "Csharp-in-AHK.ahk"
#SingleInstance
Persistent

Result := RunCSharpFile(A_ScriptDir "\tgui2.cs")    ; (tgui2.cs has a //#console line; CSConsole := true would do the same)
if CSExitCode
    MsgBox(CSOutput, "tgui2.cs failed", "Iconx")
else
    MsgBox(Result, "tgui2.cs")

MsgBox("Done")
ExitApp()
