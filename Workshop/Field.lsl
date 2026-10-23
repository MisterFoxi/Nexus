// ============================================================
// Field.lsl - field station: growth over time with a water reserve
// and consumption per cycle. [SKELETON]
// Medical crafting system (MedicalGS).
// ============================================================
// The rule engine (Workshop_Eval in the same linkset) decides which
// transitions are possible. This script supplies timing and resources:
// RESOURCE AND TIME MODEL:
// - Maintain a water reserve replenished by the player.
// - Each cycle, if the reserve covers the plant's required quantity,
// deduct water, advance effective growth time, and include a water
// group in the basket to satisfy the evaluator's required-token gate.
// The evaluator checks token presence; this station handles quantities.
// - Without water, growth stops and health declines to zero (withered).
// - Inject both meta.elapsed_time (fed cycles only) and meta.wall_time
// (actual age since planting), expressed in minutes.
//
// Requires bench_config Genre = field, compiled monde.nc linkset data,
// and Workshop_Eval.lsl in the same linkset.
//
// Not tested in-world: validate this skeleton before use. TODOs for seed
// notecard loading and harvesting refer to Workshop.lsl's delivery flow.
// ============================================================

integer EVAL_REQ = 970200;
integer EVAL_RES = 970201;

integer TICK           = 60;         // Seconds between growth cycles.
integer GROW_PER_CYCLE = 1;          // Effective growth minutes added per fed cycle.
integer HEALTH_MAX     = 5;
integer WITHER_STEP    = 1;          // Health lost per dry cycle.

// --- current plant ---
string  gName  = "plant";            // TODO: load Name from the seed notecard.
string  gTax   = "mint";             // TODO: load Taxonomy from the seed notecard.
string  gStage = "seed";
integer gPlantedAt;                  // Unix timestamp at planting.
integer gGrow;                       // Accumulated effective growth minutes.
integer gHealth;
integer gReserveWater;               // Water reserve replenished by the player.
integer gNeedWater;                  // Water consumed per cycle, read from tax:<id>:need.

// Read per-cycle water demand from tax:<id>:need = token:quantity^...
// Use the first pair; TODO: select the water/liquid token when several needs exist.
// REVIEW: the first requirement may not be water; negative demand increases the reserve and missing demand allows free growth.
integer readNeedWater(){
    string s = llLinksetDataRead("tok:"+gTax);
    if(s == "") return 0;
    string nd = llLinksetDataRead("tax:"+s+":need");
    if(nd == "") return 0;
    list first = llParseString2List(llList2String(llParseString2List(nd,["^"],[]),0), [":"], []);
    if(llGetListLength(first) < 2) return 1;              // Requirement present without a quantity: default to one.
    return (integer)llList2String(first,1);
}

// REVIEW: planting/growth/health/reserve are not persisted; reset restarts the plant with default seed identity and zero water.
plant(){
    gStage = "seed"; gGrow = 0; gHealth = HEALTH_MAX;
    gPlantedAt = llGetUnixTime();
    gNeedWater = readNeedWater();
    llSetTimerEvent((float)TICK);
    llOwnerSay("[Field] planted "+gName+" ("+gTax+"); water/cycle="+(string)gNeedWater+" reserve="+(string)gReserveWater);
}

// One basket group: rawName|count|tax|stage|props|life|eff.
string plantGroup(){ return gName+"|1|"+gTax+"|"+gStage+"||0|1000"; }
// REVIEW: the synthetic water group joins full aggregation and rule ranking, not just the required-token gate.
string waterGroup(){ return "water|1|water|plant||0|1000"; }   // Present water to satisfy the liquid/water token requirement.

cycle(){
    integer wall = (llGetUnixTime() - gPlantedAt) / 60;
    integer fed  = (gReserveWater >= gNeedWater);

    string body = plantGroup();
    // Snapshot the current plant stage before evaluation; the action header supplies updated growth and wall-clock age.
    if(fed){
        gReserveWater -= gNeedWater;
        gGrow += GROW_PER_CYCLE;
        if(gHealth < HEALTH_MAX) gHealth++;
        body += "\n" + waterGroup();                 // Water is available, so the required-token gate can pass.
    } else {
        gHealth -= WITHER_STEP;
        if(gHealth <= 0){
            gStage = "withered";
            llSetTimerEvent(0.0);
            llOwnerSay("[Field] "+gName+" has withered (out of water).");
            // TODO: update the mesh or remove the dead plant.
            return;
        }
        llOwnerSay("[Field] "+gName+" needs water (health "+(string)gHealth+"/"+(string)HEALTH_MAX+")");
        // Dry cycle: skip evaluation and growth; wait for the reserve to be refilled.
        return;
    }

    string actHdr = "meta.elapsed_time="+(string)gGrow+"^meta.wall_time="+(string)wall;
    // REVIEW: there is no pending-request flag or timeout; water/time advance even if the evaluator is missing or unresponsive.
    llMessageLinked(LINK_SET, EVAL_REQ, actHdr + "\n\n" + body, NULL_KEY);
}

default{
    state_entry(){ plant(); }

    // REVIEW: any toucher adds unlimited water; this is a prototype refill path rather than component consumption.
    touch_start(integer n){ gReserveWater += 10; llOwnerSay("[Field] water added, reserve="+(string)gReserveWater); }  // TODO: consume an actual water component instead of adding water on touch.

    timer(){ cycle(); }

    link_message(integer sender, integer num, string str, key id){
        // REVIEW: responses are not correlated to a request/client; Workshop and Field share the same response number.
        if(num != EVAL_RES) return;
        if(str == "0") return;                       // No matching rule yet (for example, not enough growth time).
        if(str == "2"){                              // A give rule means the harvest is ready.
            llSetTimerEvent(0.0);
            // REVIEW: harvest stops growth but provides no delivery/replant implementation; adding water does not restart the timer.
            llOwnerSay("[Field] harvest ready: "+gName);
            // TODO: rez the plant object (Stage=plant), following Workshop.lsl's give model.
            return;
        }
        // "1|verdict|name|qty|use|life|tax|stage|props|med|eff"
        list f = llParseStringKeepNulls(str, ["|"], []);
        if(llGetListLength(f) < 8) return;
        // REVIEW: validate response code and all fields; only stage is applied, so taxonomy/name/property changes from rules are lost.
        string ns = llList2String(f, 7);
        if(ns != "" && ns != gStage){
            gStage = ns;
            llOwnerSay("[Field] -> stage="+gStage);
            // TODO: update the growing object's mesh / notecard.
        }
    }
}
