#define SCRIPT_NAME    "WS_Eval"
#define SCRIPT_VERSION "v0.2.0"
#include "nexus_header"

// WS_Eval — bench-local engine (refonte option 1). Two read paths over the shared LinksetData world
// (tok:/tax:/law:, written by WS_Boot) and the bench genre/config:
//
//   OBSERVE (read-only, unchanged since v0.1): a consult() of the observe_when rules; replies to the HUD.
//     HUD -> WS_Eval (NX_HUD): NX|OBSERVE|<session>|<nameEsc>|<snapshotEsc>
//     WS_Eval -> HUD (NX_HUD): NX|OBSERVED|<session>|OK|<descEsc>|<nameEsc> | NONE | ERR
//
//   TAKE (transformation): resolve the react/yield laws and build the product DNA. The result is handed to
//     WS_Core (bench link EVAL_TAKE_RES), which drives COMMIT|OUT + the récipient CONFIG + craft closure.
//     HUD -> WS_Eval (NX_HUD): NX|TAKE|<session>|<nameEsc>|<snapshotEsc>
//     WS_Eval -> WS_Core (link EVAL_TAKE_RES, holder in id):
//        "1|verdict|name|qty|use|life|tax|stage|props|med|eff"   a reaction (product DNA)
//        "2" | "2|leaf^root"                                     legacy / multi-organ harvest (give)
//        "0"                                                     inert: nothing reacts
//
//   snapshot = "<actionHeader>\n\n<group>\n<group>...",  actionHeader = axis=val^...,
//     group = taxonomy|count|use|stage|props|life|eff|organ   (name is carried separately = <nameEsc>)
//
// OBSERVE uses midpoints and no random flux (a consultation must not spend the craft's randomness);
// TAKE uses the real batch draw + natural flux + oversaturation spoil (gObserving gates all of it).

integer NX_HUD = -918282;
integer EVAL_TAKE_RES = 918430;      // -> WS_Core: transformation result ("1|..."/"2[|..]"/"0"), holder in id
integer GS = 8;                      // fields per snapshot group
integer NOTOK = -999999;             // sentinel for an unknown token

// duplicate batch curve: [min,max] pairs (ppm), per duplicate count n. Overridable by ws:cfg:Batch.
list    BATCH_MULT = [ 950,1050, 1200,1300, 1400,1500, 1350,1500, 950,1150, 550,800 ];
integer N_MAX = 7;
integer gMaxEffect = 50;             // ws:cfg:MaxEffect — output axis cap
integer SPOIL_MIN = 0;               // ws:cfg:SpoilMin — oversaturation spoil floor (ppm)
integer SPOIL_MAX = 150;             // ws:cfg:SpoilMax — oversaturation spoil ceiling (ppm)
integer FLUX_ABS = 1;                // ws:cfg:FluxAbs — +/- natural variation per axis
integer gBatchSpoilMul = 1000;       // oversaturation potency multiplier for this request (ppm)
integer gObserving;                  // TRUE during consult(): midpoints, no flux, no random spoil

// aggregate (rebuilt per request)
list gAxId; list gAxVal;             // numeric axes (parallel: token id -> value)
list gToks;                          // flat token presence set
list gCats;                          // stride 2: dimension token id, value token id (meta.taxonomy/stage/organ)
integer gTaxDim; integer gStageDim; integer gOrganDim;
list gInert;                         // axes the material does not react to
list gNeed;                          // required tokens (gate)

// resolution (single genre = ws:genre)
string  rLid; integer rVerdict; string rDo; integer rCap; integer rFound;
list    rYieldGives;                 // organ ids to hand out (yield laws with give=<id>)

// prepared output
string  gTakeName;                   // product base name = the basket name sent with NX|TAKE
string  oName; integer oQty; integer oUse; integer oLife;
string  oTax; string oStage; string oProps; string oMed; integer oEff;

integer nameToId(string nm)
{
    string s = llLinksetDataRead("tok:" + nm);
    if(s == "") return NOTOK;
    return (integer)s;
}
string idToName(integer id){ return llLinksetDataRead("tok:#" + (string)id); }

axAdd(integer id, integer v)
{
    integer i = llListFindList(gAxId, [id]);
    if(i == -1){ gAxId += id; gAxVal += v; }
    else gAxVal = llListReplaceList(gAxVal, [llList2Integer(gAxVal, i) + v], i, i);
}
axSet(integer id, integer v)
{
    integer i = llListFindList(gAxId, [id]);
    if(i == -1){ gAxId += id; gAxVal += v; }
    else gAxVal = llListReplaceList(gAxVal, [v], i, i);
}
integer axGet(integer id)
{
    integer i = llListFindList(gAxId, [id]);
    if(i == -1) return 0;
    return llList2Integer(gAxVal, i);
}
integer axHas(integer id){ return llListFindList(gAxId, [id]) != -1; }
tokAdd(integer id){ if(llListFindList(gToks, [id]) == -1) gToks += id; }
integer tokHas(integer id){ return llListFindList(gToks, [id]) != -1; }
integer catHas(integer dim, integer val)
{
    integer i;
    for(i = 0; i < llGetListLength(gCats); i += 2)
        if(llList2Integer(gCats, i) == dim && llList2Integer(gCats, i + 1) == val) return TRUE;
    return FALSE;
}
catAdd(integer dim, integer val)
{
    tokAdd(val);
    if(dim != NOTOK && !catHas(dim, val)) gCats += [dim, val];
}
integer inertHas(integer id){ return llListFindList(gInert, [id]) != -1; }

integer randRange(integer lo, integer hi)
{
    if(hi <= lo) return lo;
    return lo + (integer)llFrand(hi - lo + 1);
}
integer batchMult(integer n)         // observe: midpoint; take: one random draw in the [min,max] pair (ppm)
{
    if(n < 1) n = 1;
    integer last = llGetListLength(BATCH_MULT) / 2;
    if(n > last) n = last;
    integer i = (n - 1) * 2;
    if(gObserving) return llRound(((float)llList2Integer(BATCH_MULT, i) + (float)llList2Integer(BATCH_MULT, i + 1)) / 2.0);
    return randRange(llList2Integer(BATCH_MULT, i), llList2Integer(BATCH_MULT, i + 1));
}
integer fluxAxis(integer v)          // +/- FLUX_ABS, sign-preserving; identity during observe
{
    if(gObserving) return v;
    if(FLUX_ABS <= 0 || v == 0) return v;
    integer v2 = v + randRange(-FLUX_ABS, FLUX_ABS);
    if(v > 0 && v2 <  1) v2 =  1;
    if(v < 0 && v2 > -1) v2 = -1;
    return v2;
}

loadCfg()
{
    string b = llLinksetDataRead("ws:cfg:Batch");
    if(b != ""){
        list bl = llParseString2List(b, [",", " "], []);
        integer bn = llGetListLength(bl);
        if(bn >= 2 && (bn % 2) == 0){
            BATCH_MULT = [];
            integer bi;
            for(bi = 0; bi < bn; bi++) BATCH_MULT += (integer)llList2String(bl, bi);
        }
    }
    string nm = llLinksetDataRead("ws:cfg:NMax");       if(nm != "") N_MAX = (integer)nm;
    string me = llLinksetDataRead("ws:cfg:MaxEffect");  if(me != "") gMaxEffect = (integer)me;
    string sn = llLinksetDataRead("ws:cfg:SpoilMin");   if(sn != "") SPOIL_MIN = (integer)sn;
    string sx = llLinksetDataRead("ws:cfg:SpoilMax");   if(sx != "") SPOIL_MAX = (integer)sx;
    string fa = llLinksetDataRead("ws:cfg:FluxAbs");    if(fa != "") FLUX_ABS = (integer)fa;
}

clearAggregate()
{
    gAxId = []; gAxVal = []; gToks = []; gCats = []; gInert = []; gNeed = []; gBatchSpoilMul = 1000;
    gTaxDim = nameToId("meta.taxonomy");
    gStageDim = nameToId("meta.stage");
    gOrganDim = nameToId("meta.organ");
}

// group fields: 0 taxonomy | 1 count | 2 use | 3 stage | 4 props | 5 life | 6 eff | 7 organ
addGroup(list g)
{
    integer c = (integer)llList2String(g, 1);
    string tax = llList2String(g, 0);
    string stg = llList2String(g, 3);
    string pr  = llList2String(g, 4);
    string org = llList2String(g, 7);
    float mFac = (float)batchMult(c) / 1000.0;
    if(c >= N_MAX){                                 // oversaturation: collapse output potency (take only)
        integer sp = SPOIL_MIN;
        if(!gObserving) sp = randRange(SPOIL_MIN, SPOIL_MAX);
        if(sp < gBatchSpoilMul) gBatchSpoilMul = sp;
    }
    integer taxId = nameToId(tax);
    if(taxId != NOTOK){
        string tk = llLinksetDataRead("tax:" + (string)taxId + ":toks");
        if(tk != ""){
            list tl = llParseString2List(tk, ["^"], []);
            integer j;
            for(j = 0; j < llGetListLength(tl); j++) catAdd(gTaxDim, (integer)llList2String(tl, j));
        }
        string tr = llLinksetDataRead("tax:" + (string)taxId + ":trait");
        if(tr != ""){
            list trl = llParseString2List(tr, ["^"], []);
            integer k;
            for(k = 0; k < llGetListLength(trl); k++){
                list kv = llParseString2List(llList2String(trl, k), [":"], []);
                axAdd((integer)llList2String(kv, 0), llRound((float)fluxAxis((integer)llList2String(kv, 1)) * mFac));
            }
        }
        string inr = llLinksetDataRead("tax:" + (string)taxId + ":inert");
        if(inr != ""){
            list il = llParseString2List(inr, ["^"], []);
            integer q;
            for(q = 0; q < llGetListLength(il); q++){
                integer iaid = (integer)llList2String(il, q);
                if(llListFindList(gInert, [iaid]) == -1) gInert += iaid;
            }
        }
        string ndq = llLinksetDataRead("tax:" + (string)taxId + ":need");
        if(ndq != ""){
            list ndl = llParseString2List(ndq, ["^"], []);
            integer qn;
            for(qn = 0; qn < llGetListLength(ndl); qn++){
                list nkv = llParseString2List(llList2String(ndl, qn), [":"], []);
                integer ntok = (integer)llList2String(nkv, 0);
                if(llListFindList(gNeed, [ntok]) == -1) gNeed += ntok;
            }
        }
    }
    integer stgId = nameToId(stg);
    if(stgId != NOTOK) catAdd(gStageDim, stgId);
    if(pr != ""){
        list pl = llParseString2List(pr, ["^"], []);
        integer m;
        for(m = 0; m < llGetListLength(pl); m++){
            list kv = llParseString2List(llList2String(pl, m), ["="], []);
            integer aid = nameToId(llList2String(kv, 0));
            if(aid != NOTOK) axAdd(aid, llRound((float)fluxAxis((integer)llList2String(kv, 1)) * mFac));
        }
    }
    if(org != "" && taxId != NOTOK){
        integer oid = nameToId(org);
        if(oid != NOTOK){
            catAdd(gOrganDim, oid);
            string otg = llLinksetDataRead("tax:" + (string)taxId + ":organ:" + (string)oid + ":tags");
            if(otg != ""){
                list otl = llParseString2List(otg, ["^"], []);
                integer ot;
                for(ot = 0; ot < llGetListLength(otl); ot++) catAdd(gOrganDim, (integer)llList2String(otl, ot));
            }
            string otr = llLinksetDataRead("tax:" + (string)taxId + ":organ:" + (string)oid + ":trait");
            if(otr != ""){
                list orl = llParseString2List(otr, ["^"], []);
                integer k2;
                for(k2 = 0; k2 < llGetListLength(orl); k2++){
                    list okv = llParseString2List(llList2String(orl, k2), [":"], []);
                    axAdd((integer)llList2String(okv, 0), llRound((float)fluxAxis((integer)llList2String(okv, 1)) * mFac));
                }
            }
        }
    }
}

injectAction(string hdr)
{
    if(hdr == "") return;
    list pl = llParseString2List(hdr, ["^"], []);
    integer i;
    for(i = 0; i < llGetListLength(pl); i++){
        list kv = llParseString2List(llList2String(pl, i), ["="], []);
        if(llGetListLength(kv) >= 2){
            integer aid = nameToId(llList2String(kv, 0));
            if(aid != NOTOK) axAdd(aid, (integer)llList2String(kv, 1));
        }
    }
}

// Evaluate a tokenized condition against the aggregate. A numeric condition on an inert axis always fails.
// During OBSERVE a numeric condition on an ABSENT axis also fails (do not claim an observation about an axis
// that is not present). During TAKE an absent axis reads as 0 and the numeric comparison proceeds.
integer evalWhen(string when)
{
    list terms = llParseString2List(when, ["^"], []);
    integer i;
    for(i = 0; i < llGetListLength(terms); i++){
        string t = llList2String(terms, i);
        integer tz = llSubStringIndex(t, "~");
        integer ge = llSubStringIndex(t, ">=");
        integer le = llSubStringIndex(t, "<=");
        if(tz != -1){
            list zp = llParseString2List(t, ["~"], []);
            integer zaid = (integer)llList2String(zp, 0);
            if(inertHas(zaid)) return FALSE;
            if(gObserving && !axHas(zaid)) return FALSE;
            integer zv = axGet(zaid);
            if(zv < (integer)llList2String(zp, 1) || zv > (integer)llList2String(zp, 2)) return FALSE;
        } else if(ge != -1){
            integer aid = (integer)llGetSubString(t, 0, ge - 1);
            integer kk = (integer)llGetSubString(t, ge + 2, -1);
            if(inertHas(aid)) return FALSE;
            if(gObserving && !axHas(aid)) return FALSE;
            if(axGet(aid) < kk) return FALSE;
        } else if(le != -1){
            integer aid = (integer)llGetSubString(t, 0, le - 1);
            integer kk = (integer)llGetSubString(t, le + 2, -1);
            if(inertHas(aid)) return FALSE;
            if(gObserving && !axHas(aid)) return FALSE;
            if(axGet(aid) > kk) return FALSE;
        } else {
            integer eq = llSubStringIndex(t, "=");
            if(eq != -1){
                integer dim = (integer)llGetSubString(t, 0, eq - 1);
                integer vid = (integer)llGetSubString(t, eq + 1, -1);
                if(dim == gTaxDim || dim == gStageDim || dim == gOrganDim){
                    if(!catHas(dim, vid)) return FALSE;
                } else if(!tokHas(vid)) return FALSE;
            } else {
                if(!tokHas((integer)t)) return FALSE;
            }
        }
    }
    return TRUE;
}
integer countTerms(string when){ return llGetListLength(llParseString2List(when, ["^"], [])); }

// Most conditions win; sequence breaks ties. Yield laws (verdict 2, give=<id>) accumulate out of contest.
resolve()
{
    rFound = FALSE; rYieldGives = []; integer bestTerms = -1; integer bestSeq = 0x7FFFFFFF;
    integer nq;
    for(nq = 0; nq < llGetListLength(gNeed); nq++)
        if(llListFindList(gToks, [llList2Integer(gNeed, nq)]) == -1) return;   // required-token gate -> inert
    string g = llLinksetDataRead("ws:genre");
    if(g == "") return;
    list keys = llLinksetDataFindKeys("^law:" + g + ":", 0, 1024);
    integer i;
    for(i = 0; i < llGetListLength(keys); i++){
        string wkey = llList2String(keys, i);
        if(llGetSubString(wkey, -5, -1) != ":when") jump nextk;
        list parts = llParseString2List(wkey, [":"], []);
        string lid = llList2String(parts, 2);
        string when = llLinksetDataRead(wkey);
        if(evalWhen(when)){
            integer v = (integer)llLinksetDataRead("law:" + g + ":" + lid + ":verdict");
            string doo = llLinksetDataRead("law:" + g + ":" + lid + ":do");
            if(v == 2){
                list dl = llParseString2List(doo, ["^"], []);
                integer di;
                for(di = 0; di < llGetListLength(dl); di++){
                    string cc = llList2String(dl, di);
                    if(llGetSubString(cc, 0, 4) == "give="){
                        integer goid = (integer)llGetSubString(cc, 5, -1);
                        if(llListFindList(rYieldGives, [goid]) == -1) rYieldGives += goid;
                    }
                }
            } else {
                integer terms = countTerms(when);
                integer seq = (integer)llLinksetDataRead("law:" + g + ":" + lid + ":seq");
                if(terms > bestTerms || (terms == bestTerms && seq < bestSeq)){
                    bestTerms = terms; bestSeq = seq;
                    rLid = lid; rFound = TRUE; rVerdict = v; rDo = doo;
                    string cs = llLinksetDataRead("law:" + g + ":" + lid + ":cap");
                    if(cs == "") rCap = 0; else rCap = (integer)cs;
                }
            }
        }
        @nextk;
    }
}

// Apply the winning rule to the aggregate, serialize product DNA into o*. name = gTakeName (basket name).
buildOutput(list groups)
{
    integer metaTax   = nameToId("meta.taxonomy");
    integer metaStage = nameToId("meta.stage");

    oName = gTakeName;
    oQty  = (integer)llList2String(groups, 1);
    oUse  = (integer)llList2String(groups, 2);
    oLife = (integer)llList2String(groups, 5);
    oMed  = "";
    oEff  = 1000;
    integer n = llGetListLength(groups);
    integer gi;
    for(gi = 0; gi < n; gi += GS){
        integer eE = (integer)llList2String(groups, gi + 6);
        if(eE < oEff) oEff = eE;
    }
    integer outTaxId   = nameToId(llList2String(groups, 0));
    integer outStageId = nameToId(llList2String(groups, 3));

    float effMul = 1.0;
    float qtyMul = 1.0;
    list labels;

    if(rDo != ""){
        list cl = llParseString2List(rDo, ["^"], []);
        integer i;
        for(i = 0; i < llGetListLength(cl); i++){
            string c = llList2String(cl, i);
            if(llGetSubString(c, 0, 3) == "eff*"){
                effMul *= (float)llGetSubString(c, 4, -1);
            } else if(llGetSubString(c, 0, 3) == "qty*"){
                qtyMul *= (float)llGetSubString(c, 4, -1);
            } else if(llGetSubString(c, 0, 0) == "+"){
                labels += (integer)llGetSubString(c, 1, -1);
            } else if(llGetSubString(c, 0, 0) == "-"){
                integer li = llListFindList(labels, [(integer)llGetSubString(c, 1, -1)]);
                if(li != -1) labels = llDeleteSubList(labels, li, li);
            } else {
                integer st = llSubStringIndex(c, "*");
                integer eq = llSubStringIndex(c, "=");
                if(st != -1){
                    integer aid = (integer)llGetSubString(c, 0, st - 1);
                    float f = (float)llGetSubString(c, st + 1, -1);
                    axSet(aid, llRound((float)axGet(aid) * f));
                } else if(eq != -1){
                    integer did = (integer)llGetSubString(c, 0, eq - 1);
                    integer vid = (integer)llGetSubString(c, eq + 1, -1);
                    if(did == metaStage) outStageId = vid;
                    else if(did == metaTax) outTaxId = vid;
                }
            }
        }
    }

    if(qtyMul != 1.0){
        oQty = llFloor((float)oQty * qtyMul);
        if(oQty < 1) oQty = 1;
    }

    effMul *= (float)gBatchSpoilMul / 1000.0;           // oversaturation reduces potency

    integer cap = gMaxEffect;
    if(rCap > 0 && rCap < cap) cap = rCap;

    oProps = "";
    integer na = llGetListLength(gAxId);
    integer k;
    for(k = 0; k < na; k++){
        integer id = llList2Integer(gAxId, k);
        integer val = llList2Integer(gAxVal, k);
        string nm = idToName(id);
        if(nm != "" && llSubStringIndex(nm, "meta.") != 0){     // meta.* only gate rules; never serialized
            if(llSubStringIndex(nm, "act.") == 0) val = llRound((float)val * effMul);
            if(val >  cap) val =  cap;
            if(val < -cap) val = -cap;
            if(oProps != "") oProps += "^";
            oProps += nm + "=" + (string)val;
        }
    }
    integer lj;
    for(lj = 0; lj < llGetListLength(labels); lj++){
        string lnm = idToName(llList2Integer(labels, lj));
        if(lnm != ""){ if(oProps != "") oProps += "^"; oProps += lnm + "=1"; }
    }

    oTax   = idToName(outTaxId);
    oStage = idToName(outStageId);
    // Replace a previous stage suffix on the base name instead of accumulating /chopped/minced/...
    string inputStage = llList2String(groups, 3);
    string suffix = "/" + inputStage;
    integer baseLength = llStringLength(oName) - llStringLength(suffix);
    if(inputStage != "" && baseLength > 0 && llGetSubString(oName, baseLength, -1) == suffix)
        oName = llGetSubString(oName, 0, baseLength - 1);
    if(oStage != "") oName += "/" + oStage;
}

// Parse a snapshot into a validated flat group list (stride GS); "" action returned via gActionOut.
string gActionOut;
list parseSnapshot(string snapshot, integer wantValid)
{
    gActionOut = "";
    string body = snapshot;
    integer split = llSubStringIndex(snapshot, "\n\n");
    if(split != -1){
        if(split > 0) gActionOut = llGetSubString(snapshot, 0, split - 1);
        body = llGetSubString(snapshot, split + 2, -1);
    }
    list rows = llParseStringKeepNulls(body, ["\n"], []);
    list groups = [];
    integer i;
    for(i = 0; i < llGetListLength(rows); ++i){
        string row = llList2String(rows, i);
        if(row != ""){
            list grp = llParseStringKeepNulls(row, ["|"], []);
            if(llGetListLength(grp) == GS && llList2Integer(grp, 1) >= 1) groups += grp;
        }
    }
    return groups;
}

// OBSERVE: returns "OK|<desc>", "NONE", or "ERR|<reason>".
string consult(string snapshot)
{
    list groups = parseSnapshot(snapshot, TRUE);
    if(llGetListLength(groups) == 0) return "ERR|Invalid observation snapshot.";
    string countText = llLinksetDataRead("law:observations:count");
    if(countText == "") return "ERR|Observation data not loaded.";
    string genre = llLinksetDataRead("ws:genre");

    gObserving = TRUE;
    clearAggregate();
    integer gi;
    for(gi = 0; gi < llGetListLength(groups); gi += GS)
        addGroup(llList2List(groups, gi, gi + GS - 1));
    injectAction(gActionOut);

    string text = "";
    integer count = (integer)countText;
    integer i;
    for(i = 0; i < count; ++i){
        list entry = llParseStringKeepNulls(llLinksetDataRead("law:observations:" + (string)i), ["|"], []);
        if(llGetListLength(entry) == 2 && llList2String(entry, 0) == genre){
            string base = "law:" + genre + ":" + llList2String(entry, 1);
            string desc = llLinksetDataRead(base + ":description");
            string cond = llLinksetDataRead(base + ":observe_when");
            if(desc != "" && cond != "" && (cond == "*" || evalWhen(cond))){
                if(text != "") text += " ";
                text += desc;
            }
        }
    }
    clearAggregate();
    gObserving = FALSE;
    if(text == "") return "NONE";
    return "OK|" + text;
}

// TAKE: resolve + build the product DNA, hand it to WS_Core.
takeEval(string snapshot, key holder)
{
    gObserving = FALSE;
    list groups = parseSnapshot(snapshot, FALSE);
    if(llGetListLength(groups) == 0){
        llMessageLinked(LINK_SET, EVAL_TAKE_RES, "0", holder);
        return;
    }
    clearAggregate();
    integer gi;
    for(gi = 0; gi < llGetListLength(groups); gi += GS)
        addGroup(llList2List(groups, gi, gi + GS - 1));
    injectAction(gActionOut);
    resolve();

    string result;
    if(llGetListLength(rYieldGives) > 0){               // multi-organ harvest: only organs the species has
        integer ptax = nameToId(llList2String(groups, 0));
        list haveO = [];
        if(ptax != NOTOK){
            string os = llLinksetDataRead("tax:" + (string)ptax + ":organs");
            if(os != "") haveO = llParseString2List(os, ["^"], []);
        }
        string giveList = "";
        integer yi;
        for(yi = 0; yi < llGetListLength(rYieldGives); yi++){
            integer goid = llList2Integer(rYieldGives, yi);
            if(llListFindList(haveO, [(string)goid]) != -1){
                string onm = idToName(goid);
                if(onm != ""){ if(giveList != "") giveList += "^"; giveList += onm; }
            }
        }
        if(giveList != "") result = "2|" + giveList;
        else result = "0";
    }
    else if(!rFound) result = "0";
    else if(llListFindList(llParseString2List(rDo, ["^"], []), ["give"]) != -1) result = "2";
    else {
        buildOutput(groups);
        result = "1|" + (string)rVerdict + "|" + oName + "|" + (string)oQty + "|" + (string)oUse
            + "|" + (string)oLife + "|" + oTax + "|" + oStage + "|" + oProps + "|" + oMed + "|" + (string)oEff;
    }
    clearAggregate();
    llMessageLinked(LINK_SET, EVAL_TAKE_RES, result, holder);
}

default
{
    state_entry()
    {
        llListen(NX_HUD, "", NULL_KEY, "");   // register FIRST: a later fault must never kill the listen
        nexusBoot();
        loadCfg();
    }
    on_rez(integer p){ llResetScript(); }
    changed(integer c)
    {
        if(c & CHANGED_OWNER){ llResetScript(); return; }
        if(c & CHANGED_INVENTORY) loadCfg();
    }
    link_message(integer s, integer num, string str, key id)
    {
        if(num == NEXUS_MEM_REPORT) nexusMemReport();
    }
    listen(integer chan, string nm, key who, string msg)
    {
        if(chan != NX_HUD) return;
        list f = llParseStringKeepNulls(msg, ["|"], []);
        if(llList2String(f, 0) != "NX") return;
        string verb = llList2String(f, 1);
        if(verb != "OBSERVE" && verb != "TAKE") return;

        string ticket = llLinksetDataRead("state:session");
        if(ticket == "" || llList2String(f, 2) != ticket) return;
        string holder = llLinksetDataRead("state:lock");
        if(holder == "" || who == NULL_KEY || llGetOwnerKey(who) != (key)holder) return;

        string name = llList2String(f, 3);                        // kept URL-escaped
        string snapshot = llUnescapeURL(llList2String(f, 4));

        if(verb == "TAKE"){
            gTakeName = llUnescapeURL(name);
            // field 5 = source object keys ("uuid^uuid..."), stored for WS_Core's generic give/harvest path
            llLinksetDataWrite("state:takesrc", llUnescapeURL(llList2String(f, 5)));
            takeEval(snapshot, (key)holder);
            return;
        }
        // OBSERVE
        string r = consult(snapshot);
        string status = llList2String(llParseStringKeepNulls(r, ["|"], []), 0);
        if(status == "OK")
            llRegionSayTo((key)holder, NX_HUD, "NX|OBSERVED|" + ticket + "|OK|"
                + llEscapeURL(llGetSubString(r, 3, -1)) + "|" + name);
        else if(status == "NONE")
            llRegionSayTo((key)holder, NX_HUD, "NX|OBSERVED|" + ticket + "|NONE||" + name);
        else
            llRegionSayTo((key)holder, NX_HUD, "NX|OBSERVED|" + ticket + "|ERR|"
                + llEscapeURL(llGetSubString(r, 4, -1)) + "|");
    }
}
