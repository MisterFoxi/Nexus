// Temporary FURWARE text clear. Install in the HUD ROOT prim.
// Stop alphabet tests and both renderers first, or they can overwrite the blank text.
// Clears P0_Table1 and P0_Table2 only; does not change font/color, icons or digits.

// Maintenance tool only: running alongside renderers can repeatedly overwrite their names with blanks.
clearTables()
{
    string row = "                        "; // 24 spaces.
    string blank = llDumpList2String([row, row, row, row], "\n");
    llMessageLinked(LINK_SET, 0, blank, (key)"fw_data:P0_Table1");
    llMessageLinked(LINK_SET, 0, blank, (key)"fw_data:P0_Table2");
}

default
{
    state_entry() { clearTables(); }
    on_rez(integer parameter) { llResetScript(); }
    link_message(integer sender, integer number, string payload, key id)
    {
        if ((string)id == "fw_ready") clearTables();
    }
}
