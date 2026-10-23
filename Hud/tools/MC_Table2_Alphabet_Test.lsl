// Temporary FURWARE alphabet test. Install in the HUD ROOT prim.
// Stop MC_Render_Selected while testing; leave FURWARE running.
// Table P0_Table2 must already be configured as 4 rows x 24 characters.
// Existing font and color are preserved. Remove this script after testing.
string TABLE_NAME = "P0_Table2";

string padded(string text)
{
    return llGetSubString(text + "                        ", 0, 23);
}

// Diagnostic output intentionally replaces Selected text; remove the tool before normal operation.
showAlphabet()
{
    list lines = [
        padded("ABCDEFGHIJKLMNOPQRSTUVWX"),
        padded("YZ"),
        padded("abcdefghijklmnopqrstuvwx"),
        padded("yz")
    ];
    llMessageLinked(LINK_SET, 0, "a=left;w=none;tags=off", (key)("fw_conf:" + TABLE_NAME));
    llMessageLinked(LINK_SET, 0, llDumpList2String(lines, "\n"), (key)("fw_data:" + TABLE_NAME));
}

default
{
    state_entry() { showAlphabet(); }
    on_rez(integer parameter) { llResetScript(); }
    link_message(integer sender, integer number, string payload, key id)
    {
        if ((string)id == "fw_ready") showAlphabet();
    }
}
