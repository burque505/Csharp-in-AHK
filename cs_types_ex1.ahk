#Requires AutoHotkey v2.0 64-bit
#Include "Csharp-in-AHK.ahk"
; Passing AHK variables to a top-level-statements C# program (RunCSharp) and using the results in AHK.
;
; Going in:  every value reaches C# as a string in args[]. Numbers keep AHK's format ('.' decimal point),
;            true/false become "1"/"0", dates are AHK timestamps (YYYYMMDDHH24MISS).
;            Arrays can be spread over several arguments with Arr*; a Map can be sent as "key=value" lines.
; Coming out, three ways:
;   AHK.Return(value)  RunCSharp returns the value (numbers with '.', bool -> 1/0, collections -> one item per line)
;                      and the console output goes to CSOutput.
;   Console output     without AHK.Return, RunCSharp returns what the program printed.
;   return <int>;      the program's exit code goes to CSExitCode.
;
; Parse numbers in C# with CultureInfo.InvariantCulture, so they also work on systems that use ',' as decimal point.
; Note: inside a '( ... )' continuation section, quote marks are literal, so AHK variables cannot be spliced into
; the C# code there. Pass them as arguments instead.

; --- Integer and Float: AHK.Return --------------------------------------------
Count := 7
Price := 19.95
Total := RunCSharp('
(
    using System.Globalization;

    int count = int.Parse(args[0]);
    double price = double.Parse(args[1], CultureInfo.InvariantCulture);
    AHK.Return(Math.Round(count * price * 1.08, 2));    // add 8% tax
)', Count, Price)
; AHK shows floats with full precision (19.95 -> 19.949999999999999), so format them for display
Report := Format("Integer/Float:  {} x {:.2f} + tax = {}`n", Count, Price, Total)
Report .= Format("   AHK can compute with it:  Total / 2 = {:.2f}`n`n", Total / 2)

; --- String: console output ------------------------------------------------------
Text := "the quick brown fox jumps over the lazy dog"
Words := RunCSharp('
(
    foreach (var word in args[0].Split(' ').Distinct().OrderBy(w => w))
        Console.WriteLine(word);
)', Text)
Report .= "String:  sorted unique words: " StrReplace(Trim(Words, "`r`n"), "`r`n", ", ") "`n`n"

; --- Boolean: exit code -----------------------------------------------------------
Email := "someone@example.com"
Strict := true
RunCSharp('
(
    bool strict = args[1] == "1";
    bool valid = IsValid(args[0], strict);
    Console.WriteLine(valid ? "looks valid" : "rejected");
    return valid ? 1 : 0;                                // goes to CSExitCode

    // A local function
    static bool IsValid(string email, bool strict) {
        int at = email.IndexOf('@');
        if (at < 1 || at != email.LastIndexOf('@')) return false;
        return !strict || email.IndexOf('.', at) > at + 1;
    }
)', Email, Strict)
Report .= "Boolean:  " Email " (strict: " (Strict ? "yes" : "no") ") -> " (CSExitCode ? "valid" : "invalid")
    . "`n   Console said: " Trim(CSOutput, "`r`n") "`n`n"

; --- Date / time: AHK.Return ----------------------------------------------------
Start := A_Now
Deadline := RunCSharp('
(
    var due = DateTime.ParseExact(args[0], "yyyyMMddHHmmss", null);
    for (int added = 0; added < 10; ) {                  // add 10 working days
        due = due.AddDays(1);
        if (due.DayOfWeek is not (DayOfWeek.Saturday or DayOfWeek.Sunday)) added++;
    }
    AHK.Return(due.ToString("yyyyMMddHHmmss"));          // an AHK timestamp
)', Start)
Report .= "Date:  10 working days from today is " FormatTime(Deadline, "dddd, d MMMM yyyy")
    . "`n   (" DateDiff(Deadline, Start, "Days") " calendar days, computed by AHK's DateDiff)`n`n"

; --- Array: AHK.Return a collection, plus console output ------------------------------
Scores := [88, 92.5, 71, 100, 64]
Graded := RunCSharp('
(
    using System.Globalization;

    var scores = args.Select(a => double.Parse(a, CultureInfo.InvariantCulture)).ToArray();
    Console.WriteLine($"Average: {scores.Average()}");
    AHK.Return(scores.Select(s => s >= 90 ? "A" : s >= 80 ? "B" : s >= 70 ? "C" : "F"));   // one grade per line
)', Scores*)
Grades := StrSplit(Graded, "`n")                          ; -> AHK array, same order as Scores
Report .= "Array:  " Trim(CSOutput, "`r`n") "`n"
for i, Score in Scores
    Report .= "   " Score " -> " Grades[i] "`n"
Report .= "`n"

; --- Map: key=value lines, with a record type ------------------------------------
Stock := Map("apples", 12, "pears", 0, "plums", 5, "cherries", 40)
Restock := RunCSharp('
(
    var items = args[0].Split('\n').Select(Item.Parse).ToList();
    AHK.Return(items.Where(i => i.Qty < 10).Select(i => $"{i.Name}={20 - i.Qty}"));   // order 20 of anything below 10

    // Types must come after the top-level statements
    record Item(string Name, int Qty) {
        public static Item Parse(string line) {
            var parts = line.Split('=');
            return new Item(parts[0], int.Parse(parts[1]));
        }
    }
)', MapToLines(Stock))
Order := LinesToMap(Restock)                              ; back into an AHK Map
Report .= "Map:  restock order`n"
for Fruit, Qty in Order
    Report .= "   " Fruit ": " Qty "`n"

MsgBox Report, "AHK <-> C# data types (top-level statements)"

MapToLines(M) {
    Out := ""
    for Key, Value in M
        Out .= (Out = "" ? "" : "`n") Key "=" Value
    return Out
}

LinesToMap(Lines) {
    M := Map()
    for Line in StrSplit(Lines, "`n")
        if Line != ""
            Parts := StrSplit(Line, "=", , 2), M[Parts[1]] := Parts[2]
    return M
}
