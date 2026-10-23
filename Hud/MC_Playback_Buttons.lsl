// ROOT-only visual library for atlas_playback_buttons_2x2_v1.
// 918340 LOAD: exact texture inventory name, or empty for DEFAULT_ATLAS.
// 918341 SHOW: JSON [primName, face, label], label START/CONT/PAUSE/STOP.
// 918342 STATE: STOPPED/PLAYING/PAUSED, using configured button pair below.
// 918343 STATUS: READY/LOADED/SHOWN:label/STATE:state/UNLOADED/ERROR:reason.
// Replies echo request id. No touches, playback commands, or timers are owned here.
integer LOAD = 918340;
integer SHOW = 918341;
integer STATE = 918342;
integer STATUS = 918343;
string DEFAULT_ATLAS = "atlas_buttons";
string START_PRIM = "P1_CUT";
string STOP_PRIM = "P1_STOP";
integer START_FACE = 0;
integer STOP_FACE = 0;
string gAtlas;

reply(string text, key ticket)
{
    llMessageLinked(LINK_THIS, STATUS, text, ticket);
}

integer findPrim(string name)
{
    name = llToLower(llStringTrim(name, STRING_TRIM));
    if (name == "") return 0;
    integer found;
    integer i;
    for (i = 1; i <= llGetNumberOfPrims(); ++i)
    {
        if (llToLower(llStringTrim(llGetLinkName(i), STRING_TRIM)) == name)
        {
            if (found) return 0;
            found = i;
        }
    }
    return found;
}

integer frameFor(string label)
{
    if (label == "START") return 0;
    if (label == "CONT") return 1;
    if (label == "PAUSE") return 2;
    if (label == "STOP") return 3;
    return -1;
}

integer validFace(integer link, integer face)
{
    if (link < 1 || face < 0) return FALSE;
    return face < llGetLinkNumberOfSides(link);
}

showFrame(integer link, integer face, integer frame)
{
    float u = -0.25 + (float)(frame % 2) * 0.5;
    float v = 0.25 - (float)(frame / 2) * 0.5;
    llSetLinkTextureAnim(link, 0, face, 1, 1, 0.0, 0.0, 0.0);
    llSetLinkPrimitiveParamsFast(link, [
        PRIM_TEXTURE, face, gAtlas, <0.5, 0.5, 0.0>, <u, v, 0.0>, 0.0,
        PRIM_COLOR, face, <1.0, 1.0, 1.0>, 1.0,
        PRIM_FULLBRIGHT, face, TRUE
    ]);
}

showButton(string payload, key ticket)
{
    // Check types before conversion: malformed face values must not become face 0.
    if (llJsonValueType(payload, []) != JSON_ARRAY)
    { reply("ERROR:SHOW expects [primName, face, label]", ticket); return; }
    list args = llJson2List(payload);
    if (llGetListLength(args) != 3
        || llJsonValueType(payload, [0]) != JSON_STRING
        || llJsonValueType(payload, [1]) != JSON_NUMBER
        || llJsonValueType(payload, [2]) != JSON_STRING)
    { reply("ERROR:SHOW expects [primName, face, label]", ticket); return; }
    float faceValue = (float)llList2String(args, 1);
    integer face = (integer)faceValue;
    if (faceValue != (float)face)
    { reply("ERROR:Face must be an integer", ticket); return; }
    string label = llToUpper(llStringTrim(llList2String(args, 2), STRING_TRIM));
    integer frame = frameFor(label);
    integer link = findPrim(llList2String(args, 0));
    if (frame < 0)
    { reply("ERROR:Unknown button label", ticket); return; }
    if (!validFace(link, face))
    { reply("ERROR:Missing or duplicate prim, or invalid face", ticket); return; }
    showFrame(link, face, frame);
    reply("SHOWN:" + label, ticket);
}

showState(string value, key ticket)
{
    value = llToUpper(llStringTrim(value, STRING_TRIM));
    integer left = 0; // START
    integer right = 3; // STOP
    if (value == "PLAYING") right = 2; // PAUSE
    else if (value == "PAUSED") left = 1; // CONT
    else if (value != "STOPPED")
    { reply("ERROR:STATE expects STOPPED, PLAYING or PAUSED", ticket); return; }
    integer startLink = findPrim(START_PRIM);
    integer stopLink = findPrim(STOP_PRIM);
    // Validate both before writing either; duplicate surface configuration is invalid.
    if (!validFace(startLink, START_FACE) || !validFace(stopLink, STOP_FACE)
        || (startLink == stopLink && START_FACE == STOP_FACE))
    { reply("ERROR:Invalid button pair names or faces", ticket); return; }
    showFrame(startLink, START_FACE, left);
    showFrame(stopLink, STOP_FACE, right);
    reply("STATE:" + value, ticket);
}

default
{
    state_entry() { reply("READY", NULL_KEY); }

    link_message(integer sender, integer number, string text, key ticket)
    {
        if (sender != llGetLinkNumber()) return;
        if (number == LOAD)
        {
            if (text == "") text = DEFAULT_ATLAS;
            if (llGetInventoryType(text) != INVENTORY_TEXTURE)
            { reply("ERROR:Texture missing from ROOT inventory: " + text, ticket); return; }
            gAtlas = text; // Failed LOAD leaves the previous atlas active.
            reply("LOADED", ticket);
            return;
        }
        if (number != SHOW && number != STATE) return;
        if (gAtlas == "" || llGetInventoryType(gAtlas) != INVENTORY_TEXTURE)
        { reply("ERROR:LOAD an inventory texture before SHOW or STATE", ticket); return; }
        if (number == SHOW) showButton(text, ticket);
        else showState(text, ticket);
    }

    changed(integer change)
    {
        if (change & (CHANGED_OWNER | CHANGED_LINK)) { llResetScript(); return; }
        if ((change & CHANGED_INVENTORY) && gAtlas != "")
        {
            if (llGetInventoryType(gAtlas) != INVENTORY_TEXTURE)
            {
                gAtlas = "";
                reply("UNLOADED", NULL_KEY);
            }
        }
    }

    on_rez(integer parameter) { llResetScript(); }
}
