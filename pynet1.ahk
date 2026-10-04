#Requires AutoHotkey v2
#Include "Csharp-in-AHK.ahk"
OnExit(PyShutdown)
MsgBox(RunCSharpFile(A_ScriptDir "\pynet1.cs"))

PyShutdown(*) {
    RunCSharp('#:package pythonnet@3.1.0`nusing Python.Runtime;`nif (!PythonEngine.IsInitialized) return 0;`nPythonEngine.Shutdown();`nreturn PythonEngine.IsInitialized ? 1 : 0;')
    ;RunCSharp('#:package pythonnet@3.1.0`nusing Python.Runtime;`nif (!PythonEngine.IsInitialized) return 0;`nPythonEngine.Shutdown();`nreturn 1;')
    if CSExitCode  ; 0 = shut down or never started, 1 = still running, anything else = the error code of an exception
        MsgBox("Python shutdown failed (" CSExitCode "):`n" CSOutput)
}

/*
To see the failure message once, comment out the first RunCSharp line in PyShutdown(*)
and uncomment the second one. Swap them back afterwards.
*/