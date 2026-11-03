string VERSION = "Workshop_Interface v0.9.1 (2026-11-02)";
// ROOT. Menus, player information and dedicated-HUD provisioning only.
// Reads durable identities; never writes leases, products or source stock.
integer gSessionMenu;
integer gSessionListen;
key gMenuSession = NULL_KEY;
string playerLabel(key player)
{
    if (player == NULL_KEY) return "none";
    string name = llKey2Name(player);
    if (name == "") return (string)player;
    return name + " (" + (string)player + ")";
}
string sessionInfo()
{
    list sessionData = llJson2List(llLinksetDataRead("ws:core"));
    list collector = llJson2List(llLinksetDataRead("ws:collector"));
    list config = llJson2List(llLinksetDataRead("ws:config"));
    key user = llList2Key(sessionData, 0);
    string phase = llList2String(sessionData, 4);
    key collectorUser = NULL_KEY;
    if (llList2Key(collector, 0) == llList2Key(sessionData, 3)) collectorUser = llList2Key(collector, 1);
    string workshopType = llList2String(config, 1);
    string kind = llList2String(config, 0);
    key current = user;
    if ((phase == "PRODUCT" || phase == "SETTLING") && collectorUser != NULL_KEY) current = collectorUser;
    string info = "WS type (Genre) = " + workshopType + "\nHUDKind = " + kind
        + "\nWorkshop: " + phase + "\nPlayer: " + playerLabel(current);
    if (phase != "FREE" && phase != "OFFERED" && phase != "BOUND")
        info += "\nPrepared by: " + playerLabel(user);
    return info;
}
sessionMenu()
{
    list sessionData = llJson2List(llLinksetDataRead("ws:core"));
    if (llList2String(sessionData, 4) != "BOUND") return;
    key user = llList2Key(sessionData, 0);
    key session = llList2Key(sessionData, 2);
    integer showHover = (integer)llLinksetDataRead("ws:hover");
    if (gSessionListen) llListenRemove(gSessionListen);
    gSessionMenu = -3000000 - (integer)llFrand(900000.0);
    gMenuSession = session;
    gSessionListen = llListen(gSessionMenu, "", user, "");
    string hover = "Text: OFF";
    if (showHover) hover = "Text: ON";
    llDialog(user, sessionInfo() + "\nResume, exit through the HUD stock cleanup, or toggle nearby component text.",
        ["Resume", "Exit", hover], gSessionMenu);
}
provision(key player, key session)
{
    list sessionData = llJson2List(llLinksetDataRead("ws:core"));
    list collector = llJson2List(llLinksetDataRead("ws:collector"));
    if (session == NULL_KEY) return;
    integer origin = player == llList2Key(sessionData, 0) && session == llList2Key(sessionData, 2);
    integer collecting = player == llList2Key(collector, 1) && session == llList2Key(collector, 3)
        && llList2Key(collector, 0) == llList2Key(sessionData, 3);
    if (!origin && !collecting) return;
    list config = llJson2List(llLinksetDataRead("ws:config"));
    integer development = llList2Integer(config, 5);
    string hudObject = llList2String(config, 2);
    if (development) return;
    if (player == llGetOwner())
        llRezObject(hudObject, llGetPos() + <0.0, 0.0, 1.0>, ZERO_VECTOR, ZERO_ROTATION, 0);
    else
    {
        // A rezzed inventory object keeps the station owner's ownership.
        // Give the dedicated HUD so its stock transactions belong to the actual player.
        llGiveInventory(player, hudObject);
        llRegionSayTo(player, 0, "Wear the workshop HUD you just received. Association will follow automatically.");
    }
}

outputState()
{
    list sessionData = llJson2List(llLinksetDataRead("ws:core"));
    list collector = llJson2List(llLinksetDataRead("ws:collector"));
    key run = llList2Key(sessionData, 3);
    if (llList2Key(collector, 0) != run || llList2Key(collector, 2) == NULL_KEY) return;
    list output = llJson2List(llLinksetDataRead("ws:output"));
    list dna = llParseStringKeepNulls(llList2String(output, 4), ["|"], []);
    llMessageLinked(LINK_THIS, 970211, "MCW|OUTPUT_STATE|" + llList2String(collector, 2)
        + "|" + llList2String(collector, 3) + "|" + (string)run + "|" + llList2String(output, 3)
        + "|" + llList2String(output, 5) + "|" + llEscapeURL(llGetSubString(llList2String(dna, 2), 0, 63)), run);
}

default
{
    state_entry()
    {
        llOwnerSay("[Nexus] " + VERSION);
        llMessageLinked(LINK_THIS, 970299, "INTERFACE", NULL_KEY);
    }
    link_message(integer sender, integer number, string text, key player)
    {
        if (sender != llGetLinkNumber()) return;
        if (number == 970298) { llMessageLinked(LINK_THIS, 970299, "INTERFACE", NULL_KEY); return; }
        if (number == 970290) { llOwnerSay("[Workshop interface] Free: " + (string)llGetFreeMemory()); return; }
        if (number != 970260) return;
        if (text == "INFO") llRegionSayTo(player, 0, sessionInfo());
        else if (text == "MENU")
        {
            list sessionData = llJson2List(llLinksetDataRead("ws:core"));
            if (player == llList2Key(sessionData, 0)) sessionMenu();
        }
        else if (llSubStringIndex(text, "PROVISION|") == 0) provision(player, (key)llGetSubString(text, 10, -1));
        else if (text == "OUTPUT") outputState();
    }
    listen(integer channel, string name, key user, string choice)
    {
        list sessionData = llJson2List(llLinksetDataRead("ws:core"));
        if (channel != gSessionMenu || !gSessionListen || user != llList2Key(sessionData, 0)
            || gMenuSession != llList2Key(sessionData, 2) || llList2String(sessionData, 4) != "BOUND") return;
        if (choice == "Text: ON" || choice == "Text: OFF")
        { llMessageLinked(LINK_THIS, 970261, "HOVER", gMenuSession); return; }
        if (choice != "Resume" && choice != "Exit") return;
        llListenRemove(gSessionListen); gSessionListen = 0;
        llMessageLinked(LINK_THIS, 970261, choice, gMenuSession);
    }
}
