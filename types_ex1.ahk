#Requires AutoHotkey v2.0 64-bit
#Include "Csx-in-AHK.ahk"
; Passing AHK variables to C#, processing them, and using the results back in AHK.
;
; Going in:  every value reaches C# as a string in args[]. Numbers keep AHK's format ('.' decimal point),
;            true/false become "1"/"0", dates are AHK timestamps (YYYYMMDDHH24MISS).
;            Arrays can be spread over several arguments with Arr*; a Map can be sent as "key=value" lines.
; Coming out: numbers use '.' as decimal point, bool -> 1/0, collections -> one item per line.
;
; Parse numbers in C# with CultureInfo.InvariantCulture, so they also work on systems that use ',' as decimal point.
; Note: inside a '( ... )' continuation section, quote marks are literal, so AHK variables cannot be spliced into
; the C# code there. Pass them as arguments instead.

; --- Integer and Float -------------------------------------------------------
Count := 7
Price := 19.95
Total := RunCsx('
(
    using System.Globalization;
    int count = int.Parse(args[0]);
    double price = double.Parse(args[1], CultureInfo.InvariantCulture);
    return Math.Round(count * price * 1.08, 2);       // add 8% tax
)', Count, Price)
; AHK shows floats with full precision (19.95 -> 19.949999999999999), so format them for display
Report := Format("Integer/Float:  {} x {:.2f} + tax = {}`n", Count, Price, Total)
Report .= Format("   AHK can compute with it:  Total / 2 = {:.2f}`n`n", Total / 2)

; --- String ------------------------------------------------------------------
Text := "the quick brown fox jumps over the lazy dog"
TitleCase := RunCsx('System.Globalization.CultureInfo.InvariantCulture.TextInfo.ToTitleCase(args[0])', Text)
Report .= "String:  " TitleCase "`n`n"

; --- Boolean -----------------------------------------------------------------
IsAdmin := A_IsAdmin             ; true/false in AHK
Shout := true
Message := RunCsx('
(
    bool isAdmin = args[0] == "1", shout = args[1] == "1";
    var msg = isAdmin ? "running as admin" : "running as a normal user";
    return shout ? msg.ToUpper() : msg;
)', IsAdmin, Shout)
IsEven := RunCsx('int.Parse(args[0]) % 2 == 0', Count)   ; a C# bool comes back as 1/0
Report .= "Boolean:  " Message "`n   Is " Count " even? " (IsEven ? "yes" : "no") "`n`n"

; --- Date / time -------------------------------------------------------------
Start := A_Now
Deadline := RunCsx('
(
    var start = DateTime.ParseExact(args[0], "yyyyMMddHHmmss", null);
    var due = start;
    for (int added = 0; added < 10; ) {                // add 10 working days
        due = due.AddDays(1);
        if (due.DayOfWeek is not (DayOfWeek.Saturday or DayOfWeek.Sunday)) added++;
    }
    return due.ToString("yyyyMMddHHmmss");             // an AHK timestamp
)', Start)
Report .= "Date:  10 working days from today is " FormatTime(Deadline, "dddd, d MMMM yyyy")
    . "`n   (" DateDiff(Deadline, Start, "Days") " calendar days, computed by AHK's DateDiff)`n`n"

; --- Array -------------------------------------------------------------------
Scores := [88, 92.5, 71, 100, 64]
Stats := RunCsx('
(
    using System.Globalization;
    var nums =args.Select(a => double.Parse(a, CultureInfo.InvariantCulture)).ToArray();
    return new object[] { nums.Min(), nums.Max(), nums.Average(), string.Join(" ", nums.OrderDescending()) };
)', Scores*)
Stats := StrSplit(Stats, "`n")                            ; one result per line -> AHK array
Report .= Format("Array:  min {}, max {}, average {}`n   Sorted: {}`n`n", Stats*)

; --- Map ---------------------------------------------------------------------
Stock := Map("apples", 12, "pears", 0, "plums", 5, "cherries", 40)
Restock := RunCsx('
(
    var stock = args[0].Split("\n").Select(l => l.Split("=")).ToDictionary(p => p[0], p => int.Parse(p[1]));
    // Order 20 of anything below 10, return the order as "key=value" lines
    return stock.Where(kv => kv.Value < 10).Select(kv => $"{kv.Key}={20 - kv.Value}");
)', MapToLines(Stock))
Order := LinesToMap(Restock)                              ; back into an AHK Map
Report .= "Map:  restock order`n"
for Fruit, Qty in Order
    Report .= "   " Fruit ": " Qty "`n"

MsgBox Report, "AHK <-> C# data types"

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
