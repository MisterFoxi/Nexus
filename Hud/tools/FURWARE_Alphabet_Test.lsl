// Place beside FURWARE. Displays a white alphabet on all existing tables.
// Stop other text-writing scripts while positioning the tables.
showAlphabet()
{
    string text = "";
    integer i;
    for(i=0;i<40;++i) text += "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    llMessageLinked(LINK_SET,0,"c=white;a=left;w=char;t=off;tags=off;force=on",(key)"fw_conf");
    llMessageLinked(LINK_SET,0,text,(key)"fw_data");
}
default
{
    state_entry(){ showAlphabet(); }
    link_message(integer sender,integer number,string text,key id)
    {
        if((string)id == "fw_ready") showAlphabet();
    }
}
