// @file lsl/DM_AdminConsole.lsl
// ============================================================
// DM_Admin_Console.lsl
// Document Manager — Admin Maintenance Console
//
// Purpose:
// - Dedicated owner-only command channel
// - Direct output via llOwnerSay()
// - DB maintenance using llLinksetData*
//
// Commands:
//   /77810 help
//   /77810 db count
//   /77810 db count cfg:
//   /77810 db mem
//   /77810 db memory
//   /77810 db list
//   /77810 db list cfg:
//   /77810 db list cfg: 100
//   /77810 db list cfg: all
//   /77810 db domains
//   /77810 db subdomains cfg
//   /77810 db subdomains cfg:hmi
//   /77810 db get <key>
//   /77810 db del <key>
//   /77810 db deldomain <domain>
//   /77810 db reload
//   /77810 db clear
//   /77810 db clearreload
//
// WARNING:
// - db clear resets the whole Linkset Data store.
// - This includes cfg:*, doc:*, idx:*, master:*, tmp:*, audit:*
// ============================================================


// ── VERSIONING ──────────────────────────────────────────────

string MODULE_ID = "DM_AdminConsole";

string MODULE_TAG = "lsl-dev-0-local";
string MODULE_SHA = "local";

integer UPD_VERSION_REQ = -7704201;
integer UPD_VERSION_RPL = -7704202;

reportVersion()
{
    llMessageLinked(
        LINK_SET,
        UPD_VERSION_RPL,
        MODULE_ID + "|" + MODULE_TAG,
        NULL_KEY
    );
}


// ── CHANNELS ────────────────────────────────────────────────

integer COMMAND_CHANNEL = 77810;


// ── ENGINE OPCODES ──────────────────────────────────────────

integer OP_CONFIG_RELOAD = 102;

// Legacy module diagnostics kept for compatibility.
integer OP_MODULE_PING   = 911;
integer OP_MODULE_PONG   = 912;

// ── LIST / DUMP SETTINGS ────────────────────────────────────

integer FIND_PAGE_SIZE = 32;
integer OUTPUT_LINES_PER_TICK = 4;

integer DEFAULT_MAX_LIST = 250;
integer MAX_LIST_HARD_LIMIT = 1000;
integer LIST_ALL = -1;

float OUTPUT_TICK = 0.20;

integer MODE_IDLE = 0;
integer MODE_LIST = 1;

integer gMode = MODE_IDLE;


// ── RUNTIME ─────────────────────────────────────────────────

key gOwner;
integer gListenHandle = 0;

list gDumpPage;
integer gDumpPageIndex = 0;
integer gDumpPageCount = 0;
integer gDumpOffset = 0;
integer gDumpOutputCount = 0;
integer gDumpMax = 0;
integer gDumpAll = FALSE;
integer gDumpFinished = FALSE;

string gDumpPrefix = "";
string gDumpPattern = "";



// ── UTILS ───────────────────────────────────────────────────

string trim(string s)
{
    return llStringTrim(s, STRING_TRIM);
}

integer startsWith(string s, string prefix)
{
    if (prefix == "") return TRUE;

    return llGetSubString(
        s,
        0,
        llStringLength(prefix) - 1
    ) == prefix;
}

debug(string msg)
{
    llOwnerSay("[DM-CONSOLE] " + msg);
}

out(string msg)
{
    llOwnerSay("[DM-DB] " + msg);
}

string joinFrom(list parts, integer start)
{
    integer count = llGetListLength(parts);

    if (start >= count)
    {
        return "";
    }

    return llDumpList2String(
        llList2List(parts, start, -1),
        " "
    );
}

string regexEscape(string s)
{
    string outStr = "";

    integer i;
    integer len = llStringLength(s);

    for (i = 0; i < len; ++i)
    {
        string c = llGetSubString(s, i, i);

        if (
            c == "." ||
            c == "^" ||
            c == "$" ||
            c == "*" ||
            c == "+" ||
            c == "?" ||
            c == "(" ||
            c == ")" ||
            c == "[" ||
            c == "]" ||
            c == "{" ||
            c == "}" ||
            c == "|" ||
            c == "\\"
        )
        {
            outStr += "\\" + c;
        }
        else
        {
            outStr += c;
        }
    }

    return outStr;
}

string makePatternFromPrefix(string prefix)
{
    prefix = trim(prefix);

    if (prefix == "")
    {
        return ".";
    }

    return "^" + regexEscape(prefix);
}

integer parseMax(string s)
{
    s = llToLower(trim(s));

    if (s == "all")
    {
        return LIST_ALL;
    }

    integer v = (integer)s;

    if (v <= 0)
    {
        return DEFAULT_MAX_LIST;
    }

    if (v > MAX_LIST_HARD_LIMIT)
    {
        return MAX_LIST_HARD_LIMIT;
    }

    return v;
}




removeCommandListener()
{
    if (gListenHandle)
    {
        llListenRemove(gListenHandle);
        gListenHandle = 0;
    }
}

installCommandListener()
{
    removeCommandListener();

    gListenHandle = llListen(
        COMMAND_CHANNEL,
        "",
        gOwner,
        ""
    );
}


// ── HELP ────────────────────────────────────────────────────

showHelp()
{
    debug("Command channel: /" + (string)COMMAND_CHANNEL);

    debug("Commands:");
    debug("/" + (string)COMMAND_CHANNEL + " help");
    debug("/" + (string)COMMAND_CHANNEL + " db count [prefix]");
    debug("/" + (string)COMMAND_CHANNEL + " db mem");
    debug("/" + (string)COMMAND_CHANNEL + " db memory");
    debug("/" + (string)COMMAND_CHANNEL + " db list [prefix] [max|all]");
    debug("/" + (string)COMMAND_CHANNEL + " db domains");
    debug("/" + (string)COMMAND_CHANNEL + " db subdomains <domain>");
    debug("/" + (string)COMMAND_CHANNEL + " db get <key>");
    debug("/" + (string)COMMAND_CHANNEL + " db del <key>");
    debug("/" + (string)COMMAND_CHANNEL + " db deldomain <domain>");
    debug("/" + (string)COMMAND_CHANNEL + " db reload");
    debug("/" + (string)COMMAND_CHANNEL + " db clear");
    debug("/" + (string)COMMAND_CHANNEL + " db clearreload");
}


// ── MEMORY / LINKSET DATA STATUS ────────────────────────────

string pct(integer freeBytes, integer totalBytes)
{
    if (totalBytes <= 0)
    {
        return "n/a";
    }

    return (string)((freeBytes * 100) / totalBytes) + "%";
}

cmdMemory()
{
    integer scriptFree = llGetFreeMemory();
    integer scriptUsed = llGetUsedMemory();
    integer scriptLimit = llGetMemoryLimit();

    integer lsdFree = llLinksetDataAvailable();
    integer lsdLimit = 131072;
    integer lsdUsed = lsdLimit - lsdFree;

    if (lsdUsed < 0)
    {
        lsdUsed = 0;
    }

    integer keyCount = llLinksetDataCountKeys();

    debug("Memory status:");

    debug(
        "Script RAM: free="
        + (string)scriptFree
        + " B / used="
        + (string)scriptUsed
        + " B / limit="
        + (string)scriptLimit
        + " B / free_pct="
        + pct(scriptFree, scriptLimit)
);

    debug(
        "Linkset Data: free="
        + (string)lsdFree
        + " B / used~="
        + (string)lsdUsed
        + " B / limit~="
        + (string)lsdLimit
        + " B / free_pct~="
        + pct(lsdFree, lsdLimit)
        + " / keys="
        + (string)keyCount
    );
}

// ── COUNT ───────────────────────────────────────────────────

integer countKeysByPrefix(string prefix)
{
    string pattern = makePatternFromPrefix(prefix);

    integer offset = 0;
    integer total = 0;

    list keys = llLinksetDataFindKeys(pattern, offset, FIND_PAGE_SIZE);

    while (llGetListLength(keys) > 0)
    {
        total += llGetListLength(keys);

        offset += FIND_PAGE_SIZE;
        keys = llLinksetDataFindKeys(pattern, offset, FIND_PAGE_SIZE);
    }

    return total;
}

cmdCount(string prefix)
{
    prefix = trim(prefix);

    integer total = countKeysByPrefix(prefix);

    if (prefix == "")
    {
        debug("DB count: " + (string)total + " key(s).");
    }
    else
    {
        debug("DB count for prefix [" + prefix + "]: " + (string)total + " key(s).");
    }
}


// ── DOMAINS ─────────────────────────────────────────────────

string normalizeDomain(string domain)
{
    domain = trim(domain);

    while (
        llStringLength(domain) > 0
        && llGetSubString(domain, -1, -1) == ":"
    )
    {
        domain = llDeleteSubString(
            domain,
            llStringLength(domain) - 1,
            llStringLength(domain) - 1
        );
    }

    return domain;
}

string domainFromKey(string keyName)
{
    integer separator = llSubStringIndex(keyName, ":");

    if (separator < 0)
    {
        return keyName;
    }

    if (separator == 0)
    {
        return "";
    }

    return llGetSubString(keyName, 0, separator - 1);
}

integer domainCountIndex(list domains, string domain)
{
    integer i;
    integer count = llGetListLength(domains);

    for (i = 0; i < count; i += 2)
    {
        if (llList2String(domains, i) == domain)
        {
            return i;
        }
    }

    return -1;
}

cmdDomains()
{
    list domains = [];
    integer offset = 0;
    list keys = llLinksetDataFindKeys(".", offset, FIND_PAGE_SIZE);

    while (llGetListLength(keys) > 0)
    {
        integer i;
        integer count = llGetListLength(keys);

        for (i = 0; i < count; ++i)
        {
            string keyName = llList2String(keys, i);
            string domain = domainFromKey(keyName);

            if (domain == "")
            {
                domain = "<empty>";
            }

            integer index = domainCountIndex(domains, domain);

            if (index < 0)
            {
                domains += [domain, 1];
            }
            else
            {
                integer domainCount = llList2Integer(domains, index + 1);
                domains = llListReplaceList(
                    domains,
                    [domainCount + 1],
                    index + 1,
                    index + 1
                );
            }
        }

        offset += FIND_PAGE_SIZE;
        keys = llLinksetDataFindKeys(".", offset, FIND_PAGE_SIZE);
    }

    integer domainTotal = llGetListLength(domains) / 2;

    out(
        "========== DB DOMAINS START | count="
        + (string)domainTotal
        + " =========="
    );

    if (domainTotal <= 0)
    {
        out("[empty]");
        out("========== DB DOMAINS END | count=0 ==========");
        return;
    }

    domains = llListSort(domains, 2, TRUE);

    integer j;

    for (j = 0; j < llGetListLength(domains); j += 2)
    {
        out(
            "["
            + (string)((j / 2) + 1)
            + "/"
            + (string)domainTotal
            + "] "
            + llList2String(domains, j)
            + " = "
            + (string)llList2Integer(domains, j + 1)
            + " key(s)"
        );
    }

    out(
        "========== DB DOMAINS END | count="
        + (string)domainTotal
        + " =========="
    );
}

string directSubdomainFromKey(string keyName, string domainPrefix)
{
    string base = normalizeDomain(domainPrefix);
    string prefix = base + ":";

    if (!startsWith(keyName, prefix))
    {
        return "";
    }

    string remainder = llGetSubString(
        keyName,
        llStringLength(prefix),
        -1
    );

    integer separator = llSubStringIndex(remainder, ":");
    string child;

    if (separator < 0)
    {
        child = remainder;
    }
    else
    {
        child = llGetSubString(remainder, 0, separator - 1);
    }

    if (child == "")
    {
        return "";
    }

    return base + ":" + child;
}

cmdSubdomains(string domain)
{
    domain = normalizeDomain(domain);

    if (domain == "")
    {
        debug("Usage: db subdomains <domain>");
        return;
    }

    string pattern = "^" + regexEscape(domain + ":");
    list domains = [];
    integer offset = 0;
    list keys = llLinksetDataFindKeys(pattern, offset, FIND_PAGE_SIZE);

    while (llGetListLength(keys) > 0)
    {
        integer i;
        integer count = llGetListLength(keys);

        for (i = 0; i < count; ++i)
        {
            string childDomain = directSubdomainFromKey(
                llList2String(keys, i),
                domain
            );

            if (childDomain != "")
            {
                integer index = domainCountIndex(domains, childDomain);

                if (index < 0)
                {
                    domains += [childDomain, 1];
                }
                else
                {
                    integer childCount = llList2Integer(domains, index + 1);
                    domains = llListReplaceList(
                        domains,
                        [childCount + 1],
                        index + 1,
                        index + 1
                    );
                }
            }
        }

        offset += FIND_PAGE_SIZE;
        keys = llLinksetDataFindKeys(pattern, offset, FIND_PAGE_SIZE);
    }

    integer total = llGetListLength(domains) / 2;

    out(
        "========== DB SUBDOMAINS START | domain="
        + domain
        + " | count="
        + (string)total
        + " =========="
    );

    if (total <= 0)
    {
        out("[empty]");
        out("========== DB SUBDOMAINS END | count=0 ==========");
        return;
    }

    domains = llListSort(domains, 2, TRUE);

    integer j;

    for (j = 0; j < llGetListLength(domains); j += 2)
    {
        out(
            "["
            + (string)((j / 2) + 1)
            + "/"
            + (string)total
            + "] "
            + llList2String(domains, j)
            + " = "
            + (string)llList2Integer(domains, j + 1)
            + " key(s)"
        );
    }

    out(
        "========== DB SUBDOMAINS END | count="
        + (string)total
        + " =========="
    );
}

cmdDeleteDomain(string domain)
{
    domain = normalizeDomain(domain);

    if (domain == "")
    {
        debug("Usage: db deldomain <domain>");
        return;
    }

    string pattern =
        "^"
        + regexEscape(domain)
        + "(:|$)";

    integer deleted = 0;
    integer failed = 0;
    list keys = llLinksetDataFindKeys(
        pattern,
        0,
        FIND_PAGE_SIZE
    );

    while (llGetListLength(keys) > 0)
    {
        integer i;
        integer count = llGetListLength(keys);
        integer pageDeleted = 0;

        for (i = 0; i < count; ++i)
        {
            string keyName = llList2String(keys, i);
            integer rc = llLinksetDataDelete(keyName);

            if (rc == 0)
            {
                ++deleted;
                ++pageDeleted;
            }
            else
            {
                ++failed;

                debug(
                    "Delete failed ["
                    + keyName
                    + "] rc="
                    + (string)rc
                );
            }
        }

        if (pageDeleted <= 0)
        {
            debug("Domain deletion stopped: remaining keys could not be deleted.");
            jump domain_delete_done;
        }

        keys = llLinksetDataFindKeys(
            pattern,
            0,
            FIND_PAGE_SIZE
        );
    }

@domain_delete_done;

    debug(
        "Domain ["
        + domain
        + "] deleted: "
        + (string)deleted
        + " key(s), failed="
        + (string)failed
        + "."
    );
}


// ── LIST / DUMP ─────────────────────────────────────────────

resetListState()
{
    gDumpPage = [];
    gDumpPageIndex = 0;
    gDumpPageCount = 0;
    gDumpOffset = 0;
    gDumpOutputCount = 0;
    gDumpMax = 0;
    gDumpAll = FALSE;
    gDumpFinished = FALSE;
    gDumpPrefix = "";
    gDumpPattern = "";
}

loadNextDumpPage()
{
    if (gDumpFinished)
    {
        return;
    }

    integer requestCount = FIND_PAGE_SIZE;

    if (!gDumpAll)
    {
        integer remaining = gDumpMax - gDumpOutputCount;

        if (remaining <= 0)
        {
            gDumpFinished = TRUE;
            return;
        }

        if (remaining < requestCount)
        {
            requestCount = remaining;
        }
    }

    gDumpPage = llLinksetDataFindKeys(
        gDumpPattern,
        gDumpOffset,
        requestCount
    );

    gDumpPageIndex = 0;
    gDumpPageCount = llGetListLength(gDumpPage);

    if (gDumpPageCount <= 0)
    {
        gDumpFinished = TRUE;
        return;
    }

    gDumpOffset += gDumpPageCount;

    if (gDumpPageCount < requestCount)
    {
        gDumpFinished = TRUE;
    }
}

startList(string prefix, integer maxCount)
{
    if (gMode != MODE_IDLE)
    {
        debug("A DB list is already running.");
        return;
    }

    prefix = trim(prefix);
    resetListState();

    if (maxCount == LIST_ALL)
    {
        gDumpAll = TRUE;
    }
    else
    {
        if (maxCount <= 0)
        {
            maxCount = DEFAULT_MAX_LIST;
        }

        if (maxCount > MAX_LIST_HARD_LIMIT)
        {
            maxCount = MAX_LIST_HARD_LIMIT;
        }

        gDumpMax = maxCount;
    }

    gDumpPrefix = prefix;
    gDumpPattern = makePatternFromPrefix(prefix);

    string maxLabel = (string)gDumpMax;

    if (gDumpAll)
    {
        maxLabel = "all";
    }

    if (gDumpPrefix == "")
    {
        out(
            "========== DB LIST START | prefix=<all> | max="
            + maxLabel
            + " =========="
        );
    }
    else
    {
        out(
            "========== DB LIST START | prefix="
            + gDumpPrefix
            + " | max="
            + maxLabel
            + " =========="
        );
    }

    loadNextDumpPage();

    if (gDumpPageCount <= 0)
    {
        out("[empty]");
        out("========== DB LIST END | count=0 ==========");
        debug("DB list completed: 0 key(s).");
        resetListState();
        return;
    }

    gMode = MODE_LIST;
    llSetTimerEvent(OUTPUT_TICK);
}

outputOneKey(string keyName, integer index)
{
    string value = llLinksetDataRead(keyName);

    string line =
        "["
        + (string)(index + 1)
        + "] "
        + keyName
        + " = "
        + value;

    if (llStringLength(line) <= 950)
    {
        out(line);
        return;
    }

    out(
        "["
        + (string)(index + 1)
        + "] "
        + keyName
        + " = "
        + llGetSubString(value, 0, 800)
        + " ..."
    );
}

finishList()
{
    out(
        "========== DB LIST END | count="
        + (string)gDumpOutputCount
        + " =========="
    );

    debug(
        "DB list completed: "
        + (string)gDumpOutputCount
        + " key(s)."
    );

    resetListState();
    gMode = MODE_IDLE;
    llSetTimerEvent(0.0);
}

continueList()
{
    if (gMode != MODE_LIST)
    {
        llSetTimerEvent(0.0);
        return;
    }

    integer sent = 0;

    while (sent < OUTPUT_LINES_PER_TICK)
    {
        if (!gDumpAll && gDumpOutputCount >= gDumpMax)
        {
            finishList();
            return;
        }

        if (gDumpPageIndex >= gDumpPageCount)
        {
            if (gDumpFinished)
            {
                finishList();
                return;
            }

            loadNextDumpPage();

            if (gDumpPageCount <= 0)
            {
                finishList();
                return;
            }
        }

        string keyName = llList2String(gDumpPage, gDumpPageIndex);
        ++gDumpPageIndex;

        if (startsWith(keyName, gDumpPrefix))
        {
            outputOneKey(keyName, gDumpOutputCount);
            ++gDumpOutputCount;
            ++sent;
        }
    }
}


// ── GET / DELETE ────────────────────────────────────────────

cmdGet(string keyName)
{
    keyName = trim(keyName);

    if (keyName == "")
    {
        debug("Usage: db get <key>");
        return;
    }

    string value = llLinksetDataRead(keyName);

    if (value == "")
    {
        debug("Key empty or not found: " + keyName);
        out(keyName + " = ");
        return;
    }

    out(keyName + " = " + value);
}

cmdDelete(string keyName)
{
    keyName = trim(keyName);

    if (keyName == "")
    {
        debug("Usage: db del <key>");
        return;
    }

    integer rc = llLinksetDataDelete(keyName);

    debug("Delete key [" + keyName + "] rc=" + (string)rc);
}


// ── CLEAR / RELOAD ──────────────────────────────────────────

doClear(integer withReload)
{
    debug("Clearing full Linkset Data DB...");

    llLinksetDataReset();

    debug("DB cleared.");

    if (withReload)
    {
        debug("Sending OP_CONFIG_RELOAD.");

        llMessageLinked(
            LINK_SET,
            OP_CONFIG_RELOAD,
            "admin_console_clearreload",
            NULL_KEY
        );
    }
}

cmdReload()
{
    debug("Sending OP_CONFIG_RELOAD.");

    llMessageLinked(
        LINK_SET,
        OP_CONFIG_RELOAD,
        "admin_console_reload",
        NULL_KEY
    );
}


// ── COMMAND PARSER ──────────────────────────────────────────

handleDbCommand(list parts)
{
    integer count = llGetListLength(parts);

    if (count < 2)
    {
        showHelp();
        return;
    }

    string action = llToLower(llList2String(parts, 1));

    if (action == "mem" || action == "memory")
    {
        cmdMemory();
        return;
    }

    if (action == "count")
    {
        string prefix = "";

        if (count >= 3)
        {
            prefix = llList2String(parts, 2);
        }

        cmdCount(prefix);
        return;
    }

    if (action == "list")
    {
        string prefix = "";
        integer maxCount = DEFAULT_MAX_LIST;

        if (count >= 3)
        {
            prefix = llList2String(parts, 2);
        }

        if (count >= 4)
        {
            maxCount = parseMax(llList2String(parts, 3));
        }

        startList(prefix, maxCount);
        return;
    }

    if (action == "domains" || action == "domain")
    {
        cmdDomains();
        return;
    }

    if (action == "subdomains" || action == "subdomain")
    {
        string domain = joinFrom(parts, 2);
        cmdSubdomains(domain);
        return;
    }

    if (action == "get")
    {
        string keyName = joinFrom(parts, 2);
        cmdGet(keyName);
        return;
    }

    if (action == "del" || action == "delete")
    {
        string keyName = joinFrom(parts, 2);
        cmdDelete(keyName);
        return;
    }

    if (action == "deldomain" || action == "deletedomain")
    {
        string domain = joinFrom(parts, 2);
        cmdDeleteDomain(domain);
        return;
    }

    if (action == "reload")
    {
        cmdReload();
        return;
    }

    if (action == "clear")
    {
        doClear(FALSE);
        return;
    }

    if (action == "clearreload")
    {
        doClear(TRUE);
        return;
    }

    showHelp();
}

handleCommand(string msg)
{
    msg = trim(msg);

    if (msg == "")
    {
        return;
    }

    if (llToLower(msg) == "help")
    {
        showHelp();
        return;
    }

    list parts = llParseString2List(msg, [" "], []);

    if (llGetListLength(parts) <= 0)
    {
        return;
    }

    string root = llToLower(llList2String(parts, 0));

    if (root == "db")
    {
        handleDbCommand(parts);
        return;
    }

    showHelp();
}


// ── MODULE STATUS ───────────────────────────────────────────

pong()
{
    string status = "idle";

    if (gMode == MODE_LIST)
    {
        status = "listing_db";
    }

    llMessageLinked(
        LINK_SET,
        OP_MODULE_PONG,
        MODULE_ID + "|" + status,
        NULL_KEY
    );
}


// ════════════════════════════════════════════════════════════
// DEFAULT STATE
// ════════════════════════════════════════════════════════════

default
{
    state_entry()
    {
        gOwner = llGetOwner();
        resetListState();
        gMode = MODE_IDLE;

        installCommandListener();
        reportVersion();

        debug(
            "READY. Commands on /"
            + (string)COMMAND_CHANNEL
            + "."
        );

        debug("Type: /" + (string)COMMAND_CHANNEL + " help");
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            llResetScript();
        }
    }

   

    listen(integer channel, string name, key id, string msg)
    {
        if (channel != COMMAND_CHANNEL)
        {
            return;
        }

        if (id != llGetOwner())
        {
            return;
        }

        handleCommand(msg);
    }

    timer()
    {
        if (gMode == MODE_LIST)
        {
            continueList();
            return;
        }

        llSetTimerEvent(0.0);
    }

    link_message(integer sender, integer num, string str, key id)
    {
        if (num == UPD_VERSION_REQ)
        {
            reportVersion();
            return;
        }

        if (num == OP_MODULE_PING)
        {
            if (str == "" || str == MODULE_ID)
            {
                pong();
            }

            return;
        }
    }
}
