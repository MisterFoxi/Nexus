// ROOT atlas player. Textures are in ROOT inventory.
// Resolves the child display prim by name; callers use LINK_THIS from ROOT.
// Owns the display prim's texture animation and this script's timer.
// 918330 LOAD: text = exact inventory texture name. Shows REST immediately.
// 918331 PLAY: text ignored. 918332 REST: text ignored.
// 918334 PAUSE / 918335 RESUME / 918336 ELAPSED: text ignored.
// 918333 replies: LOADED / PLAYING / REST / ERROR:reason; id echoes request.
// Also PAUSED / ELAPSED:seconds (active time only, frozen after REST).
// READY is sent to ROOT on startup; caller resends LOAD after player reset.
integer LOAD = 918330;
integer PLAY = 918331;
integer REST = 918332;
integer STATUS = 918333;
integer PAUSE = 918334;
integer RESUME = 918335;
integer ELAPSED = 918336;
string DISPLAY_PRIM = "P1_DISPLAY";
integer gDisplayLink;

// Shared format: left-to-right, then top-to-bottom, zero-based indices.
// Current display face is 2; configure this to match the assembled P1_DISPLAY mesh.
integer FACE = 2;
integer COLUMNS = 3;
integer ROWS = 1;
integer REST_FRAME = 0;
integer FIRST_FRAME = 1;
integer FRAME_COUNT = 2;
float FPS = 4.0;

string gAtlas = "";
integer gRunning = FALSE;
integer gPaused = FALSE;
float gElapsed = 0.0;
float gStartedAt;
integer gFrame;
integer gController = LINK_THIS;

integer findDisplay()
{
    integer found = 0;
    integer i;
    string name = llToLower(DISPLAY_PRIM);
    for (i = 1; i <= llGetNumberOfPrims(); ++i)
    {
        if (llToLower(llStringTrim(llGetLinkName(i), STRING_TRIM)) == name)
        {
            if (found) return 0; // Ambiguous names must never target a random prim.
            found = i;
        }
    }
    return found;
}

reply(integer destination, string text, key ticket)
{
    if (destination == llGetLinkNumber()) destination = LINK_THIS;
    llMessageLinked(destination, STATUS, text, ticket);
}

integer validSettings()
{
    if (gDisplayLink < 1) return FALSE;
    if (FACE < 0 || FACE >= llGetLinkNumberOfSides(gDisplayLink)) return FALSE;
    if (COLUMNS < 1 || ROWS < 1 || FPS <= 0.0) return FALSE;
    integer total = COLUMNS * ROWS;
    if (REST_FRAME < 0 || REST_FRAME >= total) return FALSE;
    if (FIRST_FRAME < 0 || FRAME_COUNT < 1) return FALSE;
    return FIRST_FRAME + FRAME_COUNT <= total;
}

// Address a cell by its center; UV repeats crop the selected cell without native texture animation.
showFrame(integer frame)
{
    float width = 1.0 / (float)COLUMNS;
    float height = 1.0 / (float)ROWS;
    float u = -0.5 + ((float)(frame % COLUMNS) + 0.5) * width;
    float v = 0.5 - ((float)(frame / COLUMNS) + 0.5) * height;
    llSetLinkPrimitiveParamsFast(gDisplayLink, [
        PRIM_TEXTURE, FACE, gAtlas, <width, height, 0.0>, <u, v, 0.0>, 0.0,
        PRIM_COLOR, FACE, <1.0, 1.0, 1.0>, 1.0,
        PRIM_FULLBRIGHT, FACE, TRUE
    ]);
}

float elapsedTime()
{
    if (gRunning) return gElapsed + llGetTime() - gStartedAt;
    return gElapsed;
}

stopPlayback()
{
    gElapsed = elapsedTime();
    llSetTimerEvent(0.0);
    gRunning = FALSE;
    gPaused = FALSE;
    // Clear any native animation from the old standalone test as well.
    if (gDisplayLink > 0)
        llSetLinkTextureAnim(gDisplayLink, 0, ALL_SIDES, 1, 1, 0.0, 0.0, 0.0);
}

loadAtlas(integer sender, string name, key ticket)
{
    // Validate before changing the active atlas: failed LOAD preserves it.
    integer display = findDisplay();
    if (!display)
    {
        reply(sender, "ERROR:Missing or duplicate display prim: " + DISPLAY_PRIM, ticket);
        return;
    }
    // REVIEW: active target changes before all validation succeeds; a failed LOAD can redirect existing playback. Commit the target only after validation.
    gDisplayLink = display;
    if (!validSettings())
    {
        reply(sender, "ERROR:Invalid face, grid, frame range or FPS", ticket);
        return;
    }
    if (llGetInventoryType(name) != INVENTORY_TEXTURE)
    {
        reply(sender, "ERROR:Texture missing from ROOT inventory: " + name, ticket);
        return;
    }
    stopPlayback();
    gAtlas = name;
    gController = sender;
    gFrame = REST_FRAME;
    showFrame(gFrame);
    reply(sender, "LOADED", ticket);
}

default
{
    state_entry()
    {
        gDisplayLink = findDisplay();
        stopPlayback();
        llMessageLinked(LINK_THIS, STATUS, "READY", NULL_KEY);
    }

    link_message(integer sender, integer number, string text, key ticket)
    {
        // Only root-local clients may control this face; all scripts in the root share this authority.
        if (sender != llGetLinkNumber()) return;
        if (number == LOAD) { loadAtlas(sender, text, ticket); return; }
        if (number == ELAPSED)
        {
            reply(sender, "ELAPSED:" + (string)elapsedTime(), ticket);
            return;
        }
        if (number != PLAY && number != REST && number != PAUSE && number != RESUME) return;
        if (gAtlas == "" || llGetInventoryType(gAtlas) != INVENTORY_TEXTURE)
        {
            reply(sender, "ERROR:LOAD an inventory texture before playback commands", ticket);
            return;
        }
        if (number == PAUSE)
        {
            if (!gRunning && !gPaused)
            {
                reply(sender, "ERROR:PAUSE requires active playback", ticket);
                return;
            }
            if (gRunning)
            {
                stopPlayback();
                gPaused = TRUE;
            }
            reply(sender, "PAUSED", ticket);
            return;
        }
        if (number == RESUME)
        {
            if (!gRunning && !gPaused)
            {
                reply(sender, "ERROR:RESUME requires paused playback", ticket);
                return;
            }
            if (gPaused)
            {
                gStartedAt = llGetTime();
                gPaused = FALSE;
                gRunning = TRUE;
                llSetTimerEvent(1.0 / FPS);
            }
            reply(sender, "PLAYING", ticket);
            return;
        }
        if (number == REST)
        {
            stopPlayback();
            gFrame = REST_FRAME;
            showFrame(gFrame);
            reply(sender, "REST", ticket);
            return;
        }
        // Repeated PLAY acknowledges without restarting the current cycle.
        if (!gRunning)
        {
            gElapsed = 0.0;
            gStartedAt = llGetTime();
            gPaused = FALSE;
            gFrame = FIRST_FRAME;
            showFrame(gFrame);
            gRunning = TRUE;
            llSetTimerEvent(1.0 / FPS);
        }
        reply(sender, "PLAYING", ticket);
    }

    timer()
    {
        if (!gRunning) return;
        ++gFrame;
        if (gFrame >= FIRST_FRAME + FRAME_COUNT) gFrame = FIRST_FRAME;
        showFrame(gFrame);
    }

    changed(integer change)
    {
        if (change & (CHANGED_OWNER | CHANGED_LINK)) { llResetScript(); return; }
        if ((change & CHANGED_INVENTORY) && gAtlas != "")
        {
            if (llGetInventoryType(gAtlas) != INVENTORY_TEXTURE)
            {
                stopPlayback();
                gAtlas = "";
                reply(gController, "UNLOADED", NULL_KEY);
            }
        }
    }

    on_rez(integer parameter) { llResetScript(); }
}
