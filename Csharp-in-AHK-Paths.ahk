#Requires AutoHotkey v2.0 64-bit
#SingleInstance Force
; Csharp-in-AHK-Paths.ahk: view and change where Csharp-in-AHK.ahk and Csx-in-AHK.ahk find .NET and Roslyn.
; It must be in the same folder as Csharp-in-AHK.ahk and Csx-in-AHK.ahk: it uses their detection code, edits the
; Csharp-in-AHK.ini they read (next to them), and Test runs them. Without them it shows a message and exits.
; It edits the user environment variables (HKCU\Environment) and Csharp-in-AHK.ini, and can test the result.
; Including Csx-in-AHK.ahk only reuses its detection functions. .NET is started in a separate process by Test.
#Include *i %A_ScriptDir%\Csx-in-AHK.ahk

; The library functions are looked up by name, so a missing library gives one clear message instead of load errors.
Missing := ""
for LibFile in ["Csx-in-AHK.ahk", "Csharp-in-AHK.ahk"]
    if !FileExist(A_ScriptDir "\" LibFile)
        Missing .= "    " LibFile "`n"
try
    CsxDetectDotnet := %"_CsxDetectDotnet"%, CsxDetectRoslyn := %"_CsxDetectRoslyn"%, CsxIsDotnetRoot := %"_CsxIsDotnetRoot"%
catch
    Missing .= Missing != "" ? "" : "    a version of Csx-in-AHK.ahk with path detection (yours is older)`n"
if Missing != "" {
    MsgBox("This tool must be in the same folder as Csx-in-AHK.ahk and Csharp-in-AHK.ahk.`n`nMissing:`n" Missing
        . "`nLooked in:`n    " A_ScriptDir, "Csharp-in-AHK paths", "Iconx")
    ExitApp()
}

Ini := A_ScriptDir "\Csharp-in-AHK.ini"
Loading := false
UserEnv := "HKCU\Environment"
SystemEnv := "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
Settings := [
    {Name: ".NET runtime", Env: "CSHARP_IN_AHK_DOTNET", Key: "DotnetRoot", Check: IsDotnetRoot, Detect: CsxDetectDotnet
        , Hint: "Folder containing host\fxr and shared\Microsoft.NETCore.App (.NET 8 or later)", UserValue: "", SystemValue: "", ProcessValue: "", Detected: ""},
    {Name: "Roslyn compiler", Env: "CSHARP_IN_AHK_ROSLYN", Key: "RoslynDir", Check: IsRoslynDir, Detect: CsxDetectRoslyn
        , Hint: "Folder containing csc.exe and the Microsoft.CodeAnalysis*.dll files", UserValue: "", SystemValue: "", ProcessValue: "", Detected: ""}
]

G := Gui(, "Csharp-in-AHK paths")
G.SetFont("s9", "Segoe UI")
G.AddText("w840", "Csharp-in-AHK.ahk and Csx-in-AHK.ahk use the first path found: a value set by the script, then the "
    . "environment variable, then Csharp-in-AHK.ini, then auto-detection. Leave a field empty to skip that step.")
G.AddText("w840 y+8", "Library folder (where Csharp-in-AHK.ini is read and saved): " A_ScriptDir)
for S in Settings {
    ; Columns: label, path, Browse, Delete (user variable only), OK/Invalid
    Box := G.AddGroupBox("xm y+20 w840 Section", S.Name " (" S.Hint ")")
    G.AddText("xs+12 ys+26 w270", "User variable " S.Env)
    S.EnvEdit := G.AddEdit("x+8 yp-3 w330")
    G.AddButton("x+8 yp-1 w70", "Browse...").OnEvent("Click", Browse.Bind(S, "EnvEdit"))
    S.DelBtn := G.AddButton("x+8 w60", "Delete")
    S.DelBtn.OnEvent("Click", DeleteVar.Bind(S))
    S.EnvOk := G.AddText("x+8 yp+4 w50")
    G.AddText("xs+12 y+16 w270", "System-wide variable (read-only)")
    S.SysEdit := G.AddEdit("x+8 yp-3 w330 ReadOnly")
    S.SysOk := G.AddText("x+154 yp+3 w50")
    S.EnvState := G.AddText("xs+290 y+8 w538")
    G.AddText("xs+12 y+16 w270", "Csharp-in-AHK.ini  [Paths] " S.Key)
    S.IniEdit := G.AddEdit("x+8 yp-3 w330")
    G.AddButton("x+8 yp-1 w70", "Browse...").OnEvent("Click", Browse.Bind(S, "IniEdit"))
    S.IniOk := G.AddText("x+76 yp+4 w50")
    G.AddText("xs+12 y+16 w270", "Auto-detected")
    S.AutoEdit := G.AddEdit("x+8 yp-3 w330 ReadOnly")
    G.AddButton("x+8 yp-1 w70", "Use in .ini").OnEvent("Click", UseDetected.Bind(S))
    S.InUse := G.AddText("xs+12 y+12 w816")
    S.InUse.GetPos(, &InUseY, , &InUseH), Box.GetPos(, &BoxY)
    Box.Move(, , , InUseY + InUseH + 10 - BoxY)
    S.EnvEdit.OnEvent("Change", Refresh)
    S.IniEdit.OnEvent("Change", Refresh)
}
Buttons := []
for B in [["Save .ini", SaveIni], ["Save variables", SaveEnv], ["Create missing variables", CreateMissing], ["Open .ini", OpenIni], ["Reload", Load]
    , ["Test", Test], ["Copy AHK code", CopyCode], ["Close", (*) => ExitApp()]] {
    Buttons.Push(Btn := G.AddButton((A_Index = 1 ? "xm y+22" : "x+8") " h28", B[1]))
    Btn.OnEvent("Click", B[2])
}
SB := G.AddStatusBar()
G.OnEvent("Close", (*) => ExitApp())
G.OnEvent("Escape", (*) => ExitApp())
Load()
G.Show()

; Setting a field's value from code raises its Change event. AutoHotkey runs that event after Load returns, but
; Keysharp can run it while Load is still busy, so Refresh does nothing until Load has filled in every setting.
Load(*) {
    global Loading := true
    Missing := ""
    for S in Settings {
        S.UserValue := RTrim(RegRead(UserEnv, S.Env, ""), "\")
        S.SystemValue := RTrim(RegRead(SystemEnv, S.Env, ""), "\")
        S.ProcessValue := RTrim(EnvGet(S.Env), "\")    ; What this process inherited when it started
        S.EnvEdit.Value := S.UserValue
        S.SysEdit.Value := S.SystemValue != "" ? S.SystemValue : "(not set)"
        if S.UserValue = "" && S.SystemValue = ""
            Missing .= (Missing = "" ? "" : " and ") S.Env
        S.IniEdit.Value := FileExist(Ini) ? IniRead(Ini, "Paths", S.Key, "") : ""
        S.Detected := S.Detect.Call()
        S.AutoEdit.Value := S.Detected != "" ? S.Detected : "(not found)"
    }
    Loading := false
    Refresh()
    SB.SetText(Missing != "" ? Missing " not set. Create missing variables can write the paths in use."
        : FileExist(Ini) ? "Loaded " Ini : "No Csharp-in-AHK.ini yet. Save .ini creates it in " A_ScriptDir)
}

Refresh(*) {
    if Loading
        return
    for S in Settings {
        Mark(S.EnvOk, S.EnvEdit.Value, S.Check)
        Mark(S.SysOk, S.SystemValue, S.Check)
        S.EnvState.Value := EnvState(S)
        S.DelBtn.Enabled := S.UserValue != ""
        Mark(S.IniOk, S.IniEdit.Value, S.Check)
        Path := Resolve(S, &From)
        Text := Path = "" ? "In use: nothing found" : "In use: " Path "   (" From ")"
        Valid := Path != "" && S.Check.Call(Path)
        S.InUse.SetFont(Valid ? "cGreen" : "cRed")
        S.InUse.Value := Text (Path != "" && !Valid ? "   NOT VALID" : "")
    }
}

; The path the libraries would use, ignoring values set by a script. SkipUser: as if the user variable did not exist.
Resolve(S, &From, SkipUser := false) {
    if !SkipUser && (Path := Trim(S.EnvEdit.Value)) != ""
        From := "environment variable"
    else if (Path := S.SystemValue) != ""
        From := "system environment variable"
    else if (Path := Trim(S.IniEdit.Value)) != ""
        From := "Csharp-in-AHK.ini"
    else if (Path := S.Detected) != ""
        From := "auto-detection"
    else
        From := ""
    return RTrim(Path, "\")
}

; Whether the variable exists, whether the field has unsaved changes, and what already running programs still see.
EnvState(S) {
    Edited := RTrim(Trim(S.EnvEdit.Value), "\")
    State := S.UserValue != "" ? "Set for your user." : S.SystemValue != "" ? "Not set for your user (the system-wide value applies)."
        : "Not set for your user or system-wide."
    if Edited != S.UserValue
        State .= " Edited, not saved yet."
    Saved := S.UserValue != "" ? S.UserValue : S.SystemValue
    if S.ProcessValue != Saved
        State .= " Programs started before the last change still see " (S.ProcessValue = "" ? "no value." : S.ProcessValue)
    return State
}

Mark(Ctrl, Path, Check) {
    Path := RTrim(Trim(Path), "\")
    Ok := Path != "" && Check.Call(Path)
    Ctrl.SetFont(Ok ? "cGreen" : "cRed")
    Ctrl.Value := Path = "" ? "" : Ok ? "OK" : "Invalid"
}

IsDotnetRoot(Dir) => CsxIsDotnetRoot(RTrim(Trim(Dir), "\"))

; Csx-in-AHK.ahk needs the scripting DLLs, Csharp-in-AHK.ahk does not, so check for all of them.
IsRoslynDir(Dir) {
    Dir := RTrim(Trim(Dir), "\")
    for File in ["csc.exe", "Microsoft.CodeAnalysis.dll", "Microsoft.CodeAnalysis.CSharp.dll"
        , "Microsoft.CodeAnalysis.Scripting.dll", "Microsoft.CodeAnalysis.CSharp.Scripting.dll"]
        if Dir = "" || !FileExist(Dir "\" File)
            return false
    return true
}

Browse(S, Field, *) {
    Start := Trim(S.%Field%.Value)
    if Start = ""
        Start := S.Detected
    if (Dir := DirSelect("*" Start, 3, "Select the " S.Name " folder.`n" S.Hint)) != "" {
        S.%Field%.Value := Dir
        Refresh()
    }
}

UseDetected(S, *) {
    if S.Detected = ""
        return SB.SetText("Nothing was detected for " S.Name ".")
    S.IniEdit.Value := S.Detected
    Refresh()
    SB.SetText("Copied the detected path. Click Save .ini to keep it.")
}

SaveIni(*) {
    if !FileExist(Ini) {
        ; Start from the template so the file keeps its comments. UTF-16 keeps non-ASCII paths intact.
        Template := A_ScriptDir "\Csharp-in-AHK.example.ini"
        Text := FileExist(Template) ? FileRead(Template) : "[Paths]`n"
        F := FileOpen(Ini, "w", "UTF-16"), F.Write(StrReplace(StrReplace(Text, "`r`n", "`n"), "`n", "`r`n")), F.Close()
    }
    for S in Settings
        IniWrite(RTrim(Trim(S.IniEdit.Value), "\"), Ini, "Paths", S.Key)
    SB.SetText("Saved " Ini)
}

; Creates or changes user variables after confirmation. It never deletes one (that is what Delete is for), and it saves
; nothing if a changed path is not valid.
SaveEnv(*) {
    Changes := [], List := "", Problems := ""
    for S in Settings {
        Value := RTrim(Trim(S.EnvEdit.Value), "\")
        if Value == S.UserValue
            continue
        if Value = "" {
            Problems .= S.Env ": the field is empty. To delete the variable, use its Delete button.`n"
            continue
        }
        if !S.Check.Call(Value) {
            Problems .= S.Env ": " Value " is not a valid " S.Name " folder.`n"
            continue
        }
        Changes.Push([S, Value])
        List .= (S.UserValue = "" ? "Create " S.Env " = " Value : "Change " S.Env "`n    from " S.UserValue "`n    to     " Value) "`n"
    }
    if Problems != "" {
        MsgBox("Nothing was saved.`n`n" Problems, "Save variables", "Iconx Owner" G.Hwnd)
        return SB.SetText("Nothing was saved. Fix the fields marked Invalid, or use Delete.")
    }
    if !Changes.Length
        return SB.SetText("No changes to save.")
    if MsgBox("Save these user environment variables?`n`n" List, "Save variables", "YesNo Icon? Owner" G.Hwnd) != "Yes"
        return SB.SetText("Nothing was saved.")
    for Item in Changes {
        RegWrite(Item[2], "REG_SZ", UserEnv, Item[1].Env)
        Item[1].UserValue := Item[1].EnvEdit.Value := Item[2]
    }
    EnvChanged()
    Refresh()
    SB.SetText("Saved. Programs that are already running, such as VS Code, see the change only after a restart.")
}

DeleteVar(S, *) {
    if S.UserValue = ""
        return
    Path := Resolve(S, &From, true)
    Then := Path != "" ? Path "`n(from " From ")" : "nothing (no path found)"
    if MsgBox("Delete the user variable " S.Env "?`n`nCurrent value:`n" S.UserValue "`n`nThe libraries will then use:`n" Then
        , "Delete variable", "YesNo Icon! Default2 Owner" G.Hwnd) != "Yes"
        return
    RegDelete(UserEnv, S.Env)
    S.UserValue := S.EnvEdit.Value := ""
    EnvChanged()
    Refresh()
    SB.SetText("Deleted " S.Env ". Programs that are already running, such as VS Code, see the change only after a restart.")
}

; Writes the paths in use to the variables that exist neither for the user nor system-wide. Existing ones are left alone.
CreateMissing(*) {
    ToWrite := [], List := "", Skipped := ""
    for S in Settings {
        if S.UserValue != "" || S.SystemValue != ""
            continue
        Path := Resolve(S, &From)
        if Path != "" && S.Check.Call(Path)
            ToWrite.Push([S, Path]), List .= S.Env " = " Path "`n"
        else
            Skipped .= S.Env ": no valid path to write. Enter one in its field first.`n"
    }
    if !ToWrite.Length
        return SB.SetText(Skipped != "" ? StrReplace(Trim(Skipped, "`n"), "`n", " ") : "Both variables already exist. Nothing to create.")
    Msg := "Create these user environment variables?`n`n" List (Skipped != "" ? "`nNot created:`n" Skipped : "")
        . "`nThey take precedence over Csharp-in-AHK.ini and auto-detection. If you later move or reinstall .NET or Visual Studio, "
        . "update or delete them here."
    if MsgBox(Msg, "Create missing variables", "YesNo Icon? Owner" G.Hwnd) != "Yes"
        return
    for Item in ToWrite {
        RegWrite(Item[2], "REG_SZ", UserEnv, Item[1].Env)
        Item[1].UserValue := Item[1].EnvEdit.Value := Item[2]
    }
    EnvChanged()
    Refresh()
    SB.SetText("Created " ToWrite.Length " variable(s). Programs that are already running, such as VS Code, see them only after a restart.")
}

; WM_SETTINGCHANGE tells Explorer to reload the environment for programs it starts from now on.
EnvChanged() => DllCall("SendMessageTimeout", "ptr", 0xFFFF, "uint", 0x1A, "ptr", 0, "str", "Environment", "uint", 2, "uint", 5000, "ptr*", 0)

OpenIni(*) {
    if !FileExist(Ini)
        return SB.SetText("There is no Csharp-in-AHK.ini yet. Click Save .ini to create it.")
    Run('notepad.exe "' Ini '"')
    SB.SetText("After editing the .ini in Notepad, save it and click Reload.")
}

; Runs both libraries in a new AutoHotkey process with the paths shown as "In use".
Test(*) {
    Dotnet := Resolve(Settings[1], &_), Roslyn := Resolve(Settings[2], &_)
    Script := A_Temp "\Csharp-in-AHK-paths-test.ahk", Out := A_Temp "\Csharp-in-AHK-paths-test.txt"
    Source := "
    (
    #Requires AutoHotkey v2.0 64-bit
    CSDotnetRoot := CsxDotnetRoot := A_Args[1]
    CSRoslynDir := CsxRoslynDir := A_Args[2]
    #Include @DIR@\Csharp-in-AHK.ahk
    #Include @DIR@\Csx-in-AHK.ahk
    try {
        FileAppend("RunCsx: .NET " RunCsx("Environment.Version.ToString()") "``n", "*", "UTF-8")
        FileAppend("RunCSharp: " RunCSharp('AHK.Return(System.Runtime.InteropServices.RuntimeEnvironment.GetRuntimeDirectory());') "``n", "*", "UTF-8")
    } catch as e
        FileAppend("Error: " e.Message "``n" e.Extra "``n", "*", "UTF-8")
    )"
    F := FileOpen(Script, "w", "UTF-8"), F.Write(StrReplace(Source, "@DIR@", A_ScriptDir)), F.Close()
    for Btn in Buttons
        Btn.Enabled := false
    SB.SetText("Testing... The first run with new paths compiles the host and can take several seconds.")
    try {
        RunWait(A_ComSpec ' /c ""' A_AhkPath '" /ErrorStdOut "' Script '" "' Dotnet '" "' Roslyn '" > "' Out '" 2>&1"', , "Hide")
        Result := FileExist(Out) ? Trim(FileRead(Out, "UTF-8"), "`r`n") : "No output"
    } catch as e
        Result := "Error: " e.Message
    for Btn in Buttons
        Btn.Enabled := true
    try FileDelete(Script)
    try FileDelete(Out)
    Failed := !(InStr(Result, "RunCsx: .NET ") && InStr(Result, "RunCSharp: "))    ; Passed only if both libraries ran
    SB.SetText(Failed ? "Test failed." : "Test passed.")
    MsgBox("DotnetRoot: " Dotnet "`nRoslynDir: " Roslyn "`n`n" Result, "Test " (Failed ? "failed" : "passed"), (Failed ? "Iconx" : "Iconi") " Owner" G.Hwnd)
}

CopyCode(*) {
    Dotnet := Resolve(Settings[1], &_), Roslyn := Resolve(Settings[2], &_)
    A_Clipboard := 'CSDotnetRoot := CsxDotnetRoot := "' Dotnet '"`nCSRoslynDir := CsxRoslynDir := "' Roslyn '"`n'
    SB.SetText("Copied AHK code that sets the paths in use. Paste it into a script before its first RunCSharp / RunCsx call.")
}
