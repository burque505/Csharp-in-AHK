#Requires AutoHotkey v2.0 64-bit
#Include "Csharp-in-AHK.ahk"
; matplotlib + WinForms in one script: pyplot1.cs builds a WinForms window, and Python (via pynet.cs)
; renders each plot with matplotlib straight into it. Needs Python 3.10+ with matplotlib and numpy
; (pip install matplotlib); see pynet.cs for the Python DLL path.
; AHK passes the plot shown first and gets back the path of the PNG saved with "Save PNG", if any.

OnExit(PyShutdown)

Saved := RunCSharpFile(A_ScriptDir "\pyplot1.cs", "Ripple surface (3D)")
if CSExitCode
    MsgBox("pyplot1.cs failed (" CSExitCode "):`n" CSOutput)
else if Saved != "" && MsgBox("Saved:`n" Saved "`n`nOpen it?", "pyplot1", "YesNo") = "Yes"
    Run(Saved)

PyShutdown(*) {
    RunCSharp('#:package pythonnet@3.1.0`nusing Python.Runtime;`nif (!PythonEngine.IsInitialized) return 0;`nPythonEngine.Shutdown();`nreturn PythonEngine.IsInitialized ? 1 : 0;')
    if CSExitCode  ; 0 = shut down or never started, 1 = still running, anything else = the error code of an exception
        MsgBox("Python shutdown failed (" CSExitCode "):`n" CSOutput)
}
