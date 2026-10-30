// ROOT. Continue opens P1; authenticated output state opens P3; product closure returns P0.
// MC_Selected_Controller sends 918310 only after checking the basket.
key gLastTicket;
key gLastDiscard;
integer gProductPage;
// P3 occupies local Z=90 degrees. Adjust this installation value to the mesh.
float P3_Z = PI_BY_TWO;

// Reapply an absolute local Euler Z=0; repeated Discard notifications are harmless.
pageZero()
{
    vector angles = llRot2Euler(llGetLocalRot());
    llSetLinkPrimitiveParamsFast(LINK_ROOT, [
        PRIM_ROT_LOCAL, llEuler2Rot(<angles.x, angles.y, 0.0>)
    ]);
}

default
{
    state_entry()
    {
        llMessageLinked(LINK_THIS, 918390, "STATUS", NULL_KEY);
        llMessageLinked(LINK_THIS, 918389, "STATUS", NULL_KEY);
    }
    touch_start(integer count)
    {
        integer i;
        for (i = 0; i < count; ++i)
            if (llDetectedKey(i) == llGetOwner())
            {
                string name = llToLower(llStringTrim(llGetLinkName(llDetectedLinkNumber(i)), STRING_TRIM));
                if (name == "p1_discard" && !gProductPage) pageZero();
            }
    }
    link_message(integer sender, integer number, string payload, key ticket)
    {
        if (sender == llGetLinkNumber() && number == 918391)
        {
            string outputPhase = llList2String(llParseStringKeepNulls(payload, ["|"], []), 0);
            gProductPage = outputPhase != "CLOSED" && outputPhase != "RELEASED";
            if (!gProductPage) pageZero();
            else
            {
                vector angles = llRot2Euler(llGetLocalRot());
                llSetLinkPrimitiveParamsFast(LINK_ROOT, [PRIM_ROT_LOCAL, llEuler2Rot(<angles.x, angles.y, P3_Z>)]);
            }
            return;
        }
        if (sender == llGetLinkNumber() && number == 918317
            && (payload == "DISCARD_DONE" || payload == "CRAFT_DONE") && ticket != NULL_KEY && ticket != gLastDiscard)
        {
            gLastDiscard = ticket;
            if (!gProductPage) pageZero();
            return;
        }
        if (sender != llGetLinkNumber() || number != 918310
            || payload != "CONTINUE" || ticket == NULL_KEY || ticket == gLastTicket) return;
        // REVIEW: only the most recent Continue ticket is remembered; delayed replay of an older ticket can rotate the HUD again.
        gLastTicket = ticket;
        llSetLinkPrimitiveParamsFast(LINK_ROOT, [
            PRIM_ROT_LOCAL, llEuler2Rot(<0.0, 0.0, PI>) * llGetLocalRot()
        ]);
    }
}
