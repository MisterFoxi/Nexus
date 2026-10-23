// Passive DEV monitor. Put in a separate object. No journal or deduplication list.
// Directed messages to other objects are private; no debug copies are broadcast.
// Development broadcasts only; directed TAKE/RETURN replies cannot be observed from this separate prim.
integer CHANNEL = -918274;
default
{
    state_entry()
    {
        llListen(CHANNEL, "", NULL_KEY, "");
        llOwnerSay("[Listener] DEV scan monitor ready. Directed source replies are visible only to their HUD.");
    }
    listen(integer channel, string name, key source, string text)
    {
        if (channel != CHANNEL || llGetOwnerKey(source) != llGetOwner()) return;
        llOwnerSay("[Listener] " + name + ": " + text);
    }
}
