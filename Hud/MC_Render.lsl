// Shared rendering implementation. Install in ROOT beside FURWARE.
// One instance per panel: PANEL = "NEARBY" or "SELECTED".
// Selected uses the same development face layout as Nearby; settings stay explicit.
string PANEL = "NEARBY";
integer SELECTED_QTY_FACE = 4;
integer SELECTED_ICON_FACE = 2;
integer SELECTED_PAGE_FACE = 4;
integer SELECTED_TOTAL_FACE = 4;
integer VIEW = 918290;
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

// REVIEW: duplicate normalized names select the first match; detect ambiguity to avoid writing to the wrong prim.
integer findLink(string name)
{
    integer i;
    for (i = 1; i <= llGetNumberOfPrims(); ++i)
        if (llToLower(llStringTrim(llGetLinkName(i), STRING_TRIM)) == llToLower(name)) return i;
    return 0;
}

// Log assembly mistakes during setup; validFace guards the actual writes.
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
    string tens = "P0_NEAR_QTY_TENS_";
    string units = "P0_NEAR_QTY_UNIT_";
    string icons = "P0_NEAR_ICON_";
    string page = "P0_PAGE";
    string total = "P0_PAGE_TOTAL";
    gTable = "P0_Table1";
    gQtyFace = 4; gIconFace = 2; gPageFace = 4; gTotalFace = 4;
    if (PANEL == "SELECTED")
    {
        gTable = "P0_Table2";
        tens = "P0_SEL_QTY_TENS_";
        units = "P0_SEL_QTY_"; // Exact existing prim name, no UNIT suffix.
        icons = "P0_SEL_ICON_";
        page = "P0_SELECTED_ACTUAL";
        total = "P0_SELECTED_TOTAL";
        gQtyFace = SELECTED_QTY_FACE; gIconFace = SELECTED_ICON_FACE;
        gPageFace = SELECTED_PAGE_FACE; gTotalFace = SELECTED_TOTAL_FACE;
    }
    gPageLink = checkedLink(page, gPageFace);
    gTotalLink = checkedLink(total, gTotalFace);
    gTens = []; gUnits = []; gIcons = [];
    integer i;
    for (i = 1; i <= 4; ++i)
    {
        gTens += [checkedLink(tens + (string)i, gQtyFace)];
        gUnits += [checkedLink(units + (string)i, gQtyFace)];
        gIcons += [checkedLink(icons + (string)i, gIconFace)];
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
    // Single digit per face. Out-of-range values are hidden while navigation remains functional.
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

// Flatten control characters and fit the existing 24-character FURWARE row.
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
        if (PANEL != "NEARBY" && PANEL != "SELECTED")
        { llOwnerSay("[Render] Invalid PANEL setting."); return; }
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
        // REVIEW: decoding has no field-length budget; same-root producers must bound the view payload.
        list view = llParseStringKeepNulls(payload, ["|"], []);
        if (llGetListLength(view) != 18) return;
        if (llList2Integer(view, 0) < 1 || llList2Integer(view, 1) < llList2Integer(view, 0)) return;
        integer i;
        for (i = 0; i < 18; ++i)
            view = llListReplaceList(view, [llUnescapeURL(llList2String(view, i))], i, i);
        gView = view;
        render();
    }
}
