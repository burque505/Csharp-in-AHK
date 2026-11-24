#Requires AutoHotkey v2
#Include "Csharp-in-AHK.ahk"
#SingleInstance
Persistent
RunCSharpFile(A_ScriptDir "\tgui.cs")    ; (tgui.cs has a //#console line; CSConsole := true would do the same)
if CSExitCode
    MsgBox(CSOutput, "tgui.cs failed", "Iconx")

MsgBox("Done")
ExitApp()
