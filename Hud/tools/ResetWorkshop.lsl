// Nexus_Full_Reset.lsl -- outil temporaire HUD / Workshop / Component.
// Installer dans le ROOT, avec les scripts a reinitialiser.
// Proprietaire : /77812 RESET
//
// Efface TOUTE la LSD du linkset, y compris tok:/tax:/law:/idx: et les stocks.
// Retire le texte flottant avant et apres relance, et les particules avant relance.
// Reinitialise et active TOUS les autres scripts du meme prim.
// Les scripts des prims enfants ne sont pas accessibles par ces fonctions LSL.
// World_Loader est relance en dernier ; attendre son message "loaded".
// Les scripts relances peuvent recreer leur LSD et afficher du texte lors d un usage ulterieur.
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

    // Conserver les donnees recreees par les scripts au redemarrage.
    for (i = 0; i < llGetListLength(scripts); ++i)
        restartScript(llList2String(scripts, i));
    for (i = 0; i < llGetListLength(loaders); ++i)
        restartScript(llList2String(loaders, i));

    llOwnerSay("[FULL RESET] LSD effacee ; nettoyage initial effectue. "
        + (string)(llGetListLength(scripts) + llGetListLength(loaders))
        + " scripts du prim actives et reinitialises.");
    if (llGetListLength(loaders))
        llOwnerSay("[FULL RESET] Attendre le message World_Loader 'loaded' avant utilisation.");
    llSetTimerEvent(1.0);
}

default
{
    state_entry()
    {
        gListen = llListen(COMMAND_CHANNEL, "", llGetOwner(), "");
        llOwnerSay("[FULL RESET] Pret. Proprietaire : /77812 RESET. "
            + "Efface toute la LSD et reinitialise tous les autres scripts du prim.");
    }

    timer()
    {
        llSetTimerEvent(0.0);
        // Laisser les scripts relances traiter leur initialisation.
        llSetLinkPrimitiveParamsFast(LINK_SET, [PRIM_TEXT, "", ZERO_VECTOR, 0.0]);
        llOwnerSay("[FULL RESET] Texte flottant nettoye apres relance. Retirer l'outil.");
        llSetScriptState(llGetScriptName(), FALSE);
    }

    listen(integer channel, string name, key speaker, string message)
    {
        if (gDone || channel != COMMAND_CHANNEL || speaker != llGetOwner()) return;
        if (llToUpper(llStringTrim(message, STRING_TRIM)) == "RESET") fullReset();
    }
}
