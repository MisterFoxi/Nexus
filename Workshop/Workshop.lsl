// ============================================================
// Workshop.lsl - generic workshop coordinator, protocol v0.2
// Medical crafting system (MedicalGS).
// ============================================================
// MEMORY SPLIT: this script manages configuration, presence, menus,
// the cooking/collection state machine, and delivery. Heavy processing
// (token lookup, aggregation, rules, and output generation) lives in
// Workshop_Eval.lsl, WHICH MUST BE IN THE SAME LINKSET.
// Cook sends the basket to the evaluator and receives the output DNA
// through linked messages (see EVAL_REQ/EVAL_RES below).
//
// CONFIG notecard "bench_config" (configuration convention: owner-only):
// Channel is fixed at -918273, shared by all scripts; it is not configurable.
// Genre = mortar, cauldron ; one or more genres (display and evaluator rules)
// MaxEffect = 50 ; read by Workshop_Eval
// FluxAbs = 1 ; read by Workshop_Eval
// NMax / SpoilMin / SpoilMax / Batch ; read by Workshop_Eval
//     ShowHover = 1
// CookTime = 20 ; cooking duration in seconds (recommended: below 60)
// CookSound = cook_sound ; optional sound inventory names
//     ReadySound= ready_sound
//     FailSound = fail_sound
//
// FLOW:
// touch -> scan (PING, 2 seconds) -> menu (available ingredients and Cook)
// Add ingredient -> reserve one unit immediately; selection order sets the principal.
// Cook -> send the basket to the evaluator -> response:
// inert -> refund reservations; produce nothing
// reaction -> commit reservations, cook, and retain output until collection
// collection -> fill available blank containers through CONFIG
// ============================================================

integer CRAFT_CHANNEL = -918273;
string  SEP = "|";

integer EVAL_REQ = 970200;           // main -> evaluator: basket
integer EVAL_RES = 970201;           // evaluator -> main: result
string  VERSION  = "Workshop v0.5.1 (2026-10-20)";

// ---- config ----
list    gGenres;                     // Genres displayed in the menu; rules are resolved by the evaluator.
list    gActAxes;                    // Action axes configured with "Action = <axis> : <modality>".
list    gActMods;                    // Parallel modalities (hold/hud).
list    gActVals;                    // Action values entered before cooking (temporary stepper UI).
integer gActIdx;                     // Index of the action axis currently being adjusted.
float   gGrindScale = 1.0;           // hold: intensity = round(duration_seconds * scale).
integer gGrindMax   = 10;            // hold: maximum intensity.
float   gGrindT0;                    // hold: llGetTime() at the first touch.
integer gGrindArmed;                 // hold: FALSE waits for start; TRUE waits for stop.
integer gShowHover = TRUE;
integer gCookTime  = 20;
string  gCookSnd  = "cook_sound";
string  gReadySnd = "ready_sound";
string  gFailSnd  = "fail_sound";
integer gCfgLine; key gCfgQuery; string gCfgNc;

// ---- presence (transient) ----
list gIng;                           // stride 10 : [key,name,qty,tax,stage,props,life,eff,mesh,organ]
integer IK=0; integer IN=1; integer IQ=2; integer ITX=3; integer IST=4; integer IPR=5; integer ILF=6; integer IEF=7; integer IMS=8; integer IOR=9; integer IS=10;
list gRec;                           // Available containers: stride 2 [key, capacity].
list gKept;                          // Kept sources: stride KN=7 [name,qty,tax,stage,props,life,expiry]; persisted in state:kept.
integer KN=7;

integer gListen = -1;
integer gMenuChan; integer gMenuListen = -1; key gUser;

// ---- basket ----
list    gPicks;                      // Selected labels, in selection order.
list    gCons;                       // Immediate reservations: stride 2 [key, count], retained for refunds.
integer gState;                      // 0 idle, 1 craft scan, 2 cooking, 3 pending output, 4 collection scan, 5 evaluation, 6 stepper, 7 grinding.
integer gGiveMode;                   // TRUE when the winning rule uses direct Mesh inventory delivery (give).
key     gGiveKey;                    // Key of the plant that will deliver its Mesh object.
string  gGiveOrgans;                 // Organ list "leaf^root" for multi-organ harvest; empty = legacy single give.

// ---- output received from the evaluator ----
integer rVerdict;
string oName; integer oQty; integer oUse; integer oLife;
string oTax; string oStage; string oProps; string oMed; integer oEff;

string trim(string s){ return llStringTrim(s, STRING_TRIM); }

// REVIEW: reject malformed/negative durations and overflow before storing seconds.
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

// ---------- config ----------
string findConfigNc(){
    integer n = llGetInventoryNumber(INVENTORY_NOTECARD); integer i;
    for(i=0; i<n; i++){
        string nm = llGetInventoryName(INVENTORY_NOTECARD, i);
        if(llToLower(nm) == "bench_config") return nm;
    }
    return "";
}
loadConfig(){
    gGenres = []; gActAxes = []; gActMods = [];
    // REVIEW: reload clears action lists during active sessions and retains omitted scalar settings from the previous NC.
    gCfgNc = findConfigNc();
    if(gCfgNc == ""){ llOwnerSay("[Workshop] no 'bench_config' notecard."); return; }
    gCfgLine = 0; gCfgQuery = llGetNotecardLine(gCfgNc, 0);
}
applyCfgLine(string data){
    string line = trim(data);
    integer hash = llSubStringIndex(line, "#");          // Strip inline comments (# ...).
    if(hash == 0) return;
    if(hash > 0) line = trim(llGetSubString(line, 0, hash-1));
    if(line=="") return;
    integer eq = llSubStringIndex(line,"=");
    if(eq==-1) return;
    string k = llToLower(trim(llGetSubString(line,0,eq-1)));
    string v = trim(llGetSubString(line,eq+1,-1));
    if(k=="genre"){
        gGenres = [];
        list g = llParseString2List(v, [","], []);
        integer i; for(i=0;i<llGetListLength(g);i++) gGenres += trim(llList2String(g,i));
    }
    else if(k=="showhover") gShowHover=(integer)v;
    else if(k=="cooktime") gCookTime=(integer)parseDuration(v);
    // REVIEW: enforce CookTime > 0; zero or negative disables the timer and strands committed ingredients in cooking.
    else if(k=="cooksound") gCookSnd=v;
    else if(k=="readysound") gReadySnd=v;
    else if(k=="failsound") gFailSnd=v;
    else if(k=="action"){                       // "Action = <axis> : <modality>"
        integer c = llSubStringIndex(v, ":");
        string ax; string mod;
        if(c==-1){ ax=trim(v); mod="hold"; }
        else { ax=trim(llGetSubString(v,0,c-1)); mod=trim(llToLower(llGetSubString(v,c+1,-1))); }
        if(ax!=""){ gActAxes += ax; gActMods += mod; }
    }
    else if(k=="grindscale") gGrindScale=(float)v;
    else if(k=="grindmax") gGrindMax=(integer)v;
    // MaxEffect / FluxAbs / NMax / SpoilMin / SpoilMax / Batch are read by Workshop_Eval.
}

// ---------- basket identity: NAME/STAGE ----------
string rowLabel(integer i){
    string s = llList2String(gIng,i+IN);
    string st = llList2String(gIng,i+IST);
    if(st != "") s += "/" + st;
    return s;
}
// REVIEW: name/stage is not a unique identity; same-label sources can have different taxonomy, properties, or freshness.
integer ingByLabel(string lab){     // Return the first matching label, preferring a row with stock.
    integer i; integer fb = -1;
    for(i=0; i<llGetListLength(gIng); i+=IS){
        if(rowLabel(i)==lab){
            if(fb==-1) fb=i;
            if(llList2Integer(gIng,i+IQ) > 0) return i;
        }
    }
    return fb;
}
integer countPick(string nm){
    integer c=0; integer i;
    for(i=0;i<llGetListLength(gPicks);i++) if(llList2String(gPicks,i)==nm) c++;
    return c;
}
list distinctPicks(){
    list d; integer i;
    for(i=0;i<llGetListLength(gPicks);i++){
        string nm = llList2String(gPicks,i);
        if(llListFindList(d,[nm])==-1) d += nm;
    }
    return d;
}

// Pack evaluator input: newline-separated groups with pipe-separated fields.
// rawName|count|tax|stage|props|life|eff (first group is the principal ingredient).
// REVIEW: repacking by label takes metadata from one row, not necessarily from the sources actually consumed.
string packBasket(){
    string s = "";
    list d = distinctPicks(); integer i;
    for(i=0;i<llGetListLength(d);i++){
        string lab = llList2String(d,i);
        integer idx = ingByLabel(lab);
        if(idx != -1){
            if(s != "") s += "\n";
            s += llList2String(gIng,idx+IN) + "|" + (string)countPick(lab)
               + "|" + llList2String(gIng,idx+ITX) + "|" + llList2String(gIng,idx+IST)
               + "|" + llList2String(gIng,idx+IPR) + "|" + (string)llList2Integer(gIng,idx+ILF)
               + "|" + (string)llList2Integer(gIng,idx+IEF) + "|" + llList2String(gIng,idx+IOR);
        }
    }
    return s;
}

// ---------- kept sources: output remains inside the station ----------
// gKept stride KN=7: [name,qty,tax,stage,props,life,expiry]. Persisted in
// state:kept across resets and take/re-rez; World_Loader purges tok/tax/law/idx only.
// Merged into gIng with a "KEPT<index>" sentinel and freshness calculated
// on demand. Internal sources use no CONSUME/COMMIT/REFUND whispers.
// Store an expiry timestamp so kept sources continue aging inside the station.
integer keptEff(integer life, integer expiry){      // Current freshness in parts per thousand.
    if(life <= 0 || expiry <= 0) return 1000;
    integer rem = expiry - llGetUnixTime();
    if(rem <= 0) return 0;
    // REVIEW: rem * 1000 can overflow when more than about 24.9 days remain; use bounded floating-point scaling.
    integer e = rem * 1000 / life;
    if(e > 1000) e = 1000;
    return e;
}
saveKept(){                                          // Serialize gKept into state:kept.
    string s = ""; integer i;
    for(i=0;i<llGetListLength(gKept);i+=KN){
        if(s != "") s += "\n";
        s += llList2String(gKept,i+0)+"|"+(string)llList2Integer(gKept,i+1)+"|"+llList2String(gKept,i+2)
           +"|"+llList2String(gKept,i+3)+"|"+llList2String(gKept,i+4)+"|"+(string)llList2Integer(gKept,i+5)
           +"|"+(string)llList2Integer(gKept,i+6);
    }
    if(s == "") llLinksetDataDelete("state:kept");
    // REVIEW: check linkset-data write results before treating kept inventory as persisted.
    else llLinksetDataWrite("state:kept", s);
}
loadKept(){                                          // Reload gKept from state:kept.
    gKept = [];
    string s = llLinksetDataRead("state:kept");
    if(s == "") return;
    list rows = llParseStringKeepNulls(s, ["\n"], []); integer i;
    for(i=0;i<llGetListLength(rows);i++){
        list f = llParseStringKeepNulls(llList2String(rows,i), ["|"], []);
        if(llGetListLength(f) >= KN)
            gKept += [ llList2String(f,0), (integer)llList2String(f,1), llList2String(f,2),
                       llList2String(f,3), llList2String(f,4), (integer)llList2String(f,5),
                       (integer)llList2String(f,6) ];
    }
}
pruneKept(){                                         // Remove empty or expired sources.
    integer i = 0; integer dirty = FALSE;
    while(i < llGetListLength(gKept)){
        if(llList2Integer(gKept,i+1) <= 0
           || keptEff(llList2Integer(gKept,i+5), llList2Integer(gKept,i+6)) <= 0){
            gKept = llDeleteSubList(gKept, i, i+KN-1); dirty = TRUE;
        } else i += KN;
    }
    if(dirty) saveKept();
}
mergeKept(){                                         // Merge gKept into gIng using KEPT<index> sentinels and current freshness.
    pruneKept();
    integer i; integer n = llGetListLength(gKept);
    for(i=0; i<n; i+=KN){
        integer life = llList2Integer(gKept, i+5);
        gIng += [ "KEPT"+(string)(i/KN),
                  llList2String(gKept, i+0), llList2Integer(gKept, i+1),
                  llList2String(gKept, i+2), llList2String(gKept, i+3),
                  llList2String(gKept, i+4), life, keptEff(life, llList2Integer(gKept, i+6)), "", "" ];
    }
}
keptConsume(string sentinel, integer nn){            // Decrement a KEPT<index> source at commit time.
    integer idx = (integer)llGetSubString(sentinel,4,-1) * KN;
    if(idx < 0 || (idx+KN) > llGetListLength(gKept)) return;
    integer q = llList2Integer(gKept, idx+1) - nn;
    if(q < 0) q = 0;
    gKept = llListReplaceList(gKept, [q], idx+1, idx+1);
}

// ---------- presence ----------
setIng(key k, string name, integer qty, string tax, string stage, string props, integer life, integer eff, string mesh, string organ){
    list row = [ (string)k, name, qty, tax, stage, props, life, eff, mesh, organ ];
    integer bykey = -1; integer i;
    for(i=0;i<llGetListLength(gIng);i+=IS) if(llList2String(gIng,i+IK)==(string)k){ bykey=i; jump done; }
    @done;
    if(bykey != -1) gIng = llListReplaceList(gIng, row, bykey, bykey+IS-1);
    else gIng += row;
}
integer recIndex(string k){
    integer i;
    for(i=0;i<llGetListLength(gRec);i+=2) if(llList2String(gRec,i)==k) return i;
    return -1;
}
integer recCount(){ return llGetListLength(gRec)/2; }
forgetKey(key k){
    integer i;
    for(i=0;i<llGetListLength(gIng);i+=IS) if(llList2String(gIng,i+IK)==(string)k){ gIng=llDeleteSubList(gIng,i,i+IS-1); jump d1; }
    @d1;
    integer r = recIndex((string)k);
    if(r != -1) gRec = llDeleteSubList(gRec, r, r+1);
}
scan(){
    gIng = []; gRec = [];
    llWhisper(CRAFT_CHANNEL, "PING");
    llWhisper(CRAFT_CHANNEL, "HOVER"+SEP+(string)gShowHover);
    llSetTimerEvent(2.0);
// Discovery is asynchronous; collect HERE/BLANK replies during the two-second scan window.
}
list presentNames(){
    list names; integer i;
    for(i=0;i<llGetListLength(gIng);i+=IS){
        string n = rowLabel(i);
        if(llListFindList(names,[n])==-1) names += n;
    }
    return names;
}

// ---------- sounds / smoke ----------
loopSnd(string s){ if(s!="" && llGetInventoryType(s)==INVENTORY_SOUND) llLoopSound(s,1.0); }
oneSnd(string s){ if(s!="" && llGetInventoryType(s)==INVENTORY_SOUND) llPlaySound(s,1.0); }
benchSmoke(integer on){
    if(!on){ llParticleSystem([]); return; }
    llParticleSystem([
        PSYS_PART_FLAGS, PSYS_PART_INTERP_COLOR_MASK | PSYS_PART_EMISSIVE_MASK,
        PSYS_SRC_PATTERN, PSYS_SRC_PATTERN_ANGLE_CONE,
        PSYS_PART_START_COLOR, <0.8,0.8,0.8>, PSYS_PART_END_COLOR, <0.5,0.5,0.5>,
        PSYS_PART_START_ALPHA, 0.5, PSYS_PART_END_ALPHA, 0.0,
        PSYS_PART_START_SCALE, <0.15,0.15,0.0>, PSYS_PART_END_SCALE, <0.6,0.6,0.0>,
        PSYS_PART_MAX_AGE, 3.0, PSYS_SRC_BURST_RATE, 0.3, PSYS_SRC_BURST_PART_COUNT, 2,
        PSYS_SRC_BURST_SPEED_MIN, 0.05, PSYS_SRC_BURST_SPEED_MAX, 0.15,
        PSYS_SRC_ACCEL, <0.0,0.0,0.25>, PSYS_SRC_ANGLE_BEGIN, 0.0, PSYS_SRC_ANGLE_END, 0.3
    ]);
}

// ---------- menu ----------
menuTo(key who, string body, list buttons){
    if(gMenuListen!=-1) llListenRemove(gMenuListen);
    gMenuChan = -2000000 - (integer)llFrand(900000.0);
    // REVIEW: validate dialog limits (24-byte button labels and 512-byte body); truncating button count is insufficient.
    gMenuListen = llListen(gMenuChan, "", who, "");
    if(llGetListLength(buttons) > 12) buttons = llList2List(buttons, 0, 11);
    llDialog(who, body, buttons, gMenuChan);
}
string availRecap(){
    string r=""; integer i;
    for(i=0;i<llGetListLength(gIng);i+=IS){
        if(r!="") r+=" | ";
        r += rowLabel(i)+" x"+(string)llList2Integer(gIng,i+IQ);
    }
    return r;
}
string pickRecap(){
    string r=""; list d = distinctPicks(); integer i;
    for(i=0;i<llGetListLength(d);i++){
        string nm = llList2String(d,i);
        if(r!="") r+=" | ";
        r += nm+" x"+(string)countPick(nm);
    }
    return r;
}
showMenu(){
    list names = presentNames();
    if(llGetListLength(names)==0){
        llDialog(gUser, "\nNo ingredient present around the station.", ["OK"], -1234567);
        return;
    }
    list head = ["Cook"];
    if(gUser == llGetOwner()) head += ["Stats:"+llList2String(["OFF","ON"],gShowHover)];
    integer room = 12 - llGetListLength(head);
    if(llGetListLength(names) > room) names = llList2List(names, 0, room-1);
    string body = "Genre(s): "+llDumpList2String(gGenres,", ")+"\n";
    string av = availRecap(); if(av!="") body += "Present: "+av+"\n";
    string pk = pickRecap();  if(pk!="") body += "Basket: "+pk+"\n";
    body += "Containers: "+(string)recCount()+"\n";
    body += "Click an ingredient (+1), then Cook.";
    menuTo(gUser, body, head + names);
}

// ---------- immediate reservation and refunds ----------
consAdd(key k, integer nn){
    integer i;
    for(i=0;i<llGetListLength(gCons);i+=2) if(llList2String(gCons,i)==(string)k){
        gCons = llListReplaceList(gCons, [llList2Integer(gCons,i+1)+nn], i+1, i+1); return;
    }
    gCons += [ (string)k, nn ];
}
refundAll(){
    integer i;
    for(i=0;i<llGetListLength(gCons);i+=2){
        string ck = llList2String(gCons,i);
        if(llGetSubString(ck,0,3) != "KEPT")             // Internal sources remain unchanged until COMMIT, so there is nothing to refund.
            llWhisper(CRAFT_CHANNEL, "REFUND"+SEP+ck+SEP+(string)llList2Integer(gCons,i+1));
    }
    gCons = [];
}

// ---------- action input: temporary stepper until the phase 2 HUD ----------
string packAction(){
    string s=""; integer i;
    for(i=0;i<llGetListLength(gActAxes);i++){
        if(s!="") s+="^";
        // Action values are packed separately from ingredient DNA and injected by Workshop_Eval.
        s += llList2String(gActAxes,i)+"="+(string)llList2Integer(gActVals,i);
    }
    return s;
}
startActionInput(){
    gActVals=[]; integer i;
    for(i=0;i<llGetListLength(gActAxes);i++) gActVals+=0;
    gActIdx=0; promptCurrentAction();
}
promptCurrentAction(){                           // Dispatch by configured modality.
    if(llList2String(gActMods,gActIdx) == "hold"){   // hold: intensity is measured from grinding duration.
        gState=7; gGrindArmed=FALSE;
        llRegionSayTo(gUser, 0, "Grinding '"+llList2String(gActAxes,gActIdx)
            +"': touch to START, touch again to STOP. (Tap twice quickly = no grind.)");
    } else {                                     // hud or other modality: temporary stepper UI.
        gState=6; promptAction();
    }
}
nextAction(){                                    // Advance to the next axis, or cook after the final axis.
    gActIdx++;
    if(gActIdx >= llGetListLength(gActAxes)) cook();
    else promptCurrentAction();
}
promptAction(){
    string ax=llList2String(gActAxes,gActIdx);
    string body="Set action: "+ax+" = "+(string)llList2Integer(gActVals,gActIdx)
        +"\n(modality: "+llList2String(gActMods,gActIdx)+" - stub)\nAdjust then OK.";
    menuTo(gUser, body, ["--","-","+","++","OK"]);
}

// ---------- cook: delegate evaluation to Workshop_Eval ----------
cook(){
    if(llGetListLength(gPicks)==0){
        llRegionSayTo(gUser, 0, "Basket is empty - click an ingredient first, then Cook.");
        gState=0; return;
    }
    gGiveMode = FALSE;
    gState = 5;                                   // Wait for the evaluator.
    llSetTimerEvent(5.0);                         // Timeout if no response arrives.
    // REVIEW: no request ID correlates this result; a late response can be accepted during a later evaluation.
    llMessageLinked(LINK_SET, EVAL_REQ, packAction()+"\n\n"+packBasket(), NULL_KEY);
}

// Finish cutting: ask the plant to give its Mesh object to the recorded player.
finishGive(){
    benchSmoke(FALSE); llStopSound(); llSetText("", ZERO_VECTOR, 0.0);
    string g = "GIVE"+SEP+(string)gGiveKey;                  // The plant gives to the player previously recorded by CUT.
    if(gGiveOrgans != "") g += SEP+gGiveOrgans;              // Multi-organ harvest: name each organ to hand out.
    llWhisper(CRAFT_CHANNEL, g);
    integer ci;                                             // Commit reserved ingredient units.
    // REVIEW: direct delivery commits without checking GIVE success or waiting for any acknowledgement.
    for(ci=0; ci<llGetListLength(gCons); ci+=2)
        llWhisper(CRAFT_CHANNEL, "COMMIT"+SEP+llList2String(gCons,ci));
    gCons=[]; gPicks=[]; gGiveMode=FALSE; gGiveOrgans="";
    llRegionSayTo(gUser, 0, "Cutting done - handed over.");
    gState = 0;
}

// Cooking finished: retain the product until collection is requested.
ready(){
    benchSmoke(FALSE); llStopSound();
    gState = 3;
    string verdict = "ready"; if(rVerdict == 1) verdict = "a DANGEROUS brew";
    llSetText(oName+" ("+oTax+"/"+oStage+")\n"+verdict+" - touch to collect", <0.6,0.9,0.6>, 1.0);
    loopSnd(gReadySnd);
    llRegionSayTo(gUser, 0, oName+" ("+oTax+"/"+oStage+") "+verdict+". Touch the station to collect.");
}

collectMenu(){
    string body = "Ready: "+oName+" ("+oTax+"/"+oStage+") x"+(string)oQty+"\n"
                + "Empty containers present: "+(string)recCount()+"\n"
                + "Collect into containers, Keep inside as a new source, or Discard (lost).";
    menuTo(gUser, body, ["Collect", "Keep", "Discard"]);
}

// Fill available containers; retain any output that does not fit.
deliver(){
    if(recCount() == 0){
        llRegionSayTo(gUser, 0, "No empty container present - still pending. Rez a vial and touch again.");
        gState = 3; return;
    }
    integer delivered = 0;
    while(oQty > 0 && recCount() > 0){
        string rk  = llList2String(gRec, 0);
        integer cap = llList2Integer(gRec, 1);
        // REVIEW: oQty is decremented without CONFIG acknowledgement; a missing/already-filled container silently loses output.
        integer q = oQty;
        if(cap > 0 && q > cap) q = cap;
        llWhisper(CRAFT_CHANNEL, "CONFIG"+SEP+rk+SEP+oName+SEP+(string)q+SEP+(string)oUse
            +SEP+(string)oLife+SEP+oTax+SEP+oStage+SEP+oProps+SEP+oMed+SEP+(string)oEff);
        oQty -= q; delivered += q;
        gRec = llDeleteSubList(gRec, 0, 1);
    }
    llWhisper(CRAFT_CHANNEL, "HOVER"+SEP+(string)gShowHover);
    if(oQty > 0){
        llSetText(oName+" ("+oTax+"/"+oStage+")\nx"+(string)oQty+" pending - touch to collect", <0.6,0.9,0.6>, 1.0);
        llRegionSayTo(gUser, 0, oName+": "+(string)delivered+" delivered, "+(string)oQty+" still pending - provide another container.");
        gState = 3;
    } else {
        llStopSound(); llSetText("", ZERO_VECTOR, 0.0);
        llRegionSayTo(gUser, 0, oName+" fully collected ("+(string)delivered+").");
        gState = 0;
    }
}

discard(){
    llStopSound(); llSetText("", ZERO_VECTOR, 0.0);
    llRegionSayTo(gUser, 0, oName+" discarded - lost.");
    gState = 0;
}

// Keep output inside the station as a new ingredient source.
// Start at inherited freshness (oEff), then age using an expiry timestamp.
// REVIEW: clear output after Keep/delivery/discard and gate menu verbs by state to prevent repeated use of stale output.
keepOutput(){
    // REVIEW: pending output retains frozen oEff until collection/Keep, so waiting does not reduce freshness.
    integer exp = 0;
    if(oLife > 0){
        integer e = oEff; if(e > 1000) e = 1000; if(e < 0) e = 0;
        // REVIEW: e * oLife can overflow for lifetimes above about 24.9 days at full freshness.
        exp = llGetUnixTime() + (e * oLife) / 1000;
    }
    gKept += [ oName, oQty, oTax, oStage, oProps, oLife, exp ];
    saveKept();
    llStopSound(); llSetText("", ZERO_VECTOR, 0.0);
    llRegionSayTo(gUser, 0, oName+" ("+oTax+"/"+oStage+") x"+(string)oQty+" kept inside the station as a new source.");
    gState = 0;
}

default{
    state_entry(){
        llOwnerSay("[MedicalGS] "+VERSION);
        if(gListen!=-1) llListenRemove(gListen);
        gState=0; gPicks=[]; llSetTimerEvent(0.0);
        llSetText("", ZERO_VECTOR, 0.0); llStopSound(); llParticleSystem([]);
        loadConfig();
        // REVIEW: only kept sources persist; script reset loses reservations, cooking progress, and pending output after consumption.
        loadKept();
        gListen = llListen(CRAFT_CHANNEL, "", "", "");
    }

    changed(integer c){ if(c & CHANGED_INVENTORY) loadConfig(); }

    dataserver(key q, string data){
        if(q != gCfgQuery) return;
        if(data == EOF){
            llWhisper(CRAFT_CHANNEL, "HOVER"+SEP+(string)gShowHover);
            if(gCookSnd!="" && llGetInventoryType(gCookSnd)==INVENTORY_SOUND) llPreloadSound(gCookSnd);
            if(gReadySnd!="" && llGetInventoryType(gReadySnd)==INVENTORY_SOUND) llPreloadSound(gReadySnd);
            if(llGetListLength(gGenres)==0) llOwnerSay("[Workshop] no Genre set in bench_config.");
            return;
        }
        applyCfgLine(data);
        gCfgLine++; gCfgQuery = llGetNotecardLine(gCfgNc, gCfgLine);
    }

    // Evaluator response to Cook (Workshop_Eval).
    link_message(integer sender, integer num, string str, key id){
        // REVIEW: validate response code/field count and correlate the sender/request before accepting output.
        if(num != EVAL_RES || gState != 5) return;
        llSetTimerEvent(0.0);
        list p = llParseStringKeepNulls(str, [SEP], []);
        integer code = (integer)llList2String(p,0);
        if(code == 0){                                        // Inert: no rule reacted.
            refundAll(); oneSnd(gFailSnd);
            llRegionSayTo(gUser, 0, "Nothing reacts - the ingredients are returned.");
            gPicks=[]; gState=0;
            return;
        }
        if(code == 2){                                        // Direct inventory delivery: the winning rule gives.
            string giveOrgans = "";                           // "2|leaf^root" = multi-organ harvest; "2" = legacy single Mesh.
            if(llGetListLength(p) > 1) giveOrgans = llList2String(p,1);
            integer idx0 = ingByLabel(llList2String(gPicks, 0));
            // Legacy give needs the principal's single Mesh; organ harvest resolves meshes in the Component.
            if(idx0 == -1 || (giveOrgans == "" && llList2String(gIng, idx0+IMS) == "")){
                refundAll(); oneSnd(gFailSnd);
                llRegionSayTo(gUser, 0, "Nothing to hand over (principal has no Mesh/organ).");
                gPicks=[]; gState=0;
                return;
            }
            gGiveMode = TRUE;
            gGiveOrgans = giveOrgans;
            gGiveKey  = (key)llList2String(gIng, idx0+IK);
            llWhisper(CRAFT_CHANNEL, "CUT"+SEP+(string)gGiveKey+SEP+(string)gUser);  // Send the harvesting player's UUID.
            gState = 2;                                       // The cooking state also represents cutting.
            llSetText("Cutting...", <0.95,0.85,0.5>, 1.0);
            benchSmoke(TRUE); loopSnd(gCookSnd);
            llSetTimerEvent((float)gCookTime);
            return;
        }
        rVerdict = (integer)llList2String(p,1);
        oName    = llList2String(p,2);
        oQty     = (integer)llList2String(p,3);
        oUse     = (integer)llList2String(p,4);
        oLife    = (integer)llList2String(p,5);
        oTax     = llList2String(p,6);
        oStage   = llList2String(p,7);
        oProps   = llList2String(p,8);
        oMed     = llList2String(p,9);
        oEff     = (integer)llList2String(p,10);
        // Final reaction: commit already reserved units, then start cooking.
        integer ci;
        for(ci=0; ci<llGetListLength(gCons); ci+=2){
            string ck2 = llList2String(gCons,ci);
            if(llGetSubString(ck2,0,3) == "KEPT") keptConsume(ck2, llList2Integer(gCons,ci+1));
            else llWhisper(CRAFT_CHANNEL, "COMMIT"+SEP+ck2);
        }
        pruneKept(); saveKept();           // Persist consumption of internal sources.
        gCons=[]; gPicks=[];
        gState = 2;
        llSetText("Cooking...", <0.95,0.85,0.5>, 1.0);
        benchSmoke(TRUE); loopSnd(gCookSnd);
        llSetTimerEvent((float)gCookTime);
    }

    touch_start(integer n){
        key toucher = llDetectedKey(0);
        if(gState == 2){ llRegionSayTo(toucher, 0, "Cooking... please wait."); return; }
        if(gState == 5){ llRegionSayTo(toucher, 0, "Evaluating... please wait."); return; }
        if(gState == 6){ llRegionSayTo(toucher, 0, "Setting action value..."); return; }
        if(gState == 7){                         // Grinding: measure elapsed time for the hold modality.
            if(toucher != gUser){ llRegionSayTo(toucher, 0, "Someone is using the station."); return; }
            if(!gGrindArmed){
                gGrindT0 = llGetTime(); gGrindArmed = TRUE;
                llRegionSayTo(toucher, 0, "Grinding... touch again to stop.");
            } else {
                float dur = llGetTime() - gGrindT0;
                integer val = llRound(dur * gGrindScale);
                if(val < 0) val = 0;
                if(val > gGrindMax) val = gGrindMax;
                gActVals = llListReplaceList(gActVals, [val], gActIdx, gActIdx);
                llRegionSayTo(toucher, 0, "Ground "+(string)llRound(dur)+"s -> "
                    +llList2String(gActAxes,gActIdx)+" = "+(string)val);
                nextAction();
            }
            return;
        }
        if(gState == 4){ llRegionSayTo(toucher, 0, "Looking for a container..."); return; }
        // REVIEW: collection is available to any toucher; enforce ownership here if products belong to the crafting user.
        if(gState == 3){                        // Pending product: scan for collection containers.
            gUser = toucher; gState = 4;
            llRegionSayTo(toucher, 0, "Looking for a container...");
            scan();
            return;
        }
        // REVIEW: a new touch clears gCons without refunding prior picks, including when the same user reopens the menu.
        gUser = toucher; gPicks=[]; gCons=[]; gState=1;
        llRegionSayTo(toucher, 0, "Scanning the station...");
        scan();
    }

    timer(){
        llSetTimerEvent(0.0);
        if(gState == 1){ gState=0; mergeKept(); showMenu(); return; }    // Craft scan completed: open the ingredient menu.
        if(gState == 2){                                     // Cooking finished.
            if(gGiveMode){ finishGive(); return; }           // Direct delivery: the plant gives its inventory object.
            ready(); return;
        }
        if(gState == 4){ gState=3; collectMenu(); return; }  // Collection scan completed: open Collect/Keep/Discard menu.
        if(gState == 5){                                     // Evaluator did not respond.
            refundAll(); oneSnd(gFailSnd);
            llRegionSayTo(gUser, 0, "Evaluator not responding - ingredients returned (is Workshop_Eval present in the linkset?).");
            gPicks=[]; gState=0;
            return;
        }
    }

    listen(integer chan, string nm, key id, string msg){
        if(chan == CRAFT_CHANNEL){
            // REVIEW: authenticate discovery senders and match advertised key to id; HERE/BLANK/GONE are currently trusted blindly.
            list p = llParseStringKeepNulls(msg, [SEP], []);
            string verb = llList2String(p,0);
            if(verb=="HERE"){
                integer heff = 1000;
                if(llGetListLength(p) > 10) heff = (integer)llList2String(p,10);
                string hmesh = "";
                if(llGetListLength(p) > 11) hmesh = llList2String(p,11);
                string horgan = "";
                if(llGetListLength(p) > 12) horgan = llList2String(p,12);
                setIng((key)llList2String(p,1), llList2String(p,2), (integer)llList2String(p,3),
                       llList2String(p,6), llList2String(p,7), llList2String(p,8), (integer)llList2String(p,5), heff, hmesh, horgan);
            }
            else if(verb=="BLANK"){
                string bk = llList2String(p,1);
                if(recIndex(bk) == -1) gRec += [ bk, (integer)llList2String(p,2) ];   // [key, capacity]
            }
            else if(verb=="GONE") forgetKey((key)llList2String(p,1));
            return;
        }
        if(chan == gMenuChan && id == gUser){
            if(gMenuListen!=-1){ llListenRemove(gMenuListen); gMenuListen=-1; }
            if(gState == 6){                      // Temporary stepper: adjust the action axis.
                integer val = llList2Integer(gActVals, gActIdx);
                if(msg=="--") val-=3; else if(msg=="-") val-=1;
                else if(msg=="+") val+=1; else if(msg=="++") val+=3;
                else if(msg=="OK"){ nextAction(); return; }
                gActVals = llListReplaceList(gActVals, [val], gActIdx, gActIdx);
                promptAction(); return;
            }
            // REVIEW: Collect/Keep/Discard are accepted without checking gState; avatar chat on the menu channel can invoke them early.
            if(msg == "Collect"){ deliver(); return; }
            if(msg == "Keep"){ keepOutput(); return; }
            if(msg == "Discard"){ discard(); return; }
            if(id==llGetOwner() && llSubStringIndex(msg,"Stats")==0){
                gShowHover = !gShowHover;
                llWhisper(CRAFT_CHANNEL, "HOVER"+SEP+(string)gShowHover);
                showMenu(); return;
            }
            if(msg == "Cook"){
                if(llGetListLength(gPicks)==0){ llRegionSayTo(gUser,0,"Basket is empty - click an ingredient first, then Cook."); showMenu(); }
                else if(llGetListLength(gActAxes) > 0) startActionInput();
                else cook();
                return;
            }
            // Reserve one unit immediately and track it for a possible inert-reaction refund.
            integer pidx = ingByLabel(msg);
            if(pidx != -1){
                if(llList2String(gIng, pidx+IMS) != "" && countPick(msg) >= 1){   // Mesh/give source: harvest one unit at a time.
                    llRegionSayTo(gUser, 0, "One at a time - harvest "+msg+" singly.");
                    showMenu(); return;
                }
                integer rem = llList2Integer(gIng, pidx+IQ);
                if(rem > 0){
                    key ik = (key)llList2String(gIng, pidx+IK);
                    if(llGetSubString((string)ik,0,3) != "KEPT")
                        llWhisper(CRAFT_CHANNEL, "CONSUME"+SEP+(string)ik+SEP+"1");
                    gIng = llListReplaceList(gIng, [rem-1], pidx+IQ, pidx+IQ);
                    consAdd(ik, 1);
                    // REVIEW: CONSUME is assumed successful; OK/NO replies are ignored, enabling output from stock this workshop never reserved.
                    gPicks += msg;
                    llSay(0, msg+" added to the basket.");
                } else {
                    llRegionSayTo(gUser, 0, "No more "+msg+" available.");
                }
            }
            showMenu();
            return;
        }
    }
}
