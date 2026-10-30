// Nexus_Full_Reset.lsl -- outil temporaire HUD / Workshop / Component.
// Installer dans le ROOT, avec les scripts a reinitialiser.
// Proprietaire : /77812 RESET
//
// Efface TOUTE la LSD du linkset, y compris tok:/tax:/law:/idx: et les stocks.
// Retire texte flottant et emetteurs de particules sur TOUT le linkset.
// Reinitialise et active TOUS les autres scripts du meme prim.
// Les scripts des prims enfants ne sont pas accessibles par ces fonctions LSL.
// World_Loader est relance en dernier ; attendre son message "loaded".
// Les scripts relances peuvent recreer leur LSD et leurs affichages normaux.
// Aucun reset sur touch. L'outil se desactive apres execution ; le retirer.

integer COMMAND_CHANNEL = 77812;
integer gListen;
integer gDone;

integer isWorldLoader(string name)
{
    name = llToLower(llStringTrim(name, STRING_TRIM));
    return name == "world_loader" || name == "world_loader.lsl";
}

restartScript(string name)
{
    // llResetOtherScript ne fait rien si le script est arrete.
    llSetScriptState(name, TRUE);
    llResetOtherScript(name);
}

fullReset()
{
    gDone = TRUE;
    llListenRemove(gListen);

    list scripts;
    list loaders;
    string self = llGetScriptName();
    integer count = llGetInventoryNumber(INVENTORY_SCRIPT);
    integer i;

    // Arreter TOUS les autres scripts avant le moindre effacement.
    for (i = 0; i < count; ++i)
    {
        string name = llGetInventoryName(INVENTORY_SCRIPT, i);
        if (name != self)
        {
            llSetScriptState(name, FALSE);
            if (isWorldLoader(name)) loaders += [name];
            else scripts += [name];
        }
    }

    llLinksetDataReset();
    llSetLinkPrimitiveParamsFast(LINK_SET,
        [PRIM_TEXT, "", ZERO_VECTOR, 0.0]);
    llLinkParticleSystem(LINK_SET, []);
    llStopSound();

    // Aucun effacement apres le redemarrage : conserver l'initialisation.
    for (i = 0; i < llGetListLength(scripts); ++i)
        restartScript(llList2String(scripts, i));
    for (i = 0; i < llGetListLength(loaders); ++i)
        restartScript(llList2String(loaders, i));

    llOwnerSay("[FULL RESET] LSD effacee ; texte flottant et particules retires. "
        + (string)(llGetListLength(scripts) + llGetListLength(loaders))
        + " scripts du prim actives et reinitialises.");
    if (llGetListLength(loaders))
        llOwnerSay("[FULL RESET] Attendre le message World_Loader 'loaded' avant utilisation.");
    llOwnerSay("[FULL RESET] Outil desactive. Retirer Nexus_Full_Reset.");
    llSetScriptState(self, FALSE);
}

default
{
    state_entry()
    {
        gListen = llListen(COMMAND_CHANNEL, "", llGetOwner(), "");
        llOwnerSay("[FULL RESET] Pret. Proprietaire : /77812 RESET. "
            + "Efface toute la LSD et reinitialise tous les autres scripts du prim.");
    }

    listen(integer channel, string name, key speaker, string message)
    {
        if (gDone || channel != COMMAND_CHANNEL || speaker != llGetOwner()) return;
        if (llToUpper(llStringTrim(message, STRING_TRIM)) == "RESET") fullReset();
    }
}
