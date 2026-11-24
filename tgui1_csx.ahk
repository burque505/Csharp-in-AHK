#Requires AutoHotkey v2
#Include "Csx-in-AHK.ahk"
#SingleInstance

; Runs tgui1.csx, a Terminal.Gui wizard, in a console window (the script has a //#console line;
; CsxConsole := true would do the same). The console's X button or Alt+F4 cancels the wizard.
try
    Result := RunCsxFile(A_ScriptDir "\tgui1.csx")
catch as e {
    MsgBox(e.Message, "tgui1.csx failed to compile", "Iconx")
    ExitApp()
}
if InStr(CsxOutput, "Unhandled exception.")
    MsgBox(CsxOutput, "tgui1.csx failed", "Iconx")
else
    MsgBox(Result, "tgui1.csx")
ExitApp()
