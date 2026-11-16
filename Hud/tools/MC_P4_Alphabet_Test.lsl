// Diagnostic v2: white alphabet on transparent background, with engine verification.
// ROOT beside FURWARE. Stop MC_P4_Controller while testing.
// Does not add backgrounds, move/rotate prims, reset FURWARE or modify inventory.
string TABLE_NAME = "P4_Table1";
string FONT = "f974fdfc-8fbd-2f29-2b38-3c34411c1fcc"; // FURWARE default DejaVu.
integer CHANNEL = 918499; // /918499 alphabet
integer gRows;
integer gColumns;
integer gSample;
key gProbe;
integer gWaiting;
integer gDeadline;
integer gLateCheck;
string gFirstSurface;

integer scanTable()
{
    list rowIds; list rowCounts; list coordinates; list tables;
    integer faces; integer meshCount; integer link;
    integer smallest = 2147483647;
    gSample = 0; gRows = 0; gColumns = 0;
    for(link=1;link<=llGetNumberOfPrims();++link){
        list p = llParseStringKeepNulls(llGetLinkName(link),[":"],[]);
        if(llList2String(p,0) == "FURWARE text mesh"){
            string table = llList2String(p,1);
            if(llListFindList(tables,[table]) == -1) tables += [table];
            if(table == TABLE_NAME){
                integer row = llList2Integer(p,2);
                integer col = llList2Integer(p,3);
                integer count = llList2Integer(p,4);
                if(!count) count = llGetLinkNumberOfSides(link);
                if(row < 0 || col < 0 || row > 1023 || col > 1023
                    || count < 1 || count > llGetLinkNumberOfSides(link)){
                    llOwnerSay("[FW CHECK] Invalid mesh coordinates/face count: "+llGetLinkName(link)); return FALSE;
                }
                string coordinate = (string)row+":"+(string)col;
                if(llListFindList(coordinates,[coordinate]) != -1){
                    llOwnerSay("[FW CHECK] Duplicate table coordinate: "+coordinate); return FALSE;
                }
                coordinates += [coordinate];
                if(faces && faces != count){
                    llOwnerSay("[FW CHECK] Inconsistent character-face counts in "+TABLE_NAME); return FALSE;
                }
                faces = count;
                integer index = llListFindList(rowIds,[row]);
                if(index == -1){ rowIds += [row]; rowCounts += [1]; }
                else rowCounts = llListReplaceList(rowCounts,[llList2Integer(rowCounts,index)+1],index,index);
                integer order = row*1024+col;
                if(order < smallest){ smallest=order; gSample=link; }
                ++meshCount;
            }
        }
    }
    if(!meshCount){
        llOwnerSay("[FW CHECK] TABLE NOT FOUND: "+TABLE_NAME+". Available tables: "+llDumpList2String(tables,", ")); return FALSE;
    }
    integer width = llList2Integer(rowCounts,0);
    integer i;
    for(i=0;i<llGetListLength(rowCounts);++i)
        if(llList2Integer(rowCounts,i) != width){
            llOwnerSay("[FW CHECK] Inconsistent row widths. FURWARE cannot initialize this table."); return FALSE;
        }
    gRows = llGetListLength(rowIds); gColumns = width*faces;
    if(gRows > 64 || gColumns > 128){
        llOwnerSay("[FW CHECK] Table exceeds this diagnostic's 64 x 128 limit."); return FALSE;
    }
    llOwnerSay("[FW CHECK] TABLE "+TABLE_NAME+": "+(string)gRows+" rows x "+(string)gColumns
        +" characters, "+(string)meshCount+" meshes. Sample: "+llGetLinkName(gSample));
    return TRUE;
}
prepareSurfaces()
{
    integer link;
    for(link=1;link<=llGetNumberOfPrims();++link){
        list p = llParseStringKeepNulls(llGetLinkName(link),[":"],[]);
        if(llList2String(p,0) == "FURWARE text mesh" && llList2String(p,1) == TABLE_NAME)
            llSetLinkPrimitiveParamsFast(link,[PRIM_ALPHA_MODE,ALL_SIDES,PRIM_ALPHA_MODE_BLEND,0,
                PRIM_FULLBRIGHT,ALL_SIDES,TRUE]);
    }
}
string surface()
{
    list p = llGetLinkPrimitiveParams(gSample,[PRIM_TEXTURE,0,PRIM_COLOR,0,PRIM_ALPHA_MODE,0]);
    return "font="+llList2String(p,0)+" repeats="+llList2String(p,1)+" offset="+llList2String(p,2)
        +" color="+llList2String(p,4)+" alpha="+llList2String(p,5)+" mode="+llList2String(p,6);
}
readBack()
{
    string actual = surface();
    llOwnerSay("[FW CHECK] FACE "+actual);
    list p = llGetLinkPrimitiveParams(gSample,[PRIM_TEXTURE,0,PRIM_COLOR,0]);
    if(llList2String(p,0) != FONT)
        llOwnerSay("[FW CHECK] Expected font not present: the table was not drawn here or another writer replaced it.");
    else if(llList2Vector(p,4) != <1.0,1.0,1.0> || llList2Float(p,5) < 0.99)
        llOwnerSay("[FW CHECK] Face is not white/visible: style, overlay or another writer is overriding the test.");
    else llOwnerSay("[FW CHECK] Font and white visible tint confirmed on sample face. Screen visibility still depends on mesh orientation, placement and material.");
}
showAlphabet()
{
    gWaiting = FALSE; gLateCheck = FALSE; llSetTimerEvent(0.0);
    if(!scanTable()) return;
    prepareSurfaces();
    string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    string text = "";
    integer row; integer col;
    for(row=0;row<gRows;++row){
        if(row) text += "\n";
        for(col=0;col<gColumns;++col){
            integer index = (row*gColumns+col)%62;
            text += llGetSubString(alphabet,index,index);
        }
    }
    gProbe = llGenerateKey(); gWaiting = TRUE; gDeadline = llGetUnixTime()+8;
    llMessageLinked(LINK_SET,0,"c=white;f="+FONT+";a=left;w=none;t=off;border=none;tags=off;force=on",(key)("fw_conf:"+TABLE_NAME));
    llMessageLinked(LINK_SET,0,text,(key)("fw_data:"+TABLE_NAME));
    // Real FURWARE flushes pending rendering before answering this registration query.
    llMessageLinked(LINK_SET,0,(string)gProbe,(key)("fw_touchquery:"+(string)gSample+":0"));
    llSetTimerEvent(1.0);
    llOwnerSay("[FW CHECK] SENT. Waiting for FURWARE registration/render acknowledgement.");
}
default
{
    state_entry(){ llListen(CHANNEL,"",llGetOwner(),""); showAlphabet(); }
    on_rez(integer parameter){ llResetScript(); }
    link_message(integer sender,integer number,string text,key id){
        if((string)id == "fw_ready"){ showAlphabet(); return; }
        if((string)id == "fw_touchreply" && gWaiting){
            list p = llParseStringKeepNulls(text,[":"],[]);
            if(llList2String(p,6) != (string)gProbe) return;
            gWaiting = FALSE;
            if(llList2String(p,3) != TABLE_NAME){
                llOwnerSay("[FW CHECK] ENGINE replied but has not registered this table. Check FURWARE startup errors.");
                llSetTimerEvent(0.0); return;
            }
            llOwnerSay("[FW CHECK] ENGINE registered table; active box="+llList2String(p,0));
            readBack(); gFirstSurface=surface(); gLateCheck=TRUE; gDeadline=llGetUnixTime()+2;
        }
    }
    listen(integer channel,string name,key speaker,string message){
        if(channel == CHANNEL && speaker == llGetOwner()
            && llToLower(llStringTrim(message,STRING_TRIM)) == "alphabet") showAlphabet();
    }
    timer(){
        if(llGetUnixTime() < gDeadline) return;
        if(gWaiting){
            gWaiting=FALSE;
            llOwnerSay("[FW CHECK] NO ENGINE ACK. FURWARE may be stopped, uninitialized or incompatible. This is not a successful render.");
            readBack();
        }
        else if(gLateCheck){
            if(surface() != gFirstSurface){ llOwnerSay("[FW CHECK] FACE CHANGED AFTER RENDER: another script/material update overwrote the result."); readBack(); }
            else llOwnerSay("[FW CHECK] Sample face remained unchanged after 2 seconds.");
            gLateCheck=FALSE;
        }
        llSetTimerEvent(0.0);
    }
}
