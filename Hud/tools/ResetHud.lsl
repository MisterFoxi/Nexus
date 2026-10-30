// Nexus_HUD_Full_Reset.lsl -- outil temporaire de reset complet du HUD.
// Installer dans le ROOT. Proprietaire : /77813 RESET
// Efface TOUTE la LSD du HUD (panier, requetes, preparation, association WS).
// Retire texte flottant et particules sur TOUT le linkset.
// Active et reinitialise TOUS les autres scripts du ROOT, meme arretes.
// Ne rembourse pas les unites detenues dans les composants externes.
// Les scripts des prims enfants ne sont pas accessibles par ce reset.
// Aucun reset sur touch. Outil desactive apres execution ; le retirer.

integer COMMAND_CHANNEL = 77813;
integer gListen;
integer gDone;

fullReset()
{
    gDone = TRUE;
    llListenRemove(gListen);

    list scripts;
    string self = llGetScriptName();
    integer count = llGetInventoryNumber(INVENTORY_SCRIPT);
    integer i;

    // Tout arreter avant d'effacer : aucun script ne doit recreer des donnees
    // pendant que le nettoyage est encore en cours.
    for (i = 0; i < count; ++i)
    {
        string name = llGetInventoryName(INVENTORY_SCRIPT, i);
        if (name != self)
        {
            scripts += [name];
            llSetScriptState(name, FALSE);
        }
    }

    llLinksetDataReset();
    llSetLinkPrimitiveParamsFast(LINK_SET,
        [PRIM_TEXT, "", ZERO_VECTOR, 0.0]);
    llLinkParticleSystem(LINK_SET, []);
    llStopSound();

    // Un script arrete doit etre reactive AVANT llResetOtherScript.
    // Aucun effacement apres cette boucle : conserver la nouvelle initialisation.
    for (i = 0; i < llGetListLength(scripts); ++i)
    {
        string name = llList2String(scripts, i);
        llSetScriptState(name, TRUE);
        llResetOtherScript(name);
    }

    llOwnerSay("[HUD FULL RESET] LSD effacee ; texte flottant et particules retires. "
        + (string)llGetListLength(scripts) + " scripts du ROOT actives et reinitialises.");
    llOwnerSay("[HUD FULL RESET] Les scripts recreent leurs donnees initiales. "
        + "Outil desactive : retirer Nexus_HUD_Full_Reset.");
    llSetScriptState(self, FALSE);
}

default
{
    state_entry()
    {
        gListen = llListen(COMMAND_CHANNEL, "", llGetOwner(), "");
        llOwnerSay("[HUD FULL RESET] Pret. Proprietaire : /77813 RESET.");
    }

    listen(integer channel, string name, key speaker, string message)
    {
        if (gDone || channel != COMMAND_CHANNEL || speaker != llGetOwner()) return;
        if (llToUpper(llStringTrim(message, STRING_TRIM)) == "RESET") fullReset();
    }
}
