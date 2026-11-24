//#console
// A simple Terminal.Gui wizard as a C# script (.csx), run by tgui1_csx.ahk with RunCsxFile.
// The //#console line above gives the script a console window (CsxConsole := true would do the same).
#r "nuget: Terminal.Gui, 1.12.1"

using Terminal.Gui;

Application.Init();

// The console window's X button (or Alt+F4) cancels AHK.ConsoleClosed instead of closing the window outright,
// which would end AutoHotkey too. Stop the wizard then; the window closes when the script ends.
AHK.ConsoleClosed.Register(() => Application.MainLoop.Invoke(() => Application.RequestStop()));

var wizard = new Wizard("Setup Wizard");

// Add 1st step
var firstStep = new Wizard.WizardStep("End User License Agreement");
wizard.AddStep(firstStep);
firstStep.NextButtonText = "Accept!";
firstStep.HelpText = @"This is the End User License Agreement.
You must accept this and offer up your first-born offspring
in order to continue. You must also pay monthly through the nose.
No exceptions!";
firstStep.Add(new Label("Important! Click 'Accept' only after reading License Agreement!") { AutoSize = true });

// Add 2nd step
var secondStep = new Wizard.WizardStep("Second Step");
wizard.AddStep(secondStep);
secondStep.HelpText = @"Enter your full name on one line.
(The entry box may appear oversize on your terminal.)";
var lbl = new Label("Name:") { AutoSize = true };
secondStep.Add(lbl);

var name = new TextField() { X = Pos.Right(lbl) + 1, Width = Dim.Fill() - 1 };
secondStep.Add(name);

bool finished = false;
wizard.Finished += (e) => {
    finished = true;
    MessageBox.Query("Wizard", $"Finished. The Name entered is '{name.Text}'", "Ok");
    Application.RequestStop();
};

Application.Top.Add(wizard);
Application.Run();
Application.Shutdown();

// The console closes with the script, so the result goes back to AHK as the return value
return finished ? $"Name: {name.Text}" : "The wizard was canceled.";
