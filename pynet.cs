// Python.NET helper, adapted from a LibreAutomate script by its developer.
// Use it with #load "pynet.cs" in a script that also has #:package pythonnet@3.1.0.
using Python.Runtime;

/// <summary>
/// Initializes the Python engine, locks its global interpreter and adds scope.
/// Optionally adds Python code; then you can call functions etc.
/// When disposing, unlocks/disposes objects. The engine is not shut down: it stays loaded in the
/// AutoHotkey process and is reused by later scripts (shutting it down and initializing it again in
/// the same process is not reliable, and PythonEngine.Shutdown fails on .NET 9+ anyway).
/// </summary>
public class Pynet : IDisposable {
    Py.GILState? _gil;
    PyModule? _m;

    /// <summary>
    /// Initializes the Python engine and optionally adds code.
    /// </summary>
    /// <param name="code">If not null/"", calls <b>PyModule.Exec</b>.</param>
    /// <param name="enablePrint">Redirect the output of the Python's print function to console. Default true.</param>
    public Pynet(string? code = null, bool enablePrint = true) {
        if (!PythonEngine.IsInitialized) {
            if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("PYTHONNET_PYDLL"))) Runtime.PythonDLL = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\Python\Python312\python312.dll"); //default per-user install of Python 3.12; edit this if need. Or set the environment variable.
            //Use the installation the DLL belongs to. Otherwise an inherited VIRTUAL_ENV (e.g. from VS Code) can make Python use another environment's packages.
            if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("PYTHONHOME"))) {
                string home = Path.GetDirectoryName(Runtime.PythonDLL)!;
                PythonEngine.PythonHome = home;
                PythonEngine.ProgramName = Path.Combine(home, "python.exe");
            }
            PythonEngine.Initialize();
        }
        _gil = Py.GIL();

        if (enablePrint) {
            Module.Exec("""
import sys

class NetConsole(object):
    def __init__(self, writeCallback):
        self.writeCallback = writeCallback

    def write(self, message):
        self.writeCallback(message)

    def flush(self):
        pass

def setConsoleOut(writeCallback):
    sys.stdout = NetConsole(writeCallback)
""");
            var writer = (string s) => { Console.Write(s); };
            Module.InvokeMethod("setConsoleOut", Python.Runtime.PyObject.FromManagedObject(writer));
        }

        if (!string.IsNullOrEmpty(code)) Module.Exec(code);
    }

    /// <summary>
    /// Unlocks/disposes Python objects.
    /// </summary>
    public void Dispose() {
        _m?.Dispose();
        _gil?.Dispose();
    }

    /// <summary>
    /// Gets the result of <b>Py.CreateScope</b>.
    /// You can assign it to a <c>dynamic</c> variable and call functions defined in your Python code.
    /// </summary>
    public PyModule Module => _m ??= Py.CreateScope();
}
