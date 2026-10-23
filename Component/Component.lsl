// ============================================================
//  Component — generic ELEMENT script (proto v0.4 — ADN model)
//  Gorean / medieval medical-craft RP. Drop into any mesh.
//  The mesh is pure decoration; this script holds all behavior.
// ============================================================
//  DNA MODEL: a component describes its identity instead of recipes:
//  its taxonomy class, refinement stage, and property axes.
//  Workshops derive the resulting recipes from these properties.
//
//  TWO IDENTITY PATHS at boot:
//   1) Element defined by a NO-MOD notecard (guardrail A) -> reads, registers.
//   2) Blank container: no definition NC -> replies BLANK to PING, awaits CONFIG.
//      An empty RP vial is a blank. After a successful craft, a workshop
//      sends CONFIG with the product DNA, turning the vial into the product.
//   (+ restore from KVP if already configured : survives take/re-rez)
//
//  DEFINITION NOTECARD (no-mod) :
//     Name     = Kanda leaf
//     Taxonomy = mint           ; class/alias from the taxonomy tree (tree.src)
//     Stage    = leaf           ; refinement stage
//     Mesh     = my_leaf_object ; OPTIONAL: inventory object to give the player
//                               ; at the next step. This object carries its own
//                               ; script and NC, and initializes when rezzed.
//     Quantity = 5              ; total stock (units)
//     Use      = 1              ; units per application
//     Lifetime = 7d             ; d/h/m/s; 0 or absent = unlimited
//     MED      = heal/30/wound   ; OPTIONAL: effect if THIS object is already a potion
//     Axis     = act.thermal -6 ; repeatable: <axis> <signed intensity>
//     Axis     = act.fluidifying 5
//     Axis     = org.taste 4
//
//  PROTOCOL (whisper on CRAFT_CHANNEL, fields separated by "|")
//   workshop -> all   : PING
//   elem     -> ws    : HERE|key|name|qty|use|life|taxonomy|stage|propsPacked|proto|eff|mesh
//   blank    -> ws    : BLANK|key|capacity       (available container, on PING)
//   ws       -> elem  : CONSUME|key|units
//   ws       -> elem  : COMMIT|key               (final consumption: empty -> die)
//   elem     -> ws    : OK|key|remaining  /  NO|key
//   ws       -> blank : CONFIG|key|name|qty|use|life|taxonomy|stage|propsPacked|med[|eff]
//   ws       -> elem  : REFUND|key|units          (restore reserved stock)
//   ws       -> elem  : CUT|key|avatarKey / GIVE|key (record recipient / give Mesh)
//   ws       -> all   : HOVER|0/1
//   propsPacked: "act.thermal=-6^act.fluidifying=5^org.taste=4" (empty if none)
// ============================================================

integer CRAFT_CHANNEL = -918273;
string  SEP = "|";
integer PROTO = 4;          // v4 adds freshness in parts per thousand (eff in HERE/CONFIG).
string  VERSION = "Component v0.5 (2026-10-20)";

integer ROLE_NONE  = 0;
integer ROLE_NC    = 1;     // Defined by a notecard.
integer ROLE_BLANK = 2;     // Blank/container configured by a workshop.

integer gRole;
integer gReady;

string  gName;
string  gTaxonomy;
string  gStage;
string  gProps;             // "name=val^..."
string  gMed;
string  gMesh;              // Inventory object (mesh + script + NC) to give at the next step.
integer gQuantity;
integer gUse;
integer gLifeSecs;
integer gExpiry;
integer gShowHover = TRUE;
integer gEmptyAt;              // Time stock reached zero; refunds are allowed during the grace period.
integer gCapacity;            // Container capacity (0 = unlimited).
key     gCutter;              // Player who should receive the Mesh inventory object.
integer gDying;               // Empty COMMIT: defer deletion to allow a pending GIVE.

string  gNc;
integer gLine;
key     gQuery;
string  tName; string tTax; string tStage; string tMed; string tMesh;
integer tQty; integer tUse; integer tLife; string tProps; integer tCapacity;

integer gListen = -1;

string trim(string s){ return llStringTrim(s, STRING_TRIM); }

// Check next-owner permissions; this does not verify current-owner immutability.
integer noModOk(string nc){
    return !(llGetInventoryPermMask(nc, MASK_NEXT) & PERM_MODIFY);
}

// Bare numbers mean seconds. REVIEW: reject negative, malformed, and overflowing durations.
integer parseDuration(string s){
    s = trim(llToLower(s));
    if(s=="") return 0;
    string suf = llGetSubString(s,-1,-1);
    integer n = (integer)s;
    if(suf=="d") return n*86400;
    if(suf=="h") return n*3600;
    if(suf=="m") return n*60;
    if(suf=="s") return n;
    return n;
}

addAxis(string v){
    v = trim(v);
    integer sp = llSubStringIndex(v, " ");
    if(sp == -1) return;
    string ax = trim(llGetSubString(v, 0, sp-1));
    string val = trim(llGetSubString(v, sp+1, -1));
    if(ax == "" || val == "") return;
    if(tProps != "") tProps += "^";
    tProps += ax + "=" + val;
}

// Linkset data survives script resets and take/re-rez. Keys are shared by the whole linkset.
// REVIEW: write failures are unchecked; rz_ready is not an atomic commit marker.
saveKVP(){
    llLinksetDataWrite("rz_name",  gName);
    llLinksetDataWrite("rz_tax",   gTaxonomy);
    llLinksetDataWrite("rz_stage", gStage);
    llLinksetDataWrite("rz_props", gProps);
    llLinksetDataWrite("rz_med",   gMed);
    llLinksetDataWrite("rz_mesh",  gMesh);
    llLinksetDataWrite("rz_qty",   (string)gQuantity);
    llLinksetDataWrite("rz_use",   (string)gUse);
    llLinksetDataWrite("rz_life",  (string)gLifeSecs);
    llLinksetDataWrite("rz_exp",   (string)gExpiry);
    llLinksetDataWrite("rz_ready", "1");
}
integer restoreKVP(){
    if(llLinksetDataRead("rz_ready") != "1") return FALSE;
    gName     = llLinksetDataRead("rz_name");
    gTaxonomy = llLinksetDataRead("rz_tax");
    gStage    = llLinksetDataRead("rz_stage");
    gProps    = llLinksetDataRead("rz_props");
    gMed      = llLinksetDataRead("rz_med");
    gMesh     = llLinksetDataRead("rz_mesh");
    gQuantity = (integer)llLinksetDataRead("rz_qty");
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

string fmtLeft(integer secs){
    if(secs < 0) secs = 0;
    if(secs >= 86400) return (string)(secs/86400)+"d";
    if(secs >= 3600)  return (string)(secs/3600)+"h";
    if(secs >= 60)    return (string)(secs/60)+"m";
    return (string)secs+"s";
}

// Current freshness in parts per thousand (1000 = fresh, 0 = expired). Zero life/expiry means unlimited.
integer effPerMille(){
    if(gLifeSecs <= 0 || gExpiry <= 0) return 1000;
    integer rem = gExpiry - llGetUnixTime();
    if(rem <= 0) return 0;
    // REVIEW: integer multiplication can overflow above about 24.9 days remaining.
    integer e = rem * 1000 / gLifeSecs;
    if(e > 1000) e = 1000;
    return e;
}
setStats(){
    if(!gReady) return;
    string d = "Stock " + (string)gQuantity;
    if(gTaxonomy != "") d += " | " + gTaxonomy;
    if(gStage != "")    d += "/" + gStage;
    if(gMed != "")      d += " | MED " + gMed;
    if(gExpiry > 0)     d += " | expires " + fmtLeft(gExpiry - llGetUnixTime());
    integer ef = effPerMille();
    if(gExpiry > 0)     d += " | eff " + (string)(ef/10) + "%";
    llSetObjectDesc(d);
    if(gShowHover){
        string t = gName + "\n(x" + (string)gQuantity + ")";
        if(gExpiry > 0) t += " " + (string)(ef/10) + "%";
        llSetLinkPrimitiveParamsFast(LINK_ROOT, [PRIM_TEXT, t, <0.85,0.95,0.85>, 1.0]);
    } else llSetLinkPrimitiveParamsFast(LINK_ROOT, [PRIM_TEXT, "", ZERO_VECTOR, 0.0]);
}

announce(){
    llWhisper(CRAFT_CHANNEL, "HERE"+SEP+(string)llGetKey()+SEP+gName+SEP+(string)gQuantity
        +SEP+(string)gUse+SEP+(string)gLifeSecs+SEP+gTaxonomy+SEP+gStage+SEP+gProps+SEP+(string)PROTO+SEP+(string)effPerMille()+SEP+gMesh);
}

// Publish the identity after loading a notecard, restoring state, or receiving CONFIG.
finalize(){
    if(gLifeSecs > 0 && gExpiry == 0) gExpiry = llGetUnixTime() + gLifeSecs;
    llSetObjectName(gName);
    saveKVP();
    gReady = TRUE;
    if(gExpiry > 0) llSetTimerEvent(30.0);
    setStats();
    announce();
    string meshNote = " mesh=(none)";
    if(gMesh != "") meshNote = " mesh="+gMesh;
    llOwnerSay("[Component] ready: "+gName+" ("+gTaxonomy+"/"+gStage+", x"+(string)gQuantity+")"+meshNote);
    if(gRole == ROLE_BLANK) llSay(0, gName+" loaded.");
}

die(){
    llParticleSystem([]);
    llWhisper(CRAFT_CHANNEL, "GONE"+SEP+(string)llGetKey());
    llDie();
}

// Reserve stock immediately; REFUND can undo it until COMMIT or grace-period expiry.
consume(integer units){
    if(units < 1) units = 1;
    if(gQuantity < units) return;
    gQuantity -= units;
    playEffect();
    llLinksetDataWrite("rz_qty", (string)gQuantity);
    setStats();
    // At zero stock, allow 600 seconds for REFUND before automatic deletion.
    if(gQuantity <= 0){ gEmptyAt = llGetUnixTime(); llSetTimerEvent(30.0); }  // Check every 30 seconds; delete after 600 seconds without a refund.
}

boot(){
    gRole = ROLE_NONE; gReady = FALSE;
    gTaxonomy = ""; gStage = ""; gProps = ""; gMed = ""; gExpiry = 0;

    gNc = "";
    integer ncn = llGetInventoryNumber(INVENTORY_NOTECARD); integer ni;
    for(ni=0; ni<ncn; ni++){
        string cand = llGetInventoryName(INVENTORY_NOTECARD, ni);
        if(llToLower(cand) != "bench_config"){ gNc = cand; jump foundNc; }
    }
    @foundNc;

    if(gNc != ""){
        gRole = ROLE_NC;
        if(!noModOk(gNc)){
            llOwnerSay("[Component] REFUSED: definition notecard is modifiable (guardrail A). Set it no-mod.");
            gRole = ROLE_NONE;
            return;
        }
        tName=""; tTax=""; tStage=""; tMed=""; tMesh=""; tQty=0; tUse=1; tLife=0; tProps=""; tCapacity=0;
        gLine = 0;
        gQuery = llGetNotecardLine(gNc, 0);
        return;
    }

    // REVIEW: this restore path is reached only when no definition notecard exists.
    if(restoreKVP()){
        gRole = ROLE_BLANK;
        finalize();
        return;
    }

    // New blank/container without a notecard: unlimited capacity.
    gRole = ROLE_BLANK; gCapacity = 0;
    llSetObjectName("rezzme now");
    llWhisper(CRAFT_CHANNEL, "BLANK"+SEP+(string)llGetKey()+SEP+"0");
}

default{
    state_entry(){
        llOwnerSay("[Nexus] "+VERSION);
        if(gListen != -1) llListenRemove(gListen);
        gListen = llListen(CRAFT_CHANNEL, "", "", "");
        boot();
    }

    on_rez(integer p){ llResetScript(); }

    changed(integer c){
        if(c & CHANGED_INVENTORY) llResetScript();
    }

    dataserver(key q, string data){
        if(q != gQuery) return;
        if(data == EOF){
            // REVIEW: configured containers with a Capacity NC become blank on reset; restore saved product first.
            if(tCapacity > 0){
                // Container notecard: remain blank and advertise the maximum capacity.
                gRole = ROLE_BLANK; gCapacity = tCapacity; gReady = FALSE;
                llSetObjectName("rezzme now");
                llWhisper(CRAFT_CHANNEL, "BLANK"+SEP+(string)llGetKey()+SEP+(string)gCapacity);
                return;
            }
            gName=tName; gTaxonomy=tTax; gStage=tStage; gMed=tMed; gMesh=tMesh;
            gQuantity=tQty; gUse=tUse; gLifeSecs=tLife; gProps=tProps;
            if(gName=="" || gQuantity<1){
                llOwnerSay("[Component] incomplete NC (Name / Quantity required): "+gNc);
                return;
            }
            if(gTaxonomy==""){
                llOwnerSay("[Component] NC without Taxonomy: "+gNc+" (won't be eligible for any workshop).");
            }
            // Restore remaining stock/expiry for NC items; other fields still come from the NC.
            // REVIEW: restored zero stock has no gEmptyAt deadline, so reset bypasses empty-stock cleanup.
            if(llLinksetDataRead("rz_ready") == "1"){
                gQuantity = (integer)llLinksetDataRead("rz_qty");
                gExpiry   = (integer)llLinksetDataRead("rz_exp");
            }
            finalize();
            return;
        }
        string line = trim(data);
        integer hash = llSubStringIndex(line, "#");          // Strip inline comments (# ...).
        if(hash == 0) line = ""; else if(hash > 0) line = trim(llGetSubString(line, 0, hash-1));
        if(line != ""){
            integer eq = llSubStringIndex(line,"=");
            if(eq != -1){
                string k = llToLower(trim(llGetSubString(line,0,eq-1)));
                string v = trim(llGetSubString(line,eq+1,-1));
                if(k=="name") tName=v;
                else if(k=="taxonomy") tTax=v;
                else if(k=="stage") tStage=v;
                else if(k=="quantity") tQty=(integer)v;
                else if(k=="use") tUse=(integer)v;
                else if(k=="lifetime") tLife=parseDuration(v);
                else if(k=="med") tMed=v;
                else if(k=="capacity") tCapacity=(integer)v;
                else if(k=="mesh") tMesh=v;
                else if(k=="axis") addAxis(v);
            }
        }
        gLine++;
        gQuery = llGetNotecardLine(gNc, gLine);
    }

    listen(integer chan, string nm, key id, string msg){
        if(chan != CRAFT_CHANNEL) return;
        // Keep empty fields so optional properties do not shift protocol indexes.
        // REVIEW: id is not authenticated. Any nearby script knowing this channel can mutate stock or configure blanks.
        list p = llParseStringKeepNulls(msg, [SEP], []);
        string verb = llList2String(p,0);

        if(verb == "PING"){
            if(gReady){ if(gQuantity > 0) announce(); }   // Do not advertise empty stock.
            else if(gRole == ROLE_BLANK) llWhisper(CRAFT_CHANNEL, "BLANK"+SEP+(string)llGetKey()+SEP+(string)gCapacity);
        }
        else if(verb == "CONSUME"){
            if(!gReady) return;
            if(llList2String(p,1) != (string)llGetKey()) return;
            // REVIEW: validate field count and units > 0 before checking stock; consume() clamps only afterward.
            integer units = (integer)llList2String(p,2);
            if(gQuantity < units){ llWhisper(CRAFT_CHANNEL, "NO"+SEP+(string)llGetKey()); return; }
            consume(units);
            llWhisper(CRAFT_CHANNEL, "OK"+SEP+(string)llGetKey()+SEP+(string)gQuantity);
        }
        else if(verb == "REFUND"){
            if(!gReady) return;
            if(llList2String(p,1) != (string)llGetKey()) return;
            // REVIEW: refunds have no reservation/sender match, positive-amount check, or replay protection.
            gQuantity += (integer)llList2String(p,2);
            // REVIEW: a refund after COMMIT leaves gDying set, so the next timer still deletes the item.
            gEmptyAt = 0;
            llLinksetDataWrite("rz_qty", (string)gQuantity);
            setStats();
            if(gExpiry > 0) llSetTimerEvent(30.0); else llSetTimerEvent(0.0);
            announce();
        }
        else if(verb == "COMMIT"){
            // The reaction completed: consumption is final; empty stock skips the refund grace period.
            if(!gReady) return;
            if(llList2String(p,1) != (string)llGetKey()) return;
            if(gQuantity <= 0){ gDying = TRUE; llSetTimerEvent(2.0); }   // Delete in about two seconds to allow a pending GIVE.
        }
        else if(verb == "CUT"){                 // Record the player receiving the harvested object.
            if(!gReady) return;
            if(llList2String(p,1) != (string)llGetKey()) return;
            gCutter = (key)llList2String(p,2);
        }
        else if(verb == "GIVE"){                // Give the Mesh inventory object to the recorded player.
            if(!gReady) return;
            if(llList2String(p,1) != (string)llGetKey()) return;
            if(gMesh == ""){ llOwnerSay("[Component] GIVE requested, but no Mesh is defined."); return; }
            if(llGetInventoryType(gMesh) == INVENTORY_NONE){ llOwnerSay("[Component] Mesh '"+gMesh+"' is missing from the inventory."); return; }
            if(gCutter != NULL_KEY) llGiveInventory(gCutter, gMesh);
            gCutter = NULL_KEY;
        }
        else if(verb == "CONFIG"){
            if(gRole != ROLE_BLANK || gReady) return;
            if(llList2String(p,1) != (string)llGetKey()) return;
            // REVIEW: validate field count, identity, positive quantity/use, lifetime, and gCapacity before accepting CONFIG.
            gName     = llList2String(p,2);
            gQuantity = (integer)llList2String(p,3);
            gUse      = (integer)llList2String(p,4);
            gLifeSecs = (integer)llList2String(p,5);
            gTaxonomy = llList2String(p,6);
            gStage    = llList2String(p,7);
            gProps    = llList2String(p,8);
            gMed      = llList2String(p,9);
            integer effInit = 1000;
            if(llGetListLength(p) > 10) effInit = (integer)llList2String(p,10);
            // Inherit ingredient freshness instead of starting with a fully fresh product.
            // REVIEW: clamp effInit to 0..1000 and avoid integer overflow in effInit * gLifeSecs.
            if(gLifeSecs > 0 && effInit < 1000) gExpiry = llGetUnixTime() + (effInit * gLifeSecs) / 1000;
            finalize();
        }
        else if(verb == "HOVER"){
            gShowHover = (integer)llList2String(p,1);
            setStats();
        }
    }

    touch_start(integer n){
        key t = llDetectedKey(0);
        string info = gName;
        if(!gReady){
            if(gRole == ROLE_BLANK) info = "(empty container - craft to fill)";
            else info = "(not configured)";
        }
        else {
            info += " - stock "+(string)gQuantity;
            if(gTaxonomy != "") info += " - "+gTaxonomy+"/"+gStage;
            if(gMed != "") info += " - MED "+gMed;
            if(gExpiry > 0){
                integer left = gExpiry - llGetUnixTime();
                if(left < 0) left = 0;
                info += " - expires in "+fmtLeft(left);
            }
        }
        llRegionSayTo(t, 0, info);
    }

    timer(){
        if(gDying){ die(); return; }                 // Deferred deletion after COMMIT, allowing GIVE to run first.
        // Delete empty stock if no refund arrived during the grace period.
        if(gQuantity <= 0 && gEmptyAt > 0 && llGetUnixTime() - gEmptyAt >= 600){
            die();
            return;
        }
        if(gExpiry > 0 && llGetUnixTime() >= gExpiry){
            llOwnerSay("[Component] "+gName+" has passed its lifetime.");
            die();
            return;
        }
        setStats();
    }
}
