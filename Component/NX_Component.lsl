#define SCRIPT_NAME    "Nexus_Component"
#define SCRIPT_VERSION "v0.2.1"
#include "nexus_header.lsl"

// Nexus component — full component, stock CLIENT of Nexus_Server. See dev/stock-protocol.md.
// Identity / DNA / freshness are LOCAL; the QUANTITY authority is the server.
// This script NEVER decrements itself — it registers a stable SID and reflects QTY pushes.
// The old mc:component:stock ledger + MC TAKE/RETURN/COMMIT + DEV_CHANNEL are GONE.
//
// Two identity paths at boot: (1) no-mod definition NC (guardrail A) -> registers;
// (2) blank container (no NC) -> advertises BLANK, awaits CONFIG. Plus KVP restore (survives re-rez).
//
// CHANNELS
//   NX_STOCK (-918280)  server:  out REGISTER|sid|owner|dnaHash|expiry|ncQty ;  in QTY|sid|qty
//   NX_SCAN  (-918281)  workshop<->component:
//     ws  -> all   : PING
//     elem-> ws    : HERE|objkey|sid|name|qty|use|life|taxonomy|stage|props|eff|mesh|organ[|iconUUID]
//     blank->ws    : BLANK|objkey|capacity[|iconUUID]
//     ws  -> blank : CONFIG|objkey|sid|name|use|life|taxonomy|stage|props|med[|eff[|expiryUnix]]
//     ws  -> elem  : CUT|objkey|avatarKey                 (record recipient)
//     ws  -> elem  : GIVE|objkey                          (give single Mesh)
//     ws  -> elem  : GIVE|objkey|leaf^root                (harvest: give each organ's mesh)
//     ws  -> all   : HOVER|0/1
//   props: "act.thermal=-6^org.sweet=4" (empty if none)

integer NX_STOCK = -918280;
integer NX_SCAN  = -918281;

integer ROLE_NONE = 0;
integer ROLE_NC   = 1;
integer ROLE_BLANK = 2;

string  SEP = "|";

// identity / DNA
integer gRole;
integer gReady;
string  gName; string gTaxonomy; string gStage; string gProps;
string  gMed; string gIcon; string gMesh; string gOrgan;
list    gOrganMesh;                 // stride 2: [organ, mesh, ...]
integer gUse; integer gLifeSecs; integer gExpiry; integer gCapacity;
integer gShowHover = TRUE;
key     gCutter;
integer gDying;

// stock (server-authoritative)
key     gSid;                       // stable identity, persisted in rz_sid
integer gNcQty;                     // NC seed hint only (server ignores for a known SID)
integer gQty = -1;                  // authoritative cache; -1 = unknown (awaiting QTY)
integer gRegTries;

// NC parse temporaries
string  gNc; integer gLine; key gQuery;
string  tName; string tTax; string tStage; string tMed; string tMesh; string tProps; string tIcon; string tOrgan;
list    tOrganMesh;
integer tQty; integer tUse; integer tLife; integer tCapacity;

integer gStockListen = -1;
integer gScanListen = -1;

string trim(string s){ return llStringTrim(s, STRING_TRIM); }

string iconSuffix(){
    string v = trim(gIcon);
    key tex = (key)v;
    if(tex) return SEP + llToLower((string)tex);
    if(v == "" || llGetInventoryType(v) != INVENTORY_TEXTURE) return "";
    tex = llGetInventoryKey(v);
    if(tex) return SEP + llToLower((string)tex);
    return "";
}
string productName(){
    if(gRole != ROLE_BLANK || gStage == "" || gName == gStage) return gName;
    string suf = "/" + gStage;
    integer start = llStringLength(gName) - llStringLength(suf);
    if(start >= 0 && llGetSubString(gName, start, -1) == suf) return gName;
    return gName + suf;
}
integer noModOk(string nc){ return !(llGetInventoryPermMask(nc, MASK_NEXT) & PERM_MODIFY); }

integer parseDuration(string s){
    s = trim(llToLower(s)); if(s == "") return 0;
    string suf = llGetSubString(s, -1, -1); integer n = (integer)s;
    if(suf == "d") return n*86400;
    if(suf == "h") return n*3600;
    if(suf == "m") return n*60;
    return n;
}
addAxis(string v){
    v = trim(v); integer sp = llSubStringIndex(v, " "); if(sp == -1) return;
    string ax = trim(llGetSubString(v, 0, sp-1));
    string val = trim(llGetSubString(v, sp+1, -1));
    if(ax == "" || val == "") return;
    if(tProps != "") tProps += "^";
    tProps += ax + "=" + val;
}
addOrgan(string v){
    v = trim(v); if(v == "") return;
    integer c = llSubStringIndex(v, ":");
    if(c == -1){ tOrgan = v; return; }
    string o = trim(llGetSubString(v, 0, c-1));
    string m = trim(llGetSubString(v, c+1, -1));
    if(o == "") return;
    tOrganMesh += [o, m];
}

saveKVP(){
    llLinksetDataWrite("rz_sid",   (string)gSid);
    llLinksetDataWrite("rz_name",  gName);
    llLinksetDataWrite("rz_tax",   gTaxonomy);
    llLinksetDataWrite("rz_stage", gStage);
    llLinksetDataWrite("rz_props", gProps);
    llLinksetDataWrite("rz_med",   gMed);
    llLinksetDataWrite("rz_icon",  gIcon);
    llLinksetDataWrite("rz_mesh",  gMesh);
    llLinksetDataWrite("rz_organ", gOrgan);
    llLinksetDataWrite("rz_organmesh", llDumpList2String(gOrganMesh, "^"));
    llLinksetDataWrite("rz_use",   (string)gUse);
    llLinksetDataWrite("rz_life",  (string)gLifeSecs);
    llLinksetDataWrite("rz_exp",   (string)gExpiry);
    llLinksetDataWrite("rz_ready", "1");
}
integer restoreKVP(){
    if(llLinksetDataRead("rz_ready") != "1") return FALSE;
    gSid      = (key)llLinksetDataRead("rz_sid");
    gName     = llLinksetDataRead("rz_name");
    gTaxonomy = llLinksetDataRead("rz_tax");
    gStage    = llLinksetDataRead("rz_stage");
    gProps    = llLinksetDataRead("rz_props");
    gMed      = llLinksetDataRead("rz_med");
    gMesh     = llLinksetDataRead("rz_mesh");
    if(gNc == "") gIcon = llLinksetDataRead("rz_icon");
    gOrgan    = llLinksetDataRead("rz_organ");
    string om = llLinksetDataRead("rz_organmesh");
    if(om == "") gOrganMesh = []; else gOrganMesh = llParseStringKeepNulls(om, ["^"], []);
    gUse      = (integer)llLinksetDataRead("rz_use");
    gLifeSecs = (integer)llLinksetDataRead("rz_life");
    gExpiry   = (integer)llLinksetDataRead("rz_exp");
    return TRUE;
}

playEffect(){
    llParticleSystem([
        PSYS_PART_FLAGS, PSYS_PART_EMISSIVE_MASK | PSYS_PART_INTERP_COLOR_MASK,
        PSYS_SRC_PATTERN, PSYS_SRC_PATTERN_EXPLODE,
        PSYS_PART_START_COLOR, <0.6,0.9,0.6>, PSYS_PART_END_COLOR, <0.6,0.9,0.6>,
        PSYS_PART_START_ALPHA, 0.8, PSYS_PART_END_ALPHA, 0.0,
        PSYS_PART_START_SCALE, <0.1,0.1,0.0>, PSYS_PART_END_SCALE, <0.25,0.25,0.0>,
        PSYS_PART_MAX_AGE, 1.2, PSYS_SRC_MAX_AGE, 1.5,
        PSYS_SRC_BURST_RATE, 0.05, PSYS_SRC_BURST_PART_COUNT, 12,
        PSYS_SRC_BURST_SPEED_MIN, 0.4, PSYS_SRC_BURST_SPEED_MAX, 0.8,
        PSYS_SRC_ACCEL, <0.0,0.0,-0.4>
    ]);
}
string fmtLeft(integer s){
    if(s < 0) s = 0;
    if(s >= 86400) return (string)(s/86400) + "d";
    if(s >= 3600)  return (string)(s/3600) + "h";
    if(s >= 60)    return (string)(s/60) + "m";
    return (string)s + "s";
}
integer expired(){ return gExpiry > 0 && llGetUnixTime() >= gExpiry; }
integer effPerMille(){
    if(gLifeSecs <= 0 || gExpiry <= 0) return 1000;
    integer rem = gExpiry - llGetUnixTime(); if(rem <= 0) return 0;
    integer e = (integer)((float)rem * 1000.0 / (float)gLifeSecs);
    if(e > 1000) e = 1000; return e;
}
string dnaHash(){ return llMD5String(gTaxonomy + "|" + gStage + "|" + gProps, 0); }

ensureSid(){
    // if(gSid) is FALSE for both NULL_KEY and (key)"" — unlike (gSid != NULL_KEY),
    // which wrongly passes for an empty-string key and leaves the SID blank.
    if(gSid){ llLinksetDataWrite("rz_sid", (string)gSid); return; }
    gSid = (key)llLinksetDataRead("rz_sid");
    if(gSid){ llLinksetDataWrite("rz_sid", (string)gSid); return; }
    gSid = llGenerateKey();
    llLinksetDataWrite("rz_sid", (string)gSid);
}
registerToServer(){
    llRegionSay(NX_STOCK, "NX|REGISTER|" + (string)gSid + "|" + (string)llGetOwner()
        + "|" + dnaHash() + "|" + (string)gExpiry + "|" + (string)gNcQty);
}
discardOnServer(){ llRegionSay(NX_STOCK, "NX|DISCARD|" + (string)gSid); }

integer shownQty(){ if(gQty < 0) return gNcQty; return gQty; }

setStats(){
    if(!gReady) return;
    integer shown = shownQty();
    integer ef = effPerMille();
    string d = "Stock " + (string)shown;
    if(gTaxonomy != "") d += " | " + gTaxonomy + "/" + gStage;
    if(gMed != "")      d += " | MED " + gMed;
    if(gExpiry > 0)     d += " | eff " + (string)(ef/10) + "%";
    llSetObjectDesc(d);
    integer tl = 0; if(llGetLinkNumber() != 0) tl = LINK_ROOT;
    if(gShowHover){
        string t = productName() + "\n(x" + (string)shown + ")";
        if(gExpiry > 0) t += " " + (string)(ef/10) + "%";
        llSetLinkPrimitiveParamsFast(tl, [PRIM_TEXT, t, <0.85,0.95,0.85>, 1.0]);
    } else llSetLinkPrimitiveParamsFast(tl, [PRIM_TEXT, "", ZERO_VECTOR, 0.0]);
}

announce(){
    if(!gReady || shownQty() <= 0 || expired()) return;
    llRegionSay(NX_SCAN, "HERE" + SEP + (string)llGetKey() + SEP + (string)gSid + SEP + productName()
        + SEP + (string)shownQty() + SEP + (string)gUse + SEP + (string)gLifeSecs + SEP + gTaxonomy
        + SEP + gStage + SEP + gProps + SEP + (string)effPerMille() + SEP + gMesh + SEP + gOrgan + iconSuffix());
}

// qty depleted (server 0) or expired -> schedule death, but hold a window for a trailing harvest GIVE.
lifecycle(){
    integer dead = (gQty == 0) || expired();
    if(dead && gCutter == NULL_KEY){ gDying = TRUE; llSetTimerEvent(2.0); return; }
    gDying = FALSE;
    if(gQty < 0 || gExpiry > 0 || gCutter != NULL_KEY) llSetTimerEvent(5.0);
    else llSetTimerEvent(0.0);
}

die(){
    llParticleSystem([]);
    llRegionSay(NX_SCAN, "GONE" + SEP + (string)llGetKey());
    llDie();
}

finalize(){
    if(gLifeSecs > 0 && gExpiry == 0) gExpiry = llGetUnixTime() + gLifeSecs;
    ensureSid();
    llSetObjectName(productName());
    saveKVP();
    gReady = TRUE;
    gQty = -1; gRegTries = 0;
    setStats();
    registerToServer();
    lifecycle();
    string meshNote = " mesh=(none)"; if(gMesh != "") meshNote = " mesh=" + gMesh;
    llOwnerSay("[Component] ready: " + gName + " (" + gTaxonomy + "/" + gStage + ") sid=" + (string)gSid
        + " ncQty=" + (string)gNcQty + meshNote);
}

boot(){
    gRole = ROLE_NONE; gReady = FALSE; gIcon = "";
    gTaxonomy = ""; gStage = ""; gProps = ""; gMed = ""; gExpiry = 0; gCutter = NULL_KEY;

    gNc = "";
    integer ncn = llGetInventoryNumber(INVENTORY_NOTECARD); integer ni;
    for(ni = 0; ni < ncn; ni++){
        string cand = llGetInventoryName(INVENTORY_NOTECARD, ni);
        if(llToLower(cand) != "bench_config"){ gNc = cand; jump foundNc; }
    }
    @foundNc;

    if(gNc != ""){
        gRole = ROLE_NC;
        if(!noModOk(gNc)){
            llOwnerSay("[Component] REFUSED: definition notecard is modifiable (guardrail A). Set it no-mod.");
            gRole = ROLE_NONE; return;
        }
        tName=""; tTax=""; tStage=""; tMed=""; tMesh=""; tProps=""; tIcon=""; tOrgan=""; tOrganMesh=[];
        tQty=0; tUse=1; tLife=0; tCapacity=0;
        gLine = 0; gQuery = llGetNotecardLine(gNc, 0);
        return;
    }

    if(restoreKVP()){ gRole = ROLE_BLANK; finalize(); return; }

    gRole = ROLE_BLANK; gCapacity = 0;
    llSetObjectName("rezzme now");
    llRegionSay(NX_SCAN, "BLANK" + SEP + (string)llGetKey() + SEP + "0" + iconSuffix());
}

default
{
    state_entry()
    {
        nexusBoot();
        if(gStockListen != -1) llListenRemove(gStockListen);
        gStockListen = llListen(NX_STOCK, "", NULL_KEY, "");
        if(gScanListen != -1) llListenRemove(gScanListen);
        gScanListen = llListen(NX_SCAN, "", NULL_KEY, "");
        boot();
    }
    on_rez(integer p){ llResetScript(); }
    changed(integer c){ if(c & CHANGED_INVENTORY) llResetScript(); }

    dataserver(key q, string data)
    {
        if(q != gQuery) return;
        if(data == EOF){
            gIcon = tIcon;
            if(tCapacity > 0 && llLinksetDataRead("rz_ready") == "1"){
                gRole = ROLE_BLANK; gCapacity = tCapacity;
                if(restoreKVP()) finalize();
                return;
            }
            if(tCapacity > 0){
                gRole = ROLE_BLANK; gCapacity = tCapacity; gReady = FALSE;
                llSetObjectName("rezzme now");
                llRegionSay(NX_SCAN, "BLANK" + SEP + (string)llGetKey() + SEP + (string)gCapacity + iconSuffix());
                return;
            }
            gName=tName; gTaxonomy=tTax; gStage=tStage; gMed=tMed; gMesh=tMesh;
            gNcQty=tQty; gUse=tUse; gLifeSecs=tLife; gProps=tProps;
            gOrgan=tOrgan; gOrganMesh=tOrganMesh;
            if(gName == "" || gNcQty < 1){ llOwnerSay("[Component] incomplete NC (Name/Quantity required): " + gNc); return; }
            if(gTaxonomy == "") llOwnerSay("[Component] NC without Taxonomy: " + gNc + " (won't be eligible for any workshop).");
            // Re-rez of an NC item keeps its persisted SID (server holds the real qty).
            if(llLinksetDataRead("rz_ready") == "1") gSid = (key)llLinksetDataRead("rz_sid");
            finalize();
            return;
        }
        string line = trim(data);
        integer hash = llSubStringIndex(line, "#");
        if(hash == 0) line = ""; else if(hash > 0) line = trim(llGetSubString(line, 0, hash-1));
        if(line != ""){
            integer eq = llSubStringIndex(line, "=");
            if(eq != -1){
                string k = llToLower(trim(llGetSubString(line, 0, eq-1)));
                string v = trim(llGetSubString(line, eq+1, -1));
                if(k == "name") tName = v;
                else if(k == "taxonomy") tTax = v;
                else if(k == "stage") tStage = v;
                else if(k == "quantity") tQty = (integer)v;
                else if(k == "use") tUse = (integer)v;
                else if(k == "lifetime") tLife = parseDuration(v);
                else if(k == "med") tMed = v;
                else if(k == "capacity") tCapacity = (integer)v;
                else if(k == "icon") tIcon = v;
                else if(k == "mesh") tMesh = v;
                else if(k == "organ") addOrgan(v);
                else if(k == "axis") addAxis(v);
            }
        }
        gLine++; gQuery = llGetNotecardLine(gNc, gLine);
    }

    listen(integer chan, string nm, key id, string msg)
    {
        // ---- server: authoritative quantity ----
        if(chan == NX_STOCK){
            list f = llParseStringKeepNulls(msg, [SEP], []);
            if(llList2String(f,0) != "NX" || llList2String(f,1) != "QTY") return;
            if((key)llList2String(f,2) != gSid) return;
            gQty = (integer)llList2String(f,3);
            setStats();
            if(gQty == 0) llOwnerSay("[Component] " + gName + " depleted (server).");
            lifecycle();
            return;
        }
        if(chan != NX_SCAN) return;

        list p = llParseStringKeepNulls(msg, [SEP], []);
        string verb = llList2String(p, 0);

        if(verb == "PING"){
            if(gReady){ announce(); }
            else if(gRole == ROLE_BLANK)
                llRegionSay(NX_SCAN, "BLANK" + SEP + (string)llGetKey() + SEP + (string)gCapacity + iconSuffix());
            return;
        }
        if(verb == "HOVER"){ gShowHover = (integer)llList2String(p,1); setStats(); return; }

        // all remaining verbs address a specific object
        if(llList2String(p,1) != (string)llGetKey()) return;

        if(verb == "CUT"){
            if(!gReady) return;
            gCutter = (key)llList2String(p,2);
        }
        else if(verb == "GIVE"){
            if(!gReady) return;
            string organs = ""; if(llGetListLength(p) > 2) organs = llList2String(p,2);
            if(organs != ""){
                list ol = llParseStringKeepNulls(organs, ["^"], []); integer oi;
                for(oi = 0; oi < llGetListLength(ol); oi++){
                    string o = llList2String(ol, oi);
                    integer mi = llListFindList(gOrganMesh, [o]);
                    if(mi == -1 || (mi % 2) != 0){ llOwnerSay("[Component] GIVE: no mesh for organ '" + o + "'."); jump nextOrgan; }
                    string msh = llList2String(gOrganMesh, mi+1);
                    if(msh == "" || llGetInventoryType(msh) == INVENTORY_NONE){ llOwnerSay("[Component] GIVE: mesh '" + msh + "' missing."); jump nextOrgan; }
                    if(gCutter != NULL_KEY) llGiveInventory(gCutter, msh);
                    @nextOrgan;
                }
            } else {
                if(gMesh == ""){ llOwnerSay("[Component] GIVE requested, no Mesh defined."); return; }
                if(llGetInventoryType(gMesh) == INVENTORY_NONE){ llOwnerSay("[Component] Mesh '" + gMesh + "' missing."); return; }
                if(gCutter != NULL_KEY) llGiveInventory(gCutter, gMesh);
            }
            gCutter = NULL_KEY;
            lifecycle();   // delivery window can close now
        }
        else if(verb == "CONFIG"){
            // CONFIG|objkey|sid|name|use|life|taxonomy|stage|props|med[|eff[|expiryUnix]]
            if(gRole != ROLE_BLANK || gReady) return;
            gSid = (key)llList2String(p,2);
            if(gSid == NULL_KEY) return;
            gName     = llList2String(p,3);
            gUse      = (integer)llList2String(p,4);
            gLifeSecs = (integer)llList2String(p,5);
            gTaxonomy = llList2String(p,6);
            gStage    = llList2String(p,7);
            gProps    = llList2String(p,8);
            gMed      = llList2String(p,9);
            gNcQty    = 0;                       // qty is the server's (SID was created at COMMIT)
            gExpiry   = 0;
            integer effInit = 1000;
            if(llGetListLength(p) > 10) effInit = (integer)llList2String(p,10);
            if(llGetListLength(p) > 11){
                integer ax = (integer)llList2String(p,11);
                if(ax > 0) gExpiry = ax;
            }
            else if(gLifeSecs > 0 && effInit < 1000)
                gExpiry = llGetUnixTime() + (integer)((float)effInit * (float)gLifeSecs / 1000.0);
            finalize();
        }
    }

    link_message(integer s, integer num, string str, key id)
    {
        if(num == NEXUS_MEM_REPORT) nexusMemReport();
    }

    touch_start(integer n)
    {
        key t = llDetectedKey(0);
        string info = gName;
        if(!gReady){
            if(gRole == ROLE_BLANK) info = "(empty container - craft to fill)";
            else info = "(not configured)";
        } else {
            info += " - stock " + (string)shownQty();
            if(gTaxonomy != "") info += " - " + gTaxonomy + "/" + gStage;
            if(gMed != "") info += " - MED " + gMed;
            if(gExpiry > 0) info += " - expires in " + fmtLeft(gExpiry - llGetUnixTime());
            info += " - sid " + (string)gSid;
        }
        llRegionSayTo(t, 0, info + " - " + SCRIPT_NAME + " " + SCRIPT_VERSION);
    }

    timer()
    {
        if(!gReady) return;
        if(gDying){ if(gCutter == NULL_KEY) die(); return; }
        if(expired()){
            llOwnerSay("[Component] " + gName + " has passed its lifetime.");
            discardOnServer();
            gQty = 0; lifecycle(); return;
        }
        if(gQty < 0 && gRegTries < 6){ gRegTries++; registerToServer(); }
        setStats();
    }
}
