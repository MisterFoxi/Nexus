// ============================================================
// Workshop_Eval.lsl - workshop evaluator
// Medical crafting system (MedicalGS).
// ============================================================
// MEMORY SPLIT: heavy token lookup, aggregation, rule resolution, and
// output generation live here to reduce the main script's stack/heap use.
// Share the Workshop.lsl linkset and its tok:/tax:/law: linkset data.
// Use linked messages only; this script does not use CRAFT_CHANNEL.
//
// LINKED-MESSAGE PROTOCOL: one request/response per Cook.
// main -> evaluator (EVAL_REQ): action header + "\n\n" + basket rows,
// each row: rawName|count|tax|stage|props|life|eff|organ, separated by "\n".
// evaluator -> main (EVAL_RES):
// "0" -> inert (no matching rule).
// "2" -> legacy direct delivery (bare "give", principal's single Mesh).
// "2|leaf^root" -> multi-organ harvest (yield): hand out each listed organ's mesh.
// "1|verdict|name|qty|use|life|tax|stage|props|med|eff" -> reaction.
//
// CONFIG notecard "bench_config" (configuration convention: owner-only); reads:
//   Genre, MaxEffect, FluxAbs, NMax, SpoilMin, SpoilMax, Batch
// See Workshop.lsl's header for details and the remaining configuration keys.
// ============================================================

integer EVAL_STREAM = 970202;        // bounded stored input; id = treatment UUID
integer EVAL_STEP = 970203;
integer gConfigReady;
integer gStreaming;
key gStreamRun = NULL_KEY;
integer gStreamIndex;
integer gStreamCount;
list gPrincipal;
integer gMinFreshness;
string gStreamAction;
integer EVAL_REQ = 970200;           // main -> evaluator: basket
integer EVAL_RES = 970201;           // evaluator -> main: result
integer NOTOK    = -999999;          // Sentinel for an unknown token.

integer GS = 8;                      // Fields per basket group (v0.7: + organ).
string  VERSION = "Workshop_Eval v0.7 (2026-10-24)";

// ---- configuration subset used by this evaluator ----
list    gGenres;
integer gMaxEffect = 50;
integer gCfgLine; key gCfgQuery; string gCfgNc;

// ---- duplicate batch curve: m(n) in parts per thousand, [min,max] per n=1..6 ----
// Defaults, overridden by bench_config (Batch/NMax/SpoilMin/SpoilMax).
list    BATCH_MULT = [ 950,1050, 1200,1300, 1400,1500, 1350,1500, 950,1150, 550,800 ];
integer N_MAX = 7;
integer SPOIL_MIN = 0;
integer SPOIL_MAX = 150;
integer gBatchSpoilMul = 1000;

// ---- natural variation: +/- FLUX_ABS per axis, without crossing zero ----
integer FLUX_ABS = 1;

// ---- tokens: read directly from linkset data without copying the table ----
// nameToId -> "tok:<name>"; idToName -> "tok:#<id>" (compiler reverse index).

// ---- aggregate ----
list gAxId; list gAxVal;
list gToks;
list gInert;                         // Inert axis IDs: material does not react to these axes (tax:<id>:inert).
list gNeed;                          // Tokens required for a reaction (tax:<id>:need).

// ---- resolution ----
string  rGenre; string rLid; integer rVerdict; string rDo; integer rCap; integer rFound;
list    rYieldGives;                 // Accumulated organ ids to hand out (yield laws with give=<id>).

// ---- prepared output ----
string oName; integer oQty; integer oUse; integer oLife;
string oTax; string oStage; string oProps; string oMed; integer oEff;

string trim(string s){ return llStringTrim(s, STRING_TRIM); }

// ---------- config ----------
string findConfigNc(){
    integer n = llGetInventoryNumber(INVENTORY_NOTECARD); integer i;
    for(i=0; i<n; i++){
        string nm = llGetInventoryName(INVENTORY_NOTECARD, i);
        if(llToLower(nm) == "bench_config") return nm;
    }
    return "";
}
// REVIEW: configuration reload resets genres only; omitted numeric fields retain previous values and requests can arrive mid-load.
loadConfig(){
    gConfigReady = FALSE;
    gGenres = [];
    gCfgNc = findConfigNc();
    if(gCfgNc == "") return;                        // The main script already reports a missing configuration notecard.
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
    // REVIEW: validate positive MaxEffect/NMax and ordered, bounded Spoil/Batch ranges before applying configuration.
    else if(k=="maxeffect") gMaxEffect=(integer)v;
    else if(k=="fluxabs") FLUX_ABS=(integer)v;
    else if(k=="nmax") N_MAX=(integer)v;
    else if(k=="spoilmin") SPOIL_MIN=(integer)v;
    else if(k=="spoilmax") SPOIL_MAX=(integer)v;
    else if(k=="batch"){                            // m(n) table: [min,max] pairs for successive duplicate counts.
        list b = llParseString2List(v, [",", " "], []);
        integer bn = llGetListLength(b);
        if(bn >= 2 && (bn % 2) == 0){
            BATCH_MULT = []; integer bi;
            for(bi=0; bi<bn; bi++) BATCH_MULT += (integer)llList2String(b,bi);
        } else llOwnerSay("[Eval] bench_config Batch: an even number of values is required; entry ignored.");
    }
    // Other keys (sounds, cooktime, etc.) belong to Workshop.lsl and are ignored here.
}

// ---------- direct token lookup in linkset data ----------
integer nameToId(string nm){
    string s = llLinksetDataRead("tok:"+nm);
    if(s == "") return NOTOK;
    return (integer)s;
}
string idToName(integer id){
    return llLinksetDataRead("tok:#"+(string)id);   // Empty if absent; uses the compiler's reverse index.
}

// ---------- aggregate ----------
axAdd(integer id, integer v){
    integer i = llListFindList(gAxId, [id]);
    if(i == -1){ gAxId += id; gAxVal += v; }
    else gAxVal = llListReplaceList(gAxVal, [llList2Integer(gAxVal,i)+v], i, i);
}
axSet(integer id, integer v){
    integer i = llListFindList(gAxId, [id]);
    if(i == -1){ gAxId += id; gAxVal += v; }
    else gAxVal = llListReplaceList(gAxVal, [v], i, i);
}
integer axGet(integer id){
    integer i = llListFindList(gAxId, [id]);
    if(i == -1) return 0;
    return llList2Integer(gAxVal, i);
}
tokAdd(integer id){ if(llListFindList(gToks,[id])==-1) gToks += id; }
integer tokHas(integer id){ return llListFindList(gToks,[id]) != -1; }
integer inertHas(integer id){ return llListFindList(gInert,[id]) != -1; }

// ---------- batch curve and natural variation ----------
integer randRange(integer lo, integer hi){
    if(hi <= lo) return lo;
    return lo + (integer)llFrand(hi - lo + 1);
}
integer batchMult(integer n){                       // One random m(n) draw in parts per thousand.
    if(n < 1) n = 1;
    integer last = llGetListLength(BATCH_MULT) / 2;
    if(n > last) n = last;
    integer i = (n - 1) * 2;
    return randRange(llList2Integer(BATCH_MULT, i), llList2Integer(BATCH_MULT, i+1));
}
integer fluxAxis(integer v){                        // Apply +/- FLUX_ABS while preserving the sign.
    if(FLUX_ABS <= 0 || v == 0) return v;
    integer v2 = v + randRange(-FLUX_ABS, FLUX_ABS);
    if(v > 0 && v2 <  1) v2 =  1;
    if(v < 0 && v2 > -1) v2 = -1;
    return v2;
}

// Basket groups (stride 7) -> aggregate: batch-scale duplicates, then sum groups.
// Build a new aggregate per request; token presence, inert axes, and required tokens are unioned across inputs.
clearAggregate(){
    gAxId=[]; gAxVal=[]; gToks=[]; gInert=[]; gNeed=[]; gBatchSpoilMul=1000;
}
addGroup(list groups, integer gi){
        integer c  = (integer)llList2String(groups, gi+1);
        string tax = llList2String(groups, gi+2);
        // REVIEW: validate group stride, positive count, known taxonomy/stage, and freshness before using input metadata.
        string stg = llList2String(groups, gi+3);
        string pr  = llList2String(groups, gi+4);

        float mFac = (float)batchMult(c) / 1000.0;
        if(c >= N_MAX){                             // Oversaturation: collapse output potency.
            integer sp = randRange(SPOIL_MIN, SPOIL_MAX);
            if(sp < gBatchSpoilMul) gBatchSpoilMul = sp;
        }
        integer taxId = nameToId(tax);
        if(taxId != NOTOK){
            string tk = llLinksetDataRead("tax:"+(string)taxId+":toks");
            if(tk != ""){
                list tl = llParseString2List(tk, ["^"], []); integer j;
                for(j=0;j<llGetListLength(tl);j++) tokAdd((integer)llList2String(tl,j));
            }
            string tr = llLinksetDataRead("tax:"+(string)taxId+":trait");
            if(tr != ""){
                list trl = llParseString2List(tr, ["^"], []); integer k;
                for(k=0;k<llGetListLength(trl);k++){
                    list kv = llParseString2List(llList2String(trl,k), [":"], []);
                    axAdd((integer)llList2String(kv,0), llRound((float)fluxAxis((integer)llList2String(kv,1)) * mFac));
                }
            }
            string inr = llLinksetDataRead("tax:"+(string)taxId+":inert");  // Axes this material does not react to.
            if(inr != ""){
                list il = llParseString2List(inr, ["^"], []); integer q;
                for(q=0;q<llGetListLength(il);q++){
                    integer iaid = (integer)llList2String(il,q);
                    if(llListFindList(gInert,[iaid])==-1) gInert += iaid;
                }
            }
            string ndq = llLinksetDataRead("tax:"+(string)taxId+":need");  // Required tokens: tokid:quantity^...
            if(ndq != ""){
                list ndl = llParseString2List(ndq, ["^"], []); integer qn;
                for(qn=0;qn<llGetListLength(ndl);qn++){
                    list nkv = llParseString2List(llList2String(ndl,qn), [":"], []);
                    integer ntok = (integer)llList2String(nkv,0);     // Field handles quantities; this gate checks token presence only.
                    if(llListFindList(gNeed,[ntok])==-1) gNeed += ntok;
                }
            }
        }
        integer stgId = nameToId(stg);
        if(stgId != NOTOK) tokAdd(stgId);
        if(pr != ""){
            list pl = llParseString2List(pr, ["^"], []); integer m;
            for(m=0;m<llGetListLength(pl);m++){
                list kv = llParseString2List(llList2String(pl,m), ["="], []);
                integer aid = nameToId(llList2String(kv,0));
                if(aid != NOTOK) axAdd(aid, llRound((float)fluxAxis((integer)llList2String(kv,1)) * mFac));
            }
        }
        // Organ (fresh, pre-transformation): present organ + its tags as tokens, add its trait axes.
        string org = llList2String(groups, gi+7);
        if(org != "" && taxId != NOTOK){
            integer oid = nameToId(org);
            if(oid != NOTOK){
                tokAdd(oid);
                string otg = llLinksetDataRead("tax:"+(string)taxId+":organ:"+(string)oid+":tags");
                if(otg != ""){
                    list otl = llParseString2List(otg, ["^"], []); integer ot;
                    for(ot=0;ot<llGetListLength(otl);ot++) tokAdd((integer)llList2String(otl,ot));
                }
                string otr = llLinksetDataRead("tax:"+(string)taxId+":organ:"+(string)oid+":trait");
                if(otr != ""){
                    list orl = llParseString2List(otr, ["^"], []); integer k2;
                    for(k2=0;k2<llGetListLength(orl);k2++){
                        list okv = llParseString2List(llList2String(orl,k2), [":"], []);
                        axAdd((integer)llList2String(okv,0), llRound((float)fluxAxis((integer)llList2String(okv,1)) * mFac));
                    }
                }
            }
        }
}
buildAggregate(list groups){
    clearAggregate();
    integer i;
    for(i=0; i<llGetListLength(groups); i+=GS) addGroup(groups, i);
}

// ---------- inject action axes before resolving rules ----------
injectAction(string hdr){
    if(hdr=="") return;
    list pl = llParseString2List(hdr, ["^"], []); integer i;
    for(i=0;i<llGetListLength(pl);i++){
        list kv = llParseString2List(llList2String(pl,i), ["="], []);
        if(llGetListLength(kv) >= 2){
            integer aid = nameToId(llList2String(kv,0));
            if(aid != NOTOK) axAdd(aid, (integer)llList2String(kv,1));
            else llOwnerSay("[Eval] Unknown action axis: "+llList2String(kv,0));
        }
    }
}

// ---------- evaluate a tokenized rule condition ----------
// Numeric conditions on an inert axis always fail:
// the material does not react on that axis, so the rule cannot match.
integer evalWhen(string when){
    list terms = llParseString2List(when, ["^"], []); integer i;
    for(i=0;i<llGetListLength(terms);i++){
        string t = llList2String(terms,i);
        integer tz = llSubStringIndex(t, "~");
        integer ge = llSubStringIndex(t, ">=");
        integer le = llSubStringIndex(t, "<=");
        if(tz != -1){                                   // Inclusive axis range: aid~lo~hi.
            list zp = llParseString2List(t, ["~"], []);
            integer zaid = (integer)llList2String(zp,0);
            if(inertHas(zaid)) return FALSE;
            integer zv = axGet(zaid);
            if(zv < (integer)llList2String(zp,1) || zv > (integer)llList2String(zp,2)) return FALSE;
        } else if(ge != -1){
            integer aid = (integer)llGetSubString(t,0,ge-1);
            integer kk  = (integer)llGetSubString(t,ge+2,-1);
            if(inertHas(aid)) return FALSE;
            if(axGet(aid) < kk) return FALSE;
        } else if(le != -1){
            integer aid = (integer)llGetSubString(t,0,le-1);
            integer kk  = (integer)llGetSubString(t,le+2,-1);
            if(inertHas(aid)) return FALSE;
            if(axGet(aid) > kk) return FALSE;
        } else {
            integer eq = llSubStringIndex(t, "=");
            if(eq != -1){
                integer vid = (integer)llGetSubString(t,eq+1,-1);
                if(!tokHas(vid)) return FALSE;
            } else {
                if(!tokHas((integer)t)) return FALSE;
            }
        }
    }
    return TRUE;
}
integer countTerms(string when){ return llGetListLength(llParseString2List(when,["^"],[])); }

// Most conditions wins; sequence breaks ties. Store the winning rule in r*.
resolve(){
    rFound = FALSE; rYieldGives = []; integer bestTerms = -1; integer bestSeq = 0x7FFFFFFF;
    // Required-token gate: any missing token makes the mixture inert.
    integer nq;
    for(nq=0; nq<llGetListLength(gNeed); nq++)
        if(llListFindList(gToks, [llList2Integer(gNeed,nq)]) == -1) return;
    integer gi;
    // REVIEW: rule lookup scans only the first 1024 matching keys and has no pagination; later rules can be silently skipped.
    for(gi=0; gi<llGetListLength(gGenres); gi++){
        string g = llList2String(gGenres, gi);
        // REVIEW: genre is inserted into a regular expression without escaping; regex metacharacters alter matching.
        list keys = llLinksetDataFindKeys("^law:"+g+":", 0, 1024);
        integer i;
        for(i=0;i<llGetListLength(keys);i++){
            string wkey = llList2String(keys,i);
            if(llGetSubString(wkey,-5,-1) != ":when") jump nextk;
            list parts = llParseString2List(wkey, [":"], []);
            string lid = llList2String(parts, 2);
            string when = llLinksetDataRead(wkey);
            if(evalWhen(when)){
                integer v = (integer)llLinksetDataRead("law:"+g+":"+lid+":verdict");
                string doo = llLinksetDataRead("law:"+g+":"+lid+":do");
                if(v == 2){                                   // yield: accumulate give targets (out of contest)
                    list dl = llParseString2List(doo, ["^"], []); integer di;
                    for(di=0; di<llGetListLength(dl); di++){
                        string cc = llList2String(dl,di);
                        if(llGetSubString(cc,0,4) == "give="){
                            integer goid = (integer)llGetSubString(cc,5,-1);
                            if(llListFindList(rYieldGives,[goid]) == -1) rYieldGives += goid;
                        }
                    }
                } else {                                      // react/danger: most terms wins; seq breaks ties
                    integer terms = countTerms(when);
                    integer seq = (integer)llLinksetDataRead("law:"+g+":"+lid+":seq");
                    if(terms > bestTerms || (terms == bestTerms && seq < bestSeq)){
                        bestTerms = terms; bestSeq = seq;
                        rGenre = g; rLid = lid; rFound = TRUE;
                        rVerdict = v; rDo = doo;
                        string cs = llLinksetDataRead("law:"+g+":"+lid+":cap");
                        if(cs == "") rCap = 0; else rCap = (integer)cs;
                    }
                }
            }
            @nextk;
        }
    }
}

// Apply the winning rule's operations and serialize output DNA into o*.
// The first basket group provides name, quantity, lifetime, and default taxonomy/stage.
buildOutput(list groups){
    integer metaTax   = nameToId("meta.taxonomy");
    integer metaStage = nameToId("meta.stage");

    oName  = llList2String(groups, 0);            // Raw name without the /stage suffix.
    oQty   = (integer)llList2String(groups, 1);   // Principal ingredient count.
    oUse   = 1;                                   // Use is reserved for potion application doses; crafting does not use it.
    oLife  = (integer)llList2String(groups, 5);
    oMed   = "";
    // Inherit the lowest freshness among all inputs.
    oEff = 1000;
    if(gStreaming) oEff = gMinFreshness;
    else {
    integer n = llGetListLength(groups); integer gi;
    for(gi=0; gi<n; gi+=GS){
        // REVIEW: input freshness is not validated or clamped to 0..1000 before inheritance.
        integer eE = (integer)llList2String(groups, gi+6);
        if(eE < oEff) oEff = eE;
    }
    }
    integer outTaxId   = nameToId(llList2String(groups, 2));
    integer outStageId = nameToId(llList2String(groups, 3));

    float effMul = 1.0;
    float qtyMul = 1.0;
    list labels;

    if(rDo != ""){
        list cl = llParseString2List(rDo, ["^"], []); integer i;
        for(i=0;i<llGetListLength(cl);i++){
            string c = llList2String(cl,i);
            if(llGetSubString(c,0,3) == "eff*"){
                effMul *= (float)llGetSubString(c,4,-1);
            } else if(llGetSubString(c,0,3) == "qty*"){
                qtyMul *= (float)llGetSubString(c,4,-1);
            } else if(llGetSubString(c,0,0) == "+"){
                labels += (integer)llGetSubString(c,1,-1);
            } else if(llGetSubString(c,0,0) == "-"){
                integer li = llListFindList(labels, [(integer)llGetSubString(c,1,-1)]);
                if(li != -1) labels = llDeleteSubList(labels, li, li);
            } else {
                integer st = llSubStringIndex(c, "*");
                integer eq = llSubStringIndex(c, "=");
                if(st != -1){
                    integer aid = (integer)llGetSubString(c,0,st-1);
                    float f = (float)llGetSubString(c,st+1,-1);
                    axSet(aid, llRound((float)axGet(aid) * f));
                } else if(eq != -1){
                    integer did = (integer)llGetSubString(c,0,eq-1);
                    integer vid = (integer)llGetSubString(c,eq+1,-1);
                    if(did == metaStage) outStageId = vid;
                    else if(did == metaTax) outTaxId = vid;
                }
            }
        }
    }

    // Yield (qty*): scale output quantity, round down, and enforce at least one unit.
    // REVIEW: qty* <= 0 still produces one unit; confirm whether zero yield should instead reject/consume without output.
    if(qtyMul != 1.0){
        oQty = llFloor((float)oQty * qtyMul);
        if(oQty < 1) oQty = 1;
    }

    // Oversaturation reduces potency through the batch spoil multiplier.
    effMul *= (float)gBatchSpoilMul / 1000.0;

    // Bound the rule's effect cap by MaxEffect.
    integer cap = gMaxEffect;
    if(rCap > 0 && rCap < cap) cap = rCap;

    // Serialize axes: apply effMul to act.* and clamp values to +/- cap.
    oProps = "";
    integer na = llGetListLength(gAxId); integer k;
    for(k=0; k<na; k++){
        integer id = llList2Integer(gAxId, k);
        integer val = llList2Integer(gAxVal, k);
        string nm = idToName(id);
        if(nm != "" && llSubStringIndex(nm, "meta.") != 0){   // meta.* axes only gate rules (e.g. elapsed_time); never serialize them into output.
            if(llSubStringIndex(nm, "act.") == 0) val = llRound((float)val * effMul);
            if(val >  cap) val =  cap;
            if(val < -cap) val = -cap;
            if(oProps != "") oProps += "^";
            oProps += nm + "=" + (string)val;
        }
    }
    integer lj;
    for(lj=0; lj<llGetListLength(labels); lj++){
        string lnm = idToName(llList2Integer(labels, lj));
        if(lnm != ""){ if(oProps != "") oProps += "^"; oProps += lnm + "=1"; }
    }

    oTax   = idToName(outTaxId);
    oStage = idToName(outStageId);
}

// Parse newline/pipe basket input into a flat list with stride 7.
list parseBasket(string s){
    list out = [];
    list gl = llParseStringKeepNulls(s, ["\n"], []);
    integer i;
    // REVIEW: validate exactly GS fields per row before flattening; malformed rows shift all following group indexes.
    for(i=0;i<llGetListLength(gl);i++){
        string g = llList2String(gl,i);
        if(g != "") out += llParseStringKeepNulls(g, ["|"], []);
    }
    return out;
}


sendResult(string result, key request){
    if(gStreaming){
        integer stored = llLinksetDataWrite("ws:eval:result", llList2Json(JSON_ARRAY,[request,result]));
        if(stored == 0 || stored == 5) llMessageLinked(LINK_THIS,EVAL_RES,"STORED",request);
        else llMessageLinked(LINK_THIS,EVAL_RES,"ERROR|Cannot save evaluation result.",request);
        gStreamRun=NULL_KEY;
    } else llMessageLinked(LINK_SET,EVAL_RES,result,request);
}
evaluate(list groups, string actHdr, key request){
        // REVIEW: require a complete configuration and loaded rule data before evaluating; partial loading can yield false inert results.
        injectAction(actHdr);
        resolve();
        // Multi-organ harvest (yield): hand out each accumulated organ the principal species actually has.
        if(llGetListLength(rYieldGives) > 0){
            integer ptax = nameToId(llList2String(groups, 2));
            list haveO = [];
            if(ptax != NOTOK){
                string os = llLinksetDataRead("tax:"+(string)ptax+":organs");
                if(os != "") haveO = llParseString2List(os, ["^"], []);
            }
            string giveList = ""; integer yi;
            for(yi=0; yi<llGetListLength(rYieldGives); yi++){
                integer goid = llList2Integer(rYieldGives, yi);
                if(llListFindList(haveO, [(string)goid]) != -1){        // only organs the species declares
                    string onm = idToName(goid);
                    if(onm != ""){ if(giveList != "") giveList += "^"; giveList += onm; }
                }
            }
            if(giveList != ""){
                sendResult("2|"+giveList, request);
                gAxId=[]; gAxVal=[]; gToks=[]; gInert=[]; gNeed=[]; rYieldGives=[];
                return;
            }
        }
        if(!rFound){
            sendResult("0", request);   // Inert: no matching rule.
        } else if(llListFindList(llParseString2List(rDo, ["^"], []), ["give"]) != -1){
            sendResult("2", request);   // Legacy direct delivery: bare "give".
        } else {
            buildOutput(groups);
            string res = "1|"+(string)rVerdict+"|"+oName+"|"+(string)oQty+"|"+(string)oUse
                +"|"+(string)oLife+"|"+oTax+"|"+oStage+"|"+oProps+"|"+oMed+"|"+(string)oEff;
            sendResult(res, request);
        }

    gAxId=[]; gAxVal=[]; gToks=[]; gInert=[]; gNeed=[]; rYieldGives=[];
    gPrincipal=[]; gStreaming=FALSE;
}
streamStep(){
    if(gStreamRun == NULL_KEY) return;
    if(gStreamIndex >= gStreamCount){
        evaluate(gPrincipal,gStreamAction,gStreamRun);
        return;
    }
    list group=llParseStringKeepNulls(llLinksetDataRead("ws:in:group:"+(string)gStreamIndex),["|"],[]);
    if(llGetListLength(group) != GS || llList2Integer(group,1) < 1){
        llMessageLinked(LINK_THIS,EVAL_RES,"ERROR|Invalid stored evaluation group.",gStreamRun);
        gStreamRun=NULL_KEY; gStreaming=FALSE; clearAggregate(); return;
    }
    if(gStreamIndex == 0) gPrincipal=group;
    integer freshness=llList2Integer(group,6);
    if(freshness < gMinFreshness) gMinFreshness=freshness;
    addGroup(group,0);
    ++gStreamIndex;
    llMessageLinked(LINK_THIS,EVAL_STEP,"",gStreamRun);
}
evalReady(){ if(gConfigReady) llMessageLinked(LINK_THIS,970299,"EVAL",NULL_KEY); }
default{
    state_entry(){ llOwnerSay("[MedicalGS] "+VERSION+"; progressive Workshop input"); loadConfig(); }
    changed(integer c){ if(c & CHANGED_INVENTORY) loadConfig(); }
    dataserver(key q,string data){
        if(q != gCfgQuery) return;
        if(data == EOF){
            gConfigReady=llGetListLength(gGenres)>0;
            if(!gConfigReady) llOwnerSay("[Eval] no Genre set in bench_config.");
            evalReady(); return;
        }
        applyCfgLine(data); ++gCfgLine; gCfgQuery=llGetNotecardLine(gCfgNc,gCfgLine);
    }
    link_message(integer sender,integer num,string str,key id){
        if(num == 970298){ evalReady(); return; }
        if(num == 970290){ llOwnerSay("[Workshop Eval] Free: "+(string)llGetFreeMemory()); return; }
        if(num == EVAL_STEP && sender == llGetLinkNumber() && id == gStreamRun){ streamStep(); return; }
        if(num == EVAL_STREAM && sender == llGetLinkNumber()){
            if(id == NULL_KEY || !gConfigReady) return;
            list cached=llJson2List(llLinksetDataRead("ws:eval:result"));
            if(llList2Key(cached,0) == id){ llMessageLinked(LINK_THIS,EVAL_RES,"STORED",id); return; }
            if(gStreamRun != NULL_KEY) return;
            list input=llJson2List(llLinksetDataRead("ws:input"));
            if(llList2Key(input,0) != id || llList2String(input,1) != "READY" || llList2Integer(input,3)<1){
                llMessageLinked(LINK_THIS,EVAL_RES,"ERROR|Stored input not ready.",id); return;
            }
            clearAggregate(); gStreaming=TRUE; gStreamRun=id;
            gStreamIndex=0; gStreamCount=llList2Integer(input,3); gMinFreshness=1000;
            gPrincipal=[]; gStreamAction=str;
            llMessageLinked(LINK_THIS,EVAL_STEP,"",id); return;
        }
        // Field's existing direct request remains available in its own linkset.
        if(num != EVAL_REQ || gStreamRun != NULL_KEY) return;
        string actHdr=""; string body=str;
        integer sp=llSubStringIndex(str,"\n\n");
        if(sp != -1){
            if(sp>0) actHdr=llGetSubString(str,0,sp-1);
            body=llGetSubString(str,sp+2,-1);
        }
        list groups=parseBasket(body);
        if(llGetListLength(groups)<GS || llGetListLength(groups)%GS){
            llMessageLinked(LINK_SET,EVAL_RES,"0",id); return;
        }
        gStreaming=FALSE; buildAggregate(groups); evaluate(groups,actHdr,id);
    }
}
