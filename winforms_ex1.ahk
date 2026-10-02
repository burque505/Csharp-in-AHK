#Requires AutoHotkey v2.0 64-bit
#Include "Csx-in-AHK.ahk"
; Minimal WinForms example: show a C# dialog and return what the user typed to AHK.

Name := RunCsx('
(
    using System.Windows.Forms;

    var form = new Form { Text = "WinForms from AHK", Width = 320, Height = 140, StartPosition = FormStartPosition.CenterScreen };
    var box = new TextBox { Left = 12, Top = 12, Width = 280, Text = "World" };
    var ok = new Button { Text = "OK", Left = 217, Top = 50, DialogResult = DialogResult.OK };
    form.Controls.AddRange(new Control[] { box, ok });
    form.AcceptButton = ok;

    return form.ShowDialog() == DialogResult.OK ? box.Text : "";
)')

MsgBox Name = "" ? "Cancelled" : "Hello, " Name "!"
