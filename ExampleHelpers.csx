// Loaded by Example.csx with #load. Functions and classes defined here are available to the loading script.

string Greet(string name) => $"Hello, {name}!";

class SystemInfo {
    public string Machine => Environment.MachineName;
    public string Runtime => System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription;
    public TimeSpan Uptime => TimeSpan.FromMilliseconds(Environment.TickCount64);
}
