// ROOT beside FURWARE. Craft page only; never targets P0 prims.
// P1_Table1 must already be configured as four rows x 24 characters.
string PANEL = "P1";
integer P1_QTY_FACE = 4;
integer P1_ICON_FACE = 2;
integer P1_PAGE_FACE = 4;
integer P1_TOTAL_FACE = 4;
integer VIEW = 918314;
integer RENDER_READY = 918291;
string ATLAS_NAME = "medieval_digits_atlas_5x2";
key DEFAULT_ICON = "f1076325-9b08-d475-fd4c-346e4e93f33d";
string gTable;
integer gQtyFace;
integer gIconFace;
integer gPageFace;
integer gTotalFace;
integer gPageLink;
integer gTotalLink;
list gTens;
list gUnits;
list gIcons;
// View: current page, total pages, then 4 x [name, quantity, icon, occupied].
list gView;
integer gCleared;

// REVIEW: duplicate normalized names select the first match; detect ambiguity before writing faces.
integer findLink(string name)
{
    integer i;
    for (i = 1; i <= llGetNumberOfPrims(); ++i)
        if (llToLower(llStringTrim(llGetLinkName(i), STRING_TRIM)) == llToLower(name)) return i;
    return 0;
}

integer checkedLink(string name, integer face)
{
    integer link = findLink(name);
    if (!link) llOwnerSay("[Render " + PANEL + "] Missing prim: " + name);
    else if (face < 0 || face >= llGetLinkNumberOfSides(link))
        llOwnerSay("[Render " + PANEL + "] Configure face for " + name);
    return link;
}

configure()
{
    gTable = "P1_Table1";
    gQtyFace = P1_QTY_FACE; gIconFace = P1_ICON_FACE;
    gPageFace = P1_PAGE_FACE; gTotalFace = P1_TOTAL_FACE;
    gPageLink = checkedLink("P1_ACTUAL", gPageFace);
    gTotalLink = checkedLink("P1_TOTAL", gTotalFace);
    gTens = []; gUnits = []; gIcons = [];
    integer i;
    for (i = 1; i <= 4; ++i)
    {
        gTens += [checkedLink("P1_TENS_" + (string)i, gQtyFace)];
        gUnits += [checkedLink("P1_UNIT_" + (string)i, gQtyFace)];
        gIcons += [checkedLink("P1_Icon_" + (string)i, gIconFace)];
    }
}
integer validFace(integer link, integer face)
{
    if (!link || face < 0) return FALSE;
    return face < llGetLinkNumberOfSides(link);
}

hide(integer link, integer face)
{
    if (validFace(link, face)) llSetLinkAlpha(link, 0.0, face);
}

digit(integer link, integer face, integer value)
{
    if (!validFace(link, face)) return;
    if (value < 0 || value > 9) { hide(link, face); return; }
    list texture = llGetLinkPrimitiveParams(link, [PRIM_TEXTURE, face]);
    key atlas = llList2Key(texture, 0);
    if (llGetInventoryType(ATLAS_NAME) == INVENTORY_TEXTURE)
    {
        key inventoryAtlas = llGetInventoryKey(ATLAS_NAME);
        if (inventoryAtlas != NULL_KEY) atlas = inventoryAtlas;
    }
    if (atlas == NULL_KEY || atlas == TEXTURE_TRANSPARENT)
    {
        hide(link, face);
        llOwnerSay("[Render] Apply " + ATLAS_NAME + " to " + llGetLinkName(link));
        return;
    }
    float u = -0.4 + 0.2 * (float)(value % 5);
    float v = 0.25 - 0.5 * (float)(value / 5);
    llSetLinkPrimitiveParamsFast(link, [
        PRIM_TEXTURE, face, atlas, <0.2, 0.5, 0.0>, <u, v, 0.0>, 0.0,
        PRIM_COLOR, face, <1.0, 1.0, 1.0>, 1.0]);
}

string displayName(string name)
{
    name = llDumpList2String(llParseStringKeepNulls(name,
        [llUnescapeURL("%0A"), llUnescapeURL("%0D"), llUnescapeURL("%09")], []), " ");
    if (llStringLength(name) > 24) return llGetSubString(name, 0, 20) + "...";
    while (llStringLength(name) < 24) name += " ";
    return name;
}

key resolvedIcon(string value)
{
    key icon = (key)llStringTrim(value, STRING_TRIM);
    if (icon) return icon;
    return DEFAULT_ICON;
}

render()
{
    // Keep Discard clearing authoritative even when FURWARE announces readiness again.
    if (gCleared)
    {
        integer i;
        for (i = 0; i < 4; ++i)
        {
            hide(llList2Integer(gTens, i), gQtyFace);
            hide(llList2Integer(gUnits, i), gQtyFace);
            hide(llList2Integer(gIcons, i), gIconFace);
        }
        hide(gPageLink, gPageFace); hide(gTotalLink, gTotalFace);
        string row = "                        ";
        llMessageLinked(LINK_SET, 0, llDumpList2String([row, row, row, row], "\n"), (key)("fw_data:" + gTable));
        return;
    }
    if (llGetListLength(gView) != 18) return;
    list lines;
    integer row;
    for (row = 0; row < 4; ++row)
    {
        integer offset = 2 + row * 4;
        integer tens = llList2Integer(gTens, row);
        integer units = llList2Integer(gUnits, row);
        integer iconLink = llList2Integer(gIcons, row);
        integer occupied = llList2Integer(gView, offset + 3);
        integer quantity = llList2Integer(gView, offset + 1);
        string name = "";
        if (occupied) name = llList2String(gView, offset);
        lines += [displayName(name)];
        if (!occupied || quantity <= 0 || quantity > 99)
        {
            hide(tens, gQtyFace); hide(units, gQtyFace);
            if (occupied && quantity > 99)
                llOwnerSay("[Render " + PANEL + "] Quantity exceeds two digits: " + (string)quantity);
        }
        else
        {
            if (quantity >= 10) digit(tens, gQtyFace, quantity / 10);
            else hide(tens, gQtyFace);
            digit(units, gQtyFace, quantity % 10);
        }
        if (!occupied) hide(iconLink, gIconFace);
        else if (validFace(iconLink, gIconFace))
        {
            key icon = resolvedIcon(llList2String(gView, offset + 2));
            llSetLinkPrimitiveParamsFast(iconLink, [
                PRIM_TEXTURE, gIconFace, icon, <1.0, 1.0, 0.0>, ZERO_VECTOR, 0.0,
                PRIM_COLOR, gIconFace, <1.0, 1.0, 1.0>, 1.0]);
        }
    }
    llMessageLinked(LINK_SET, 0, "a=left;w=none;tags=off", (key)("fw_conf:" + gTable));
    llMessageLinked(LINK_SET, 0, llDumpList2String(lines, "\n"), (key)("fw_data:" + gTable));
    digit(gPageLink, gPageFace, llList2Integer(gView, 0));
    digit(gTotalLink, gTotalFace, llList2Integer(gView, 1));
    if (llList2Integer(gView, 1) > 9)
        llOwnerSay("[Render " + PANEL + "] Page indicators above 9 are hidden; navigation remains available.");
}

default
{
    state_entry()
    {
        configure();
        llMessageLinked(LINK_THIS, RENDER_READY, PANEL, NULL_KEY);
    }
    on_rez(integer parameter) { llResetScript(); }
    changed(integer change)
    {
        if (change & CHANGED_LINK) { configure(); render(); }
    }
    link_message(integer sender, integer number, string payload, key panel)
    {
        if ((string)panel == "fw_ready") { render(); return; }
        if (sender != llGetLinkNumber() || number != VIEW || (string)panel != PANEL) return;
        if (payload == "CLEAR") { gCleared = TRUE; gView = []; render(); return; }
        // REVIEW: decoded fields have no length budget; accept view messages only from trusted, bounded producers.
        list view = llParseStringKeepNulls(payload, ["|"], []);
        if (llGetListLength(view) != 18) return;
        if (llList2Integer(view, 0) < 1 || llList2Integer(view, 1) < llList2Integer(view, 0)) return;
        integer i;
        for (i = 0; i < 18; ++i)
            view = llListReplaceList(view, [llUnescapeURL(llList2String(view, i))], i, i);
        gView = view;
        gCleared = FALSE;
        render();
    }
}
