#:package pythonnet@3.1.0
#load "pynet.cs"
using Python.Runtime;

//#if true

string code = """
def Multi(a1, a2):
    return a1 * a2

def JoinStr(a1, a2):
    return a1 + a2
""";
using var pyn = new Pynet(code);
dynamic m = pyn.Module;
double d1 = m.Multi(2, 3.5);
string s1 = m.JoinStr("joi", "ned");
Console.WriteLine($"{d1} {s1}");

//#elif !true

using var pyn1 = new Pynet();
dynamic mod = Py.Import("math");
Console.WriteLine(mod.cos(mod.pi * 2));

//#elif !true

using var pyn2 = new Pynet();
Console.WriteLine(PythonEngine.Eval("3 + 4"));

//#elif !true

string code1 = """
import ctypes
ctypes.windll.user32.MessageBoxW(0, "Text", "Title", 1)
""";
using var pyn3 = new Pynet();
PythonEngine.RunSimpleString(code1);

//#endif

using var pyn4 = new Pynet();

string code2 = """
print("Monkey")
""";

PythonEngine.RunSimpleString(code2);
