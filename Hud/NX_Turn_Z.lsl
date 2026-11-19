#define SCRIPT_NAME    "NX_Turn_Z"
#define SCRIPT_VERSION "v0.1.5"
#include "nexus_header"

// NX_Turn_Z — ROOT page-rotation executor for the worn HUD (kept visual layer, adapted to the refonte).
// Dumb rotator: it sets the root prim's ABSOLUTE local Z rotation to a page (2D HUD, X/Y always 0).
// Navigation LOGIC lives in NX_HudNav; this script only reacts to rotation triggers.
//   Pages (absolute local Z): P0 home/selection = 270 , P1 cut/craft = 180 , P3 transfer = 90 , P4 observation = 0.
//   918310 CONTINUE -> P1 ; 918410 OPEN/BACK -> P4(observation)/P1 ; 918391 WAIT_CONTAINER -> P3, CLOSED/RELEASED -> P0 ;
//   918317 DISCARD_DONE/CRAFT_DONE -> P0 ; owner touch on P1_DISCARD (p1_action3) -> P0 directly.
// Default page is P0: forced at boot, on wear (attach) and on rez, so the HUD never opens on a stale page.

key gLastTicket;
key gLastDiscard;
integer gProductPage;
integer gObservationPage;
// Absolute local-Z angle of each page (radians).
float P0_Z = 4.71238898;       // 270 (= 3*PI/2)  home / selection (default)
float P1_Z = PI;               // 180  cut / craft
float P3_Z = PI_BY_TWO;        //  90  transfer / recipient
float P4_Z = 0.0;              //   0  observation

// Go to the home page P0 (absolute). Repeated Discard notifications are harmless.
pageZero()
{
    gObservationPage = FALSE;
    llSetLinkPrimitiveParamsFast(LINK_ROOT, [PRIM_ROT_LOCAL, llEuler2Rot(<0.0, 0.0, P0_Z>)]);
}

// Force the home page P0 and clear transient page flags (boot / wear / rez).
resetToHome()
{
    gProductPage = FALSE;
    pageZero();
}

default
{
    state_entry()
    {
        nexusBoot();
        resetToHome();
        llMessageLinked(LINK_THIS, 918390, "STATUS", NULL_KEY);
    }
    attach(key id){ if (id != NULL_KEY) resetToHome(); }   // worn: open on P0
    on_rez(integer p){ resetToHome(); }
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
            llSetLinkPrimitiveParamsFast(LINK_ROOT, [PRIM_ROT_LOCAL, llEuler2Rot(<0.0, 0.0, angle>)]);
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
                llSetLinkPrimitiveParamsFast(LINK_ROOT, [PRIM_ROT_LOCAL, llEuler2Rot(<0.0, 0.0, P3_Z>)]);
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
        llSetLinkPrimitiveParamsFast(LINK_ROOT, [PRIM_ROT_LOCAL, llEuler2Rot(<0.0, 0.0, P1_Z>)]);
    }
}
