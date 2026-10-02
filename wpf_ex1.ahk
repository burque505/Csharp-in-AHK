#Requires AutoHotkey v2.0 64-bit
#Include "Csx-in-AHK.ahk"
; Minimal WPF example: show a C# window and return what the user typed to AHK.
; Use ShowDialog() rather than Application.Run(): only one WPF Application can exist per process.

Name := RunCsx('
(
    using System.Windows;
    using System.Windows.Controls;

    var box = new TextBox { Text = "World", Margin = new Thickness(10) };
    var ok = new Button { Content = "OK", IsDefault = true, Width = 80, Margin = new Thickness(10), HorizontalAlignment = HorizontalAlignment.Right };
    var window = new Window {
        Title = "WPF from AHK", Width = 320, SizeToContent = SizeToContent.Height,
        WindowStartupLocation = WindowStartupLocation.CenterScreen,
        Content = new StackPanel { Children = { box, ok } }
    };
    ok.Click += (s, e) => window.DialogResult = true;

    return window.ShowDialog() == true ? box.Text : "";
)')

MsgBox Name = "" ? "Cancelled" : "Hello, " Name "!"
