#define SCRIPT_NAME    "NX_Turn_Z"
#define SCRIPT_VERSION "v0.1.0"
#include "nexus_header"

// NX_Turn_Z — ROOT page-rotation executor for the worn HUD (kept visual layer, adapted to the refonte).
// Dumb rotator: it turns the root prim's local Z to a page and holds X/Y. Navigation LOGIC lives in
// NX_HudNav; this script only reacts to rotation triggers.
//   P0 = 0 , P1 = -90 , P4 = +90 , P3 = 180 (local Z).
//   918310 CONTINUE -> P1 ; 918410 OPEN/BACK -> P4/P1 ; 918391 WAIT_CONTAINER -> P3, CLOSED/RELEASED -> P0 ;
//   918317 DISCARD_DONE/CRAFT_DONE -> P0 ; owner touch on P1_DISCARD (p1_action3) -> P0 directly.
// Refonte change: the old P4-OPEN gate read the dead store mc:workshop:session; removed (that gating moves
// to the craft flow).

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
        nexusBoot();
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
        if (number == NEXUS_MEM_REPORT) { nexusMemReport(); return; }
        if(sender == llGetLinkNumber() && number == 918410 && ticket != NULL_KEY && !gProductPage){
            if(payload == "OPEN"){
                gObservationPage = TRUE;                   // craft-paused observation; gating moved to the craft flow
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
