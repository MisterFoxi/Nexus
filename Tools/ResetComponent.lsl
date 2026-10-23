// ============================================================
//  ResetComponent.lsl  —  outil de reset (MedicalGS)
// ============================================================
//  A GLISSER dans le prim d'un composant a remettre a zero.
//  Au state_entry :
//    1. vide TOUTE la LinksetData du linkset (etat persiste rz_*),
//    2. efface le hover text de la racine,
//    3. reset le(s) autre(s) script(s) du prim (= Component.lsl)
//       -> le composant reboote propre depuis sa NC.
//
//  Ne se detruit pas et ne se reset pas lui-meme (pas de boucle) :
//  retire-le du prim quand tu as fini.
//
//  /!\ JAMAIS dans un BENCH (atelier) : il effacerait le monde charge
//      (tok:/tax:/law:/idx:). Garde-fou integre : il refuse de tourner
//      si des donnees de monde sont presentes dans le linkset.
// ============================================================

default{
    state_entry(){
        llOwnerSay("[MedicalGS] ResetComponent v0.5 (2026-10-20)");
        // garde-fou : si le linkset porte le monde (tok:/law:), c'est un BENCH -> NE PAS reset
        if(llGetListLength(llLinksetDataFindKeys("^(tok|law):", 0, 1)) > 0){
            llOwnerSay("[Reset] ABORT : donnees de monde (tok:/law:) presentes -> ceci est un BENCH, pas un composant. Retire-moi.");
            return;
        }
        llLinksetDataReset();                                           // 1. vide la LinksetData
        llSetLinkPrimitiveParamsFast(LINK_ROOT, [PRIM_TEXT, "", ZERO_VECTOR, 0.0]);  // 2. efface le hover

        // 3. reset les autres scripts du prim (le composant), pas soi-meme
        string me = llGetScriptName();
        integer n = llGetInventoryNumber(INVENTORY_SCRIPT);
        integer i;
        for(i=0; i<n; i++){
            string s = llGetInventoryName(INVENTORY_SCRIPT, i);
            if(s != me) llResetOtherScript(s);
        }
        llOwnerSay("[Reset] LinksetData videe, hover efface, composant reset.");
    }

    on_rez(integer p){ llResetScript(); }
}
