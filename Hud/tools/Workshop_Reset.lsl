
DM-CONSOLE] READY. Commands on /77809.
[4:49 AM] Kanda leaf/chopped: [DM-CONSOLE] Type: /77809 help
[4:49 AM] Kanda leaf/chopped: [DM-DB] ========== DB LIST START | prefix=<all> | max=250 ==========
[4:49 AM] Kanda leaf/chopped: [DM-DB] [1] mc:component:stock = 4|fb0afb60-830b-2164-e4d5-7e1a1ffec719|1|756ff472-92b1-8279-fcd6-3d98b8268fc0|TAKE|1|OK|4
[4:49 AM] Kanda leaf/chopped: [DM-DB] [2] rz_exp = 1794312965
[4:49 AM] Kanda leaf/chopped: [DM-DB] [3] rz_life = 604800
[4:49 AM] Kanda leaf/chopped: [DM-DB] [4] rz_name = Kanda leaf/chopped
[4:49 AM] Kanda leaf/chopped: [DM-DB] [5] rz_props = act.nervous=-1^org.smell=-1^act.thermal=-7^act.fluidifying=6
[4:49 AM] Kanda leaf/chopped: [DM-DB] [6] rz_qty = 4
[4:49 AM] Kanda leaf/chopped: [DM-DB] [7] rz_ready = 1
[4:49 AM] Kanda leaf/chopped: [DM-DB] [8] rz_stage = chopped
[4:49 AM] Kanda leaf/chopped: [DM-DB] [9] rz_tax = mint
[4:49 AM] Kanda leaf/chopped: [DM-DB] [10] rz_use = 1
[4:49 AM] Kanda leaf/chopped: [DM-DB] ========== DB LIST END | count=10 ==========
[4:49 AM] Kanda leaf/chopped: [DM-CONSOLE] DB list completed: 10 key(s).

13:49
Le dump confirme que le COMMIT n’a pas été enregistré par le composant. Son dernier reçu est le TAKE 756ff472…, pour le même HUD. Il reste 4 unités disponibles et 1 unité réservée. Le COMMIT b09c98ba… est toujours en attente côté HUD. Le produit Kanda leaf/minced est déjà calculé et attend dans le Workshop.

Le correctif que je propose est de permettre un retry explicite depuis P3 pendant SETTLING. Il renverrait uniquement le COMMIT enregistré, avec le même UUID, la même source et la même quantité. Si la source l’applique, le HUD pourra clôturer la préparation et poursuivre vers les récipients sélectionnés. Si la source l’a déjà appliqué lors d’une tentative dont la réponse s’est perdue, Component renverra son reçu sans appliquer l’opération une seconde fois.

Ce correctif débloquerait la reprise. Les dumps ne montrent pas pourquoi la première tentative n’a pas été enregistrée par la source. Tu m’autorises à ajouter ce retry ciblé dans le HUD ? Je te demande l’accord conformément à ta consigne avant modification.

13:50
oui et on fait un plan de test 

13:50
Le retry ciblé est dans les sources actives du HUD v0.9.2. Pendant SETTLING, un clic sur Transfer dans P3 renvoie le COMMIT en attente avec le même UUID, la même source et la même quantité.

Pour reprendre le traitement bloqué, remplace ensemble MC_P3_Controller, MC_Selected_Controller et MC_Workshop_Link dans le prim racine du HUD existant, en conservant la LSD. Puis approche-toi du Kanda leaf/chopped d’origine et clique une fois sur Transfer. Le résultat attendu sur la source est 4 unités disponibles, 0 réservée, avec le reçu b09c98ba…|COMMIT|1|OK|4. Après confirmation de la clôture, clique de nouveau sur Transfer si la livraison n’a pas démarré.

Le plan de test en jeu couvre cette reprise, deux préparations successives, le double clic, la perte de réponse et le redémarrage du HUD.

La suite HUD et les vérifications ciblées du retry passent en simulation locale. La reprise du traitement réel reste à valider dans Second Life.


Plan de test - reprise COMMIT.md modifié
+22
-0
13:51
reverse. Je prefere faire une RAZ et suivre un plan de test 

13:52
Le retry COMMIT a été annulé. Les trois scripts HUD ont été restaurés dans les sources actives et leurs empreintes vérifiées. Si tu as installé la v0.9.2 dans Second Life, remplace ces trois scripts par les versions restaurées avant le test.

Le plan de test après RAZ reproduit les deux Chomp successifs avec deux récipients distincts. Le récipient rempli au premier transfert sert d’ingrédient au second. Si SETTLING persiste, arrête-toi au premier blocage et relève les états du HUD, du WS et de cette source avant de recommencer.

La RAZ et le test restent à faire en jeu.

13:53
le script pour le ws est pas a jours. il efface pas les overtext:
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

…
13:58
Le script fourni efface déjà le texte flottant du linkset du WS avant de redémarrer les scripts. Le correctif dépend de l’objet qui porte encore le texte.

Au-dessus du cutting board : il faut identifier le script qui réécrit le texte après le redémarrage. Workshop_Output peut afficher le produit en attente, mais le journal fourni ne montre pas ce qu’il affiche après la RAZ.
Au-dessus des ingrédients ou des récipients : ce sont des objets séparés. Leur texte est géré par Component, via la commande HOVER|0. La RAZ du WS ne leur envoie pas cette commande.
Quel texte reste visible après la RAZ, et au-dessus de quel objet ? Si ce sont les textes des composants, je te propose d’ajouter l’envoi de HOVER|0 à la fin de la RAZ. J’attends ton accord avant de modifier le script.

13:58
tu l'as ecrit !!!!! 

13:58
Oui, j’ai écrit ce script et je t’ai indiqué de l’utiliser dans le plan de test. J’ai annoncé que le texte flottant serait retiré, alors que le script ne le nettoie qu’avant le redémarrage. J’aurais dû vérifier le résultat après la relance.

Je propose de corriger ResetWorkshop.lsl pour que la RAZ du cutting board termine par un second nettoyage du texte sur tous ses prims, après la relance des scripts. Je limiterais la correction au cutting board pour que la RAZ ne modifie pas l’affichage des objets voisins.

Tu me donnes le feu vert pour modifier ce script ? Je te le demande conformément à ta consigne d’accord avant modification.

13:58
oui

13:59
J’ai corrigé ResetWorkshop.lsl dans les sources actives. Le script efface désormais le texte flottant de tous les prims liés du WS une seconde fois, une seconde après la relance des scripts, puis se désactive.

Pour vérifier en jeu, remplace l’ancien outil et lance /77812 RESET. Au message Texte flottant nettoye apres relance, vérifie que le texte a disparu, puis retire l’outil. Le délai d’une seconde reste à vérifier dans Second Life. Je n’ai pas exécuté la RAZ.

13:59





















C:
Users
lcc
Lsl dev
Nexus
Hud
tools
ResetWorkshop.lsl
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

Filtrer les fichiers
