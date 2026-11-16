// ROOT. Continue opens P1; observation opens P4; output opens P3; closure returns P0.
// MC_Selected_Controller sends 918310 only after checking the basket.
key gLastTicket;
key gLastDiscard;
integer gProductPage;
integer gObservationPage;
// Vertical linkset: P1 is on the side and P3 is opposite P0.
float P1_Z = -PI_BY_TWO;
float P3_Z = PI;
float P4_Z = PI_BY_TWO;

// Reapply an absolute local Euler Z=0; repeated Discard notifications are harmless.
pageZero()
{
    gObservationPage = FALSE;
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
    }
    touch_start(integer count)
    {
        integer i;
        for (i = 0; i < count; ++i)
            if (llDetectedKey(i) == llGetOwner())
            {
                string name = llToLower(llStringTrim(llGetLinkName(llDetectedLinkNumber(i)), STRING_TRIM));
                if (name == "p1_action3" && !gProductPage) pageZero();
            }
    }
    link_message(integer sender, integer number, string payload, key ticket)
    {
        if(sender == llGetLinkNumber() && number == 918410 && ticket != NULL_KEY && !gProductPage){
            if(payload == "OPEN"){
                list session = llJson2List(llLinksetDataRead("mc:workshop:session"));
                string phase = llList2String(session,5);
                if(phase != "" && phase != "IDLE") return;
                gObservationPage = TRUE;
            }
            else if(payload == "BACK"){
                if(!gObservationPage) return;
                gObservationPage = FALSE;
            }
            else return;
            float angle = P1_Z;
            if(gObservationPage) angle = P4_Z;
            vector current = llRot2Euler(llGetLocalRot());
            llSetLinkPrimitiveParamsFast(LINK_ROOT,[PRIM_ROT_LOCAL,llEuler2Rot(<current.x,current.y,angle>)]);
            return;
        }
        if (sender == llGetLinkNumber() && number == 918391)
        {
            string outputPhase = llList2String(llParseStringKeepNulls(payload, ["|"], []), 0);
            if (outputPhase == "CLOSED" || outputPhase == "RELEASED")
            { gProductPage = FALSE; pageZero(); }
            else if (outputPhase == "WAIT_CONTAINER")
            {
                gProductPage = TRUE;
                gObservationPage = FALSE;
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
        gObservationPage = FALSE;
        vector angles = llRot2Euler(llGetLocalRot());
        llSetLinkPrimitiveParamsFast(LINK_ROOT, [
            PRIM_ROT_LOCAL, llEuler2Rot(<angles.x, angles.y, P1_Z>)
        ]);
    }
}
