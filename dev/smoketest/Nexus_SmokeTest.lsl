#define SCRIPT_NAME    "Nexus_SmokeTest"
#define SCRIPT_VERSION "v0.1.0"
#define SCRIPT_DATE    "2026-11-17"
#include "nexus_header.lsl"

// Throwaway smoke test for the preprocessor header convention (CONVENTIONS.md §3-§4).
// Not a production script; no fiche. Validates the toolchain, not gameplay.
//
// Expected on rez / reset:
//   [Nexus] Nexus_SmokeTest v0.1.0 (2026-11-17) | free <n> b
// Owner touch -> fires the on-demand memory report across the linkset; each
// script carrying nexus_header replies with its "free ... | observed min ..." line.
//
// PASS criteria:
//   - the #include expanded (script compiles; banner prints with the right name/version/date);
//   - free is a plausible byte count;
//   - touch produces the memory-report line.

default
{
    state_entry()
    {
        nexusBoot();
    }

    touch_start(integer n)
    {
        if (llDetectedKey(0) == llGetOwner())
            llMessageLinked(LINK_SET, NEXUS_MEM_REPORT, "", NULL_KEY);
    }

    link_message(integer sender, integer num, string str, key id)
    {
        if (num == NEXUS_MEM_REPORT) nexusMemReport();
    }

    on_rez(integer p) { llResetScript(); }
}
