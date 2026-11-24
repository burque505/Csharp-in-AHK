#Requires AutoHotkey v2
#Include "Csx-in-AHK.ahk"
#SingleInstance

; Runs tgui2.csx, a Terminal.Gui login window, in a console window (the script has a //#console line;
; CsxConsole := true would do the same). Close it with Ctrl+Q, a successful login (admin / password),
; or the console's X button; the user name entered is returned.
try
    Result := RunCsxFile(A_ScriptDir "\tgui2.csx")
catch as e {
    MsgBox(e.Message, "tgui2.csx failed to compile", "Iconx")
    ExitApp()
}
if InStr(CsxOutput, "Unhandled exception.")
    MsgBox(CsxOutput, "tgui2.csx failed", "Iconx")
else
    MsgBox(Result, "tgui2.csx")
ExitApp()
