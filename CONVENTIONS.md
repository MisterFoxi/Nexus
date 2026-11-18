# Nexus — Development Conventions

*Dev protocol for the Nexus project (rebuild). Applies to **every** script born in the refactored base. Goal: rigor, traceability, debuggability. No silent exceptions.*

---

## 1. Golden rule

**One script = one responsibility.** If you can't state its role in a single sentence, it does too much.

The **version shown at boot is the real version of the file.** Never modify a script without bumping its version and updating its fiche. No drift between code, boot banner and fiche.

---

## 2. Versioning (SemVer)

Every script carries a `vMAJOR.MINOR.PATCH` version:

- **MAJOR** — protocol / persistent-format break (another script or an older object stops being compatible).
- **MINOR** — backward-compatible addition (new message, new optional field).
- **PATCH** — fix with no interface change.

The **date** always accompanies the version: `v0.3.1 (2026-11-18)`.

---

## 3. Boot banner (mandatory)

Every script prints, as the very first thing in `state_entry()`, one line in a single format:

```
[Nexus] <ScriptName> v<MAJOR.MINOR.PATCH> (<date>) | heap <bytes> b | lsd <bytes> b free
```

`heap` = `llGetFreeMemory()` (this script's free Mono memory, its starting point); `lsd` = `llLinksetDataAvailable()` (free bytes in the shared linkset datastore). Both read at boot.

### Single source via preprocessor (`#include`)

The official SL VSCode plugin supports a C-style preprocessor (`#include`, `#define` incl. function-like macros, `#ifdef/#ifndef/#if/#elif/#else`, include guards, circular-include protection). Confirmed.

Includes resolve via `slVscodeEdit.preprocessor.includePaths` (default `"."`, `"./include/"`, `"**/include/"`). Canonical home: **`include/nexus_header.lsl`** → `#include "nexus_header"` resolves from any script with no relative path. **Never put the extension on the include directive** — base name only (`"nexus_header"`, not `"nexus_header.lsl"`). Compilation happens **in the viewer** (the plugin shows compile errors in real time on save); there is no bundled optimizer.

The banner format and the memory report live in **one shared file**, included everywhere. Each script only declares its identity:

```lsl
#define SCRIPT_NAME    "Workshop_Eval"
#define SCRIPT_VERSION "v0.1.0"
#include "nexus_header"
```

`nexus_header.lsl` (to be written, specified here) provides:
- a `nexusBoot()` function called at the top of `state_entry()` → prints the banner above;
- an on-demand **memory report** handler (see §4).

> **Behavioral validation (in-world smoke test):** toolchain support is confirmed; what remains is to verify behavior. Run `dev/smoketest/Nexus_SmokeTest.lsl` in-world → check the banner prints with the right name/version/date, `free` is sane, and an owner touch produces the memory-report line.

---

## 4. On-demand memory report

A reserved link-message code triggers, in every script of the linkset, a report:

```
[Nexus] <ScriptName> heap <bytes> b | observed min <bytes> b | lsd <bytes> b free
```

- Reserved code: **970290** (carried over from the old base; to be fixed in `nexus_header.lsl`).
- Each script keeps a `gMinFree` (lowest `llGetFreeMemory()` observed), updated at hot moments.
- Purpose: measure the real margin under load, not just at boot.

---

## 5. Dev & tracking fiche — one per script

Location: `dev/fiches/<ScriptName>.md`. Template: `dev/fiches/_TEMPLATE.md`.

Rule: **any change to a script** →
1. version bump (§2) + new banner date,
2. new line in the fiche **changelog**,
3. update of the affected fiche sections (interfaces, state, open points).

The fiche is the script's long-term memory: it must let someone (or you in six months) understand the role, the dependencies and the debt **without reading all the code**.

---

## 6. Tracked debt (no more orphan `// REVIEW:`)

A known debt point does not live only as a code comment: it is **copied into the fiche's "Open points / debt" section**, dated. One `// REVIEW:` in code = one line in the fiche. Known gaps are never lost again.

---

## 7. Tests (lean, three layers)

Testing effort decreases layer by layer; we keep the net where it counts, without the factory.

- **A — compile/parse (cheap, systematic):** every script must parse via Tailslide before commit. Parse step only, no simulation. Catches ~80% of mistakes (syntax, broken include).
- **B — in-world smoke tests (where the real SL bugs live):** messaging, memory, permissions, re-rez — only testable in-world. A small **LSL test rig** (an object that pings/injects messages and logs) + an action→expected **checklist** (like the current test plan).
- **C — Python unit tests, ONLY for the engine's pure logic** (`Eval`: axis aggregation, "most terms wins" resolution, batch curve, clamp). Deterministic, off-world, high value — this alone warrants a *reduced* `lsl_runtime`, not the old monster.

In one line: **Python reserved for the brain (Eval); everything else in-world + checklist.**

---

## 8. Method reminders

- No code modification without explicit go.
- Web searches require prior agreement.
- Architecture decisions live in the **project** (`claude/socle-refonte-reseau.md`); the **close-to-code tracking** lives in the repo (this file + `dev/fiches/`).
