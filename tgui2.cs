/*/ console true; nuget Terminal\Terminal.GUI; /*/
// A simple Terminal.Gui example in C# - using C# 9.0 Top-level statements
// For LA, make sure console checkbox in Properties is checked.
//#console
#:package Terminal.Gui@1.12.1
using Terminal.Gui;

Application.Init();
var window = new ExampleWindow();

// The console window's X button (or Alt+F4) cancels AHK.ConsoleClosed instead of closing the window outright,
// which would end AutoHotkey too. Stop the app then, the same as Ctrl+Q; the window closes when the script ends.
AHK.ConsoleClosed.Register(() => Application.MainLoop.Invoke(() => Application.RequestStop()));

Application.Run(window);

// Before the application exits, reset Terminal.Gui for clean shutdown
Application.Shutdown();

// The console closes with the script, so the result goes back to AHK instead of Console.WriteLine
AHK.Return($"Username: {window.usernameText.Text}");

// Defines a top-level window with border and title
/// <summary>
/// Example from github page, https://github.com/gui-cs/Terminal.Gui
/// with multiline TextView added
/// </summary>
public class ExampleWindow : Window {
	/// <summary>
	/// User name
	/// </summary>
	public TextField usernameText;
	/// <summary>
	/// Example terminal window
	/// </summary>
	public ExampleWindow() {
		Title = "Example App (Ctrl+Q to quit)";

		// Create input components and labels
		var usernameLabel = new Label() {
			Text = "Username:"
		};

		usernameText = new TextField("") {
			// Position text field adjacent to the label
			X = Pos.Right(usernameLabel) + 1,

			// Fill remaining horizontal space
			Width = Dim.Fill(),
		};

		var passwordLabel = new Label() {
			Text = "Password:",
			X = Pos.Left(usernameLabel),
			Y = Pos.Bottom(usernameLabel) + 1
		};

		var passwordText = new TextField("") {
			Secret = true,
			// align with the text box above
			X = Pos.Left(usernameText),
			Y = Pos.Top(passwordLabel),
			Width = Dim.Fill(),
		};

		// Create login button
		var btnLogin = new Button() {
			Text = "Login",
			Y = Pos.Bottom(passwordText) + 1,
			// center the login button horizontally
			X = Pos.Center(),
			IsDefault = true,
		};

		var commentBoxLabel = new Label() {
			Text = "Multiline Comment Box",
			X = Pos.Center(),
			Y = Pos.Bottom(btnLogin) + 1
		};

		var commentBox = new TextView() {
			X = Pos.Left(passwordLabel) + 2,
			Y = Pos.Bottom(commentBoxLabel) + 1,
			Width = Dim.Fill(2),
			Height = 400,
			WordWrap = true,

		};

		// When login button is clicked display a message popup
		btnLogin.Clicked += () => {
			if (usernameText.Text == "admin" && passwordText.Text == "password") {
				MessageBox.Query("Logging In", "Login Successful", "Ok");
				Application.RequestStop();
			} else {
				MessageBox.ErrorQuery("Logging In", "Incorrect username or password", "Ok");
			}
		};

		// Add the views to the Window
		Add(usernameLabel, usernameText, passwordLabel, passwordText, btnLogin, commentBoxLabel, commentBox);
	}
}
