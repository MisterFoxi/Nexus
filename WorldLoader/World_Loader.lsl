// ============================================================
//  World_Loader.lsl  —  medical crafting system (Nexus)
//  Domain: INGEST the world knowledge.
//  Reads the compiled notecard (tok:/tax:/law:/idx:) produced by
//  compiler.py and writes it into the shared LinksetData of the linkset.
//  Evaluation lives in ANOTHER script (same linkset, same LSD).
//  Reload = redelivery: replace the physics, keep the live state.
//
//  Archive/inspect via DM_AdminConsole.lsl (generic), e.g.
//    /77810 db list tok:   /77810 db list law:   /77810 db domains
//    (do NOT use 'db clear': it wipes state: too ;
//     'db reload' is a DM_Data opcode, no effect here.)
// ============================================================

string  NC_NAME   = "";                      // forced world notecard name, or "" => first card that isn't bench_config
integer LINK_MSG  = 970100;                 // link_message channel "world ready"
string  WORLD_RE  = "^(tok|tax|law|idx):";  // world-knowledge realms (wiped on reload)
string  VERSION   = "World_Loader v0.5 (2026-10-20)";

// --- read state ---
key     gQuery;          // current notecard read handle
integer gLine;           // current line
integer gWritten;        // keys written
integer gSkipped;        // skipped lines (empty/comment/malformed)
string  gNC;             // actual notecard name

report(string msg) { llOwnerSay("[World_Loader] " + msg); }

// notecard to load: NC_NAME if set, else the first card that is NOT bench_config
// (bench_config belongs to Workshop.lsl, never ingest it as world knowledge)
string pickNotecard()
{
    if (NC_NAME != "" && llGetInventoryType(NC_NAME) == INVENTORY_NOTECARD)
        return NC_NAME;
    integer n = llGetInventoryNumber(INVENTORY_NOTECARD);
    integer i;
    for (i = 0; i < n; i++)
    {
        string nm = llGetInventoryName(INVENTORY_NOTECARD, i);
        if (llToLower(nm) != "bench_config") return nm;
    }
    return "";
}

// Wipe the world realms (tok/tax/law/idx), keep the live state (state:/rz_).
// Find a batch, delete it, re-find until empty. Uses only core LSD calls
// (no llLinksetDataDeleteFound) and does not depend on count=0 semantics.
integer wipeWorld()
{
    integer n = 0;
    integer guard = 0;
    list keys = llLinksetDataFindKeys(WORLD_RE, 0, 256);
    while (llGetListLength(keys) > 0 && guard < 20000)
    {
        integer L = llGetListLength(keys);
        integer i;
        for (i = 0; i < L; i++) llLinksetDataDelete(llList2String(keys, i));
        n += L;
        guard += L;
        keys = llLinksetDataFindKeys(WORLD_RE, 0, 256);   // remaining after deletions
    }
    return n;
}

startLoad()
{
    gNC = pickNotecard();
    if (gNC == "")
    {
        report("no notecard to load (drop 'monde.nc').");
        return;
    }
    // prefix reset: wipe the world knowledge, never the live state (state:/rz_)
    integer removed = wipeWorld();
    report("reloading '" + gNC + "' (purged " + (string)removed + " world keys)...");
    gLine = 0; gWritten = 0; gSkipped = 0;
    gQuery = llGetNotecardLine(gNC, gLine);
}

default
{
    state_entry() { llOwnerSay("[Nexus] "+VERSION); startLoad(); }

    on_rez(integer p) { startLoad(); }

    // notecard (or a script) changed in inventory => reload
    changed(integer c)
    {
        if (c & CHANGED_INVENTORY) startLoad();
    }

    dataserver(key id, string data)
    {
        if (id != gQuery) return;              // not our request

        if (data == EOF)
        {
            report("loaded: " + (string)gWritten + " keys written, "
                   + (string)gSkipped + " lines skipped.");
            // signal "world ready" to the evaluator (same linkset)
            llMessageLinked(LINK_SET, LINK_MSG, "WORLD_LOADED|" + (string)gWritten, NULL_KEY);
            return;
        }

        // --- parse one "key = value" line ---
        string line = llStringTrim(data, STRING_TRIM);
        if (line != "" && llGetSubString(line, 0, 0) != "#")   // ignore empty + comments
        {
            integer sep = llSubStringIndex(line, " = ");        // first " = " only
            if (sep != -1)
            {
                string k = llStringTrim(llGetSubString(line, 0, sep - 1), STRING_TRIM);
                string v = llStringTrim(llGetSubString(line, sep + 3, -1), STRING_TRIM);
                if (v == "") v = "1";                           // idx: => presence, sentinel value
                if (llLinksetDataWrite(k, v) == LINKSETDATA_OK) ++gWritten;
                else { ++gSkipped; report("write refused: " + k); }
            }
            else { ++gSkipped; }                                // line without separator
        }
        else { ++gSkipped; }

        gQuery = llGetNotecardLine(gNC, ++gLine);               // next line
    }
}
