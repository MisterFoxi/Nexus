#define SCRIPT_NAME    "NX_Sniffer"
#define SCRIPT_VERSION "v0.1.0"
#include "nexus_header"

// DEV message monitor. Drop into a prim to watch the Nexus traffic that prim can see:
//   - open-channel chat on the NX channels (broadcasts; AND anything llRegionSayTo'd to THIS object/avatar);
//   - link_messages on this prim's linkset (the internal bus).
//
// IMPORTANT: a directed llRegionSayTo between two OTHER objects is private — it cannot be sniffed from a
// third prim. Most bench<->HUD bind traffic is directed, so place this script where the traffic lands:
//   * in the worn HUD ROOT  -> sees bench->avatar (HUDQ/OFFER/BOUND) + the HUD's link bus;
//   * in the bench linkset  -> sees HUD->bench (HUDA/ACCEPT/UNBIND) + the bench's link bus;
//   * in a free-floating prim -> sees only broadcasts (e.g. scan PING on CRAFT).
//
// Owner-only output. Toggle with  /918700 chat | link | all | off  in local chat.

integer NX_STOCK = -918280;            // stock + world
integer NX_SCAN  = -918281;            // component scan
integer NX_HUD   = -918282;            // bench <-> worn HUD
integer CRAFT    = -918273;            // scan PING / HERE / BLANK broadcasts
integer CMD      = 918700;             // owner command channel

integer gChat = TRUE;
integer gLink = TRUE;

string chanName(integer c)
{
    if(c == NX_STOCK) return "STOCK";
    if(c == NX_SCAN)  return "SCAN";
    if(c == NX_HUD)   return "HUD";
    if(c == CRAFT)    return "CRAFT";
    return (string)c;
}

arm()
{
    llListen(NX_STOCK, "", NULL_KEY, "");
    llListen(NX_SCAN,  "", NULL_KEY, "");
    llListen(NX_HUD,   "", NULL_KEY, "");
    llListen(CRAFT,    "", NULL_KEY, "");
    llListen(CMD,      "", llGetOwner(), "");
}

default
{
    state_entry()
    {
        nexusBoot();
        arm();
        llOwnerSay("[Sniffer] ready on STOCK/SCAN/HUD/CRAFT + link bus. "
            + "Toggle: /" + (string)CMD + " chat|link|all|off. "
            + "Directed RegionSayTo to other objects is not visible from here.");
    }
    on_rez(integer p){ llResetScript(); }
    changed(integer c){ if(c & CHANGED_OWNER) llResetScript(); }

    listen(integer chan, string nm, key id, string msg)
    {
        if(chan == CMD)
        {
            string m = llToLower(llStringTrim(msg, STRING_TRIM));
            if(m == "off")       { gChat = FALSE; gLink = FALSE; }
            else if(m == "chat") { gChat = TRUE;  gLink = FALSE; }
            else if(m == "link") { gChat = FALSE; gLink = TRUE;  }
            else if(m == "all")  { gChat = TRUE;  gLink = TRUE;  }
            else { llOwnerSay("[Sniffer] usage: /" + (string)CMD + " chat|link|all|off"); return; }
            llOwnerSay("[Sniffer] chat=" + (string)gChat + " link=" + (string)gLink);
            return;
        }
        if(!gChat) return;
        // Show every owner's traffic (contention tests use a 2nd avatar); the channels are Nexus-specific.
        llOwnerSay("[Sniffer] <" + chanName(chan) + "> " + nm + " (" + (string)id + "): " + msg);
    }

    link_message(integer s, integer num, string str, key id)
    {
        if(num == NEXUS_MEM_REPORT) { nexusMemReport(); return; }
        if(!gLink) return;
        llOwnerSay("[Sniffer] [link " + (string)num + "] '" + str + "' id=" + (string)id);
    }
}
