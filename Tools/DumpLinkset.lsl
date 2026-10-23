// ============================================================
//  DumpLinkset.lsl  —  outil de debug (MedicalGS)
// ============================================================
//  A GLISSER dans un prim : dump TOUTE la LinksetData du linkset
//  dans le chat owner (pas de menu). Dump au state_entry / rez,
//  et a chaque touch. Lignes groupees (~900 car) pour eviter le
//  throttle de llOwnerSay. Lecture seule : ne modifie rien.
//
//  Astuce : edite PATTERN pour filtrer un realm, ex :
//    "^tok:"  "^law:"  "^rz_"  "^idx:"   ("." = tout)
// ============================================================

string PATTERN = ".";          // "." = toutes les cles ; "^law:" pour filtrer

dump(){
    list keys = llLinksetDataFindKeys(PATTERN, 0, 0);   // 0 = toutes
    keys = llListSort(keys, 1, TRUE);                   // tri alpha
    integer n = llGetListLength(keys);
    llOwnerSay("=== LinksetData dump : " + (string)n + " cles (pattern \"" + PATTERN + "\") ===");
    string buf = "";
    integer i;
    for(i = 0; i < n; i++){
        string k = llList2String(keys, i);
        string row = k + " = " + llLinksetDataRead(k);
        if(buf != "" && llStringLength(buf) + llStringLength(row) + 1 > 900){
            llOwnerSay(buf);
            buf = "";
        }
        if(buf != "") buf += "\n";
        buf += row;
    }
    if(buf != "") llOwnerSay(buf);
    llOwnerSay("=== end (" + (string)n + " cles) ===");
}

default{
    state_entry(){ llOwnerSay("[MedicalGS] DumpLinkset v0.5 (2026-10-20)"); dump(); }
    on_rez(integer p){ dump(); }
    touch_start(integer t){ dump(); }
}
