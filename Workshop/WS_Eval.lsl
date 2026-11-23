#define SCRIPT_NAME    "WS_Eval"
#define SCRIPT_VERSION "v0.1.0"
#include "nexus_header"

// WS_Eval — bench-local observation engine (refonte option 1). Observe-only port of the old
// Workshop_Eval consult path. Reads the cached world (tok:/tax:/law:) and the bench genre/config
// straight from the shared LinksetData (written by WS_Boot). It aggregates the snapshot, matches the
// observe_when rules of this bench's genre, and concatenates their descriptions. No transformation,
// no stock, no output — pure read-only consultation.
//
//   HUD -> WS_Eval (NX_HUD): NX|OBSERVE|<session>|<nameEsc>|<snapshotEsc>
//   WS_Eval -> HUD (NX_HUD): NX|OBSERVED|<session>|OK|<descEsc>|<nameEsc>
//                            NX|OBSERVED|<session>|NONE||<nameEsc>
//                            NX|OBSERVED|<session>|ERR|<reasonEsc>|
//   snapshot = "<actionHeader>\n\n<group>\n<group>...",
//     actionHeader = axis=val^...,  group = taxonomy|count|use|stage|props|life|eff|organ
//
// V1 scope: targeted at the cutting_board observe rules; the aggregation is the full taxonomy/stage/
// organ/axis semantics (batch midpoint, no random flux), which already covers every genre's observe
// rules. Transformation laws (do/react/yield) are intentionally NOT ported here.

integer NX_HUD = -918282;
integer GS = 8;                      // fields per snapshot group
integer NOTOK = -999999;             // sentinel for an unknown token

// duplicate batch curve: midpoint of each [min,max] pair (ppm), per duplicate count n. Overridable by ws:cfg:Batch.
list    BATCH_MULT = [ 950,1050, 1200,1300, 1400,1500, 1350,1500, 950,1150, 550,800 ];
integer N_MAX = 7;

// aggregate (rebuilt per request)
list gAxId; list gAxVal;             // numeric axes (parallel: token id -> value)
list gToks;                          // flat token presence set
list gCats;                          // stride 2: dimension token id, value token id (meta.taxonomy/stage/organ)
integer gTaxDim; integer gStageDim; integer gOrganDim;
list gInert;                         // axes the material does not react to
list gNeed;                          // required tokens (populated, unused by observe per spec)

integer nameToId(string nm)
{
    string s = llLinksetDataRead("tok:" + nm);
    if(s == "") return NOTOK;
    return (integer)s;
}
axAdd(integer id, integer v)
{
    integer i = llListFindList(gAxId, [id]);
    if(i == -1){ gAxId += id; gAxVal += v; }
    else gAxVal = llListReplaceList(gAxVal, [llList2Integer(gAxVal, i) + v], i, i);
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

integer batchMult(integer n)         // observe uses the midpoint of the [min,max] pair for n (ppm)
{
    if(n < 1) n = 1;
    integer last = llGetListLength(BATCH_MULT) / 2;
    if(n > last) n = last;
    integer i = (n - 1) * 2;
    return llRound(((float)llList2Integer(BATCH_MULT, i) + (float)llList2Integer(BATCH_MULT, i + 1)) / 2.0);
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
    string nm = llLinksetDataRead("ws:cfg:NMax");
    if(nm != "") N_MAX = (integer)nm;
}

clearAggregate()
{
    gAxId = []; gAxVal = []; gToks = []; gCats = []; gInert = []; gNeed = [];
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
                axAdd((integer)llList2String(kv, 0), llRound((float)((integer)llList2String(kv, 1)) * mFac));
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
            if(aid != NOTOK) axAdd(aid, llRound((float)((integer)llList2String(kv, 1)) * mFac));
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
                    axAdd((integer)llList2String(okv, 0), llRound((float)((integer)llList2String(okv, 1)) * mFac));
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

// Evaluate a tokenized condition against the aggregate. A numeric condition on an absent or inert axis fails.
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
            if(inertHas(zaid) || !axHas(zaid)) return FALSE;
            integer zv = axGet(zaid);
            if(zv < (integer)llList2String(zp, 1) || zv > (integer)llList2String(zp, 2)) return FALSE;
        } else if(ge != -1){
            integer aid = (integer)llGetSubString(t, 0, ge - 1);
            integer kk = (integer)llGetSubString(t, ge + 2, -1);
            if(inertHas(aid) || !axHas(aid)) return FALSE;
            if(axGet(aid) < kk) return FALSE;
        } else if(le != -1){
            integer aid = (integer)llGetSubString(t, 0, le - 1);
            integer kk = (integer)llGetSubString(t, le + 2, -1);
            if(inertHas(aid) || !axHas(aid)) return FALSE;
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

// Returns "OK|<desc>", "NONE", or "ERR|<reason>".
string consult(string snapshot)
{
    string action = "";
    string body = snapshot;
    integer split = llSubStringIndex(snapshot, "\n\n");
    if(split != -1){
        if(split > 0) action = llGetSubString(snapshot, 0, split - 1);
        body = llGetSubString(snapshot, split + 2, -1);
    }
    list rows = llParseStringKeepNulls(body, ["\n"], []);
    list groups = [];
    integer valid = TRUE;
    integer i;
    for(i = 0; i < llGetListLength(rows); ++i){
        string row = llList2String(rows, i);
        if(row != ""){
            list grp = llParseStringKeepNulls(row, ["|"], []);
            if(llGetListLength(grp) != GS || llList2Integer(grp, 1) < 1) valid = FALSE;
            else groups += grp;
        }
    }
    if(!valid || llGetListLength(groups) == 0) return "ERR|Invalid observation snapshot.";
    string countText = llLinksetDataRead("law:observations:count");
    if(countText == "") return "ERR|Observation data not loaded.";
    string genre = llLinksetDataRead("ws:genre");

    clearAggregate();
    integer gi;
    for(gi = 0; gi < llGetListLength(groups); gi += GS)
        addGroup(llList2List(groups, gi, gi + GS - 1));
    injectAction(action);

    string text = "";
    integer count = (integer)countText;
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
    if(text == "") return "NONE";
    return "OK|" + text;
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
        if(llList2String(f, 0) != "NX" || llList2String(f, 1) != "OBSERVE") return;
        string ticket = llLinksetDataRead("state:session");
        if(ticket == "" || llList2String(f, 2) != ticket) return;
        string holder = llLinksetDataRead("state:lock");
        if(holder == "" || who == NULL_KEY || llGetOwnerKey(who) != (key)holder) return;

        string name = llList2String(f, 3);                        // kept URL-escaped, echoed as-is
        string snapshot = llUnescapeURL(llList2String(f, 4));
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
