#define SCRIPT_NAME    "NX_Render_P3_NEAR"
#define SCRIPT_VERSION "v0.1.2"
#include "nexus_header"

// Shared rendering implementation (copy of NX_Render preset to the P3_NEAR panel). Install in ROOT beside
// FURWARE and NX_P3_Controller. Renders the available-containers table of the récipient page.
string PANEL = "P3_NEAR";
integer VIEW = 918290;
integer RENDER_READY = 918291;
string ATLAS_NAME = "atlas-quantites-fleches-v2";
integer FACE = 1;
key DEFAULT_ICON = "f1076325-9b08-d475-fd4c-346e4e93f33d";
string gTable;
integer gPageLink;
list gUnits;
list gIcons;
// View: current page, total pages, then 4 x [name, quantity, icon, occupied].
list gView;

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
    string quantity = "P0_QTY_";
    string icon = "P0_Icon_";
    gTable = "P0_Table1";
    if (PANEL == "SELECTED")
    {
        gTable = "P0_Table2";
        quantity = "P0_SEL_QTY_";
        icon = "P0_SEL_ICON_";
    }
    else if (PANEL == "P3_NEAR")
    {
        gTable = "P3_Table1";
        quantity = "P3_QTY_";
        icon = "P3_Icon_";
    }
    else if (PANEL == "P3_SEL")
    {
        gTable = "P3_Table2";
        quantity = "P3_Sel_QTY_";
        icon = "P3_Sel_Icon_";
    }
    gPageLink = 0;
    if (PANEL == "NEARBY") gPageLink = checkedLink("P0_PAGE", FACE);
    else if (PANEL == "SELECTED") gPageLink = checkedLink("P0_SEL_PAGE", FACE);
    gUnits = []; gIcons = [];
    integer i;
    for (i = 0; i < 4; ++i)
    {
        gUnits += [findLink(quantity + (string)i)];
        gIcons += [findLink(icon + (string)i)];
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

integer atlasCell(integer link, string atlas, integer frame, integer columns, integer rows)
{
    if (!validFace(link, FACE)) return FALSE;
    if (llGetInventoryType(atlas) != INVENTORY_TEXTURE) atlas += ".png";
    if (llGetInventoryType(atlas) != INVENTORY_TEXTURE) return FALSE;
    float width = 1.0 / (float)columns;
    float height = 1.0 / (float)rows;
    float u = -0.5 + ((float)(frame % columns) + 0.5) * width;
    float v = 0.5 - ((float)(frame / columns) + 0.5) * height;
    llSetLinkPrimitiveParamsFast(link, [
        PRIM_TEXTURE, FACE, atlas, <width, height, 0.0>, <u, v, 0.0>, 0.0,
        PRIM_COLOR, FACE, <1.0, 1.0, 1.0>, 1.0]);
    return TRUE;
}

string displayName(string name)
{
    name = llDumpList2String(llParseStringKeepNulls(name,
        [llUnescapeURL("%0A"), llUnescapeURL("%0D"), llUnescapeURL("%09")], []), " ");
    if (llStringLength(name) > 24) return llGetSubString(name, 0, 20) + "...";
    while (llStringLength(name) < 24) name += " ";
    return name;
}

render()
{
    if (llGetListLength(gView) != 18) return;
    list lines;
    integer row;
    for (row = 0; row < 4; ++row)
    {
        integer offset = 2 + row * 4;
        integer units = llList2Integer(gUnits, row);
        integer iconLink = llList2Integer(gIcons, row);
        integer occupied = llList2Integer(gView, offset + 3);
        integer quantity = llList2Integer(gView, offset + 1);
        string name = "";
        if (occupied) name = llList2String(gView, offset);
        integer quantityShown;
        if (occupied && quantity >= 1 && quantity <= 10)
            quantityShown = atlasCell(units, ATLAS_NAME, quantity - 1, 4, 4);
        if (!quantityShown)
        {
            hide(units, FACE);
            if (occupied && quantity > 0)
            {
                string suffix = " " + (string)quantity;
                name = llGetSubString(name, 0, 23 - llStringLength(suffix)) + suffix;
            }
        }
        lines += [displayName(name)];
        if (!occupied) hide(iconLink, FACE);
        else if (validFace(iconLink, FACE))
        {
            key icon = (key)llStringTrim(llList2String(gView, offset + 2), STRING_TRIM);
            integer hasIcon = FALSE;
            if (icon) hasIcon = TRUE;
            if (hasIcon || !atlasCell(iconLink, ATLAS_NAME, 12, 4, 4))
            {
                if (!hasIcon) icon = DEFAULT_ICON;
                llSetLinkPrimitiveParamsFast(iconLink, [
                    PRIM_TEXTURE, FACE, icon, <1.0, 1.0, 0.0>, ZERO_VECTOR, 0.0,
                    PRIM_COLOR, FACE, <1.0, 1.0, 1.0>, 1.0]);
            }
        }
    }
    if (PANEL == "P3_SEL") lines = llList2List(lines, 0, 0);
    llMessageLinked(LINK_SET, 0, "a=left;w=none;tags=off", (key)("fw_conf:" + gTable));
    llMessageLinked(LINK_SET, 0, llDumpList2String(lines, "\n"), (key)("fw_data:" + gTable));
    if (PANEL == "P3_NEAR")
    {
        atlasCell(findLink("P2_TITLE"), "atlas-hud-titres-v2", 2, 2, 2);
        atlasCell(findLink("P2_ACTION1"), "atlas-hud-actions-v2", 0, 2, 2);
        atlasCell(findLink("P2_ACTION2"), "atlas-hud-actions-v2", 3, 2, 2);
    }
}

default
{
    state_entry()
    { nexusBoot();
        if (PANEL != "NEARBY" && PANEL != "SELECTED" && PANEL != "P3_NEAR" && PANEL != "P3_SEL")
        { llOwnerSay("[Render] Invalid PANEL setting."); return; }
        configure();
        gView = [1, 1, "", 0, "", 0, "", 0, "", 0, "", 0, "", 0, "", 0, "", 0];
        render();
        llMessageLinked(LINK_THIS, RENDER_READY, PANEL, NULL_KEY);
    }
    on_rez(integer parameter) { llResetScript(); }
    changed(integer change)
    {
        if (change & CHANGED_LINK) configure();
        if (change & (CHANGED_LINK | CHANGED_INVENTORY)) render();
    }
    link_message(integer sender, integer number, string payload, key panel)
    {
        if (number == NEXUS_MEM_REPORT) { nexusMemReport(); return; }
        if ((string)panel == "fw_ready") { render(); return; }
        if (sender != llGetLinkNumber() || number != VIEW || (string)panel != PANEL) return;
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
