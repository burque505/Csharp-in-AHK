/*/ console true; nuget Terminal\Terminal.GUI; /*/
//#console
// A simple Terminal.Gui example in C# - using C# 9.0 Top-level statements
// For LA, make sure console checkbox in Properties is checked.
#:package Terminal.Gui@1.12.1

using Terminal.Gui;
using NStack;
//using System.Windows.Forms;

//System.Windows.Forms.MessageBox.Show("Got this far.");

Application.Init();

var wizard = new Wizard ($"Setup Wizard");

// Add 1st step
var firstStep = new Wizard.WizardStep ("End User License Agreement");
wizard.AddStep(firstStep);
firstStep.NextButtonText = "Accept!";
firstStep.HelpText = @"This is the End User License Agreement.
You must accept this and offer up your first-born offspring
in order to continue. You must also pay monthly through the nose.
No exceptions!";
var firstLbl = new Terminal.Gui.Label("Important! Click 'Accept' only after reading License Agreement!") { AutoSize = true };
firstStep.Add(firstLbl);

// Add 2nd step
var secondStep = new Wizard.WizardStep ("Second Step");
wizard.AddStep(secondStep);
secondStep.HelpText = @"Enter your full name on one line.
(The entry box may appear oversize on your terminal.)";
var lbl = new Terminal.Gui.Label ("Name:") { AutoSize = true };
secondStep.Add(lbl);

var name = new TextField () { X = Pos.Right (lbl) + 1, Width = Dim.Fill () - 1 };
secondStep.Add(name);

wizard.Finished += (args) =>
{
    Terminal.Gui.MessageBox.Query("Wizard", $"Finished. The Name entered is '{name.Text}'", "Ok");
    Application.RequestStop();
};

Application.Top.Add (wizard);
Application.Run ();
Application.Shutdown ();

