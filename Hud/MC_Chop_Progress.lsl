// ROOT. Self-initializing renderer for P1_PROGRESS; timing belongs to MC_P1_Animation.
// 918350 LOAD: inventory texture name, empty = known default names below.
// 918351 SHOW: active seconds, IDLE (empty board), or SPOILED. Replies use 918353, echo id.
integer LOAD = 918350;
integer SHOW = 918351;
integer STATUS = 918353;
string DEFAULT_ATLAS = "atlas_progress";
string DISPLAY_PRIM = "P1_PROGRESS";
integer FACE = 2;
float FULL_SECONDS = 10.0;
string gAtlas;
integer gLast = -1;
integer gLink;
string gLastError;

reply(string text, key ticket)
{
    llMessageLinked(LINK_THIS, STATUS, text, ticket);
}

fail(string text, key ticket)
{
    if (text != gLastError) llOwnerSay("[Chop progress] " + text);
    gLastError = text;
    reply("ERROR:" + text, ticket);
}

integer findDisplay()
{
    integer found;
    integer i;
    for (i = 1; i <= llGetNumberOfPrims(); ++i)
    {
        if (llToLower(llStringTrim(llGetLinkName(i), STRING_TRIM))
            == llToLower(llStringTrim(DISPLAY_PRIM, STRING_TRIM)))
        {
            if (found) return 0;
            found = i;
        }
    }
    return found;
}

integer target(key ticket)
{
    integer display = findDisplay();
    if (display < 1)
    { fail("Missing or duplicate display prim: " + DISPLAY_PRIM, ticket); return 0; }
    if (FACE < 0 || FACE >= llGetLinkNumberOfSides(display))
    { fail("Invalid face " + (string)FACE + " on " + DISPLAY_PRIM, ticket); return 0; }
    return display;
}

string savedValue()
{
    string saved = llLinksetDataRead("mc:chop:session");
    if (saved == "")
    {
        if (llLinksetDataRead("mc:simple:craft_started") == "1") return "SPOILED";
        return "IDLE";
    }
    list values = llJson2List(saved);
    if (llJsonValueType(saved, []) != JSON_ARRAY || llGetListLength(values) != 3
        || llJsonValueType(saved, [0]) != JSON_NUMBER
        || llJsonValueType(saved, [1]) != JSON_NUMBER
        || llJsonValueType(saved, [2]) != JSON_NUMBER) return "SPOILED";
    if (llList2Integer(values, 1)) return "SPOILED";
    if (llList2Integer(values, 0)) return llList2String(values, 2);
    return "IDLE";
}

integer show(string text, key ticket)
{
    integer stage;
    integer spoiled = text == "SPOILED";
    if (spoiled) stage = 0;
    else if (text == "IDLE") stage = 0; // Empty board, without grade or gauge.
    else
    {
        if (llJsonValueType(text, []) != JSON_NUMBER)
        { fail("SHOW expects nonnegative seconds, IDLE or SPOILED", ticket); return FALSE; }
        float seconds = (float)text;
        if (seconds < 0.0 || FULL_SECONDS <= 0.0)
        { fail("Invalid seconds or FULL_SECONDS", ticket); return FALSE; }
        if (seconds >= FULL_SECONDS) stage = 5;
        else stage = 1 + (integer)(seconds * 4.0 / FULL_SECONDS);
    }
    integer display = target(ticket);
    if (!display) return FALSE;
    integer visual = stage;
    if (spoiled) visual = 6;
    if (visual != gLast || display != gLink)
    {
        float height = 0.484375;
        float v = 0.2578125;
        if (stage >= 3) { height = 0.48828125; v = -0.228515625; }
        float u = -0.333333333 + (float)(stage % 3) / 3.0;
        string label = "";
        if (spoiled) label = "Spoiled";
        llSetLinkTextureAnim(display, 0, FACE, 1, 1, 0.0, 0.0, 0.0);
        llSetLinkPrimitiveParamsFast(display, [
            PRIM_TEXTURE, FACE, gAtlas, <0.333333333, height, 0.0>, <u, v, 0.0>, 0.0,
            PRIM_COLOR, FACE, <1.0, 1.0, 1.0>, 1.0,
            PRIM_FULLBRIGHT, FACE, TRUE,
            PRIM_TEXT, label, <1.0, 0.2, 0.1>, 1.0
        ]);
        gLast = visual;
        gLink = display;
    }
    gLastError = "";
    reply("SHOWN:" + (string)visual, ticket);
    return TRUE;
}

loadTexture(string name, key ticket)
{
    if (name == "")
    {
        name = DEFAULT_ATLAS;
        // Accept the exported filename as well as the short SL inventory name.
        if (llGetInventoryType(name) != INVENTORY_TEXTURE) name = "atlas_chop_progress_v2";
        if (llGetInventoryType(name) != INVENTORY_TEXTURE) name = "atlas_chop_progress_v2.png";
    }
    if (llGetInventoryType(name) != INVENTORY_TEXTURE)
    {
        fail("Missing texture in this prim. Put MC_Chop_Progress and atlas_progress "
            + "(or atlas_chop_progress_v2) together in ROOT. Requested: " + name, ticket);
        return;
    }
    if (!target(ticket)) return; // LOADED means a validated surface was initialized.
    string previous = gAtlas;
    gAtlas = name;
    gLast = -1;
    if (!show(savedValue(), ticket)) return;
    reply("LOADED", ticket);
    if (previous != name)
        llOwnerSay("[Chop progress] Initialized " + DISPLAY_PRIM + " face " + (string)FACE + " with " + name + ".");
}

default
{
    state_entry()
    {
        loadTexture("", NULL_KEY); // Draw even if no controller handshake arrives.
        reply("READY", NULL_KEY);
    }
    link_message(integer sender, integer number, string text, key ticket)
    {
        if (sender != llGetLinkNumber()) return;
        if (number == LOAD) { loadTexture(text, ticket); return; }
        if (number != SHOW) return;
        if (gAtlas == "" || llGetInventoryType(gAtlas) != INVENTORY_TEXTURE)
        { fail("LOAD progress atlas first", ticket); return; }
        show(text, ticket);
    }
    changed(integer change)
    {
        if (change & (CHANGED_OWNER | CHANGED_LINK)) { llResetScript(); return; }
        if (change & CHANGED_INVENTORY)
        {
            if (gAtlas != "" && llGetInventoryType(gAtlas) != INVENTORY_TEXTURE)
            { gAtlas = ""; gLast = -1; reply("UNLOADED", NULL_KEY); }
            if (gAtlas == "")
            {
                loadTexture("", NULL_KEY);
                reply("READY", NULL_KEY); // Replay the current live state after recovery.
            }
        }
    }
    on_rez(integer parameter) { llResetScript(); }
}
