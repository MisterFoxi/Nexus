// Drop into the HUD root. Owner command: /77814 dump
// One JSON record per prim. Positions and sizes are in metres.
// For a child, position and rotation are relative to the root.

integer CHANNEL = 77814;
integer gLink;
integer gLastLink;
integer gDumping;
integer gCount;
key gRoot;

finish(string status)
{
    llSetTimerEvent(0.0);
    gDumping = FALSE;
    llOwnerSay("[PRIMS] END " + status + " | rows=" + (string)gCount);
}

default
{
    state_entry()
    {
        llListen(CHANNEL, "", llGetOwner(), "");
        llOwnerSay("[PRIMS] DumpLinkedPrims v1.0 | /77814 dump");
    }

    listen(integer channel, string name, key speaker, string message)
    {
        if (speaker != llGetOwner() || llToLower(llStringTrim(message, STRING_TRIM)) != "dump") return;
        if (gDumping)
        {
            llOwnerSay("[PRIMS] Dump already running.");
            return;
        }
        gLastLink = llGetNumberOfPrims();
        gLink = 1;
        if (llGetLinkNumber() == 0) gLink = 0;
        if (gLink == 0) gLastLink = 0;
        gRoot = llGetLinkKey(gLink);
        if (gLink == 0) gRoot = llGetKey();
        gCount = 0;
        gDumping = TRUE;
        llOwnerSay("[PRIMS] START " + (string)gRoot
            + " | fields: link,name,uuid,faces,position,rotation,scale");
        llSetTimerEvent(0.25);
    }

    timer()
    {
        key prim = llGetLinkKey(gLink);
        if (gLink == 0) prim = llGetKey();
        if (prim != NULL_KEY && llGetAgentSize(prim) == ZERO_VECTOR)
        {
            list params = llGetLinkPrimitiveParams(gLink, [PRIM_POS_LOCAL, PRIM_ROT_LOCAL, PRIM_SIZE]);
            string name = llGetLinkName(gLink);
            if (gLink == 0) name = llGetObjectName();
            llOwnerSay("[PRIMS] " + llList2Json(JSON_ARRAY, [
                gLink, name, (string)prim, llGetLinkNumberOfSides(gLink),
                (string)llList2Vector(params, 0), (string)llList2Rot(params, 1),
                (string)llList2Vector(params, 2)
            ]));
            ++gCount;
        }
        ++gLink;
        if (gLink > gLastLink) finish("OK");
    }

    changed(integer flags)
    {
        if (flags & CHANGED_OWNER) llResetScript();
        if (gDumping && (flags & CHANGED_LINK)) finish("LINKSET CHANGED");
    }
}
