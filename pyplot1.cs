#:package pythonnet@3.1.0
#load "pynet.cs"
// matplotlib inside a WinForms window: Python renders each frame to PNG in memory (Agg backend),
// C# shows it in a PictureBox. Used by pyplot1.ahk.
// args[0] (optional): the plot shown first. AHK.Return: the path of the saved PNG, or "".
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;
using Python.Runtime;

string python = """
import sys, io, base64
if not hasattr(sys, "argv"): sys.argv = [""]
import matplotlib
matplotlib.use("Agg")
import matplotlib.style
import numpy as np
from matplotlib.figure import Figure
from matplotlib.backends.backend_agg import FigureCanvasAgg
from matplotlib.collections import LineCollection
from matplotlib.colors import LightSource

PLOTS = ["Ripple surface (3D)", "Lissajous curve", "Polar rose", "Mandelbrot zoom", "Complex phase field"]

def info():
    return "Python %s | matplotlib %s | numpy %s" % (sys.version.split()[0], matplotlib.__version__, np.__version__)

def ripple(fig, f, t, cmap):
    fig.subplots_adjust(0, 0, 1, 1)
    ax = fig.add_subplot(projection="3d")
    ax.set_box_aspect(None, zoom=1.35)
    x = np.linspace(-8, 8, 90)
    X, Y = np.meshgrid(x, x)
    R = np.hypot(X, Y)
    Z = np.sin(f * 0.5 * R - t) * np.exp(-0.12 * R)
    rgb = LightSource(azdeg=315, altdeg=40).shade(Z, cmap=matplotlib.colormaps[cmap], vert_exag=3, blend_mode="soft")
    ax.plot_surface(X, Y, Z, facecolors=rgb, rstride=1, cstride=1, linewidth=0, antialiased=False, shade=False)
    ax.set_zlim(-1.3, 1.3)
    ax.view_init(elev=32, azim=np.degrees(t) * 0.5 + 30)
    ax.set_axis_off()

def lissajous(fig, f, t, cmap):
    ax = fig.add_subplot()
    s = np.linspace(0, 2 * np.pi, 3000)
    x, y = np.sin(f * s + t), np.sin((f + 1) * s)
    pts = np.column_stack([x, y]).reshape(-1, 1, 2)
    lc = LineCollection(np.concatenate([pts[:-1], pts[1:]], axis=1), cmap=cmap, linewidth=2.5)
    lc.set_array(s)
    ax.add_collection(lc)
    ax.set_xlim(-1.1, 1.1); ax.set_ylim(-1.1, 1.1)
    ax.set_aspect("equal"); ax.set_axis_off()

def rose(fig, f, t, cmap):
    ax = fig.add_subplot(projection="polar")
    theta = np.linspace(0, 2 * np.pi, 4000)
    k = f / 3
    r = np.abs(np.cos(k * theta * 3 + t)) * (0.6 + 0.4 * np.cos(theta * 2 - t))
    ax.scatter(theta + t / 4, r, c=theta, cmap=cmap, s=3)
    ax.fill(theta + t / 4, r, alpha=0.15, color=matplotlib.colormaps[cmap](0.7))
    ax.set_axis_off()

def mandelbrot(fig, f, t, cmap, w, h):
    ax = fig.add_axes([0, 0, 1, 1])
    cx, cy, width = -0.743643887, 0.131825904, 3.0 * 0.55 ** f
    nx, ny = min(w, 520), min(h, 400)
    x = np.linspace(cx - width / 2, cx + width / 2, nx)
    y = np.linspace(cy - width / 2 * ny / nx, cy + width / 2 * ny / nx, ny)
    c = x[None, :] + 1j * y[:, None]
    z = np.zeros_like(c)
    n = np.zeros(c.shape)
    alive = np.ones(c.shape, bool)
    for i in range(60 + 12 * f):
        z[alive] = z[alive] ** 2 + c[alive]
        escaped = alive & (np.abs(z) > 4)
        n[escaped] = i + 1 - np.log2(np.log2(np.abs(z[escaped])))
        alive &= ~escaped
    img = np.ma.masked_where(alive, np.mod(np.sqrt(n) * 0.7 + t / (2 * np.pi), 1))
    colors = matplotlib.colormaps[cmap].with_extremes(bad="black")
    ax.imshow(img, cmap=colors, origin="lower", interpolation="bilinear", aspect="auto", vmin=0, vmax=1)
    ax.set_axis_off()

def phase(fig, f, t, cmap):
    ax = fig.add_axes([0, 0, 1, 1])
    x = np.linspace(-2, 2, 500)
    z = x[None, :] + 1j * x[:, None] * 0.7
    w = (z ** f - 1) / (z ** 2 + 0.5 * np.exp(1j * t))
    # Domain coloring: hue from the argument, brightness bands from log2 of the magnitude.
    hue = matplotlib.colormaps[cmap]((np.angle(w) / (2 * np.pi)) % 1)[..., :3]
    bands = 0.6 + 0.4 * np.mod(np.log2(np.abs(w) + 1e-12), 1)
    ax.imshow(hue * bands[..., None], origin="lower", aspect="auto", interpolation="bilinear")
    ax.set_axis_off()

def render(kind, f, t, cmap, dark, w, h, scale):
    style = "dark_background" if dark else "default"
    with matplotlib.style.context(style):
        fig = Figure(figsize=(w / 100, h / 100), dpi=100 * scale)
        i = PLOTS.index(kind)
        if i == 0: ripple(fig, f, t, cmap)
        elif i == 1: lissajous(fig, f, t, cmap)
        elif i == 2: rose(fig, f, t, cmap)
        elif i == 3: mandelbrot(fig, f, t, cmap, w, h)
        else: phase(fig, f, t, cmap)
        buf = io.BytesIO()
        FigureCanvasAgg(fig).print_png(buf)
    return base64.b64encode(buf.getvalue()).decode("ascii")
""";

using var py = new Pynet(python);
dynamic m = py.Module;
string[] plots = ((string)m.Eval("'|'.join(PLOTS)")).Split('|');
string[] colormaps = { "viridis", "plasma", "inferno", "magma", "turbo", "twilight", "cividis", "coolwarm", "Spectral", "cubehelix" };
string savedPath = "";

Application.EnableVisualStyles();
var font = new Font("Segoe UI", 9.5f);
var form = new Form { Text = "matplotlib in WinForms, hosted by AutoHotkey", Width = 1100, Height = 720,
    StartPosition = FormStartPosition.CenterScreen, Font = font, MinimumSize = new Size(700, 450) };
var pic = new PictureBox { Dock = DockStyle.Fill, SizeMode = PictureBoxSizeMode.Zoom };
var panel = new FlowLayoutPanel { Dock = DockStyle.Left, Width = 230, FlowDirection = FlowDirection.TopDown,
    WrapContents = false, Padding = new Padding(12) };
var status = new StatusStrip();
var statusText = new ToolStripStatusLabel { Spring = true, TextAlign = ContentAlignment.MiddleLeft };
var versions = new ToolStripStatusLabel((string)m.info());
status.Items.AddRange(new ToolStripItem[] { statusText, versions });

Label Caption(string text) => new Label { Text = text, AutoSize = true, Margin = new Padding(0, 10, 0, 2) };
var plotBox = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 200 };
plotBox.Items.AddRange(plots);
plotBox.SelectedIndex = Math.Max(0, Array.IndexOf(plots, args.Length > 0 ? args[0] : ""));
var freq = new TrackBar { Minimum = 1, Maximum = 12, Value = 4, Width = 200, TickStyle = TickStyle.None };
var phaseBar = new TrackBar { Minimum = 0, Maximum = 359, Value = 0, Width = 200, TickStyle = TickStyle.None };
var cmapBox = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 200 };
cmapBox.Items.AddRange(colormaps);
cmapBox.SelectedIndex = 0;
var dark = new CheckBox { Text = "Dark theme", AutoSize = true, Checked = true, Margin = new Padding(0, 12, 0, 0) };
var animate = new CheckBox { Text = "Animate phase", AutoSize = true, Margin = new Padding(0, 6, 0, 0) };
var save = new Button { Text = "Save PNG (2x)...", Width = 200, Height = 32, Margin = new Padding(0, 18, 0, 0) };
var close = new Button { Text = "Close", Width = 200, Height = 32, DialogResult = DialogResult.Cancel, Margin = new Padding(0, 6, 0, 0) };
var freqLabel = Caption("");
var phaseLabel = Caption("");
panel.Controls.AddRange(new Control[] { Caption("Plot"), plotBox, freqLabel, freq, phaseLabel, phaseBar,
    Caption("Colormap"), cmapBox, dark, animate, save, close });
form.Controls.AddRange(new Control[] { pic, panel, status });
form.CancelButton = close;

// Theme the WinForms side to match the plot.
void ApplyTheme() {
    Color back = dark.Checked ? Color.Black : Color.White, fore = dark.Checked ? Color.Gainsboro : Color.Black;
    Color side = dark.Checked ? Color.FromArgb(32, 32, 36) : SystemColors.Control;
    pic.BackColor = back;
    panel.BackColor = side;
    foreach (Control c in panel.Controls) if (c is Label or CheckBox) c.ForeColor = fore;
    foreach (var t in new[] { freq, phaseBar }) t.BackColor = side;
    // Standard buttons draw black text on the panel's background, so use flat buttons in the dark theme.
    foreach (var b in new[] { save, close }) {
        b.FlatStyle = dark.Checked ? FlatStyle.Flat : FlatStyle.Standard;
        b.FlatAppearance.BorderColor = Color.FromArgb(90, 90, 100);
        b.FlatAppearance.MouseOverBackColor = Color.FromArgb(62, 62, 70);
        b.BackColor = dark.Checked ? Color.FromArgb(48, 48, 54) : SystemColors.Control;
        b.ForeColor = fore;
        b.UseVisualStyleBackColor = !dark.Checked;
    }
}

string Kind() => (string)plotBox.SelectedItem!;
double PhaseRad() => phaseBar.Value * Math.PI / 180;
string Render(int width, int height, int scale) =>
    m.render(Kind(), freq.Value, PhaseRad(), (string)cmapBox.SelectedItem!, dark.Checked, width, height, scale);

void Redraw() {
    freqLabel.Text = $"Frequency / zoom: {freq.Value}";
    phaseLabel.Text = $"Phase: {phaseBar.Value} deg";
    if (pic.ClientSize.Width < 50 || pic.ClientSize.Height < 50) return;
    var sw = Stopwatch.StartNew();
    try {
        using var ms = new MemoryStream(Convert.FromBase64String(Render(pic.ClientSize.Width, pic.ClientSize.Height, 1)));
        var old = pic.Image;
        pic.Image = new Bitmap(ms);
        old?.Dispose();
        statusText.Text = $"{Kind()} rendered by matplotlib in {sw.ElapsedMilliseconds} ms";
    } catch (PythonException ex) {
        statusText.Text = "Python error: " + ex.Message;
    }
}

// Coalesce bursts of slider/resize events into one render.
var pending = new System.Windows.Forms.Timer { Interval = 40 };
pending.Tick += (s, e) => { pending.Stop(); Redraw(); };
void Schedule() { pending.Stop(); pending.Start(); }

var anim = new System.Windows.Forms.Timer { Interval = 30 };
anim.Tick += (s, e) => phaseBar.Value = (phaseBar.Value + 6) % 360;
animate.CheckedChanged += (s, e) => anim.Enabled = animate.Checked;

plotBox.SelectedIndexChanged += (s, e) => Schedule();
cmapBox.SelectedIndexChanged += (s, e) => Schedule();
freq.ValueChanged += (s, e) => Schedule();
phaseBar.ValueChanged += (s, e) => Schedule();
dark.CheckedChanged += (s, e) => { ApplyTheme(); Schedule(); };
pic.Resize += (s, e) => Schedule();
form.Shown += (s, e) => Redraw();
form.FormClosing += (s, e) => { anim.Stop(); pending.Stop(); };

save.Click += (s, e) => {
    using var dlg = new SaveFileDialog { Filter = "PNG image|*.png", FileName = Kind().Split(' ')[0].ToLowerInvariant() + ".png",
        InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.MyPictures) };
    bool wasAnimating = anim.Enabled;
    anim.Stop();
    if (dlg.ShowDialog(form) == DialogResult.OK) {
        File.WriteAllBytes(dlg.FileName, Convert.FromBase64String(Render(pic.ClientSize.Width, pic.ClientSize.Height, 2)));
        savedPath = dlg.FileName;
        statusText.Text = "Saved " + savedPath;
    }
    anim.Enabled = wasAnimating;
};

ApplyTheme();
form.ShowDialog();
pic.Image?.Dispose();
form.Dispose();
AHK.Return(savedPath);
