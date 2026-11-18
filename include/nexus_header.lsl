// nexus_header.lsl — shared boot banner + on-demand memory report.
// #include at the top of every Nexus script. See CONVENTIONS.md §3-§4.
//
// Define BEFORE the #include:
//   #define SCRIPT_NAME    "Nexus_Server"   ; label shown in the banner
//   #define SCRIPT_VERSION "v0.1.0"
//   #include "nexus_header"
//
// The date is automatic (__DATE__, build date) — scripts do NOT declare SCRIPT_DATE.
// Include guards are automatic, so this file needs no manual #ifndef guard.
//
// Then: call nexusBoot() first in state_entry(), and route NEXUS_MEM_REPORT to
// nexusMemReport() from your link_message.

integer NEXUS_MEM_REPORT = 970290;    // on-demand memory report, whole linkset
integer gNexusMinFree = 0x7FFFFFFF;   // lowest llGetFreeMemory() observed (script heap)

// Update the observed heap floor; also call at hot moments. Returns current free heap.
integer nexusMem()
{
    integer free = llGetFreeMemory();
    if (free < gNexusMinFree) gNexusMinFree = free;
    return free;
}

// Boot banner — call FIRST in state_entry().
// heap = this script's free Mono memory; lsd = free bytes in the linkset datastore (shared).
nexusBoot()
{
    integer free = nexusMem();
    llOwnerSay("[Nexus] " + SCRIPT_NAME + " " + SCRIPT_VERSION
        + " (" + __DATE__ + ") | heap " + (string)free + " b"
        + " | lsd " + (string)llLinksetDataAvailable() + " b free");
}

// On-demand report — call from link_message when num == NEXUS_MEM_REPORT.
nexusMemReport()
{
    integer free = nexusMem();
    llOwnerSay("[Nexus] " + SCRIPT_NAME + " heap " + (string)free
        + " b | observed min " + (string)gNexusMinFree + " b"
        + " | lsd " + (string)llLinksetDataAvailable() + " b free");
}
