tok:fab.chaleur = 0
tok:fab.thermal = 0
tok:fab.acidity = 1
tok:fab.stability = 2
tok:act.thermal = 3
tok:act.fluidifying = 4
tok:act.nervous = 5
tok:org.smell = 7
tok:act.toxic = 8
tok:act.vomiting = 9
tok:meta.stage = 10
tok:leaf = 11
tok:powder = 12
tok:essence = 13
tok:meta.taxonomy = 14
tok:leaf_plant = 15
tok:menthe = 16
tok:mint = 16
tok:root = 17
tok:liquid = 18
tok:pils = 20
tok:poultice = 21
tok:fab.grind = 22
tok:plant = 23
tok:twig = 24
tok:bark = 25
tok:salad = 26
tok:cuttable = 27
tok:chopped = 28
tok:minced = 29
tok:org.sweet = 30
tok:org.sour = 31
tok:org.salty = 32
tok:org.bitter = 33
tok:org.umami = 34
tok:org.viscosity = 35
tok:act.todo = 36
tok:water = 37
tok:oil = 38
tok:mineral = 39
tok:salt = 40
tok:sugar = 41
tok:seed = 42
tok:sprout = 43
tok:mature = 44
tok:harvested = 45
tok:sliced = 46
tok:fried = 47
tok:meta.elapsed_time = 48
tok:potato = 49
tok:sul = 49
tok:withered = 50
tok:meta.wall_time = 53
tok:brine = 54
tok:saline_iv = 55
tok:meta.organ = 56
tok:kanda = 57
tok:beast = 58
tok:verr = 59
tok:blood = 60
tok:bone = 61
tok:fat = 62
tok:flower = 63
tok:fruit = 64
tok:hide = 65
tok:meat = 66
tok:stem = 67
tok:edible = 68
tok:grindable = 69
tok:smokable = 70
tok:tannable = 71
tok:org.purity = 72
tok:tree = 73
tok:herb = 74
tok:willow = 75
tok:branch = 76
tok:trunk = 77

tok:#0 = fab.thermal
tok:#1 = fab.acidity
tok:#2 = fab.stability
tok:#3 = act.thermal
tok:#4 = act.fluidifying
tok:#5 = act.nervous
tok:#7 = org.smell
tok:#8 = act.toxic
tok:#9 = act.vomiting
tok:#10 = meta.stage
tok:#11 = leaf
tok:#12 = powder
tok:#13 = essence
tok:#14 = meta.taxonomy
tok:#15 = leaf_plant
tok:#16 = mint
tok:#17 = root
tok:#18 = liquid
tok:#20 = pils
tok:#21 = poultice
tok:#22 = fab.grind
tok:#23 = plant
tok:#24 = twig
tok:#25 = bark
tok:#26 = salad
tok:#27 = cuttable
tok:#28 = chopped
tok:#29 = minced
tok:#30 = org.sweet
tok:#31 = org.sour
tok:#32 = org.salty
tok:#33 = org.bitter
tok:#34 = org.umami
tok:#35 = org.viscosity
tok:#36 = act.todo
tok:#37 = water
tok:#38 = oil
tok:#39 = mineral
tok:#40 = salt
tok:#41 = sugar
tok:#42 = seed
tok:#43 = sprout
tok:#44 = mature
tok:#45 = harvested
tok:#46 = sliced
tok:#47 = fried
tok:#48 = meta.elapsed_time
tok:#49 = potato
tok:#50 = withered
tok:#53 = meta.wall_time
tok:#54 = brine
tok:#55 = saline_iv
tok:#56 = meta.organ
tok:#57 = kanda
tok:#58 = beast
tok:#59 = verr
tok:#60 = blood
tok:#61 = bone
tok:#62 = fat
tok:#63 = flower
tok:#64 = fruit
tok:#65 = hide
tok:#66 = meat
tok:#67 = stem
tok:#68 = edible
tok:#69 = grindable
tok:#70 = smokable
tok:#71 = tannable
tok:#72 = org.purity
tok:#73 = tree
tok:#74 = herb
tok:#75 = willow
tok:#76 = branch
tok:#77 = trunk

tax:15:toks = 15^23^26^27
tax:15:trait = 7:-1
tax:15:abstract = 1
tax:16:toks = 16^15^23^26^27
tax:16:trait = 5:-2^7:-1
tax:17:toks = 17^26^27
tax:17:trait = 30:1
tax:18:toks = 18
tax:18:trait = 35:0
tax:23:toks = 23
tax:23:abstract = 1
tax:37:toks = 37^18
tax:37:trait = 7:0^35:-4^72:1
tax:38:toks = 38^18
tax:38:trait = 35:5
tax:39:toks = 39
tax:39:inert = 0
tax:40:toks = 40^39
tax:40:trait = 32:5
tax:40:inert = 0
tax:41:toks = 41^39
tax:41:trait = 30:5
tax:41:inert = 0
tax:49:toks = 49^17^26^27
tax:49:trait = 30:1
tax:57:toks = 57^16^15^23^26^27
tax:57:trait = 5:-2^7:-1
tax:57:organs = 11^17^63
tax:57:organ:11:trait = 4:3
tax:57:organ:11:tags = 68^69^70
tax:57:organ:17:trait = 33:8
tax:57:organ:17:tags = 69
tax:57:organ:63:tags = 70
tax:58:toks = 58
tax:58:abstract = 1
tax:59:toks = 59^58
tax:59:organs = 61^65^66
tax:59:organ:61:tags = 69
tax:59:organ:65:tags = 71
tax:59:organ:66:trait = 34:5
tax:59:organ:66:tags = 68
tax:73:toks = 73^23
tax:73:abstract = 1
tax:74:toks = 74^23
tax:74:abstract = 1
tax:75:toks = 75^73^23
tax:75:organs = 25
tax:75:organ:25:trait = 33:2
tax:75:organ:25:tags = 69

dom:st:cauldron = medical
dom:st:crafter = medical
dom:tok:36 = medical
dom:tok:8 = medical
dom:tok:9 = medical

law:cutting_board:harvest:when = 10=23^14=27
law:cutting_board:harvest:verdict = 0
law:cutting_board:harvest:seq = 0
law:cutting_board:harvest:do = give
law:cutting_board:harvest_leaf:when = 10=23^14=27
law:cutting_board:harvest_leaf:verdict = 2
law:cutting_board:harvest_leaf:seq = 1
law:cutting_board:harvest_leaf:do = give=11
law:cutting_board:harvest_root:when = 10=23^14=27
law:cutting_board:harvest_root:verdict = 2
law:cutting_board:harvest_root:seq = 2
law:cutting_board:harvest_root:do = give=17
law:cutting_board:chop:when = 14=15^10=11
law:cutting_board:chop:verdict = 0
law:cutting_board:chop:seq = 3
law:cutting_board:chop:do = 10=28^qty*5
law:cutting_board:chop:description = The leaves are chopped.
law:cutting_board:choptatoes:when = 14=49^10=45
law:cutting_board:choptatoes:verdict = 0
law:cutting_board:choptatoes:seq = 4
law:cutting_board:choptatoes:do = 10=46
law:cutting_board:mince:when = 14=15^10=28
law:cutting_board:mince:verdict = 0
law:cutting_board:mince:seq = 5
law:cutting_board:mince:do = 10=29
law:mortar:grind_organ:when = 56=69
law:mortar:grind_organ:verdict = 0
law:mortar:grind_organ:seq = 6
law:mortar:grind_organ:do = 10=12^qty*0.6
law:mortar:grind:when = 14=15^10=11
law:mortar:grind:verdict = 0
law:mortar:grind:seq = 7
law:mortar:grind:do = 10=12^5*2^qty*0.6
law:mortar:over:when = 14=15^10=11^22~9~10
law:mortar:over:verdict = 0
law:mortar:over:seq = 8
law:mortar:over:do = 10=12^5*2^eff*0.5^qty*0.5
law:mortar:grind_fine:when = 14=15^10=28
law:mortar:grind_fine:verdict = 0
law:mortar:grind_fine:seq = 9
law:mortar:grind_fine:do = 10=12^5*2.5^qty*0.9
law:mortar:over_fine:when = 14=15^10=28^22~9~10
law:mortar:over_fine:verdict = 0
law:mortar:over_fine:seq = 10
law:mortar:over_fine:do = 10=12^5*2.5^eff*0.5^qty*0.5
law:mortar:grind_ultra:when = 14=15^10=29
law:mortar:grind_ultra:verdict = 0
law:mortar:grind_ultra:seq = 11
law:mortar:grind_ultra:do = 10=12^5*3
law:mortar:over_ultra:when = 14=15^10=29^22~9~10
law:mortar:over_ultra:verdict = 0
law:mortar:over_ultra:seq = 12
law:mortar:over_ultra:do = 10=12^5*3^eff*0.5^qty*0.5
law:mortar:poultice:when = 14=15^10=12^14=18
law:mortar:poultice:verdict = 0
law:mortar:poultice:seq = 13
law:mortar:poultice:do = 10=21^4*1.5
law:alambic:distill_water:when = 14=37^72~3~6
law:alambic:distill_water:verdict = 0
law:alambic:distill_water:seq = 14
law:alambic:distill_water:do = 72*3
law:cauldron:overcooked:when = 0~14~23
law:cauldron:overcooked:verdict = 0
law:cauldron:overcooked:seq = 15
law:cauldron:overcooked:do = eff*0.5
law:cauldron:cooked_ok:when = 0~10~13
law:cauldron:cooked_ok:verdict = 0
law:cauldron:cooked_ok:seq = 16
law:cauldron:corrosif:when = 1~-7~-3^2~8~10
law:cauldron:corrosif:verdict = 1
law:cauldron:corrosif:seq = 17
law:cauldron:corrosif:do = +8
law:cauldron:corrosif:cap = 10
law:cauldron:vomitif:when = 33~3~7
law:cauldron:vomitif:verdict = 0
law:cauldron:vomitif:seq = 18
law:cauldron:vomitif:do = +9
law:cauldron:boil_water:when = 0~14~23^14=37^72~0~2
law:cauldron:boil_water:verdict = 0
law:cauldron:boil_water:seq = 19
law:cauldron:boil_water:do = 72*3
law:cauldron:perf:when = 14=37^72>=7^32<=2
law:cauldron:perf:verdict = 0
law:cauldron:perf:seq = 20
law:cauldron:perf:do = 10=55
law:cauldron:brine:when = 14=37^72>=3^32>=3
law:cauldron:brine:verdict = 0
law:cauldron:brine:seq = 21
law:cauldron:brine:do = 10=54
law:cauldron:fry:when = 0~24~30^35~3~7
law:cauldron:fry:verdict = 0
law:cauldron:fry:seq = 22
law:cauldron:fry:do = +36
law:cauldron:makefries:when = 14=49^0~24~30^35~3~7^10=46
law:cauldron:makefries:verdict = 0
law:cauldron:makefries:seq = 23
law:cauldron:makefries:do = 10=47^eff*1.5
law:field:sprout:when = 10=42^48>=60
law:field:sprout:verdict = 0
law:field:sprout:seq = 24
law:field:sprout:do = 10=43
law:field:mature:when = 10=43^48>=240
law:field:mature:verdict = 0
law:field:mature:seq = 25
law:field:mature:do = 10=44
law:field:harvest:when = 10=44
law:field:harvest:verdict = 0
law:field:harvest:seq = 26
law:field:harvest:do = give
law:cauldron:observe_simmer:observe_when = 0~10~13
law:cauldron:observe_simmer:observe_seq = 0
law:cauldron:observe_simmer:description = The mixture is gently simmering.
law:cauldron:observe_boiling:observe_when = 0~14~23
law:cauldron:observe_boiling:observe_seq = 1
law:cauldron:observe_boiling:description = The mixture is boiling.
law:cauldron:observe_thick:observe_when = 35~3~7
law:cauldron:observe_thick:observe_seq = 2
law:cauldron:observe_thick:description = The mixture is thick.
law:cauldron:observe_putrid:observe_when = 7~3~7
law:cauldron:observe_putrid:observe_seq = 3
law:cauldron:observe_putrid:description = It gives off a putrid smell.
law:observations:count = 4
law:observations:0 = cauldron|observe_simmer
law:observations:1 = cauldron|observe_boiling
law:observations:2 = cauldron|observe_thick
law:observations:3 = cauldron|observe_putrid

idx:cutting_board:lawprop:23:harvest =
idx:cutting_board:lawprop:27:harvest =
idx:cutting_board:lawprop:23:harvest_leaf =
idx:cutting_board:lawprop:27:harvest_leaf =
idx:cutting_board:lawprop:23:harvest_root =
idx:cutting_board:lawprop:27:harvest_root =
idx:cutting_board:lawprop:15:chop =
idx:cutting_board:lawprop:11:chop =
idx:cutting_board:lawprop:49:choptatoes =
idx:cutting_board:lawprop:45:choptatoes =
idx:cutting_board:lawprop:15:mince =
idx:cutting_board:lawprop:28:mince =
idx:mortar:lawprop:69:grind_organ =
idx:mortar:lawprop:15:grind =
idx:mortar:lawprop:11:grind =
idx:mortar:lawprop:15:over =
idx:mortar:lawprop:11:over =
idx:mortar:lawprop:22:over =
idx:mortar:lawprop:15:grind_fine =
idx:mortar:lawprop:28:grind_fine =
idx:mortar:lawprop:15:over_fine =
idx:mortar:lawprop:28:over_fine =
idx:mortar:lawprop:22:over_fine =
idx:mortar:lawprop:15:grind_ultra =
idx:mortar:lawprop:29:grind_ultra =
idx:mortar:lawprop:15:over_ultra =
idx:mortar:lawprop:29:over_ultra =
idx:mortar:lawprop:22:over_ultra =
idx:mortar:lawprop:15:poultice =
idx:mortar:lawprop:12:poultice =
idx:mortar:lawprop:18:poultice =
idx:alambic:lawprop:37:distill_water =
idx:alambic:lawprop:72:distill_water =
idx:cauldron:lawprop:0:overcooked =
idx:cauldron:lawprop:0:cooked_ok =
idx:cauldron:lawprop:1:corrosif =
idx:cauldron:lawprop:2:corrosif =
idx:cauldron:lawprop:33:vomitif =
idx:cauldron:lawprop:0:boil_water =
idx:cauldron:lawprop:37:boil_water =
idx:cauldron:lawprop:72:boil_water =
idx:cauldron:lawprop:37:perf =
idx:cauldron:lawprop:72:perf =
idx:cauldron:lawprop:32:perf =
idx:cauldron:lawprop:37:brine =
idx:cauldron:lawprop:72:brine =
idx:cauldron:lawprop:32:brine =
idx:cauldron:lawprop:0:fry =
idx:cauldron:lawprop:35:fry =
idx:cauldron:lawprop:49:makefries =
idx:cauldron:lawprop:0:makefries =
idx:cauldron:lawprop:35:makefries =
idx:cauldron:lawprop:46:makefries =
idx:field:lawprop:42:sprout =
idx:field:lawprop:48:sprout =
idx:field:lawprop:43:mature =
idx:field:lawprop:48:mature =
idx:field:lawprop:44:harvest =
