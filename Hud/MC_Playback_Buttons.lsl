// ROOT-only visual library for atlas_playback_buttons_2x2_v1.
// 918340 LOAD: exact texture inventory name, or empty for DEFAULT_ATLAS.
// 918341 SHOW: JSON [primName, face, label], label START/CONT/PAUSE/STOP.
// 918342 STATE: STOPPED (unused), PLAYING, PAUSED, USED or SPOILED.
// 918343 STATUS: READY/LOADED/SHOWN:label/STATE:state/UNLOADED/ERROR:reason.
// Also follows confirmed player status 918333 directly for texture updates.
// Replies echo request id. No touches, playback commands, or timers are owned here.
integer LOAD = 918340;
integer SHOW = 918341;
integer STATE = 918342;
integer STATUS = 918343;
string DEFAULT_ATLAS = "atlas_buttons";
string START_PRIM = "P1_CUT";
string STOP_PRIM = "P1_STOP";
integer START_FACE = 2;
integer STOP_FACE = 2;
integer DIAGNOSTIC_CHANNEL = 918344; // Owner chat: /918344 buttons (read-only).
string gAtlas;
integer gUsed;
string gLastError;

reply(string text, key ticket)
{
    if (llSubStringIndex(text, "ERROR:") == 0 && text != gLastError)
    {
        llOwnerSay("[Button textures] " + text);
        gLastError = text;
    }
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

string defaultAtlas()
{
    if (llGetInventoryType(DEFAULT_ATLAS) == INVENTORY_TEXTURE) return DEFAULT_ATLAS;
    if (llGetInventoryType("atlas_playback_buttons_2x2_v1") == INVENTORY_TEXTURE) return "atlas_playback_buttons_2x2_v1";
    if (llGetInventoryType("atlas_playback_buttons_2x2_v1.png") == INVENTORY_TEXTURE) return "atlas_playback_buttons_2x2_v1.png";
    return "";
}

string surfaceError(string name, integer link, integer face)
{
    if (!link) return "ERROR:Missing or duplicate button prim: " + name;
    if (!validFace(link, face)) return "ERROR:" + name + " face " + (string)face
        + " is invalid; prim has " + (string)llGetLinkNumberOfSides(link) + " faces";
    return "";
}

inspectButton(string name, integer face)
{
    integer link = findPrim(name);
    string error = surfaceError(name, link, face);
    if (error != "") { llOwnerSay("[Button textures] " + error); return; }
    list texture = llGetLinkPrimitiveParams(link, [PRIM_TEXTURE, face]);
    llOwnerSay("[Button textures] " + name + " link=" + (string)link + " face=" + (string)face
        + " texture=" + llList2String(texture, 0) + " repeats=" + llList2String(texture, 1)
        + " offset=" + llList2String(texture, 2));
}

diagnose()
{
    string available = defaultAtlas();
    if (available == "") available = "MISSING";
    llOwnerSay("[Button textures] Script running; active atlas=" + gAtlas + "; available atlas=" + available);
    inspectButton(START_PRIM, START_FACE);
    inspectButton(STOP_PRIM, STOP_FACE);
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
    if (value == "PLAYING" || value == "PAUSED" || value == "USED" || value == "SPOILED") gUsed = TRUE;
    if (value == "STOPPED" && gUsed) value = "USED";
    integer left = 0; // START
    integer right = 3; // STOP
    if (value == "PLAYING") left = 2; // PAUSE / STOP; visual selection only.
    else if (value == "PAUSED" || value == "USED" || value == "SPOILED") left = 1;
    else if (value != "STOPPED")
    { reply("ERROR:Unknown button state", ticket); return; }
    integer startLink = findPrim(START_PRIM);
    integer stopLink = findPrim(STOP_PRIM);
    // Validate both before writing either; duplicate surface configuration is invalid.
    string error = surfaceError(START_PRIM, startLink, START_FACE);
    if (error == "") error = surfaceError(STOP_PRIM, stopLink, STOP_FACE);
    if (error == "" && startLink == stopLink && START_FACE == STOP_FACE)
        error = "ERROR:Both button names target the same surface";
    if (error != "") { reply(error, ticket); return; }
    showFrame(startLink, START_FACE, left);
    showFrame(stopLink, STOP_FACE, right);
    if (value == "SPOILED")
    {
        llSetLinkPrimitiveParamsFast(startLink, [PRIM_COLOR, START_FACE, <0.4, 0.4, 0.4>, 1.0]);
        llSetLinkPrimitiveParamsFast(stopLink, [PRIM_COLOR, STOP_FACE, <0.4, 0.4, 0.4>, 1.0]);
    }
    reply("STATE:" + value, ticket);
}

default
{
    state_entry()
    {
        llListen(DIAGNOSTIC_CHANNEL, "", llGetOwner(), "");
        list session = llJson2List(llLinksetDataRead("mc:chop:session"));
        gUsed = llList2Integer(session, 0) || llLinksetDataRead("mc:simple:craft_started") == "1";
        reply("READY", NULL_KEY);
    }

    link_message(integer sender, integer number, string text, key ticket)
    {
        if (sender != llGetLinkNumber()) return;
        // Observe CONFIRMED animation states directly. Never send playback/touch commands.
        if (number == 918333 && (text == "PLAYING" || text == "PAUSED" || text == "REST"))
        {
            if (gAtlas == "")
            {
                string name = defaultAtlas();
                if (name == "")
                { reply("ERROR:Missing button atlas in ROOT inventory", ticket); return; }
                gAtlas = name;
            }
            if (text == "REST")
            {
                if (gUsed) showState("USED", ticket);
                else showState("STOPPED", ticket);
            }
            else showState(text, ticket);
            return;
        }
        if (number == 918317 && (text == "DISCARD_DONE" || text == "CRAFT_DONE") && ticket != NULL_KEY
            && llLinksetDataRead("mc:simple:craft_started") != "1")
        {
            gUsed = FALSE;
            if (gAtlas != "") showState("STOPPED", ticket);
            return;
        }
        if (number == LOAD)
        {
            if (text == "")
            {
                text = defaultAtlas();
                if (text == "")
                { reply("ERROR:Missing button atlas in ROOT inventory (atlas_buttons or atlas_playback_buttons_2x2_v1[.png])", ticket); return; }
            }
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

    listen(integer channel, string name, key source, string text)
    {
        if (channel == DIAGNOSTIC_CHANNEL && source == llGetOwner()
            && llToLower(llStringTrim(text, STRING_TRIM)) == "buttons") diagnose();
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
