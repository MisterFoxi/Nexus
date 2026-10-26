// ROOT. Continue rotates 180 degrees; Discard always returns local Z to zero.
// MC_Selected_Controller sends 918310 only after checking the basket.
key gLastTicket;
key gLastDiscard;

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
    touch_start(integer count)
    {
        integer i;
        for (i = 0; i < count; ++i)
            if (llDetectedKey(i) == llGetOwner()
                && llToLower(llStringTrim(llGetLinkName(llDetectedLinkNumber(i)), STRING_TRIM)) == "p1_discard")
                pageZero();
    }
    link_message(integer sender, integer number, string payload, key ticket)
    {
        if (sender == llGetLinkNumber() && number == 918317
            && (payload == "DISCARD_DONE" || payload == "CRAFT_DONE") && ticket != NULL_KEY && ticket != gLastDiscard)
        {
            gLastDiscard = ticket;
            pageZero();
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
