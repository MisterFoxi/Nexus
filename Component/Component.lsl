// ============================================================
//  Component — generic ELEMENT script (protocol 5 — ADN model)
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
//     Organ    = leaf           ; OPTIONAL identity: this component IS that organ
//                               ; (matched by 'meta.organ is ...'); vanishes after
//                               ; the first transformation.
//     Organ    = leaf : KandaLeaf ; OPTIONAL, repeatable: a WHOLE plant hands out
//                               ; this organ's mesh at harvest (feature B).
//     Quantity = 5              ; total stock (units)
//     Use      = 1              ; units per application
//     Lifetime = 7d             ; d/h/m/s; 0 or absent = unlimited
//     MED      = heal/30/wound   ; OPTIONAL: effect if THIS object is already a potion
//     Axis     = act.thermal -6 ; repeatable: <axis> <signed intensity>
//     Axis     = act.fluidifying 5
//     Axis     = org.sweet 4     ; vocabulary: compiler/axes.src
//
//  PROTOCOL (whisper on CRAFT_CHANNEL, fields separated by "|")
//   workshop -> all   : PING
//   elem     -> ws    : HERE|key|name|qty|use|life|taxonomy|stage|propsPacked|proto|eff|mesh|organ
//   blank    -> ws    : BLANK|key|capacity       (available container, on PING)
//   ws       -> blank : CONFIG|key|name|qty|use|life|taxonomy|stage|propsPacked|med[|eff]
//   ws       -> elem  : CUT|key|avatarKey                 (record recipient)
//   ws       -> elem  : GIVE|key            (give single Mesh)
//   ws       -> elem  : GIVE|key|leaf^root  (harvest: give each listed organ's mesh)
//   ws       -> all   : HOVER|0/1
//   propsPacked: "act.thermal=-6^act.fluidifying=5^org.sweet=4" (empty if none)
// ============================================================

// Production remains -918273; the current HUD uses DEV_CHANNEL.
integer CRAFT_CHANNEL = -918273;
integer DEV_CHANNEL = -918274;
integer VERSION_CHANNEL = 918276; // Owner chat: /918276 version; same-owner debug tools may whisper VERSION.
// HUD on either channel: MC|TAKE/RETURN/COMMIT|source|request|units.
// TAKE/RETURN use exactly one unit; COMMIT finalizes held units (no second debit).
// Reply: MC|RESULT|source|request|verb|OK/NO|remaining, whispered on the request channel.
// A client record retains its latest request/reply, not a historical request journal.
// The HUD must COMMIT used/discarded units, or RETURN unused units, to close a craft.
string STOCK_KEY = "mc:component:stock";
// One atomic record: stock | repeated [client,held,lastRequest,verb,units,status,replyStock].
// rz_qty is a compatibility mirror; this record is authoritative once created.
list gHeld;
integer HS = 7;
integer gStockFault;
string  SEP = "|";
integer PROTO = 5;          // v5 adds the organ field in HERE and organ->mesh harvest delivery.
string  VERSION = "Component v0.7.1 (2026-10-27)"; // Bump script revision on changes; PROTO is independent.

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
string  gMesh;              // Inventory object (mesh + script + NC) to give at the next step (single-mesh delivery).
string  gOrgan;            // This component's organ identity (e.g. "leaf"); empty = not an organ.
list    gOrganMesh;        // Harvest map, stride 2: [organName, meshName, ...] — a whole plant's organs to hand out.
integer gQuantity;
integer gUse;
integer gLifeSecs;
integer gExpiry;
integer gShowHover = TRUE;
integer gCapacity;            // Container capacity (0 = unlimited).
key     gCutter;              // Player who should receive the Mesh inventory object.
integer gDying;               // Closed empty/expired source: defer deletion to allow a pending GIVE.

string  gNc;
integer gLine;
key     gQuery;
string  tName; string tTax; string tStage; string tMed; string tMesh;
integer tQty; integer tUse; integer tLife; string tProps; integer tCapacity;
string  tOrgan; list tOrganMesh;

integer gListen = -1;
integer gDevListen = -1;
integer gVersionListen = -1;

string trim(string s){ return llStringTrim(s, STRING_TRIM); }

reportVersion(){
    llOwnerSay("[Nexus] "+VERSION+" | protocol "+(string)PROTO);
    llWhisper(VERSION_CHANNEL,"MC|VERSION|"+(string)llGetKey()+"|"+VERSION+"|"+(string)PROTO);
}

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

// 'Organ = leaf'              -> this component IS a leaf (identity, matched by 'meta.organ is ...').
// 'Organ = leaf : KandaLeaf'  -> a whole plant that hands out a 'leaf' mesh at harvest (repeatable).
addOrgan(string v){
    v = trim(v);
    if(v == "") return;
    integer c = llSubStringIndex(v, ":");
    if(c == -1){ tOrgan = v; return; }
    string o = trim(llGetSubString(v, 0, c-1));
    string m = trim(llGetSubString(v, c+1, -1));
    if(o == "") return;
    tOrganMesh += [o, m];
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
    llLinksetDataWrite("rz_organ", gOrgan);
    llLinksetDataWrite("rz_organmesh", llDumpList2String(gOrganMesh, "^"));
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
    gOrgan    = llLinksetDataRead("rz_organ");
    string om = llLinksetDataRead("rz_organmesh");
    if(om == "") gOrganMesh = []; else gOrganMesh = llParseStringKeepNulls(om, ["^"], []);
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
    integer e = (integer)((float)rem * 1000.0 / (float)gLifeSecs);
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
    integer textLink = 0; // An unlinked prim is link 0; a linked object's root is link 1.
    if(llGetLinkNumber() != 0) textLink = LINK_ROOT;
    if(gShowHover){
        string t = gName + "\n(x" + (string)gQuantity + ")";
        if(gExpiry > 0) t += " " + (string)(ef/10) + "%";
        llSetLinkPrimitiveParamsFast(textLink, [PRIM_TEXT, t, <0.85,0.95,0.85>, 1.0]);
    } else llSetLinkPrimitiveParamsFast(textLink, [PRIM_TEXT, "", ZERO_VECTOR, 0.0]);
}

announce(){
    if(!gReady || gQuantity <= 0 || expired()) return;
    llWhisper(CRAFT_CHANNEL, "HERE"+SEP+(string)llGetKey()+SEP+gName+SEP+(string)gQuantity
        +SEP+(string)gUse+SEP+(string)gLifeSecs+SEP+gTaxonomy+SEP+gStage+SEP+gProps+SEP+(string)PROTO+SEP+(string)effPerMille()+SEP+gMesh+SEP+gOrgan);
}

// Publish the identity after loading a notecard, restoring state, or receiving CONFIG.
finalize(){
    if(gLifeSecs > 0 && gExpiry == 0) gExpiry = llGetUnixTime() + gLifeSecs;
    llSetObjectName(gName);
    if(!restoreStock()) return;
    saveKVP();
    gReady = TRUE;
    lifecycle();
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
    llWhisper(DEV_CHANNEL, "GONE"+SEP+(string)llGetKey());
    llDie();
}

integer expired(){ return gExpiry > 0 && llGetUnixTime() >= gExpiry; }

integer validClientKey(key value){
    if(value) return TRUE;
    return FALSE;
}

integer heldIndex(key client){
    integer i;
    for(i=0; i<llGetListLength(gHeld); i+=HS)
        if(llList2Key(gHeld,i) == client) return i;
    return -1;
}

integer hasHeld(){
    integer i;
    for(i=0; i<llGetListLength(gHeld); i+=HS)
        if(llList2Integer(gHeld,i+1) > 0) return TRUE;
    return FALSE;
}

// Keep the original expiry ticking. Only deletion waits for outstanding crafts.
lifecycle(){
    gDying = !hasHeld() && (gQuantity <= 0 || expired());
    if(gDying) llSetTimerEvent(2.0); // Preserve the existing CUT/GIVE delivery window.
    else if(gExpiry > 0 || hasHeld()) llSetTimerEvent(30.0);
    else llSetTimerEvent(0.0);
}

integer restoreStock(){
    string saved = llLinksetDataRead(STOCK_KEY);
    if(saved == "") return TRUE; // First migration inherits rz_qty, never the NC's initial stock.
    list fields = llParseStringKeepNulls(saved, [SEP], []);
    integer quantity = llList2Integer(fields,0);
    integer count = llGetListLength(fields);
    if((count-1)%HS != 0 || quantity < 0 || (string)quantity != llList2String(fields,0)){
        gStockFault=TRUE; llOwnerSay("[Component] Invalid saved stock; source locked."); return FALSE;
    }
    list held = [];
    if(count > 1) held = llList2List(fields,1,-1);
    integer i;
    for(i=0; i<llGetListLength(held); i+=HS){
        if(!validClientKey(llList2Key(held,i)) || llList2Integer(held,i+1) < 0
            || (string)llList2Integer(held,i+1) != llList2String(held,i+1)){
            gStockFault=TRUE; llOwnerSay("[Component] Invalid saved holds; source locked."); return FALSE;
        }
    }
    gQuantity=quantity; gHeld=held;
    return TRUE;
}

// Quantity, held units and the latest receipt commit together before any OK.
integer storeStock(integer quantity, list held){
    integer result = llLinksetDataWrite(STOCK_KEY, llDumpList2String([quantity]+held,SEP));
    if(result != 0 && result != 5){
        llOwnerSay("[Component] Cannot persist stock; request not applied or acknowledged."); return FALSE;
    }
    gQuantity=quantity; gHeld=held;
    llLinksetDataWrite("rz_qty", (string)gQuantity);
    return TRUE;
}

list clientRows(key client, integer index, integer held, key request, string verb,
    integer units, string status, integer stock){
    list row = [client,held,request,verb,units,status,stock];
    if(index < 0) return gHeld+row;
    return llListReplaceList(gHeld,row,index,index+HS-1);
}

hudResult(integer channel, key request, string verb, string status, integer stock){
    llWhisper(channel,"MC|RESULT|"+(string)llGetKey()+"|"+(string)request
        +"|"+verb+"|"+status+"|"+(string)stock);
}

hudRequest(integer channel, key client, list fields){
    if(!gReady || gStockFault || llGetOwnerKey(client) != llGetOwner()) return;
    if(llGetListLength(fields) != 5 || llList2Key(fields,2) != llGetKey()) return;
    string verb = llList2String(fields,1);
    key request = llList2Key(fields,3);
    integer units = llList2Integer(fields,4);
    if(!validClientKey(request) || units <= 0 || (string)units != llList2String(fields,4)) return;
    if(verb != "TAKE" && verb != "RETURN" && verb != "COMMIT") return;
    if(verb != "COMMIT" && units != 1) return;
    integer index = heldIndex(client);
    integer held = 0;
    if(index >= 0){
        held = llList2Integer(gHeld,index+1);
        if(llList2Key(gHeld,index+2) == request){
            if(llList2String(gHeld,index+3) == verb && llList2Integer(gHeld,index+4) == units)
                hudResult(channel,request,verb,llList2String(gHeld,index+5),llList2Integer(gHeld,index+6));
            return; // A conflicting reuse of the same request is never applied.
        }
    }
    integer stock = gQuantity;
    string status = "NO";
    if(verb == "TAKE"){
        if(!expired() && !gDying && stock >= units && held < 2147483647){
            stock -= units; held += units; status="OK";
        }
    } else if(held >= units){
        if(verb == "COMMIT"){ held -= units; status="OK"; }
        else if(stock <= 2147483647-units){ stock += units; held -= units; status="OK"; }
    }
    if(!storeStock(stock,clientRows(client,index,held,request,verb,units,status,stock))) return;
    if(status == "OK" && verb == "TAKE") playEffect();
    setStats();
    hudResult(channel,request,verb,status,stock);
    lifecycle();
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
        tOrgan=""; tOrganMesh=[];
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
        if(gDevListen != -1) llListenRemove(gDevListen);
        gDevListen = llListen(DEV_CHANNEL, "", "", "");
        if(gVersionListen != -1) llListenRemove(gVersionListen);
        gVersionListen = llListen(VERSION_CHANNEL, "", "", "");
        boot();
    }

    on_rez(integer p){ llResetScript(); }

    changed(integer c){
        if(c & CHANGED_INVENTORY) llResetScript();
    }

    dataserver(key q, string data){
        if(q != gQuery) return;
        if(data == EOF){
            if(tCapacity > 0 && llLinksetDataRead("rz_ready") == "1"){
                gRole=ROLE_BLANK; gCapacity=tCapacity;
                if(restoreKVP()) finalize();
                return;
            }
            if(tCapacity > 0){
                // Container notecard: remain blank and advertise the maximum capacity.
                gRole = ROLE_BLANK; gCapacity = tCapacity; gReady = FALSE;
                llSetObjectName("rezzme now");
                llWhisper(CRAFT_CHANNEL, "BLANK"+SEP+(string)llGetKey()+SEP+(string)gCapacity);
                return;
            }
            gName=tName; gTaxonomy=tTax; gStage=tStage; gMed=tMed; gMesh=tMesh;
            gQuantity=tQty; gUse=tUse; gLifeSecs=tLife; gProps=tProps;
            gOrgan=tOrgan; gOrganMesh=tOrganMesh;
            if(gName=="" || gQuantity<1){
                llOwnerSay("[Component] incomplete NC (Name / Quantity required): "+gNc);
                return;
            }
            if(gTaxonomy==""){
                llOwnerSay("[Component] NC without Taxonomy: "+gNc+" (won't be eligible for any workshop).");
            }
            // Restore remaining stock/expiry for NC items; other fields still come from the NC.
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
                else if(k=="organ") addOrgan(v);
                else if(k=="axis") addAxis(v);
            }
        }
        gLine++;
        gQuery = llGetNotecardLine(gNc, gLine);
    }

    listen(integer chan, string nm, key id, string msg){
        if(chan == VERSION_CHANNEL){
            if(llGetOwnerKey(id) == llGetOwner() && llToLower(trim(msg)) == "version") reportVersion();
            return;
        }
        if(chan != CRAFT_CHANNEL && chan != DEV_CHANNEL) return;
        // Keep empty fields so optional properties do not shift protocol indexes.
        // REVIEW: id is not authenticated. Any nearby script knowing this channel can mutate stock or configure blanks.
        list p = llParseStringKeepNulls(msg, [SEP], []);
        string verb = llList2String(p,0);

        if(verb == "MC"){ hudRequest(chan,id,p); return; }
        if(chan == DEV_CHANNEL){
            // Discovery stays compatible with the current development HUD.
            if(verb == "PING"){
                if(gReady && gQuantity > 0 && !expired())
                    llWhisper(chan,"HERE"+SEP+(string)llGetKey()+SEP+gName+SEP+(string)gQuantity
                        +SEP+(string)gUse+SEP+(string)gLifeSecs+SEP+gTaxonomy+SEP+gStage+SEP+gProps
                        +SEP+(string)PROTO+SEP+(string)effPerMille()+SEP+gMesh+SEP+gOrgan);
                else if(!gReady && gRole == ROLE_BLANK)
                    llWhisper(chan,"BLANK"+SEP+(string)llGetKey()+SEP+(string)gCapacity);
            }
            return;
        }
        if(verb == "PING"){
            if(gReady){ if(gQuantity > 0 && !expired()) announce(); }   // Do not advertise empty stock.
            else if(gRole == ROLE_BLANK) llWhisper(CRAFT_CHANNEL, "BLANK"+SEP+(string)llGetKey()+SEP+(string)gCapacity);
        }
        else if(verb == "CUT"){                 // Record the player receiving the harvested object.
            if(!gReady) return;
            if(llList2String(p,1) != (string)llGetKey()) return;
            gCutter = (key)llList2String(p,2);
        }
        else if(verb == "GIVE"){                // Give organ mesh object(s) to the recorded player.
            if(!gReady) return;
            if(llList2String(p,1) != (string)llGetKey()) return;
            string organs = "";
            if(llGetListLength(p) > 2) organs = llList2String(p,2);
            if(organs != ""){                    // GIVE|key|leaf^root : multi-organ harvest.
                list ol = llParseStringKeepNulls(organs, ["^"], []); integer oi;
                for(oi=0; oi<llGetListLength(ol); oi++){
                    string o = llList2String(ol, oi);
                    integer mi = llListFindList(gOrganMesh, [o]);
                    if(mi == -1 || (mi % 2) != 0){ llOwnerSay("[Component] GIVE: no mesh mapped for organ '"+o+"'."); jump nextOrgan; }
                    string msh = llList2String(gOrganMesh, mi+1);
                    if(msh == "" || llGetInventoryType(msh) == INVENTORY_NONE){ llOwnerSay("[Component] GIVE: mesh '"+msh+"' missing for organ '"+o+"'."); jump nextOrgan; }
                    if(gCutter != NULL_KEY) llGiveInventory(gCutter, msh);
                    @nextOrgan;
                }
                gCutter = NULL_KEY;
                return;
            }
            // Single-mesh delivery (GIVE|key).
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
        llRegionSayTo(t, 0, info+" - "+VERSION+" - protocol "+(string)PROTO);
    }

    timer(){
        if(!gReady || gStockFault) return;
        // No timeout may destroy a source while a HUD/workshop still holds units.
        if(hasHeld()){ setStats(); return; }
        if(gQuantity <= 0){ die(); return; }
        if(expired()){
            llOwnerSay("[Component] "+gName+" has passed its lifetime.");
            die();
            return;
        }
        setStats();
    }
}
