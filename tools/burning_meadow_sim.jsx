import { useState, useCallback, useRef, useEffect } from "react";

// ── CARD DATABASE (regenerated from CardDB.gd by tools/_sync_sim.py) ──
const CARDS = {
  // Starters
  goblin: { name:"Goblin", type:"creature", rarity:"starter", cost:1, atk:1, hp:2, keywords:["on_enter"], floop:null },
  ratling: { name:"Ratling", type:"creature", rarity:"starter", cost:1, atk:2, hp:2, keywords:["wither","on_death","floop"], floop:{type:"damage_opposing_grow",value:1} },
  sprite: { name:"Sprite", type:"creature", rarity:"starter", cost:1, atk:1, hp:2, keywords:["floop"], floop:{type:"buff_adjacent_atk",value:1} },
  brute: { name:"Brute", type:"creature", rarity:"starter", cost:2, atk:2, hp:3, keywords:["on_enter"], floop:null },
  troll: { name:"Troll", type:"creature", rarity:"starter", cost:2, atk:2, hp:3, keywords:["floop"], floop:{type:"heal_self",value:2} },
  naga: { name:"Naga", type:"creature", rarity:"starter", cost:3, atk:3, hp:4, keywords:["floop"], floop:{type:"damage_opposing",value:2} },
  // Starter Spells
  fireball: { name:"Fireball", type:"spell", rarity:"starter", cost:1, effect:"damage_face", value:3, target:"none" },
  strike: { name:"Strike", type:"spell", rarity:"starter", cost:1, effect:"damage", value:3, target:"any_creature" },
  // Common Creatures
  bloodhound: { name:"Bloodhound", type:"creature", rarity:"common", cost:1, atk:1, hp:3, keywords:["on_enter","floop"], floop:{type:"slay_draw",value:1} },
  gravedigger: { name:"Gravedigger", type:"creature", rarity:"common", cost:1, atk:1, hp:3, keywords:["floop"], floop:{type:"raise_dead"} },
  hexblade: { name:"Hexblade", type:"creature", rarity:"common", cost:1, atk:1, hp:3, keywords:["floop"], floop:{type:"discount_next",value:1} },
  hound: { name:"Hound", type:"creature", rarity:"common", cost:1, atk:1, hp:3, keywords:["on_death","floop"], floop:{type:"damage_any",value:2} },
  lookout: { name:"Lookout", type:"creature", rarity:"common", cost:1, atk:1, hp:3, keywords:["on_enter","floop"], floop:{type:"scry",value:1} },
  mana_sprite: { name:"Mana Sprite", type:"creature", rarity:"common", cost:1, atk:1, hp:3, keywords:["floop"], floop:{type:"gain_mana",value:1} },
  plague_rat: { name:"Plague Rat", type:"creature", rarity:"common", cost:1, atk:1, hp:1, keywords:["poison","on_death","floop"], floop:{type:"damage_opposing",value:1} },
  raven: { name:"Raven", type:"creature", rarity:"common", cost:1, atk:2, hp:2, keywords:["ranged","floop"], floop:{type:"reorder_deck",value:3} },
  scavenger: { name:"Scavenger", type:"creature", rarity:"common", cost:1, atk:1, hp:3, keywords:["on_enter","floop"], floop:{type:"gain_gold",value:2} },
  stone_wall: { name:"Stone Wall", type:"creature", rarity:"common", cost:1, atk:0, hp:5, keywords:["thorns","floop"], floop:{type:"shield_adjacent",value:1} },
  torchbearer: { name:"Torchbearer", type:"creature", rarity:"common", cost:1, atk:1, hp:3, keywords:["adj_buff","wither","floop"], floop:{type:"grant_thorns_adjacent",value:1} },
  warding_stone: { name:"Warding Stone", type:"creature", rarity:"common", cost:1, atk:0, hp:5, keywords:["guardian","thorns","floop"], floop:{type:"heal_self",value:2} },
  crystal_sentry: { name:"Crystal Sentry", type:"creature", rarity:"common", cost:2, atk:2, hp:4, keywords:["shield","floop"], floop:{type:"grant_shield_adjacent"} },
  harpy: { name:"Harpy", type:"creature", rarity:"common", cost:2, atk:2, hp:3, keywords:["swift","floop"], floop:{type:"relocate"} },
  pikeman: { name:"Pikeman", type:"creature", rarity:"common", cost:2, atk:3, hp:3, keywords:["on_enter","floop"], floop:{type:"damage_opposing_splash",value:1} },
  shieldbearer: { name:"Shieldbearer", type:"creature", rarity:"common", cost:2, atk:1, hp:5, keywords:["armored","floop"], floop:{type:"shield_adjacent",value:1} },
  squire_captain: { name:"Squire Captain", type:"creature", rarity:"common", cost:2, atk:2, hp:4, keywords:["summon","floop"], floop:{type:"buff_tokens_atk",value:1} },
  thornguard: { name:"Thornguard", type:"creature", rarity:"common", cost:2, atk:1, hp:4, keywords:["thorns","on_death","floop"], floop:{type:"buff_thorns",value:2} },
  // Common Spells
  adrenaline: { name:"Adrenaline", type:"spell", rarity:"common", cost:0, effect:"custom_adrenaline", value:0, target:"none", exhaust:true },
  blood_tithe: { name:"Blood Tithe", type:"spell", rarity:"common", cost:0, effect:"custom_blood_tithe", value:0, target:"none" },
  gambit: { name:"Gambit", type:"spell", rarity:"common", cost:0, effect:"custom_gambit", value:0, target:"none" },
  provision: { name:"Provision", type:"spell", rarity:"common", cost:0, effect:"draw", value:2, target:"none", exhaust:true },
  quick_shot: { name:"Quick Shot", type:"spell", rarity:"common", cost:0, effect:"damage", value:1, target:"any" },
  scrap: { name:"Scrap", type:"spell", rarity:"common", cost:0, effect:"custom_scrap", value:0, target:"none" },
  shove: { name:"Shove", type:"spell", rarity:"common", cost:0, effect:"damage", value:2, target:"enemy_creature" },
  flame_bolt: { name:"Flame Bolt", type:"spell", rarity:"common", cost:1, effect:"damage_face", value:3, target:"none" },
  frost_bolt: { name:"Frost Bolt", type:"spell", rarity:"common", cost:1, effect:"damage", value:2, target:"any_creature" },
  lost_tome: { name:"Lost Tome", type:"spell", rarity:"common", cost:1, effect:"draw", value:1, target:"none", exhaust:true },
  patch_up: { name:"Patch Up", type:"spell", rarity:"common", cost:1, effect:"heal", value:4, target:"friendly_creature" },
  reckless_charge: { name:"Reckless Charge", type:"spell", rarity:"common", cost:1, effect:"damage", value:3, target:"any_creature" },
  ricochet: { name:"Ricochet", type:"spell", rarity:"common", cost:1, effect:"damage", value:2, target:"none" },
  shield_wall: { name:"Shield Wall", type:"spell", rarity:"common", cost:1, effect:"buff_hp", value:4, target:"friendly_creature" },
  slash: { name:"Slash", type:"spell", rarity:"common", cost:1, effect:"damage", value:3, target:"any_creature" },
  war_cry: { name:"War Cry", type:"spell", rarity:"common", cost:1, effect:"buff_all_atk", value:1, target:"none" },
  // Uncommon Creatures
  blood_pyre: { name:"Blood Pyre", type:"creature", rarity:"uncommon", cost:1, atk:1, hp:3, keywords:["on_death","floop"], floop:{type:"blood_sacrifice",value:2} },
  chaos_imp: { name:"Chaos Imp", type:"creature", rarity:"uncommon", cost:1, atk:1, hp:2, keywords:["on_enter","floop"], floop:{type:"discard_top_damage"} },
  familiar: { name:"Familiar", type:"creature", rarity:"uncommon", cost:1, atk:1, hp:3, keywords:["on_enter","floop"], floop:{type:"buff_familiar_pick"} },
  mule: { name:"Mule", type:"creature", rarity:"uncommon", cost:1, atk:0, hp:3, keywords:["on_enter","floop"], floop:{type:"filter_draw"} },
  vengeance: { name:"Vengeance", type:"creature", rarity:"uncommon", cost:1, atk:1, hp:3, keywords:["floop"], floop:{type:"damage_face",value:2} },
  adaptable: { name:"Adaptable", type:"creature", rarity:"uncommon", cost:2, atk:3, hp:3, keywords:["on_enter","floop"], floop:{type:"self_buff_atk",value:1} },
  basilisk: { name:"Basilisk", type:"creature", rarity:"uncommon", cost:2, atk:1, hp:4, keywords:["poison","floop"], floop:{type:"damage_opposing",value:1} },
  battle_drummer: { name:"Battle Drummer", type:"creature", rarity:"uncommon", cost:2, atk:1, hp:4, keywords:["adj_buff","floop"], floop:{type:"buff_all_atk_permanent",value:1} },
  berserker: { name:"Berserker", type:"creature", rarity:"uncommon", cost:2, atk:3, hp:3, keywords:["floop"], floop:{type:"damage_self_opposing",value:2} },
  cleave_hound: { name:"Cleave Hound", type:"creature", rarity:"uncommon", cost:2, atk:3, hp:3, keywords:["floop"], floop:{type:"self_buff_atk",value:1} },
  copycat: { name:"Copycat", type:"creature", rarity:"uncommon", cost:2, atk:0, hp:1, keywords:["on_enter","floop"], floop:{type:"copy_opposing_floop"} },
  duelist: { name:"Duelist", type:"creature", rarity:"uncommon", cost:2, atk:2, hp:3, keywords:["swift","on_enter","floop"], floop:{type:"damage_opposing_heal",value:2} },
  glass_knight: { name:"Glass Knight", type:"creature", rarity:"uncommon", cost:2, atk:3, hp:2, keywords:["shield","swift","floop"], floop:{type:"self_buff_atk",value:1} },
  griffin: { name:"Griffin", type:"creature", rarity:"uncommon", cost:2, atk:2, hp:3, keywords:["swift","on_death","floop"], floop:{type:"challenge"} },
  husk: { name:"Husk", type:"creature", rarity:"uncommon", cost:2, atk:2, hp:4, keywords:["floop"], floop:{type:"heal_self",value:2} },
  leyline_conduit: { name:"Leyline Conduit", type:"creature", rarity:"uncommon", cost:2, atk:0, hp:4, keywords:["floop"], floop:{type:"gain_mana",value:2} },
  necromancer: { name:"Necromancer", type:"creature", rarity:"uncommon", cost:2, atk:1, hp:3, keywords:["on_death","floop"], floop:{type:"kill_adjacent_summon"} },
  revenant: { name:"Revenant", type:"creature", rarity:"uncommon", cost:2, atk:2, hp:3, keywords:["on_death","floop"], floop:{type:"damage_opposing",value:1} },
  scholar: { name:"Scholar", type:"creature", rarity:"uncommon", cost:2, atk:2, hp:3, keywords:["on_enter"], floop:null },
  summoner: { name:"Summoner", type:"creature", rarity:"uncommon", cost:2, atk:1, hp:3, keywords:["summon","floop"], floop:{type:"summon_random"} },
  witch: { name:"Witch", type:"creature", rarity:"uncommon", cost:2, atk:2, hp:4, keywords:["on_enter","floop"], floop:{type:"gain_mana",value:1} },
  iron_bastion: { name:"Iron Bastion", type:"creature", rarity:"uncommon", cost:3, atk:1, hp:7, keywords:["armored","floop"], floop:{type:"grant_armored_all"} },
  ironclad_veteran: { name:"Ironclad Veteran", type:"creature", rarity:"uncommon", cost:3, atk:2, hp:4, keywords:["on_enter","floop"], floop:{type:"discount_next",value:2} },
  paladin: { name:"Paladin", type:"creature", rarity:"uncommon", cost:3, atk:2, hp:4, keywords:["last_stand","adj_buff","floop"], floop:{type:"heal_all_friendly",value:2} },
  royal_guard: { name:"Royal Guard", type:"creature", rarity:"uncommon", cost:3, atk:2, hp:5, keywords:["floop"], floop:{type:"redirect_adjacent"} },
  // Uncommon Spells
  bloodletting: { name:"Bloodletting", type:"spell", rarity:"uncommon", cost:0, effect:"custom_bloodletting", value:0, target:"none" },
  offering: { name:"Offering", type:"spell", rarity:"uncommon", cost:0, effect:"custom_offering", value:0, target:"friendly_creature", exhaust:true },
  soul_swap: { name:"Soul Swap", type:"spell", rarity:"uncommon", cost:0, effect:"custom_soul_swap", value:0, target:"any_creature" },
  turbo: { name:"Turbo", type:"spell", rarity:"uncommon", cost:0, effect:"custom_turbo", value:0, target:"none" },
  war_chant: { name:"War Chant", type:"spell", rarity:"uncommon", cost:0, effect:"custom_war_chant", value:0, target:"none" },
  ambush: { name:"Ambush", type:"spell", rarity:"uncommon", cost:1, effect:"damage_all_enemies", value:1, target:"none" },
  charge_spell: { name:"Charge!", type:"spell", rarity:"uncommon", cost:1, effect:"damage", value:1, target:"friendly_creature" },
  dark_pact: { name:"Dark Pact", type:"spell", rarity:"uncommon", cost:1, effect:"buff_all_atk", value:1, target:"none" },
  fuel_the_pyre: { name:"Fuel the Pyre", type:"spell", rarity:"uncommon", cost:1, effect:"custom_fuel_the_pyre", value:0, target:"friendly_creature" },
  grave_pact: { name:"Grave Pact", type:"spell", rarity:"uncommon", cost:1, effect:"custom_grave_pact", value:0, target:"none" },
  grave_robbery: { name:"Grave Robbery", type:"spell", rarity:"uncommon", cost:1, effect:"custom_grave_robbery", value:0, target:"none", exhaust:true },
  hex: { name:"Hex", type:"spell", rarity:"uncommon", cost:1, effect:"damage", value:2, target:"enemy_creature" },
  hoarfrost: { name:"Hoarfrost", type:"spell", rarity:"uncommon", cost:1, effect:"damage_all_enemies", value:1, target:"friendly_creature" },
  holy_smite: { name:"Holy Smite", type:"spell", rarity:"uncommon", cost:1, effect:"damage", value:3, target:"enemy_creature" },
  lay_on_hands: { name:"Lay on Hands", type:"spell", rarity:"uncommon", cost:1, effect:"heal", value:99, target:"friendly_creature" },
  pillage: { name:"Pillage", type:"spell", rarity:"uncommon", cost:1, effect:"damage", value:3, target:"any_creature" },
  reanimate: { name:"Reanimate", type:"spell", rarity:"uncommon", cost:1, effect:"draw", value:1, target:"none", exhaust:true },
  recycle: { name:"Recycle", type:"spell", rarity:"uncommon", cost:1, effect:"custom_recycle", value:0, target:"none" },
  venom_tip: { name:"Venom Tip", type:"spell", rarity:"uncommon", cost:1, effect:"buff_hp", value:0, target:"friendly_creature", exhaust:true },
  echo_spell: { name:"Echo", type:"spell", rarity:"uncommon", cost:2, effect:"custom_echo_spell", value:0, target:"none", exhaust:true },
  inspire: { name:"Inspire", type:"spell", rarity:"uncommon", cost:2, effect:"buff_all_atk", value:2, target:"none", exhaust:true },
  smite_spell: { name:"Smite", type:"spell", rarity:"uncommon", cost:2, effect:"damage", value:6, target:"any_creature", exhaust:true },
  war_council: { name:"War Council", type:"spell", rarity:"uncommon", cost:2, effect:"draw", value:1, target:"none", exhaust:true },
  overwhelming_force: { name:"Overwhelming Force", type:"spell", rarity:"uncommon", cost:4, effect:"buff_all_atk", value:3, target:"none", exhaust:true },
  // Rare Creatures
  assassin: { name:"Assassin", type:"creature", rarity:"rare", cost:2, atk:5, hp:1, keywords:["swift","piercing","floop"], floop:{type:"execute",value:2} },
  corpse_eater: { name:"Corpse Eater", type:"creature", rarity:"rare", cost:2, atk:2, hp:4, keywords:["floop"], floop:{type:"devour_adjacent"} },
  warden_of_graves: { name:"Warden of Graves", type:"creature", rarity:"rare", cost:2, atk:2, hp:4, keywords:["floop"], floop:{type:"graveyard_damage"} },
  doppelganger: { name:"Doppelganger", type:"creature", rarity:"rare", cost:3, atk:2, hp:3, keywords:["on_enter","floop"], floop:{type:"become_copy"} },
  hydra: { name:"Hydra", type:"creature", rarity:"rare", cost:3, atk:2, hp:5, keywords:["floop"], floop:{type:"grow_per_enemies"} },
  siege_golem: { name:"Siege Golem", type:"creature", rarity:"rare", cost:3, atk:3, hp:5, keywords:["floop"], floop:{type:"damage_opposing",value:3} },
  treasure_hunter: { name:"Treasure Hunter", type:"creature", rarity:"rare", cost:3, atk:2, hp:3, keywords:["on_enter"], floop:null },
  vampire_lord: { name:"Vampire Lord", type:"creature", rarity:"rare", cost:3, atk:2, hp:4, keywords:["regenerate","floop"], floop:{type:"drain",value:2} },
  doom_knight: { name:"Doom Knight", type:"creature", rarity:"rare", cost:4, atk:3, hp:5, keywords:["piercing","swift","floop"], floop:{type:"self_buff_atk",value:2} },
  dragon_hatchling: { name:"Dragon Hatchling", type:"creature", rarity:"rare", cost:4, atk:3, hp:4, keywords:["on_enter","wither","floop"], floop:{type:"damage_all",value:1} },
  riteforge: { name:"Riteforge", type:"creature", rarity:"rare", cost:4, atk:0, hp:5, keywords:["floop"], floop:{type:"gain_mana",value:1} },
  warchief: { name:"Warchief", type:"creature", rarity:"rare", cost:4, atk:0, hp:5, keywords:["floop"], floop:{type:"summon_random"} },
  // Rare Spells
  unholy_bargain: { name:"Unholy Bargain", type:"spell", rarity:"rare", cost:0, effect:"draw", value:3, target:"none", exhaust:true },
  mass_grave: { name:"Mass Grave", type:"spell", rarity:"rare", cost:1, effect:"damage_all_enemies", value:3, target:"none", exhaust:true },
  banish: { name:"Banish", type:"spell", rarity:"rare", cost:2, effect:"custom_banish", value:0, target:"enemy_creature", exhaust:true },
  earthquake: { name:"Earthquake", type:"spell", rarity:"rare", cost:2, effect:"damage_all", value:3, target:"none", exhaust:true },
  kings_command: { name:"King's Command", type:"spell", rarity:"rare", cost:2, effect:"buff_all_atk", value:3, target:"none", exhaust:true },
  time_snare: { name:"Time Snare", type:"spell", rarity:"rare", cost:2, effect:"custom_time_snare", value:0, target:"none", exhaust:true },
  apocalypse: { name:"Apocalypse", type:"spell", rarity:"rare", cost:3, effect:"damage_all", value:99, target:"none", exhaust:true },
  cataclysm: { name:"Cataclysm", type:"spell", rarity:"rare", cost:3, effect:"custom_cataclysm", value:0, target:"none", exhaust:true },
  inferno: { name:"Inferno", type:"spell", rarity:"rare", cost:4, effect:"damage_all_enemies", value:4, target:"none", exhaust:true },
};



// ── RELICS (regenerated from RelicDB.gd by tools/_sync_sim.py) ──
const STARTING_RELICS = [
  { id:"iron_buckler", name:"Iron Buckler", desc:"First creature you play each fight gains Last Stand." },
  { id:"ember_crown", name:"Ember Crown", desc:"Your first spell each turn costs 0." },
  { id:"couriers_bag", name:"Courier's Bag", desc:"Draw 6 on turn 1 of each fight instead of 5." },
  { id:"coin_purse", name:"Coin Purse", desc:"Gain 10 extra gold per fight." },
  { id:"worn_spellbook", name:"Worn Spellbook", desc:"Your damage spells deal +1 damage." },
  { id:"scouts_emblem", name:"Scout's Emblem", desc:"Card rewards show 4 choices instead of 3." },
  { id:"soul_lantern", name:"Soul Lantern", desc:"First friendly death each round: +1 mana next turn." },
  { id:"veterans_medal", name:"Veteran's Medal", desc:"Your 1-cost creatures have +1/+1." },
];

const COMBAT_RELICS = [
  { id:"war_drum", name:"War Drum", desc:"On-enter damage effects deal +1." },
  { id:"banner_of_unity", name:"Banner of Unity", desc:"Adjacency buffs give +1 extra." },
  { id:"swift_boots", name:"Swift Boots", desc:"Swift creatures have +1 ATK." },
  { id:"fortress_stone", name:"Fortress Stone", desc:"Armored creatures take 2 less instead of 1." },
  { id:"briar_amulet", name:"Briar Amulet", desc:"Thorns deals 2 instead of 1." },
  { id:"echo_staff", name:"Echo Staff", desc:"Floop abilities trigger twice." },
  { id:"piercing_crown", name:"Piercing Crown", desc:"Piercing overflow damage +1." },
  { id:"conscription_relic", name:"Conscription", desc:"Token creatures from Summon have +1 HP." },
  { id:"bone_ring", name:"Bone Ring", desc:"On-death effects deal +1 damage." },
  { id:"pyromaniac_ring", name:"Pyromaniac's Ring", desc:"Spells that deal face damage deal +1." },
  { id:"war_horn", name:"War Horn", desc:"Spells that buff ATK give +1 extra." },
  { id:"battle_scars", name:"Battle Scars", desc:"First time you take face damage each fight: gain 2 bonus mana this turn." },
  { id:"glass_cannon", name:"Glass Cannon", desc:"Your creatures have +1 ATK but -1 HP." },
  { id:"stone_skin", name:"Stone Skin", desc:"Your creatures have +1 HP but -1 ATK." },
  { id:"thiefs_gloves", name:"Thief's Gloves", desc:"Win taking 0 face damage: gain 5 gold." },
  { id:"butchers_cleaver", name:"Butcher's Cleaver", desc:"Sacrifice a creature: next creature this turn +2 ATK for 2 turns." },
  { id:"vultures_feast", name:"Vulture's Feast", desc:"After fight, heal 1 HP per friendly death, max 5." },
  { id:"gamblers_coin", name:"Gambler's Coin", desc:"Start of fight: draw 1 extra OR 3 to random enemy." },
  { id:"bone_pile", name:"Bone Pile", desc:"Sacrifice: deal creature's ATK to opposing creature." },
  { id:"resonance_crystal", name:"Resonance Crystal", desc:"First keyword creature death: all allies gain that keyword." },
  { id:"mimic_ring", name:"Mimic Ring", desc:"Played creature copies 1 keyword from adjacent ally." },
  { id:"scroll_of_greed", name:"Scroll of Greed", desc:"Non-normal draw: gain 1 gold per card." },
  { id:"bloodstone_relic", name:"Bloodstone", desc:"When you take face damage, creatures +1 ATK this turn." },
  { id:"phoenix_heart", name:"Phoenix Heart", desc:"Once per run: when you would die, revive at 1 HP instead." },
  { id:"vanguard_banner", name:"Vanguard Banner", desc:"Your front-row creatures have +1 ATK." },
  { id:"rear_guard_charm", name:"Rear Guard Charm", desc:"When a front-row friendly dies, the back-row creature in its column gains +1/+1 permanent." },
  { id:"phantom_veil", name:"Phantom Veil", desc:"Once per round: the first friendly that would die survives at 1 HP." },
  { id:"hexagonal_shield", name:"Hexagonal Shield", desc:"Enemy ranged attacks can't target your back row." },
  { id:"lantern", name:"Lantern", desc:"Gain 1 bonus mana on turn 1 of each combat." },
  { id:"happy_flower", name:"Happy Flower", desc:"Every 3 turns, gain 1 bonus mana." },
  { id:"ice_cream", name:"Ice Cream", desc:"Unspent mana carries over fully between turns (no cap)." },
  { id:"art_of_war", name:"Art of War", desc:"If you play no cards this turn, gain 1 extra mana next turn." },
  { id:"sundial", name:"Sundial", desc:"Every 3 deck shuffles, gain 2 mana." },
];

const UTILITY_RELICS = [
  { id:"merchants_license", name:"Merchant's License", desc:"Shop prices reduced by 25%." },
  { id:"collectors_tome", name:"Collector's Tome", desc:"Pick 2 cards from reward instead of 1." },
  { id:"blacksmiths_hammer", name:"Blacksmith's Hammer", desc:"Sharpen/Fortify give +3 instead of +2. Imbue offers 3 choices." },
  { id:"scavengers_pouch", name:"Scavenger's Pouch", desc:"Gain 20 gold when you remove a card." },
];

const BOSS_RELICS = [
  { id:"cursed_key", name:"Cursed Key", desc:"+1 max mana. Gain a Curse after every combat reward." },
  { id:"coffee_dripper", name:"Coffee Dripper", desc:"+1 max mana. Can't heal at rest sites." },
  { id:"fusion_hammer", name:"Fusion Hammer", desc:"+1 max mana. Can't upgrade cards at rest sites." },
  { id:"ectoplasm", name:"Ectoplasm", desc:"+1 max mana. Can't gain gold." },
  { id:"busted_crown", name:"Busted Crown", desc:"+1 max mana. Card rewards show 1 choice instead of 3." },
  { id:"sozu", name:"Sozu", desc:"+1 max mana. Can't gain potions." },
  { id:"philosophers_stone", name:"Philosopher's Stone", desc:"+1 max mana. All enemies get +1 ATK." },
  { id:"velvet_choker", name:"Velvet Choker", desc:"+1 max mana. Can only play 5 cards per turn." },
  { id:"mark_of_pain", name:"Mark of Pain", desc:"+1 max mana. Start each combat with 2 Curses in draw pile." },
];

// ── ENCOUNTERS (HP matched to design doc) ────────────────────
const ENCOUNTERS = {
  act1_combat: [
    { name:"Goblin Scouts", hp:11, deck:[{n:"Goblin",a:2,h:2},{n:"Goblin",a:2,h:2},{n:"Goblin",a:2,h:2},{n:"Goblin",a:2,h:2},{n:"G.Scout",a:2,h:3},{n:"G.Scout",a:2,h:3}], reinf:{n:"Runt",a:1,h:1}, passive:null },
    { name:"Wolf Pack", hp:13, deck:[{n:"Wolf",a:2,h:3},{n:"Wolf",a:2,h:3},{n:"Wolf",a:2,h:3},{n:"Dire",a:3,h:3},{n:"Dire",a:3,h:3},{n:"Alpha",a:3,h:4}], reinf:{n:"Pup",a:1,h:1}, passive:"adj_death_buff" },
    { name:"Bandit Camp", hp:13, deck:[{n:"Bandit",a:2,h:3},{n:"Bandit",a:2,h:3},{n:"Bandit",a:2,h:3},{n:"Archer",a:2,h:3},{n:"Archer",a:2,h:3},{n:"Captain",a:3,h:3}], reinf:{n:"Thug",a:1,h:2}, passive:"steal_mana" },
    { name:"Mushroom Grove", hp:9, deck:[{n:"Sprout",a:1,h:4},{n:"Sprout",a:1,h:4},{n:"Sprout",a:1,h:4},{n:"Spore",a:2,h:4},{n:"Spore",a:2,h:4},{n:"Mycelium",a:2,h:5}], reinf:{n:"Spore",a:1,h:2}, passive:"heal_all_1" },
    { name:"Stone Sentinels", hp:11, deck:[{n:"Golem",a:2,h:3},{n:"Golem",a:2,h:3},{n:"Golem",a:2,h:4},{n:"Golem",a:2,h:4},{n:"Hurler",a:3,h:3},{n:"Granite",a:2,h:4}], reinf:{n:"Fragment",a:1,h:2}, passive:null },
    { name:"Harpy Nest", hp:12, deck:[{n:"Harpy",a:3,h:2},{n:"Harpy",a:3,h:2},{n:"Harpy",a:3,h:2},{n:"W.Harpy",a:3,h:2,kw:["swift"]},{n:"W.Harpy",a:3,h:2,kw:["swift"]},{n:"Matron",a:2,h:4}], reinf:{n:"Chick",a:1,h:1}, passive:null },
  ],
  act1_elite: [
    { name:"Orc Warband", hp:18, deck:[{n:"Warrior",a:3,h:3},{n:"Brute",a:3,h:4},{n:"Chief",a:4,h:4}], reinf:{n:"Grunt",a:2,h:2}, passive:"random_enemy_atk_1" },
    { name:"Necromancer's Tower", hp:18, deck:[{n:"Skeleton",a:1,h:1},{n:"Skeleton",a:1,h:1},{n:"B.Knight",a:2,h:3,onDeath:{type:"summon",atk:2,hp:2}},{n:"Acolyte",a:1,h:3},{n:"Lich",a:2,h:4,kw:["regenerate"]}], reinf:{n:"Risen",a:1,h:2}, passive:"death_summon_skeleton" },
  ],
  act1_boss: [
    { name:"The Iron Warden", hp:23, deck:[{n:"Sentinel",a:3,h:3},{n:"Sentinel",a:3,h:3},{n:"Sentinel",a:3,h:3},{n:"I.Guard",a:2,h:4,kw:["armored"]},{n:"Engine",a:3,h:2},{n:"Champion",a:4,h:3,kw:["swift"]},{n:"Vanguard",a:4,h:4,kw:["last_stand"]}], reinf:{n:"Recruit",a:2,h:2}, passive:null },
    { name:"Dragon Lord", hp:21, deck:[{n:"Drake",a:3,h:3},{n:"Drake",a:3,h:3},{n:"Drake",a:3,h:3},{n:"Wyrm",a:3,h:4,kw:["regenerate"]},{n:"Wyrm",a:3,h:4,kw:["regenerate"]},{n:"Elder",a:4,h:5}], reinf:{n:"Whelp",a:2,h:2}, passive:"all_piercing" },
  ],
  act2_combat: [
    { name:"Cultist Enclave", hp:16, deck:[{n:"Cultist",a:3,h:3},{n:"Cultist",a:3,h:3},{n:"Cultist",a:3,h:3},{n:"D.Priest",a:2,h:4,kw:["regenerate"]},{n:"D.Priest",a:2,h:4,kw:["regenerate"]},{n:"Zealot",a:3,h:3},{n:"Fanatic",a:4,h:4}], reinf:{n:"Initiate",a:2,h:2}, passive:"random_enemy_buff_1" },
    { name:"Swamp Horror", hp:16, deck:[{n:"Lurker",a:2,h:5},{n:"Lurker",a:2,h:5},{n:"Lurker",a:2,h:5},{n:"Mire",a:3,h:4},{n:"Mire",a:3,h:4},{n:"Hag",a:2,h:3},{n:"Hydra",a:3,h:3,kw:["regenerate"]}], reinf:{n:"Leech",a:1,h:3}, passive:"all_thorns" },
    { name:"Mercenary Co.", hp:15, deck:[{n:"Sell",a:3,h:3},{n:"Sell",a:3,h:3},{n:"Captain",a:4,h:4},{n:"Captain",a:4,h:4},{n:"Sharp",a:3,h:2},{n:"Enforcer",a:4,h:3,kw:["swift"]},{n:"Brute",a:5,h:4}], reinf:{n:"Recruit",a:2,h:3}, passive:"4atk_piercing" },
    { name:"Haunted Crypt", hp:17, deck:[{n:"Wraith",a:3,h:4},{n:"Wraith",a:3,h:4},{n:"Wraith",a:3,h:4},{n:"Banshee",a:2,h:3},{n:"Banshee",a:2,h:3},{n:"Warden",a:3,h:5,kw:["armored"]},{n:"Specter",a:2,h:2,kw:["swift"]}], reinf:{n:"Shade",a:2,h:2}, passive:"floop_punish" },
    { name:"Fire Giant's Forge", hp:18, deck:[{n:"F.Golem",a:3,h:5},{n:"F.Golem",a:3,h:5},{n:"F.Golem",a:3,h:5},{n:"F.Guard",a:2,h:6,kw:["armored"]},{n:"F.Guard",a:2,h:6,kw:["armored"]},{n:"Ember",a:4,h:3},{n:"Slag",a:0,h:6}], reinf:{n:"Cinder",a:2,h:2}, passive:"1_dmg_all" },
  ],
  act2_elite: [
    { name:"Demon Vanguard", hp:25, deck:[{n:"D.Soldier",a:3,h:4},{n:"D.Soldier",a:3,h:4},{n:"D.Soldier",a:3,h:4},{n:"Hellhound",a:4,h:3,kw:["swift"]},{n:"Hellhound",a:4,h:3,kw:["swift"]},{n:"Pit Fiend",a:4,h:5,kw:["armored","regenerate"]},{n:"Infernal",a:5,h:4,kw:["piercing"]}], reinf:{n:"Imp",a:2,h:3}, passive:"spell_enemy_atk" },
    { name:"The Puppeteer", hp:23, deck:[{n:"Marionette",a:2,h:3},{n:"Marionette",a:2,h:3},{n:"Marionette",a:2,h:3},{n:"Marionette",a:2,h:3},{n:"P.Knight",a:3,h:4},{n:"P.Knight",a:3,h:4},{n:"S.Double",a:3,h:3},{n:"P.Guard",a:3,h:5}], reinf:{n:"String",a:1,h:2}, passive:null },
  ],
  act2_boss: [
    { name:"The Collector", hp:31, deck:[{n:"C.Golem",a:3,h:4},{n:"C.Golem",a:3,h:4},{n:"C.Golem",a:3,h:4},{n:"Display",a:2,h:5,kw:["armored"]},{n:"Pride",a:4,h:4},{n:"S.Cage",a:3,h:3},{n:"Champion",a:4,h:5,kw:["swift"]}], reinf:{n:"Trinket",a:2,h:3}, passive:"heal_on_play" },
    { name:"The Hollow King", hp:29, deck:[{n:"H.Knight",a:2,h:4},{n:"H.Knight",a:2,h:4},{n:"H.Knight",a:2,h:4},{n:"V.Guard",a:1,h:5,kw:["armored","regenerate"]},{n:"S.Blade",a:3,h:2,kw:["swift","piercing"]},{n:"Champion",a:4,h:4,kw:["last_stand"]}], reinf:{n:"Shade",a:2,h:2}, passive:"3_to_highest" },
  ],
  act3_combat: [
    { name:"Mirror Temple", hp:20, deck:[{n:"M.Knight",a:3,h:4},{n:"M.Knight",a:3,h:4},{n:"M.Knight",a:3,h:4},{n:"Reflect",a:2,h:3,kw:["swift"]},{n:"Reflect",a:2,h:3,kw:["swift"]},{n:"Doppel",a:4,h:4},{n:"Guardian",a:4,h:5,kw:["last_stand"]}], reinf:{n:"Shard",a:2,h:3}, passive:"death_heal_enemies" },
    { name:"Elemental Nexus", hp:21, deck:[{n:"Fire",a:4,h:3},{n:"Fire",a:4,h:3},{n:"Ice",a:2,h:5},{n:"Ice",a:2,h:5},{n:"Storm",a:3,h:4},{n:"Earth",a:3,h:6,kw:["armored"]},{n:"Core",a:2,h:4}], reinf:{n:"Spark",a:2,h:2}, passive:"cycle_buff" },
    { name:"Executioner's Block", hp:19, deck:[{n:"Headsman",a:4,h:4},{n:"Headsman",a:4,h:4},{n:"Torturer",a:3,h:3},{n:"Torturer",a:3,h:3},{n:"Condemned",a:2,h:5,kw:["thorns","last_stand"]},{n:"Executr",a:5,h:4,kw:["piercing"]}], reinf:{n:"Jailer",a:2,h:4}, passive:"highest_face" },
    { name:"Dragon's Lair", hp:22, deck:[{n:"Drake",a:3,h:4,kw:["piercing"]},{n:"Drake",a:3,h:4,kw:["piercing"]},{n:"Drake",a:3,h:4,kw:["piercing"]},{n:"Wyrm",a:4,h:5,kw:["regenerate"]},{n:"Wyrm",a:4,h:5,kw:["regenerate"]},{n:"Elder",a:5,h:6}], reinf:{n:"Whelp",a:2,h:3}, passive:"aoe_every_3" },
  ],
  act3_elite: [
    { name:"The Archlich", hp:29, deck:[{n:"S.Knight",a:3,h:4},{n:"S.Knight",a:3,h:4},{n:"S.Knight",a:3,h:4},{n:"B.Dragon",a:4,h:5,kw:["piercing","regenerate"]},{n:"Acolyte",a:2,h:3},{n:"Phylact",a:0,h:8}], reinf:{n:"Risen",a:2,h:3}, passive:"cant_die_to_attacks" },
    { name:"The Void Walker", hp:27, deck:[{n:"V.Spawn",a:3,h:4},{n:"V.Spawn",a:3,h:4},{n:"V.Spawn",a:3,h:4},{n:"R.Stalker",a:4,h:3,kw:["swift"]},{n:"R.Stalker",a:4,h:3,kw:["swift"]},{n:"Null",a:3,h:5},{n:"V.Maw",a:5,h:5}], reinf:{n:"Fragment",a:2,h:2}, passive:"exile_card" },
  ],
  act3_boss: [
    { name:"THE DEVIL", hp:36, deck:[{n:"D.Soldier",a:3,h:4},{n:"D.Soldier",a:3,h:4},{n:"D.Soldier",a:3,h:4},{n:"D.Soldier",a:3,h:4},{n:"H.Imp",a:3,h:3},{n:"P.Fiend",a:4,h:5,kw:["armored","regenerate"]},{n:"Reaper",a:3,h:4,kw:["swift","piercing"]},{n:"Champion",a:5,h:6,kw:["last_stand"]},{n:"Vanguard",a:4,h:5,kw:["last_stand"]}], reinf:{n:"Demon",a:3,h:3}, passive:"devil_cycle" },
  ],
};

// ── SIMULATION ENGINE ─────────────────────────────────────────
function shuffle(arr) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}
function pick(arr, n = 1) {
  return shuffle(arr).slice(0, Math.min(n, arr.length));
}
function rarityWeight(act, isElite) {
  // StS-style pyramid: rares are scarce, uncommons are the workhorse tier
  if (isElite) return { common: 0, uncommon: 70, rare: 30 };
  if (act === 1) return { common: 65, uncommon: 30, rare: 5 };
  if (act === 2) return { common: 55, uncommon: 35, rare: 10 };
  return { common: 45, uncommon: 40, rare: 15 };
}
function rollRarity(weights) {
  const r = Math.random() * 100;
  if (r < weights.common) return "common";
  if (r < weights.common + weights.uncommon) return "uncommon";
  return "rare";
}
function getCardPool(rarity) {
  return Object.entries(CARDS).filter(([, c]) => c.rarity === rarity).map(([id]) => id);
}

function scoreCard(cardId, currentDeck) {
  const card = CARDS[cardId];
  if (!card) return 0;
  let score = 0;

  if (card.type === "spell") {
    if (card.effect === "damage_face") score += 15;
    if (card.effect === "custom_blood_tithe") score += 12;
    if (card.effect === "custom_inferno") score += 20;
    if (card.effect === "custom_lightning") score += 12;
    if (card.effect === "damage_all_enemies") score += 14;
    if (card.effect === "damage_all") score += 10;
    if (card.effect === "custom_apocalypse") score += 16;
    if (card.effect === "custom_banish") score += 14;
    if (card.effect === "custom_time_snare") score += 12;
    if (card.effect === "buff_all_atk") score += 10 + card.value * 3;
    if (card.effect === "custom_overwhelming") score += 18;
    if (card.effect === "custom_kings_command") score += 18;
    if (card.effect === "draw") score += 8;
    if (card.effect === "custom_adrenaline") score += 10;
    if (card.effect === "custom_bloodletting") score += 8;
    if (card.effect === "damage") score += 8 + card.value;
    if (card.effect === "custom_mending_light") score += 10;
    if (score === 0) score += 6;
  } else if (card.type === "creature") {
    score += card.atk * 4 + card.hp * 2;
    const kw = card.keywords || [];
    if (kw.includes("swift")) score += 6;
    if (kw.includes("piercing")) score += 5;
    if (kw.includes("armored")) score += 4;
    if (kw.includes("thorns")) score += 3;
    if (kw.includes("regenerate")) score += 4;
    if (kw.includes("last_stand")) score += 5;
    if (kw.includes("ranged")) score += 3;
    if (card.floop) score += 4;
    if (kw.some(k => k.startsWith("on_enter_damage"))) score += 4;
    if (kw.some(k => k.startsWith("on_enter_draw"))) score += 3;
    if (card.cost === 0 && card.atk <= 1) score -= 3;
  }

  const creatureCount = currentDeck.filter(id => CARDS[id]?.type === "creature").length;
  const spellCount = currentDeck.filter(id => CARDS[id]?.type === "spell").length;
  if (card.type === "creature" && creatureCount > spellCount * 3) score += 3;
  if (card.type === "spell" && spellCount < 3) score += 5;

  return score;
}

function pickBestCard(pool, deck, numChoices) {
  if (pool.length === 0) return null;
  const choices = pick(pool, numChoices);
  // 60% chance to pick randomly, 40% chance to pick best — explores more card variety
  if (Math.random() < 0.6) return choices[Math.floor(Math.random() * choices.length)];
  let best = choices[0];
  let bestScore = scoreCard(choices[0], deck);
  for (let i = 1; i < choices.length; i++) {
    const s = scoreCard(choices[i], deck);
    if (s > bestScore) { best = choices[i]; bestScore = s; }
  }
  return best;
}
function makeStarterDeck() {
  return ["goblin","goblin","goblin","goblin","brute","brute","brute","brute","sprite","troll"];
}

// ── 4×4 LANE COMBAT (4 lanes × 2 rows per side = 8 slots) ───
// Front row is attacked first and blocks for back row.
// Both rows attack every round. Front attacks first.

function makeCreature(data, laneIdx, row) {
  const kw = data.kw || [];
  return {
    n: data.n, atk: data.a >= 4 ? data.a - 1 : data.a, hp: data.h, currentHP: data.h,
    isStructure: data.a === 0,
    lane: laneIdx, row: row || "front",
    swift: kw.includes("swift"), piercing: kw.includes("piercing"),
    armored: kw.includes("armored"), thorns: kw.includes("thorns"),
    regenerate: kw.includes("regenerate"), last_stand: kw.includes("last_stand"),
    lastStandUsed: false, keywords: kw,
    onDeath: data.onDeath || null,
  };
}

function makePlayerCreature(cardId, card, laneIdx, row, relics, bonusAtk) {
  const hasRelic = (id) => relics.some(r => r.id === id);
  let atk = card.atk + (bonusAtk || 0);
  let hp = card.hp;
  if (hasRelic("veterans_medal") && card.cost === 1) { atk++; hp++; }
  if (hasRelic("glass_cannon")) { atk++; hp = Math.max(1, hp - 1); }
  if (hasRelic("stone_skin")) { hp++; atk = Math.max(0, atk - 1); }
  const kw = card.keywords || [];
  return {
    id: cardId, n: card.name, atk, hp, currentHP: hp,
    lane: laneIdx, row: row || "front", floop: card.floop, keywords: kw,
    swift: kw.includes("swift"), piercing: kw.includes("piercing"),
    armored: kw.includes("armored"), thorns: kw.includes("thorns"),
    regenerate: kw.includes("regenerate"), last_stand: kw.includes("last_stand"),
    lastStandUsed: false, ranged: kw.includes("ranged"),
    cannotAttack: kw.includes("cannot_attack"),
    wither: kw.includes("wither"), _flooped: false,
    diesEndTurn: kw.includes("dies_end_turn"),
    faceOnly: kw.includes("face_only"),
  };
}

function applyDamage(target, dmg, isCreatureAttack) {
  let finalDmg = dmg;
  if (isCreatureAttack && target.armored) {
    finalDmg = Math.max(1, dmg - (target._fortressStone ? 2 : 1));
  }
  target.currentHP -= finalDmg;
  if (target.currentHP <= 0 && target.last_stand && !target.lastStandUsed) {
    target.currentHP = 1;
    target.lastStandUsed = true;
  }
  let thornsDmg = 0;
  if (isCreatureAttack && target.thorns && target.currentHP > 0) {
    thornsDmg = target._briarAmulet ? 2 : 1;
  }
  return { dealt: finalDmg, thornsDmg };
}

function findBestSlot(pF, pB, eF, eB, creatureAtk) {
  const atk = creatureAtk || 1;

  const frontKill = [], frontFace = [], frontBlock = [], frontWeak = [];
  for (let i = 0; i < 4; i++) {
    if (pF[i] !== null) continue;
    const enemy = eF[i] || eB[i];
    if (!enemy) frontFace.push(i);
    else if (atk >= enemy.currentHP) frontKill.push(i);
    else if (enemy.atk >= 3) frontBlock.push(i);
    else frontWeak.push(i);
  }
  const frontPick = frontKill.length > 0 ? frontKill :
                    frontFace.length > 0 ? frontFace :
                    frontBlock.length > 0 ? frontBlock :
                    frontWeak.length > 0 ? frontWeak : null;
  if (frontPick) return { lane: frontPick[Math.floor(Math.random() * frontPick.length)], row: "front" };

  const backKill = [], backFace = [], backBlock = [], backWeak = [];
  for (let i = 0; i < 4; i++) {
    if (pB[i] !== null) continue;
    const enemy = eF[i] || eB[i];
    if (!enemy) backFace.push(i);
    else if (atk >= enemy.currentHP) backKill.push(i);
    else if (enemy.atk >= 3) backBlock.push(i);
    else backWeak.push(i);
  }
  const backPick = backKill.length > 0 ? backKill :
                   backFace.length > 0 ? backFace :
                   backBlock.length > 0 ? backBlock :
                   backWeak.length > 0 ? backWeak : null;
  if (backPick) return { lane: backPick[Math.floor(Math.random() * backPick.length)], row: "back" };

  return null;
}

function simCombat(playerDeckIds, relics, encounter, baseMana, log, encounterType, incomingHP, bonusAtk) {
  let playerHP = incomingHP;
  let enemyHP = encounter.hp;
  const enemyDeck = [...encounter.deck];
  let enemyDeckIdx = 0;
  const hasRelic = (id) => relics.some(r => r.id === id);
  const philosopherStone = hasRelic("philosophers_stone");
  const passive = encounter.passive;
  const reactive = encounter.reactive || null;

  // Board: 4 lanes × 2 rows per side = 8 slots each
  let pF = [null, null, null, null]; // player front
  let pB = [null, null, null, null]; // player back
  let eF = [null, null, null, null]; // enemy front
  let eB = [null, null, null, null]; // enemy back

  const allPlayer = () => [...pF, ...pB].filter(c => c !== null);
  const allEnemy = () => [...eF, ...eB].filter(c => c !== null);

  // Find attack target: front first, then back, null = face
  function atkTarget(lane, side) {
    if (side === "player") {
      if (eF[lane] && eF[lane].currentHP > 0) return eF[lane];
      if (eB[lane] && eB[lane].currentHP > 0) return eB[lane];
      return null;
    }
    if (pF[lane] && pF[lane].currentHP > 0) return pF[lane];
    if (pB[lane] && pB[lane].currentHP > 0) return pB[lane];
    return null;
  }

  // Place enemy: front first (prefer blocking player), then back overflow
  function placeEnemy(data) {
    const frontBlock = [], frontEmpty = [];
    for (let i = 0; i < 4; i++) {
      if (eF[i] !== null) continue;
      if (pF[i] !== null || pB[i] !== null) frontBlock.push(i);
      frontEmpty.push(i);
    }
    const ft = frontBlock.length > 0 ? frontBlock : frontEmpty;
    if (ft.length > 0) {
      const lane = ft[Math.floor(Math.random() * ft.length)];
      const c = makeCreature(data, lane, "front");
      if (philosopherStone) c.atk++;
      eF[lane] = c;
      return true;
    }
    const backEmpty = [];
    for (let i = 0; i < 4; i++) { if (eB[i] === null) backEmpty.push(i); }
    if (backEmpty.length > 0) {
      const lane = backEmpty[Math.floor(Math.random() * backEmpty.length)];
      const c = makeCreature(data, lane, "back");
      if (philosopherStone) c.atk++;
      eB[lane] = c;
      return true;
    }
    return false;
  }

  // Place 2 starting enemies
  for (let i = 0; i < 2 && enemyDeckIdx < enemyDeck.length; i++) {
    placeEnemy(enemyDeck[enemyDeckIdx++]);
  }

  let drawPile = shuffle([...playerDeckIds]);
  let discardPile = [];
  let creaturesLost = 0;
  let totalDmgDealt = 0;
  let round = 0;
  const MAX_ROUNDS = 25;
  let fightLog = [];
  let bankedMana = 0;
  let firstCreaturePlayed = false;
  let phoenixUsed = false;
  let timeSnarePlayed = false;
  let bonusManaNextTurn = 0;
  let soulLanternUsedThisRound = false;
  let floopCount = 0;

  function drawCards(n, hand) {
    for (let i = 0; i < n; i++) {
      if (drawPile.length === 0 && discardPile.length > 0) {
        drawPile = shuffle([...discardPile]);
        discardPile = [];
      }
      if (drawPile.length > 0) hand.push(drawPile.pop());
    }
  }

  // On-death processing for player creatures
  function runOnDeath(creature, lane) {
    const kw = creature.keywords || [];
    const boneBonus = hasRelic("bone_ring") ? 1 : 0;
    for (const k of kw) {
      if (k === "on_death_2_opposing") {
        const dmg = 2 + boneBonus;
        const t = eF[lane] || eB[lane];
        if (t) { t.currentHP -= dmg; totalDmgDealt += dmg; }
      }
      if (k === "on_death_1_all") {
        const dmg = 1 + boneBonus;
        allEnemy().forEach(e => { e.currentHP -= dmg; totalDmgDealt += dmg; });
      }
      if (k === "on_death_return" && creature.id) {
        drawPile.push(creature.id);
      }
      if (k === "on_death_summon_2_2") {
        if (pF[lane] === null) pF[lane] = { n:"Token", atk:2, hp:2, currentHP:2, lane, row:"front", keywords:[], _flooped:false };
        else if (pB[lane] === null) pB[lane] = { n:"Token", atk:2, hp:2, currentHP:2, lane, row:"back", keywords:[], _flooped:false };
      }
      if (k === "on_death_bonus_mana") {
        bonusManaNextTurn += 1;
      }
      if (k === "passive_draw_on_death") {
        drawCards(1, []); // draw but card is lost (no hand during combat resolution)
      }
    }
    // Soul Lantern: first death each round gives +1 mana next turn
    if (hasRelic("soul_lantern") && !soulLanternUsedThisRound) {
      soulLanternUsedThisRound = true;
      bonusManaNextTurn += 1;
    }
  }

  // Encounter passive: fires ONLY when an enemy creature dies (matches real game)
  function onEnemyCreatureDeath(lane, deadCreature) {
    if (passive === "death_summon_skeleton" && deadCreature && deadCreature.n !== "Skeleton") placeEnemy({ n:"Skeleton", a:1, h:1 });
    if (passive === "adj_death_buff") {
      for (const arr of [eF, eB]) {
        if (lane > 0 && arr[lane - 1]) arr[lane - 1].atk++;
        if (lane < 3 && arr[lane + 1]) arr[lane + 1].atk++;
      }
    }
    // Enemy on_death effects (e.g., Bone Knight summon)
    if (deadCreature && deadCreature.onDeath) {
      runEnemyOnDeath(deadCreature, lane);
    }
  }

  function runEnemyOnDeath(creature, lane) {
    const od = creature.onDeath;
    if (!od) return;
    if (od.type === "summon") placeEnemy({ n:"Token", a:od.atk, h:od.hp });
  }

  // Reactive passive dispatch (fires on player actions or any creature death)
  function dispatchReactive(trigger, sourceLane, deadCreature) {
    if (!passive && !reactive) return;
    if (trigger === "ON_CREATURE_DEATH") {
      if (passive === "death_heal_enemies") allEnemy().forEach(e => { if (e.currentHP > 0) e.currentHP = Math.min(e.hp, e.currentHP + 1); });
      // double_on_death: re-fire the dying creature's on_death (for enemy creatures with on_death data)
      if ((passive === "double_on_death" || reactive === "double_on_death") && deadCreature && deadCreature.onDeath) {
        runEnemyOnDeath(deadCreature, sourceLane);
      }
    }
    if (trigger === "ON_PLAYER_SPELL") {
      if (passive === "spell_enemy_atk") {
        // Real game: buffs Chieftain specifically. Sim approximation: buff highest-ATK enemy.
        const ec = allEnemy();
        if (ec.length > 0) {
          const chief = ec.find(e => e.n === "Chieftain" || e.n === "Chief");
          if (chief) chief.atk++;
        }
      }
    }
    if (trigger === "ON_PLAYER_FLOOP") {
      if (passive === "floop_punish") {
        // 1 damage to the flooping creature (handled at call site)
      }
    }
    if (trigger === "ON_PLAYER_SUMMON") {
      if (passive === "heal_on_play") allEnemy().forEach(e => { if (e.currentHP > 0) e.currentHP = Math.min(e.hp, e.currentHP + 1); });
    }
    if (trigger === "ON_PLAYER_DRAW" && passive === "exile_card") {
      if (drawPile.length > 0) drawPile.pop();
    }
  }

  function cleanDead() {
    for (let i = 0; i < 4; i++) {
      // Player front/back
      for (const arr of [pF, pB]) {
        if (arr[i] && arr[i].currentHP <= 0) {
          creaturesLost++;
          runOnDeath(arr[i], i);
          dispatchReactive("ON_CREATURE_DEATH", i, arr[i]);
          if (arr[i].id) discardPile.push(arr[i].id);
          arr[i] = null;
        }
      }
      // Enemy front/back
      for (const arr of [eF, eB]) {
        if (arr[i] && arr[i].currentHP <= 0) {
          const dead = arr[i];
          onEnemyCreatureDeath(i, dead);
          dispatchReactive("ON_CREATURE_DEATH", i, dead);
          arr[i] = null;
        }
      }
    }
  }

  function runOnEnter(creature, lane, drawHand) {
    const kw = creature.keywords || [];
    const dmgBonus = hasRelic("war_drum") ? 1 : 0;
    for (const k of kw) {
      if (k === "on_enter_damage_1" || k === "on_enter_damage_2") {
        const baseDmg = k === "on_enter_damage_2" ? 2 : 1;
        const dmg = baseDmg + dmgBonus;
        const t = eF[lane] || eB[lane];
        if (t) { t.currentHP -= dmg; totalDmgDealt += dmg; }
      }
      if (k === "on_enter_draw_1") drawCards(1, drawHand);
      if (k === "on_enter_draw_2") drawCards(2, drawHand);
      if (k === "on_enter_2_all_enemies") {
        const dmg = 2 + dmgBonus;
        allEnemy().forEach(e => { e.currentHP -= dmg; totalDmgDealt += dmg; });
      }
    }
  }

  // ── SIMULTANEOUS COMBAT HELPERS ──
  // Collect one creature's intended attack into the batch (does NOT apply damage yet)
  function collectAttack(attacker, lane, side, batch) {
    if (attacker.atk <= 0) return;
    // Siege Golem: face-only, blocked if any creature in opposing lane
    if (attacker.faceOnly) {
      attacker._attacked = true;
      const t = atkTarget(lane, side);
      if (t === null) {
        batch.faceHits.push({ side, dmg: attacker.atk });
      }
      // If blocked, golem swings at nothing — no batch entry
      return;
    }
    const t = atkTarget(lane, side);
    attacker._attacked = true;
    if (t) {
      // Calculate damage (armored reduces)
      let finalDmg = attacker.atk;
      if (t.armored) finalDmg = Math.max(1, finalDmg - (t._fortressStone ? 2 : 1));
      batch.attacks.push({ attacker, target: t, dmg: finalDmg, side, lane, piercing: !!attacker.piercing });
    } else {
      // No target — face hit
      batch.faceHits.push({ side, dmg: attacker.atk });
    }
  }

  // Apply all collected attacks simultaneously
  function applySimultaneous(batch) {
    // 1. Sum total damage per target & track piercing damage per target
    const targetDmg = new Map();   // target → total damage
    const targetPDmg = new Map();  // target → total piercing-sourced damage
    const targetSide = new Map();  // target → side of the ATTACKER (for face-dmg tracking)
    const attackerThorns = [];     // [attacker, thornsDmg] pairs

    for (const a of batch.attacks) {
      targetDmg.set(a.target, (targetDmg.get(a.target) || 0) + a.dmg);
      if (a.piercing) targetPDmg.set(a.target, (targetPDmg.get(a.target) || 0) + a.dmg);
      // Track which side is attacking (for piercing overflow direction)
      if (!targetSide.has(a.target)) targetSide.set(a.target, a.side);
      // Track totalDmgDealt for player attacks
      if (a.side === "player") totalDmgDealt += a.dmg;
      // Thorns: attacker takes thorns damage if target has thorns
      if (a.target.thorns) {
        const td = a.target._briarAmulet ? 2 : 1;
        attackerThorns.push([a.attacker, td]);
      }
    }

    // 2. Apply all damage to targets at once
    for (const [target, dmg] of targetDmg) {
      target.currentHP -= dmg;
    }

    // 3. Last Stand: if target dropped to ≤0 and has unused last stand, save it
    for (const [target] of targetDmg) {
      if (target.currentHP <= 0 && target.last_stand && !target.lastStandUsed) {
        target.currentHP = 1;
        target.lastStandUsed = true;
      }
    }

    // 4. Piercing overflow → face damage
    for (const [target, dmg] of targetDmg) {
      if (target.currentHP > 0) continue; // survived — no overflow
      const piercingDmg = targetPDmg.get(target) || 0;
      if (piercingDmg <= 0) continue;
      const overflow = Math.min(piercingDmg, -target.currentHP);
      if (overflow <= 0) continue;
      const attackSide = targetSide.get(target);
      const piercingBonus = (attackSide === "player" && hasRelic("piercing_crown")) ? 1 : 0;
      const totalOverflow = overflow + piercingBonus;
      if (attackSide === "player") { enemyHP -= totalOverflow; totalDmgDealt += totalOverflow; }
      else { playerHP -= totalOverflow; }
    }

    // 5. Apply thorns damage to attackers (simultaneously with everything else)
    for (const [attacker, td] of attackerThorns) {
      attacker.currentHP -= td;
    }

    // 6. Face hits (creatures with no opposing target)
    for (const fh of batch.faceHits) {
      if (fh.side === "player") { enemyHP -= fh.dmg; totalDmgDealt += fh.dmg; }
      else { playerHP -= fh.dmg; }
    }
  }

  // Create a fresh attack batch
  function newBatch() { return { attacks: [], faceHits: [] }; }

  // Legacy resolveAttack for ranged (still sequential per-creature but uses applyDamage)
  function resolveAttack(attacker, lane, side) {
    if (attacker.faceOnly) {
      attacker._attacked = true;
      const t = atkTarget(lane, side);
      if (t === null) {
        if (side === "player") { enemyHP -= attacker.atk; totalDmgDealt += attacker.atk; }
        else playerHP -= attacker.atk;
      }
      return;
    }
    const t = atkTarget(lane, side);
    if (t) {
      const res = applyDamage(t, attacker.atk, true);
      if (side === "player") totalDmgDealt += res.dealt;
      if (res.thornsDmg > 0) attacker.currentHP -= res.thornsDmg;
      if (t.currentHP <= 0 && attacker.piercing) {
        const overflow = -t.currentHP + (side === "player" && hasRelic("piercing_crown") ? 1 : 0);
        if (overflow > 0) {
          if (side === "player") { enemyHP -= overflow; totalDmgDealt += overflow; }
          else playerHP -= overflow;
        }
      }
    } else {
      if (side === "player") { enemyHP -= attacker.atk; totalDmgDealt += attacker.atk; }
      else playerHP -= attacker.atk;
    }
    attacker._attacked = true;
  }

  // ── MAIN COMBAT LOOP ──
  while (round < MAX_ROUNDS && playerHP > 0 && enemyHP > 0) {
    round++;
    timeSnarePlayed = false;
    soulLanternUsedThisRound = false;

    // Regenerate / wither (start of round)
    allPlayer().forEach(c => {
      if (c.regenerate) c.currentHP = Math.min(c.hp, c.currentHP + 1);
      if (c.wither) c.atk = Math.max(0, c.atk - 1);
    });
    allEnemy().forEach(c => {
      if (c.regenerate) c.currentHP = Math.min(c.hp, c.currentHP + 1);
    });

    // Mana — no banking on round 1 (matches real game)
    let manaBank = round === 1 ? 0 : (hasRelic("ice_cream") ? bankedMana : Math.min(1, bankedMana));
    let mana = baseMana + manaBank + bonusManaNextTurn + (hasRelic("lantern") && round === 1 ? 1 : 0);
    bonusManaNextTurn = 0;
    if (hasRelic("happy_flower") && round > 0 && round % 3 === 0) mana++;
    allPlayer().forEach(c => {
      if (c.keywords?.includes("passive_mana_1")) mana++;
    });

    // Draw
    let hand = [];
    const drawCount = (hasRelic("couriers_bag") && round === 1) ? 5 : 4;
    drawCards(drawCount, hand);
    dispatchReactive("ON_PLAYER_DRAW", -1);

    // ── PLAYER TURN: Multi-pass smart AI ──
    let cardsPlayed = 0;
    const maxCards = hasRelic("velvet_choker") ? 5 : 99;
    let kept = [];
    let firstSpellThisTurn = true;
    const spellDmg = (card) => card.value + (hasRelic("worn_spellbook") ? 1 : 0);

    function spellCost(card) {
      if (card.type === "spell" && firstSpellThisTurn && hasRelic("ember_crown")) return 0;
      return card.cost;
    }
    function trySpell(cardId) {
      const card = CARDS[cardId];
      if (!card || card.type !== "spell" || cardsPlayed >= maxCards) return false;
      if (spellCost(card) > mana) return false;
      mana -= spellCost(card);
      cardsPlayed++;
      if (firstSpellThisTurn && hasRelic("ember_crown")) firstSpellThisTurn = false;
      resolveSpell(card, cardId);
      dispatchReactive("ON_PLAYER_SPELL", -1);
      if (!card.exhaust) discardPile.push(cardId);
      cleanDead();
      return true;
    }
    function tryCreature(cardId) {
      const card = CARDS[cardId];
      if (!card || card.type !== "creature" || cardsPlayed >= maxCards) return false;
      if (card.cost > mana) return false;
      let effAtk = card.atk + (bonusAtk || 0);
      if (hasRelic("veterans_medal") && card.cost === 1) effAtk++;
      if (hasRelic("glass_cannon")) effAtk++;
      if (hasRelic("vanguard_banner")) effAtk++;
      const slot = findBestSlot(pF, pB, eF, eB, effAtk);
      if (!slot) return false;
      mana -= card.cost;
      cardsPlayed++;
      const creature = makePlayerCreature(cardId, card, slot.lane, slot.row, relics, bonusAtk || 0);
      if (hasRelic("iron_buckler") && !firstCreaturePlayed) {
        creature.hp += 2; creature.currentHP += 2;
        firstCreaturePlayed = true;
      }
      if (hasRelic("fortress_stone") && creature.armored) creature._fortressStone = true;
      if (hasRelic("briar_amulet") && creature.thorns) creature._briarAmulet = true;
      if (hasRelic("swift_boots") && creature.swift) creature.atk++;
      if (hasRelic("vanguard_banner") && slot.row === "front") creature.atk++;
      if (slot.row === "front") pF[slot.lane] = creature;
      else pB[slot.lane] = creature;
      runOnEnter(creature, slot.lane, kept);
      dispatchReactive("ON_PLAYER_SUMMON", slot.lane);
      cleanDead();
      return true;
    }

    // Categorize hand into play phases
    const freeSpells = [], killSpells = [], creatures = [], buffSpells = [], otherSpells = [];
    for (const cardId of hand) {
      const card = CARDS[cardId];
      if (!card) { kept.push(cardId); continue; }
      if (card.type === "creature") {
        creatures.push(cardId);
      } else if (card.type === "spell") {
        if (card.cost === 0) {
          freeSpells.push(cardId);
        } else if (["damage","custom_lightning","custom_reckless","damage_all_enemies","custom_banish",
                     "custom_inferno","custom_holy_smite","damage_all","custom_apocalypse"].includes(card.effect)) {
          // Damage/removal spells — play before creatures to open lanes
          killSpells.push(cardId);
        } else if (["buff_all_atk","custom_overwhelming","custom_kings_command","custom_dark_pact",
                     "buff_hp","heal","custom_second_wind","custom_lay_on_hands","custom_barricade","custom_battle_hymn",
                     "custom_war_chant","custom_mending_light"].includes(card.effect)) {
          buffSpells.push(cardId);
        } else {
          otherSpells.push(cardId);
        }
      }
    }
    // Sort creatures: strongest ATK first, then HP
    creatures.sort((a, b) => {
      const ca = CARDS[a], cb = CARDS[b];
      if (ca.atk !== cb.atk) return cb.atk - ca.atk;
      return cb.hp - ca.hp;
    });
    // Sort kill spells: prefer spells that can actually kill an enemy (lethal shots first)
    killSpells.sort((a, b) => {
      const ca = CARDS[a], cb = CARDS[b];
      const aLethal = allEnemy().some(e => e.currentHP <= spellDmg(ca));
      const bLethal = allEnemy().some(e => e.currentHP <= spellDmg(cb));
      if (aLethal && !bLethal) return -1;
      if (bLethal && !aLethal) return 1;
      return ca.cost - cb.cost;
    });

    // PASS 1: Free spells (mana/draw generation — adrenaline, scrap, etc.)
    for (const id of freeSpells) { if (!trySpell(id)) kept.push(id); }
    // PASS 2: Kill spells (clear enemies to open face-damage lanes)
    for (const id of killSpells) { if (!trySpell(id)) kept.push(id); }
    // PASS 3: Creatures (fill lanes — open opposing lanes get face damage)
    for (const id of creatures) { if (!tryCreature(id)) kept.push(id); }
    // PASS 4: Buff spells (now that creatures are on board)
    for (const id of buffSpells) {
      if (allPlayer().length > 0) { if (!trySpell(id)) kept.push(id); }
      else kept.push(id);
    }
    // PASS 5: Remaining spells
    for (const id of otherSpells) { if (!trySpell(id)) kept.push(id); }

    function resolveSpell(card, cardId) {
      const spellDmgBonus = hasRelic("worn_spellbook") ? 1 : 0;
      const enemies = allEnemy();
      const friendlies = allPlayer();

      if (card.effect === "damage" && enemies.length > 0) {
        const dmg = card.value + spellDmgBonus;
        // Smart targeting: prefer lethal kills on highest-ATK enemies, else hit highest-ATK
        const killable = enemies.filter(e => e.currentHP <= dmg && e.currentHP > 0);
        let target;
        if (killable.length > 0) {
          target = killable.reduce((a, b) => a.atk > b.atk ? a : b);
        } else {
          target = enemies.reduce((a, b) => a.atk > b.atk ? a : (a.atk === b.atk && a.currentHP < b.currentHP ? a : b));
        }
        target.currentHP -= dmg;
        totalDmgDealt += dmg;
      } else if (card.effect === "damage_face") {
        const dmg = card.value + spellDmgBonus;
        enemyHP -= dmg; totalDmgDealt += dmg;
      } else if (card.effect === "damage_all_enemies") {
        const dmg = card.value + spellDmgBonus;
        enemies.forEach(e => { e.currentHP -= dmg; totalDmgDealt += dmg; });
      } else if (card.effect === "damage_all") {
        const dmg = card.value;
        enemies.forEach(e => { e.currentHP -= dmg; totalDmgDealt += dmg; });
        friendlies.forEach(p => { p.currentHP -= dmg; });
      } else if (card.effect === "draw") {
        drawCards(card.value, kept);
      } else if (card.effect === "buff_all_atk") {
        friendlies.forEach(p => { p.atk += card.value; });
      } else if (card.effect === "buff_hp" && friendlies.length > 0) {
        const target = friendlies.reduce((a, b) => a.currentHP < b.currentHP ? a : b);
        target.currentHP += card.value; target.hp += card.value;
      } else if (card.effect === "heal" && friendlies.length > 0) {
        const t = friendlies.reduce((a, b) => (a.hp - a.currentHP) > (b.hp - b.currentHP) ? a : b);
        t.currentHP = Math.min(t.hp, t.currentHP + card.value);
      } else if (card.effect === "custom_adrenaline") {
        mana++; drawCards(1, kept);
      } else if (card.effect === "custom_bloodletting") {
        playerHP -= 2; mana += 2;
      } else if (card.effect === "custom_turbo") {
        mana += 2; discardPile.push("curse");
      } else if (card.effect === "custom_concentrate") {
        let discarded = 0;
        while (discarded < 2 && kept.length > 0) {
          discardPile.push(kept.pop()); discarded++;
        }
        mana += 2;
      } else if (card.effect === "custom_scrap") {
        if (kept.length > 0) { discardPile.push(kept.pop()); mana++; }
      } else if (card.effect === "custom_blood_tithe") {
        enemyHP -= 3; playerHP -= 2; totalDmgDealt += 3;
      } else if (card.effect === "custom_reckless" && enemies.length > 0) {
        const dmg = 3 + spellDmgBonus;
        const killable = enemies.filter(e => e.currentHP <= dmg && e.currentHP > 0);
        const t = killable.length > 0
          ? killable.reduce((a, b) => a.atk > b.atk ? a : b)
          : enemies.reduce((a, b) => a.atk > b.atk ? a : b);
        t.currentHP -= dmg; totalDmgDealt += dmg;
        playerHP -= 1; drawCards(1, kept);
      } else if (card.effect === "custom_unholy_bargain") {
        playerHP -= 3; drawCards(3, kept);
      } else if (card.effect === "custom_inferno") {
        const dmg = 4 + spellDmgBonus;
        enemies.forEach(e => { e.currentHP -= dmg; totalDmgDealt += dmg; });
        enemyHP -= dmg; totalDmgDealt += dmg;
      } else if (card.effect === "custom_overwhelming") {
        friendlies.forEach(p => { p.atk += 3; });
      } else if (card.effect === "custom_kings_command") {
        friendlies.forEach(p => { p.atk += 3; p.hp++; p.currentHP++; });
      } else if (card.effect === "custom_apocalypse") {
        enemyHP -= enemies.length; totalDmgDealt += enemies.length;
        for (let i = 0; i < 4; i++) { eF[i] = null; eB[i] = null; }
        creaturesLost += friendlies.length;
        for (let i = 0; i < 4; i++) { pF[i] = null; pB[i] = null; }
      } else if (card.effect === "custom_banish" && enemies.length > 0) {
        const biggest = enemies.reduce((a, b) => (a.atk * 10 + a.currentHP) > (b.atk * 10 + b.currentHP) ? a : b);
        // Remove from correct array
        for (let i = 0; i < 4; i++) {
          if (eF[i] === biggest) { eF[i] = null; break; }
          if (eB[i] === biggest) { eB[i] = null; break; }
        }
      } else if (card.effect === "custom_time_snare") {
        timeSnarePlayed = true;
      } else if (card.effect === "custom_lightning" && enemies.length > 0) {
        const t = enemies[0];
        const dmg = 2 + spellDmgBonus;
        t.currentHP -= dmg; enemyHP -= 1; totalDmgDealt += dmg + 1;
      } else if (card.effect === "custom_mending_light") {
        playerHP = Math.min(25, playerHP + 3);
        friendlies.forEach(p => { p.currentHP = Math.min(p.hp, p.currentHP + 1); });
      } else if (card.effect === "custom_dark_pact") {
        friendlies.forEach(p => { p.atk += 1; });
        enemies.forEach(e => { e.atk += 1; });
        playerHP -= 2;
      } else if (card.effect === "custom_second_wind" && friendlies.length > 0) {
        const t = friendlies.reduce((a, b) => (a.hp - a.currentHP) > (b.hp - b.currentHP) ? a : b);
        t.currentHP = t.hp; t.atk += 1;
      } else if (card.effect === "custom_lay_on_hands" && friendlies.length > 0) {
        const t = friendlies.reduce((a, b) => (a.hp - a.currentHP) > (b.hp - b.currentHP) ? a : b);
        t.currentHP = t.hp; t.hp += 2; t.currentHP += 2;
      } else if (card.effect === "custom_mass_grave") {
        const dmg = discardPile.length;
        enemyHP -= dmg; totalDmgDealt += dmg;
      } else if (card.effect === "custom_cataclysm" && friendlies.length > 0) {
        const highest = friendlies.reduce((a, b) => a.atk > b.atk ? a : b);
        enemies.forEach(e => { e.currentHP -= highest.atk; totalDmgDealt += highest.atk; });
        enemyHP -= highest.atk; totalDmgDealt += highest.atk;
      } else if (card.effect === "custom_holy_smite" && enemies.length > 0) {
        const t = enemies.reduce((a, b) => (a.hp - a.currentHP) > (b.hp - b.currentHP) ? a : b);
        const dmg = t.hp - t.currentHP;
        if (dmg > 0) { t.currentHP -= dmg; totalDmgDealt += dmg; }
      } else if (card.effect === "custom_battle_hymn") {
        friendlies.forEach(p => { p.atk += 1; p.hp += 1; p.currentHP += 1; });
      } else if (card.effect === "custom_barricade" && friendlies.length > 0) {
        const t = friendlies.reduce((a, b) => a.currentHP < b.currentHP ? a : b);
        t.currentHP += card.value; t.hp += card.value;
        t.armored = true;
      } else if (card.effect === "custom_shove" && enemies.length > 0) {
        const t = enemies.reduce((a, b) => a.atk > b.atk ? a : b);
        const dmg = 2 + (hasRelic("worn_spellbook") ? 1 : 0);
        t.currentHP -= dmg; totalDmgDealt += dmg;
        t.atk = Math.max(0, t.atk - 1);
      }
    }

    // ── FLOOP PHASE ──
    // Player floops: AI decides (both rows)
    for (const arr of [pF, pB]) {
      for (let i = 0; i < 4; i++) {
        const c = arr[i];
        if (!c || !c.floop || c.cannotAttack) continue;
        const ft = c.floop.type;
        const fv = c.floop.value || 0;
        const enemies = allEnemy();
        const opposing = eF[i] || eB[i];
        let shouldFloop = false;

        if (ft === "damage_any") {
          // Floop if: no opposing target (would hit face instead), or fv can kill any enemy, or fv >= our atk (worth trading attack)
          if (enemies.length > 0 && (!opposing || fv >= c.atk || enemies.some(e => e.currentHP <= fv))) shouldFloop = true;
        }
        if (ft === "damage_all_enemies" && enemies.length >= 1) shouldFloop = true;
        if (ft === "damage_opposing") {
          // Floop if opposing exists and fv can kill it or fv is decent damage
          if (opposing && (opposing.currentHP <= fv || fv >= 2)) shouldFloop = true;
        }
        if (ft === "damage_opposing_heal" && opposing) shouldFloop = true;
        if (ft === "damage_opposing_splash" && enemies.length >= 1) shouldFloop = true;
        if (ft === "drain" && opposing) shouldFloop = true;
        if (ft === "buff_all_atk_permanent") shouldFloop = allPlayer().length >= 1;
        if (ft === "buff_adjacent_atk") shouldFloop = allPlayer().length >= 1;
        if (ft === "heal_all_friendly") shouldFloop = allPlayer().some(p => p.currentHP < p.hp);
        if (ft === "heal_self" && c.currentHP < c.hp) shouldFloop = true;
        if (ft === "gain_mana") shouldFloop = true;
        if (ft === "stun_opposing" && opposing && opposing.atk >= 2) shouldFloop = true;
        if (ft === "damage_face") shouldFloop = true;
        if (ft === "grow_atk") shouldFloop = true;
        if (ft === "grow_per_enemies" && enemies.length >= 1) shouldFloop = true;

        if (shouldFloop) {
          c._flooped = true;
          c._attacked = true;
          floopCount++;

          // Reactive: floop_punish — 1 damage to flooper
          if (passive === "floop_punish") c.currentHP -= 1;
          dispatchReactive("ON_PLAYER_FLOOP", i);

          if (ft === "damage_any" && enemies.length > 0) {
            const killable = enemies.filter(e => e.currentHP <= fv && e.currentHP > 0);
            const t = killable.length > 0
              ? killable.reduce((a, b) => a.atk > b.atk ? a : b)
              : enemies.reduce((a, b) => a.atk > b.atk ? a : b);
            t.currentHP -= fv; totalDmgDealt += fv;
          } else if (ft === "damage_all_enemies") {
            allEnemy().forEach(e => { e.currentHP -= fv; totalDmgDealt += fv; });
          } else if (ft === "damage_opposing" && opposing) {
            opposing.currentHP -= fv; totalDmgDealt += fv;
          } else if (ft === "damage_opposing_heal" && opposing) {
            opposing.currentHP -= fv; totalDmgDealt += fv;
            c.currentHP = Math.min(c.hp, c.currentHP + 1);
          } else if (ft === "damage_opposing_splash") {
            if (opposing) { opposing.currentHP -= fv; totalDmgDealt += fv; }
            // Splash adjacent columns (target front or back)
            for (const di of [-1, 1]) {
              const ni = i + di;
              if (ni >= 0 && ni < 4) {
                const adj = eF[ni] || eB[ni];
                if (adj) { adj.currentHP -= fv; totalDmgDealt += fv; }
              }
            }
          } else if (ft === "drain" && opposing) {
            opposing.currentHP -= fv; totalDmgDealt += fv;
            c.currentHP = Math.min(c.hp, c.currentHP + fv);
          } else if (ft === "buff_all_atk_permanent") {
            allPlayer().forEach(p => { p.atk += fv; });
          } else if (ft === "buff_adjacent_atk") {
            // Adjacent in same row
            const myArr = c.row === "front" ? pF : pB;
            if (i > 0 && myArr[i - 1]) myArr[i - 1].atk += fv;
            if (i < 3 && myArr[i + 1]) myArr[i + 1].atk += fv;
          } else if (ft === "heal_all_friendly") {
            allPlayer().forEach(p => { p.currentHP = Math.min(p.hp, p.currentHP + fv); });
          } else if (ft === "heal_self") {
            c.currentHP = Math.min(c.hp, c.currentHP + fv);
          } else if (ft === "gain_mana") {
            mana += fv;
          } else if (ft === "stun_opposing" && opposing) {
            opposing._stunned = true;
          } else if (ft === "damage_face") {
            enemyHP -= fv; totalDmgDealt += fv;
          } else if (ft === "grow_atk") {
            c.atk += fv;
          } else if (ft === "grow_per_enemies") {
            c.atk += enemies.length * fv;
          }

          // Echo Staff: double floop
          if (hasRelic("echo_staff")) {
            if (ft === "damage_all_enemies") {
              allEnemy().forEach(e => { e.currentHP -= fv; totalDmgDealt += fv; });
            } else if (ft === "buff_all_atk_permanent") {
              allPlayer().forEach(p => { p.atk += fv; });
            } else if (ft === "gain_mana") { mana += fv; }
            else if (ft === "damage_face") { enemyHP -= fv; totalDmgDealt += fv; }
            else if (ft === "heal_all_friendly") {
              allPlayer().forEach(p => { p.currentHP = Math.min(p.hp, p.currentHP + fv); });
            }
          }
        }
      }
    }

    // Post-floop: play remaining cards with same multi-pass logic (floop may have gained mana)
    if (cardsPlayed < maxCards && kept.length > 0) {
      const postKept = [];
      const postCreatures = [], postKill = [], postBuff = [], postOther = [];
      for (const cardId of kept) {
        const card = CARDS[cardId];
        if (!card) { postKept.push(cardId); continue; }
        if (card.type === "creature") postCreatures.push(cardId);
        else if (["damage","custom_lightning","custom_reckless","damage_all_enemies","custom_banish",
                   "custom_inferno","custom_holy_smite","damage_all","custom_apocalypse"].includes(card.effect)) postKill.push(cardId);
        else if (["buff_all_atk","custom_overwhelming","custom_kings_command","custom_dark_pact",
                   "buff_hp","heal","custom_second_wind","custom_lay_on_hands","custom_barricade","custom_battle_hymn",
                   "custom_war_chant","custom_mending_light"].includes(card.effect)) postBuff.push(cardId);
        else postOther.push(cardId);
      }
      postCreatures.sort((a, b) => (CARDS[b].atk - CARDS[a].atk) || (CARDS[b].hp - CARDS[a].hp));
      for (const id of postKill) { if (!trySpell(id)) postKept.push(id); }
      for (const id of postCreatures) { if (!tryCreature(id)) postKept.push(id); }
      for (const id of postBuff) {
        if (allPlayer().length > 0) { if (!trySpell(id)) postKept.push(id); }
        else postKept.push(id);
      }
      for (const id of postOther) { if (!trySpell(id)) postKept.push(id); }
      kept = postKept;
    }

    cleanDead();

    // ── SIMULTANEOUS SWIFT PHASE ──
    // All swift creatures (player + enemy, front + back) attack at once
    {
      const swiftBatch = newBatch();
      // Player swift (front + back)
      for (let lane = 0; lane < 4; lane++) {
        const c = pF[lane];
        if (c && c.swift && !c._flooped && !c._attacked && !c.cannotAttack && c.atk > 0)
          collectAttack(c, lane, "player", swiftBatch);
      }
      for (let lane = 0; lane < 4; lane++) {
        const c = pB[lane];
        if (c && c.swift && !c._flooped && !c._attacked && !c.cannotAttack && c.atk > 0)
          collectAttack(c, lane, "player", swiftBatch);
      }
      // Enemy swift (front + back)
      for (let lane = 0; lane < 4; lane++) {
        const c = eF[lane];
        if (c && c.swift && !c._stunned && !c._attacked && c.atk > 0)
          collectAttack(c, lane, "enemy", swiftBatch);
      }
      for (let lane = 0; lane < 4; lane++) {
        const c = eB[lane];
        if (c && c.swift && !c._stunned && !c._attacked && c.atk > 0)
          collectAttack(c, lane, "enemy", swiftBatch);
      }
      applySimultaneous(swiftBatch);
      cleanDead();
    }

    // ── SIMULTANEOUS MAIN COMBAT PHASE ──
    // ALL remaining creatures (player + enemy, melee + ranged) attack at once
    {
      const combatBatch = newBatch();

      // Player melee (front + back) — non-swift, non-ranged
      for (let lane = 0; lane < 4; lane++) {
        const c = pF[lane];
        if (c && !c._flooped && !c._attacked && !c.cannotAttack && !c.ranged && c.atk > 0)
          collectAttack(c, lane, "player", combatBatch);
      }
      for (let lane = 0; lane < 4; lane++) {
        const c = pB[lane];
        if (c && !c._flooped && !c._attacked && !c.cannotAttack && !c.ranged && c.atk > 0)
          collectAttack(c, lane, "player", combatBatch);
      }

      // Enemy melee (front + back) — skipped if Time Snare played
      if (!timeSnarePlayed) {
        for (let lane = 0; lane < 4; lane++) {
          const e = eF[lane];
          if (e && !e._attacked && !e._stunned && e.atk > 0 && !e.isStructure)
            collectAttack(e, lane, "enemy", combatBatch);
        }
        for (let lane = 0; lane < 4; lane++) {
          const e = eB[lane];
          if (e && !e._attacked && !e._stunned && e.atk > 0 && !e.isStructure)
            collectAttack(e, lane, "enemy", combatBatch);
        }
      }

      // Ranged creatures (player only, prefer back-row targets)
      for (const arr of [pF, pB]) {
        for (let lane = 0; lane < 4; lane++) {
          const c = arr[lane];
          if (!c || !c.ranged || c._attacked || c._flooped || c.cannotAttack || c.atk <= 0) continue;
          c._attacked = true;
          // Pick random target: prefer back row
          const backs = [eB[0], eB[1], eB[2], eB[3]].filter(e => e && e.currentHP > 0);
          const fronts = [eF[0], eF[1], eF[2], eF[3]].filter(e => e && e.currentHP > 0);
          const pool = backs.length > 0 ? backs : fronts;
          if (pool.length > 0) {
            const t = pool[Math.floor(Math.random() * pool.length)];
            let finalDmg = c.atk;
            if (t.armored) finalDmg = Math.max(1, finalDmg - (t._fortressStone ? 2 : 1));
            combatBatch.attacks.push({ attacker: c, target: t, dmg: finalDmg, side: "player", lane, piercing: !!c.piercing });
          } else {
            combatBatch.faceHits.push({ side: "player", dmg: c.atk });
          }
        }
      }

      applySimultaneous(combatBatch);
      cleanDead();
    }

    // Berserker growth
    for (const arr of [pF, pB, eF, eB]) {
      for (let i = 0; i < 4; i++) {
        if (arr[i]?.keywords?.includes("berserker_growth") && arr[i]._attacked) arr[i].atk++;
      }
    }

    // Bloodstone
    if (hasRelic("bloodstone")) {
      const tookFace = [0,1,2,3].some(i => (eF[i] || eB[i]) && !pF[i] && !pB[i]);
      if (tookFace) allPlayer().forEach(p => { p.atk++; });
    }

    // Phoenix Heart
    if (playerHP <= 0 && hasRelic("phoenix_heart") && !phoenixUsed) {
      playerHP = 1; phoenixUsed = true;
    }

    // ── POST-COMBAT CLEANUP ──
    // Reset per-round state
    for (const arr of [pF, pB, eF, eB]) {
      for (let i = 0; i < 4; i++) {
        if (arr[i]) { arr[i]._flooped = false; arr[i]._attacked = false; arr[i]._stunned = false; }
      }
    }

    // Dies-end-of-turn creatures (Assassin)
    for (const arr of [pF, pB]) {
      for (let i = 0; i < 4; i++) {
        if (arr[i]?.diesEndTurn) { creaturesLost++; runOnDeath(arr[i], i); arr[i] = null; }
      }
    }

    // Discard remaining hand
    kept.forEach(id => { if (id !== "curse") discardPile.push(id); });

    // Mana banking
    bankedMana = Math.max(0, mana);

    // ── ENEMY REINFORCEMENT ── (matches real game: front-first, escalation at round 8)
    const maxPlace = (encounterType === "boss") ? 2 :
                     (encounterType === "elite") ? (round <= 2 ? 1 : 2) :
                     (round <= 2 ? 1 : (Math.random() < 0.33 ? 2 : 1));
    for (let p = 0; p < maxPlace; p++) {
      let data;
      if (enemyDeckIdx < enemyDeck.length) {
        data = enemyDeck[enemyDeckIdx++];
      } else {
        data = { ...encounter.reinf };
        if (round > 12) { data.a = (data.a || 1) + (round - 12); data.h += (round - 12); }
      }
      placeEnemy(data);
    }
    // Escalation double-place for regular combats after round 8
    if (encounterType === "combat" && round >= 8) {
      const escData = enemyDeckIdx < enemyDeck.length ? enemyDeck[enemyDeckIdx++] : { ...encounter.reinf };
      placeEnemy(escData);
    }

    // ── ENCOUNTER PASSIVES (end of round) ──
    if (passive === "2_face_dmg") playerHP -= 2;
    if (passive === "heal_all_1") allEnemy().forEach(e => { e.currentHP = Math.min(e.hp, e.currentHP + 1); });
    if (passive === "1_dmg_all") {
      allPlayer().forEach(c => { c.currentHP -= 1; });
      allEnemy().forEach(c => { c.currentHP -= 1; });
    }
    if (passive === "random_enemy_atk_1") {
      const ec = allEnemy();
      if (ec.length > 0) ec[Math.floor(Math.random() * ec.length)].atk++;
    }
    if (passive === "random_enemy_buff_1") {
      const ec = allEnemy();
      if (ec.length > 0) { const t = ec[Math.floor(Math.random() * ec.length)]; t.atk++; t.currentHP++; t.hp++; }
    }
    if (passive === "all_thorns") allEnemy().forEach(e => { e.thorns = true; });
    if (passive === "3_to_highest") {
      const pc = allPlayer();
      if (pc.length > 0) { const t = pc.reduce((a, b) => a.atk > b.atk ? a : b); t.currentHP -= 3; }
    }
    if (passive === "devil_cycle") {
      const ph = ((round - 1) % 3);
      if (ph === 0) playerHP -= 2;
      if (ph === 1) allEnemy().forEach(e => { e.currentHP = Math.min(e.hp, e.currentHP + 1); });
      if (ph === 2) {
        const pc = allPlayer();
        if (pc.length > 0) { const t = pc.reduce((a, b) => a.atk > b.atk ? a : b); t.currentHP -= 3; }
      }
    }
    if (passive === "highest_face") {
      const ec = allEnemy();
      if (ec.length > 0) { const t = ec.reduce((a, b) => a.atk > b.atk ? a : b); playerHP -= t.atk; }
    }
    if (passive === "cycle_buff") {
      const ph = ((round - 1) % 3);
      if (ph === 0) allEnemy().forEach(e => { e.atk++; });
      if (ph === 1) allEnemy().forEach(e => { e.currentHP = Math.min(e.hp, e.currentHP + 2); });
      if (ph === 2) allEnemy().forEach(e => { e.thorns = true; });
    }
    if (passive === "aoe_every_3" && round % 3 === 0) {
      allPlayer().forEach(c => { c.currentHP -= 3; });
    }
    if (passive === "steal_mana" && mana > 0) {
      bankedMana = Math.max(0, bankedMana - 1);
    }
    if (passive === "all_piercing") allEnemy().forEach(e => { e.piercing = true; });
    if (passive === "4atk_piercing") allEnemy().forEach(e => { if (e.atk >= 4) e.piercing = true; });
    if (passive === "cant_die_to_attacks") {
      // Phylactery: find the 0-ATK high-HP creature and ensure it survives attacks
      for (const arr of [eF, eB]) {
        for (let i = 0; i < 4; i++) {
          if (arr[i] && arr[i].atk === 0 && arr[i].currentHP <= 0) {
            arr[i].currentHP = 1;
          }
        }
      }
    }

    cleanDead();

    fightLog.push({
      round, playerHP, enemyHP,
      playerBoard: allPlayer().length,
      enemyBoard: allEnemy().length,
      cardsPlayed,
    });
  }

  const won = enemyHP <= 0 && playerHP > 0;
  return { won, playerHP: Math.max(0, playerHP), enemyHP, rounds: round, creaturesLost, totalDmgDealt, fightLog, floopCount };
}

// ── RUN SIMULATION ────────────────────────────────────────────
function simulateRun() {
  const runLog = [];
  let deck = makeStarterDeck();
  let gold = 0;
  let hp = 25;
  let maxHP = 25;
  let baseMana = 3;
  const relics = [...pick(STARTING_RELICS, 1)];
  let act = 1;
  let alive = true;
  let cardsAdded = [];
  let cardsRemoved = [];
  let nodesVisited = [];
  let hpTrajectory = [{ node: "Start", hp, act: 0 }];
  let roundsPerFight = [];
  let totalFloops = 0;

  const addToLog = (entry) => runLog.push(entry);
  const trackCombat = (result, nodeName) => {
    roundsPerFight.push(result.rounds);
    totalFloops += result.floopCount || 0;
    hpTrajectory.push({ node: nodeName, hp: result.won ? result.playerHP : 0, act });
  };
  addToLog({ type: "start", relic: relics[0].name, deck: [...deck] });

  for (act = 1; act <= 3 && alive; act++) {
    const combatPool = shuffle(ENCOUNTERS[`act${act}_combat`]);
    const elitePool = shuffle(ENCOUNTERS[`act${act}_elite`]);
    const bossPool = ENCOUNTERS[`act${act}_boss`];

    // Combat 1
    let result = simCombat(deck, relics, combatPool[0], baseMana, addToLog, "combat", hp, act - 1);
    nodesVisited.push({ type: "combat", name: combatPool[0].name, act });
    addToLog({ type: "combat", act, encounter: combatPool[0].name, ...result });
    trackCombat(result, combatPool[0].name);
    if (!result.won) { hp = 0; alive = false; break; }
    hp = Math.min(maxHP, result.playerHP);
    gold += 15 + (relics.some(r => r.id === "coin_purse") ? 10 : 0);

    // Card reward
    const rw = rarityWeight(act, false);
    const r1 = rollRarity(rw);
    const pool1 = getCardPool(r1);
    if (pool1.length > 0) {
      const choice = pickBestCard(pool1, deck, 3);
      deck.push(choice);
      cardsAdded.push(CARDS[choice].name);
      addToLog({ type: "card_reward", card: CARDS[choice].name, rarity: r1 });
    }

    // Combat 2
    const c2 = combatPool[1] || combatPool[0];
    result = simCombat(deck, relics, c2, baseMana, addToLog, "combat", hp, act - 1);
    nodesVisited.push({ type: "combat", name: c2.name, act });
    addToLog({ type: "combat", act, encounter: c2.name, ...result });
    trackCombat(result, c2.name);
    if (!result.won) { hp = 0; alive = false; break; }
    hp = Math.min(maxHP, result.playerHP);
    gold += 15;

    const r2 = rollRarity(rw);
    const pool2 = getCardPool(r2);
    if (pool2.length > 0) {
      const choice = pickBestCard(pool2, deck, 3);
      deck.push(choice);
      cardsAdded.push(CARDS[choice].name);
    }

    // Rest / Shop
    if (hp < maxHP * 0.7 && !relics.some(r => r.id === "coffee_dripper")) {
      hp = maxHP;
      addToLog({ type: "rest", hp: maxHP });
      if (deck.length > 7) {
        const goblins = deck.filter(id => id === "goblin");
        const brutes = deck.filter(id => id === "brute");
        const toRemove = goblins.length > 0 ? "goblin" : (brutes.length > 0 ? "brute" : null);
        if (toRemove) {
          const removeIdx = deck.indexOf(toRemove);
          const removed = deck.splice(removeIdx, 1)[0];
          cardsRemoved.push(CARDS[removed].name);
        }
      }
    } else {
      if (gold >= 75) {
        const shopR = rollRarity(rw);
        const shopPool = getCardPool(shopR);
        if (shopPool.length > 0) {
          const shopCard = pickBestCard(shopPool, deck, 3);
          if (shopCard) {
            deck.push(shopCard);
            const price = shopR === "rare" ? 120 : shopR === "uncommon" ? 75 : 50;
            gold -= Math.min(gold, price);
            cardsAdded.push(CARDS[shopCard].name);
          }
        }
      }
      if (gold >= 50 && deck.length > 8) {
        const goblins = deck.filter(id => id === "goblin");
        if (goblins.length > 0) {
          const idx = deck.indexOf("goblin");
          const removed = deck.splice(idx, 1)[0];
          gold -= 50;
          cardsRemoved.push(CARDS[removed].name);
        }
      }
    }

    // Combat 3
    if (combatPool.length > 2) {
      result = simCombat(deck, relics, combatPool[2], baseMana, addToLog, "combat", hp, act - 1);
      nodesVisited.push({ type: "combat", name: combatPool[2].name, act });
      addToLog({ type: "combat", act, encounter: combatPool[2].name, ...result });
      trackCombat(result, combatPool[2].name);
      if (!result.won) { hp = 0; alive = false; break; }
      hp = Math.min(maxHP, result.playerHP);
      gold += 15;
    }

    // Elite
    const elite = elitePool[0];
    result = simCombat(deck, relics, elite, baseMana, addToLog, "elite", hp, act - 1);
    nodesVisited.push({ type: "elite", name: elite.name, act });
    addToLog({ type: "elite", act, encounter: elite.name, ...result });
    trackCombat(result, elite.name);
    if (!result.won) { hp = 0; alive = false; break; }
    hp = Math.min(maxHP, result.playerHP);
    gold += 25;

    const eliteRelic = pick(COMBAT_RELICS.filter(r => !relics.some(pr => pr.id === r.id)), 1);
    if (eliteRelic.length > 0) {
      relics.push(eliteRelic[0]);
      addToLog({ type: "relic_reward", relic: eliteRelic[0].name });
    }
    const er = rollRarity(rarityWeight(act, true));
    const ePool = getCardPool(er);
    if (ePool.length > 0) {
      const eCard = pickBestCard(ePool, deck, 3);
      deck.push(eCard);
      cardsAdded.push(CARDS[eCard].name);
    }

    // Pre-boss rest
    if (!relics.some(r => r.id === "coffee_dripper")) {
      hp = maxHP;
      addToLog({ type: "rest", hp: maxHP, note: "Pre-boss rest" });
    }

    // Boss
    const boss = pick(bossPool, 1)[0];
    result = simCombat(deck, relics, boss, baseMana, addToLog, "boss", hp, act);
    nodesVisited.push({ type: "boss", name: boss.name, act });
    addToLog({ type: "boss", act, encounter: boss.name, ...result });
    trackCombat(result, boss.name);
    if (!result.won) { hp = 0; alive = false; break; }
    hp = Math.min(maxHP, result.playerHP);
    gold += 30;

    const bossRelic = pick(BOSS_RELICS.filter(r => !relics.some(pr => pr.id === r.id)), 1);
    if (bossRelic.length > 0) {
      relics.push(bossRelic[0]);
      baseMana++;
      addToLog({ type: "boss_relic", relic: bossRelic[0].name, mana: baseMana });
    }
  }

  const won = alive && act > 3;
  return {
    won, finalHP: hp, finalDeck: deck, deckSize: deck.length,
    relics: relics.map(r => r.name), cardsAdded, cardsRemoved,
    runLog, nodesVisited, acts: Math.min(act, 3),
    diedTo: !alive ? nodesVisited[nodesVisited.length - 1]?.name : null,
    hpTrajectory, roundsPerFight, totalFloops,
  };
}

// ── BATCH SIMULATION ──────────────────────────────────────────
function runBatch(n) {
  const results = [];
  const cardPickCounts = {};
  const relicCounts = {};
  const deathMap = {};
  let wins = 0;
  let totalRounds = 0;
  let totalFights = 0;

  for (let i = 0; i < n; i++) {
    const run = simulateRun();
    results.push(run);
    if (run.won) wins++;
    run.cardsAdded.forEach(c => { cardPickCounts[c] = (cardPickCounts[c] || 0) + 1; });
    run.relics.forEach(r => { relicCounts[r] = (relicCounts[r] || 0) + 1; });
    if (run.diedTo) deathMap[run.diedTo] = (deathMap[run.diedTo] || 0) + 1;
    run.runLog.filter(e => e.type === "combat" || e.type === "elite" || e.type === "boss").forEach(e => {
      totalRounds += e.rounds || 0;
      totalFights++;
    });
  }

  const topCards = Object.entries(cardPickCounts).sort((a, b) => b[1] - a[1]).slice(0, 15);
  const topRelics = Object.entries(relicCounts).sort((a, b) => b[1] - a[1]).slice(0, 10);
  const topDeaths = Object.entries(deathMap).sort((a, b) => b[1] - a[1]).slice(0, 8);

  // Deck analytics: winning vs losing
  const winRuns = results.filter(r => r.won);
  const lossRuns = results.filter(r => !r.won);
  const deckStats = (runs) => {
    if (runs.length === 0) return { avgSize: 0, avgCreatures: 0, avgSpells: 0, avgCost: 0, keywordFreq: {}, topCards: [] };
    let totalSize = 0, totalCreatures = 0, totalSpells = 0, totalCost = 0, totalCards = 0;
    const kwCounts = {};
    const cardCounts = {};
    runs.forEach(r => {
      const d = r.finalDeck;
      totalSize += d.length;
      d.forEach(id => {
        const c = CARDS[id];
        if (!c) return;
        totalCards++;
        if (c.type === "creature") totalCreatures++;
        if (c.type === "spell") totalSpells++;
        totalCost += c.cost || 0;
        (c.keywords || []).forEach(k => { kwCounts[k] = (kwCounts[k] || 0) + 1; });
        const name = c.name;
        cardCounts[name] = (cardCounts[name] || 0) + 1;
      });
    });
    const n = runs.length;
    const topKw = Object.entries(kwCounts).sort((a, b) => b[1] - a[1]).slice(0, 6).map(([k, v]) => ({ kw: k, avg: (v / n).toFixed(1) }));
    const topC = Object.entries(cardCounts).sort((a, b) => b[1] - a[1]).slice(0, 8).map(([name, v]) => ({ name, avg: (v / n).toFixed(1) }));
    return {
      avgSize: (totalSize / n).toFixed(1),
      avgCreatures: (totalCreatures / n).toFixed(1),
      avgSpells: (totalSpells / n).toFixed(1),
      avgCost: (totalCost / Math.max(1, totalCards)).toFixed(2),
      topKeywords: topKw,
      topCards: topC,
    };
  };
  const deckAnalytics = { wins: deckStats(winRuns), losses: deckStats(lossRuns) };

  // Per-card win rates: for each card, how often did runs containing it win?
  const cardWinData = {};
  results.forEach(r => {
    const seen = new Set(r.cardsAdded);
    seen.forEach(name => {
      if (!cardWinData[name]) cardWinData[name] = { picked: 0, wins: 0 };
      cardWinData[name].picked++;
      if (r.won) cardWinData[name].wins++;
    });
  });
  const cardWinRates = Object.entries(cardWinData)
    .filter(([, d]) => d.picked >= Math.max(10, n * 0.01))
    .map(([name, d]) => ({ name, picked: d.picked, wins: d.wins, wr: (d.wins / d.picked * 100).toFixed(1) }))
    .sort((a, b) => b.wr - a.wr);

  // ── CARD SYNERGY PAIRS ──
  const pairWinData = {};
  results.forEach(r => {
    const unique = [...new Set(r.cardsAdded)].sort();
    for (let i = 0; i < unique.length; i++) {
      for (let j = i + 1; j < unique.length; j++) {
        const key = unique[i] + " + " + unique[j];
        if (!pairWinData[key]) pairWinData[key] = { count: 0, wins: 0 };
        pairWinData[key].count++;
        if (r.won) pairWinData[key].wins++;
      }
    }
  });
  const synergyPairs = Object.entries(pairWinData)
    .filter(([, d]) => d.count >= Math.max(15, n * 0.015))
    .map(([pair, d]) => ({ pair, count: d.count, wr: (d.wins / d.count * 100).toFixed(1) }))
    .sort((a, b) => b.wr - a.wr);

  // ── ROUND HISTOGRAM ──
  const roundHist = {};
  results.forEach(r => {
    r.roundsPerFight.forEach(rd => {
      roundHist[rd] = (roundHist[rd] || 0) + 1;
    });
  });
  const roundHistArr = Object.entries(roundHist).map(([r, c]) => ({ round: Number(r), count: c })).sort((a, b) => a.round - b.round);

  // ── HP TRAJECTORY ──
  const maxNodes = 15;
  const hpTrajWin = new Array(maxNodes).fill(0);
  const hpTrajLoss = new Array(maxNodes).fill(0);
  const hpTrajWinN = new Array(maxNodes).fill(0);
  const hpTrajLossN = new Array(maxNodes).fill(0);
  results.forEach(r => {
    const traj = r.hpTrajectory;
    for (let i = 0; i < Math.min(traj.length, maxNodes); i++) {
      if (r.won) { hpTrajWin[i] += traj[i].hp; hpTrajWinN[i]++; }
      else { hpTrajLoss[i] += traj[i].hp; hpTrajLossN[i]++; }
    }
  });
  const hpTrajectory = [];
  for (let i = 0; i < maxNodes; i++) {
    const w = hpTrajWinN[i] > 0 ? (hpTrajWin[i] / hpTrajWinN[i]).toFixed(1) : null;
    const l = hpTrajLossN[i] > 0 ? (hpTrajLoss[i] / hpTrajLossN[i]).toFixed(1) : null;
    if (w !== null || l !== null) hpTrajectory.push({ node: i, winHP: w, lossHP: l });
  }

  // ── ARCHETYPE DETECTION ──
  const archetypes = { Aggro: { wins: 0, total: 0 }, Sacrifice: { wins: 0, total: 0 }, Control: { wins: 0, total: 0 }, "Swift Burst": { wins: 0, total: 0 }, "Death Synergy": { wins: 0, total: 0 }, "Spell Heavy": { wins: 0, total: 0 } };
  const sacCards = new Set(["Corpse Eater","Blood Pyre","Bloodsworn","Necromancer","Mass Grave","Fuel the Pyre","Offering"]);
  const ctrlCards = new Set(["Shieldbearer","Stone Wall","Thornguard","Iron Bastion","Sentinel","Shield Wall","Barricade","Patch Up","Mending Light","Lay on Hands"]);
  const swiftCards = new Set(["Assassin","Harpy","Griffin","Doom Knight"]);
  const deathCards = new Set(["Warden of Graves","Gravedigger","Corpse Eater","Grave Pact","Grave Robbery","Doppelganger"]);
  results.forEach(r => {
    const names = new Set(r.cardsAdded);
    const deck = r.finalDeck;
    const creatures = deck.filter(id => CARDS[id]?.type === "creature").length;
    const spells = deck.filter(id => CARDS[id]?.type === "spell").length;
    const avgCost = deck.reduce((s, id) => s + (CARDS[id]?.cost || 0), 0) / Math.max(1, deck.length);
    const swiftCount = deck.filter(id => (CARDS[id]?.keywords || []).includes("swift")).length;
    // Classify (a deck can be multiple, but pick the strongest signal)
    let best = "Aggro", bestScore = 0;
    const sacScore = [...names].filter(n => sacCards.has(n)).length;
    const ctrlScore = [...names].filter(n => ctrlCards.has(n)).length;
    const swiftScore = [...names].filter(n => swiftCards.has(n)).length + swiftCount;
    const deathScore = [...names].filter(n => deathCards.has(n)).length;
    const spellScore = spells > creatures ? 2 : 0;
    const aggroScore = avgCost <= 1.6 ? 2 : (avgCost <= 1.9 ? 1 : 0);
    if (sacScore > bestScore) { best = "Sacrifice"; bestScore = sacScore; }
    if (ctrlScore > bestScore) { best = "Control"; bestScore = ctrlScore; }
    if (swiftScore > bestScore) { best = "Swift Burst"; bestScore = swiftScore; }
    if (deathScore > bestScore) { best = "Death Synergy"; bestScore = deathScore; }
    if (spellScore > bestScore) { best = "Spell Heavy"; bestScore = spellScore; }
    if (aggroScore > bestScore) { best = "Aggro"; }
    archetypes[best].total++;
    if (r.won) archetypes[best].wins++;
  });
  const archetypeData = Object.entries(archetypes)
    .filter(([, d]) => d.total >= 5)
    .map(([name, d]) => ({ name, total: d.total, wins: d.wins, wr: (d.wins / Math.max(1, d.total) * 100).toFixed(1) }))
    .sort((a, b) => b.wr - a.wr);

  // ── FLOOP STATS ──
  const winFloops = winRuns.length > 0 ? (winRuns.reduce((s, r) => s + r.totalFloops, 0) / winRuns.length).toFixed(1) : "0";
  const lossFloops = lossRuns.length > 0 ? (lossRuns.reduce((s, r) => s + r.totalFloops, 0) / lossRuns.length).toFixed(1) : "0";
  const floopStats = { winAvg: winFloops, lossAvg: lossFloops };

  // ── MANA CURVE ──
  const curveBuckets = (runs) => {
    const b = { "0": 0, "1": 0, "2": 0, "3": 0, "4+": 0 };
    let total = 0;
    runs.forEach(r => {
      r.finalDeck.forEach(id => {
        const c = CARDS[id]; if (!c) return;
        total++;
        if (c.cost === 0) b["0"]++;
        else if (c.cost === 1) b["1"]++;
        else if (c.cost === 2) b["2"]++;
        else if (c.cost === 3) b["3"]++;
        else b["4+"]++;
      });
    });
    return Object.entries(b).map(([cost, count]) => ({ cost, pct: (count / Math.max(1, total) * 100).toFixed(0) }));
  };
  const manaCurve = { wins: curveBuckets(winRuns), losses: curveBuckets(lossRuns) };

  return { wins, total: n, winRate: (wins / n * 100).toFixed(1), topCards, topRelics, topDeaths, avgRounds: (totalRounds / Math.max(1, totalFights)).toFixed(1), results, deckAnalytics, cardWinRates, synergyPairs, roundHistArr, hpTrajectory, archetypeData, floopStats, manaCurve };
}

// ── COLORS ────────────────────────────────────────────────────
const C = {
  bg: "#1a1410",
  panel: "#241e17",
  panelBorder: "#3d3226",
  gold: "#d4a849",
  goldDim: "#8a7340",
  text: "#e8dcc8",
  textDim: "#9a8e7c",
  red: "#c44b4b",
  green: "#5a9a5a",
  blue: "#4b7cc4",
  purple: "#8855aa",
  rarCommon: "#888",
  rarUncommon: "#4b9",
  rarRare: "#d4a849",
};

// ── MAIN COMPONENT ───────────────────────────────────────────
export default function BurningMeadowSim() {
  const [view, setView] = useState("menu");
  const [singleRun, setSingleRun] = useState(null);
  const [batchResult, setBatchResult] = useState(null);
  const [batchSize, setBatchSize] = useState(100);
  const [running, setRunning] = useState(false);

  const doSingleRun = useCallback(() => {
    const run = simulateRun();
    setSingleRun(run);
    setView("single");
  }, []);

  const doBatchRun = useCallback(() => {
    setRunning(true);
    setTimeout(() => {
      const res = runBatch(batchSize);
      setBatchResult(res);
      setRunning(false);
      setView("batch");
    }, 50);
  }, [batchSize]);

  const panelStyle = {
    background: C.panel,
    border: `1px solid ${C.panelBorder}`,
    borderRadius: 6,
    padding: "14px 16px",
    marginBottom: 12,
  };

  const btnStyle = (color) => ({
    background: "transparent",
    border: `1px solid ${color}`,
    color,
    padding: "8px 18px",
    borderRadius: 4,
    cursor: "pointer",
    fontFamily: "inherit",
    fontSize: 14,
    transition: "all 0.2s",
  });

  const renderMenu = () => (
    <div>
      <div style={{ textAlign: "center", marginBottom: 30 }}>
        <div style={{ fontSize: 28, color: C.gold, fontWeight: 600, letterSpacing: 2 }}>BURNING MEADOW</div>
        <div style={{ fontSize: 13, color: C.goldDim, letterSpacing: 3, marginTop: 4 }}>COMBAT SIMULATOR v4.0</div>
        <div style={{ fontSize: 11, color: C.textDim, marginTop: 8 }}>Simultaneous Combat · Synergies · Archetypes · HP Curves · Mana Analysis</div>
      </div>

      <div style={panelStyle}>
        <div style={{ display: "flex", gap: 12, flexDirection: "column" }}>
          <button onClick={doSingleRun} style={btnStyle(C.gold)}
            onMouseOver={e => { e.target.style.background = C.gold + "22"; }}
            onMouseOut={e => { e.target.style.background = "transparent"; }}>
            ⚔ Single Run
          </button>
          <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
            <button onClick={doBatchRun} disabled={running} style={btnStyle(C.green)}
              onMouseOver={e => { if(!running) e.target.style.background = C.green + "22"; }}
              onMouseOut={e => { e.target.style.background = "transparent"; }}>
              {running ? "Simulating..." : `⚡ Batch (${batchSize} runs)`}
            </button>
            <select value={batchSize} onChange={e => setBatchSize(Number(e.target.value))}
              style={{ background: C.panel, border: `1px solid ${C.panelBorder}`, color: C.text, padding: "6px 8px", borderRadius: 4, fontFamily: "inherit" }}>
              {[100, 500, 1000, 2500, 5000, 10000].map(n => <option key={n} value={n}>{n}</option>)}
            </select>
          </div>
        </div>
      </div>

      <div style={{ ...panelStyle, fontSize: 12, color: C.textDim, lineHeight: 1.7 }}>
        <div style={{ color: C.gold, fontSize: 11, textTransform: "uppercase", letterSpacing: 1, marginBottom: 8 }}>v3.0 — Matches Real Game Engine</div>
        <div>✓ <span style={{color:C.green}}>4x4 board</span> — 4 lanes × 2 rows (front/back), 8 slots per side</div>
        <div>✓ <span style={{color:C.green}}>Front-row blocking</span> — front attacked first, shields back row</div>
        <div>✓ <span style={{color:C.green}}>Both rows attack</span> — front first, then back each round</div>
        <div>✓ <span style={{color:C.green}}>On-death effects</span> — damage opposing, AoE, summon tokens, return, mana</div>
        <div>✓ <span style={{color:C.green}}>Reactive passives</span> — ON_SPELL, ON_FLOOP, ON_DEATH, ON_SUMMON, ON_DRAW</div>
        <div>✓ <span style={{color:C.green}}>Ranged targeting</span> — prefers back row, then front, then face</div>
        <div>✓ <span style={{color:C.green}}>Mana banking</span> — disabled round 1, max 1 (Ice Cream uncaps)</div>
        <div>✓ <span style={{color:C.green}}>Escalation</span> — double-place after round 8 for regular combats</div>
        <div>✓ <span style={{color:C.green}}>Soul Lantern / Siege / Berserker / dies-end-turn</span></div>
      </div>
    </div>
  );

  const renderSingle = () => {
    if (!singleRun) return null;
    const r = singleRun;
    return (
      <div>
        <button onClick={() => setView("menu")} style={btnStyle(C.textDim)}>← Back</button>
        <div style={{ ...panelStyle, marginTop: 12 }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <div style={{ fontSize: 20, color: r.won ? C.green : C.red, fontWeight: 600 }}>
              {r.won ? "VICTORY" : "DEFEAT"}
            </div>
            <div style={{ fontSize: 13, color: C.textDim }}>
              Acts: {r.acts}/3 · Deck: {r.deckSize} · HP: {r.finalHP}
            </div>
          </div>
          {r.diedTo && <div style={{ color: C.red, fontSize: 13, marginTop: 4 }}>Died to: {r.diedTo}</div>}
        </div>

        <div style={panelStyle}>
          <div style={{ fontSize: 11, color: C.goldDim, textTransform: "uppercase", letterSpacing: 1, marginBottom: 8 }}>Relics</div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
            {r.relics.map((name, i) => (
              <span key={i} style={{ background: C.gold + "22", border: `1px solid ${C.gold}44`, padding: "3px 8px", borderRadius: 3, fontSize: 12, color: C.gold }}>{name}</span>
            ))}
          </div>
        </div>

        <div style={panelStyle}>
          <div style={{ fontSize: 11, color: C.goldDim, textTransform: "uppercase", letterSpacing: 1, marginBottom: 8 }}>Run Log</div>
          {r.runLog.filter(e => e.type === "combat" || e.type === "elite" || e.type === "boss" || e.type === "rest" || e.type === "card_reward" || e.type === "boss_relic").map((e, i) => {
            if (e.type === "rest") return <div key={i} style={{ padding: "3px 0", fontSize: 12, color: C.green }}>🏕 Rest → {e.hp} HP</div>;
            if (e.type === "card_reward") return <div key={i} style={{ padding: "3px 0", fontSize: 12, color: C.blue }}>🃏 +{e.card} ({e.rarity})</div>;
            if (e.type === "boss_relic") return <div key={i} style={{ padding: "3px 0", fontSize: 12, color: C.purple }}>👑 +{e.relic} (mana→{e.mana})</div>;
            const icon = e.type === "boss" ? "👹" : e.type === "elite" ? "💀" : "⚔";
            return (
              <div key={i} style={{ padding: "4px 0", fontSize: 12, borderBottom: `1px solid ${C.panelBorder}22`, display: "flex", justifyContent: "space-between" }}>
                <span style={{ color: e.won ? C.green : C.red }}>
                  {icon} A{e.act} {e.encounter} {e.won ? "✓" : "✗"}
                </span>
                <span style={{ color: C.textDim, fontSize: 11 }}>
                  R{e.rounds} · HP:{e.playerHP} · E:{e.enemyHP} · Lost:{e.creaturesLost}
                </span>
              </div>
            );
          })}
        </div>

        <button onClick={doSingleRun} style={btnStyle(C.gold)}>Run Again</button>
      </div>
    );
  };

  const renderBatch = () => {
    if (!batchResult) return null;
    const b = batchResult;
    const wrColor = parseFloat(b.winRate) > 50 ? C.green : parseFloat(b.winRate) > 25 ? C.gold : C.red;

    return (
      <div>
        <button onClick={() => setView("menu")} style={btnStyle(C.textDim)}>← Back</button>

        <div style={{ ...panelStyle, marginTop: 12, textAlign: "center" }}>
          <div style={{ fontSize: 42, fontWeight: 600, color: wrColor }}>{b.winRate}%</div>
          <div style={{ fontSize: 13, color: C.textDim }}>{b.wins} wins / {b.total} runs · Avg {b.avgRounds} rounds/fight</div>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
          <div style={panelStyle}>
            <div style={{ fontSize: 11, color: C.goldDim, textTransform: "uppercase", letterSpacing: 1, marginBottom: 10 }}>Most Picked Cards</div>
            {b.topCards.map(([name, count], i) => {
              const card = Object.values(CARDS).find(c => c.name === name);
              const rarColor = card?.rarity === "rare" ? C.rarRare : card?.rarity === "uncommon" ? C.rarUncommon : C.rarCommon;
              return (
                <div key={i} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "3px 0", borderBottom: `1px solid ${C.panelBorder}22` }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                    <span style={{ color: C.textDim, fontSize: 11, width: 16 }}>{i + 1}.</span>
                    <span style={{ width: 6, height: 6, borderRadius: "50%", background: rarColor, flexShrink: 0 }} />
                    <span style={{ fontSize: 13, color: C.text }}>{name}</span>
                  </div>
                  <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                    <div style={{ width: Math.min(60, count / b.total * 300), height: 4, background: rarColor + "66", borderRadius: 2 }} />
                    <span style={{ fontSize: 11, color: C.textDim, width: 28, textAlign: "right" }}>{count}</span>
                  </div>
                </div>
              );
            })}
          </div>

          <div>
            <div style={panelStyle}>
              <div style={{ fontSize: 11, color: C.goldDim, textTransform: "uppercase", letterSpacing: 1, marginBottom: 10 }}>Most Picked Relics</div>
              {b.topRelics.map(([name, count], i) => (
                <div key={i} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "3px 0", borderBottom: `1px solid ${C.panelBorder}22` }}>
                  <span style={{ fontSize: 13, color: C.gold }}>{name}</span>
                  <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                    <div style={{ width: Math.min(50, count / b.total * 200), height: 4, background: C.gold + "44", borderRadius: 2 }} />
                    <span style={{ fontSize: 11, color: C.textDim, width: 28, textAlign: "right" }}>{count}</span>
                  </div>
                </div>
              ))}
            </div>

            <div style={panelStyle}>
              <div style={{ fontSize: 11, color: C.red, textTransform: "uppercase", letterSpacing: 1, marginBottom: 10 }}>Death Map</div>
              {b.topDeaths.map(([name, count], i) => (
                <div key={i} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "3px 0", borderBottom: `1px solid ${C.panelBorder}22` }}>
                  <span style={{ fontSize: 13, color: C.text }}>{name}</span>
                  <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                    <div style={{ width: Math.min(50, count / Math.max(1, b.total - b.wins) * 200), height: 4, background: C.red + "44", borderRadius: 2 }} />
                    <span style={{ fontSize: 11, color: C.textDim, width: 28, textAlign: "right" }}>{count}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>

        {b.deckAnalytics && <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
          {["wins", "losses"].map(cat => {
            const da = b.deckAnalytics[cat];
            if (!da || da.avgSize === 0) return null;
            const isWin = cat === "wins";
            return (
              <div key={cat} style={panelStyle}>
                <div style={{ fontSize: 11, color: isWin ? C.green : C.red, textTransform: "uppercase", letterSpacing: 1, marginBottom: 10 }}>
                  {isWin ? "Winning" : "Losing"} Deck Profile ({isWin ? b.wins : b.total - b.wins} runs)
                </div>
                <div style={{ fontSize: 12, color: C.textDim, marginBottom: 8 }}>
                  Avg size: <span style={{ color: C.text }}>{da.avgSize}</span> &middot;
                  Creatures: <span style={{ color: C.text }}>{da.avgCreatures}</span> &middot;
                  Spells: <span style={{ color: C.text }}>{da.avgSpells}</span> &middot;
                  Avg cost: <span style={{ color: C.text }}>{da.avgCost}</span>
                </div>
                <div style={{ fontSize: 11, color: C.goldDim, marginBottom: 4 }}>Top Cards (avg/run)</div>
                {da.topCards.map((c, i) => (
                  <div key={i} style={{ display: "flex", justifyContent: "space-between", padding: "2px 0", fontSize: 12, borderBottom: `1px solid ${C.panelBorder}22` }}>
                    <span style={{ color: C.text }}>{c.name}</span>
                    <span style={{ color: C.textDim }}>{c.avg}</span>
                  </div>
                ))}
                {da.topKeywords && da.topKeywords.length > 0 && <>
                  <div style={{ fontSize: 11, color: C.goldDim, marginTop: 8, marginBottom: 4 }}>Keywords (avg/run)</div>
                  <div style={{ display: "flex", flexWrap: "wrap", gap: 4 }}>
                    {da.topKeywords.map((k, i) => (
                      <span key={i} style={{ background: (isWin ? C.green : C.red) + "22", border: `1px solid ${(isWin ? C.green : C.red)}44`, padding: "2px 6px", borderRadius: 3, fontSize: 11, color: C.text }}>
                        {k.kw}: {k.avg}
                      </span>
                    ))}
                  </div>
                </>}
              </div>
            );
          })}
        </div>}

        {b.cardWinRates && b.cardWinRates.length > 0 && <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
          <div style={panelStyle}>
            <div style={{ fontSize: 11, color: C.green, textTransform: "uppercase", letterSpacing: 1, marginBottom: 10 }}>Highest Win Rate Cards</div>
            {b.cardWinRates.slice(0, 15).map((c, i) => {
              const card = Object.values(CARDS).find(cd => cd.name === c.name);
              const rarColor = card?.rarity === "rare" ? C.rarRare : card?.rarity === "uncommon" ? C.rarUncommon : C.rarCommon;
              const typeTag = card?.type === "spell" ? " [S]" : "";
              return (
                <div key={i} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "3px 0", borderBottom: `1px solid ${C.panelBorder}22` }}>
                  <span style={{ fontSize: 13, color: rarColor }}>{c.name}{typeTag}</span>
                  <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    <span style={{ fontSize: 11, color: C.textDim }}>{c.picked}x</span>
                    <span style={{ fontSize: 13, fontWeight: 600, color: C.green, width: 45, textAlign: "right" }}>{c.wr}%</span>
                  </div>
                </div>
              );
            })}
          </div>
          <div style={panelStyle}>
            <div style={{ fontSize: 11, color: C.red, textTransform: "uppercase", letterSpacing: 1, marginBottom: 10 }}>Lowest Win Rate Cards</div>
            {[...b.cardWinRates].sort((a, b) => a.wr - b.wr).slice(0, 15).map((c, i) => {
              const card = Object.values(CARDS).find(cd => cd.name === c.name);
              const rarColor = card?.rarity === "rare" ? C.rarRare : card?.rarity === "uncommon" ? C.rarUncommon : C.rarCommon;
              const typeTag = card?.type === "spell" ? " [S]" : "";
              return (
                <div key={i} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "3px 0", borderBottom: `1px solid ${C.panelBorder}22` }}>
                  <span style={{ fontSize: 13, color: rarColor }}>{c.name}{typeTag}</span>
                  <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    <span style={{ fontSize: 11, color: C.textDim }}>{c.picked}x</span>
                    <span style={{ fontSize: 13, fontWeight: 600, color: C.red, width: 45, textAlign: "right" }}>{c.wr}%</span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>}

        {/* ── SYNERGY PAIRS ── */}
        {b.synergyPairs && b.synergyPairs.length > 0 && <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
          <div style={panelStyle}>
            <div style={{ fontSize: 11, color: C.green, textTransform: "uppercase", letterSpacing: 1, marginBottom: 10 }}>Best Card Synergies</div>
            {b.synergyPairs.slice(0, 12).map((p, i) => (
              <div key={i} style={{ display: "flex", justifyContent: "space-between", padding: "3px 0", fontSize: 12, borderBottom: `1px solid ${C.panelBorder}22` }}>
                <span style={{ color: C.text }}>{p.pair}</span>
                <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                  <span style={{ color: C.textDim, fontSize: 11 }}>{p.count}x</span>
                  <span style={{ color: C.green, fontWeight: 600, width: 42, textAlign: "right" }}>{p.wr}%</span>
                </div>
              </div>
            ))}
          </div>
          <div style={panelStyle}>
            <div style={{ fontSize: 11, color: C.red, textTransform: "uppercase", letterSpacing: 1, marginBottom: 10 }}>Worst Card Synergies</div>
            {[...b.synergyPairs].sort((a, b) => a.wr - b.wr).slice(0, 12).map((p, i) => (
              <div key={i} style={{ display: "flex", justifyContent: "space-between", padding: "3px 0", fontSize: 12, borderBottom: `1px solid ${C.panelBorder}22` }}>
                <span style={{ color: C.text }}>{p.pair}</span>
                <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                  <span style={{ color: C.textDim, fontSize: 11 }}>{p.count}x</span>
                  <span style={{ color: C.red, fontWeight: 600, width: 42, textAlign: "right" }}>{p.wr}%</span>
                </div>
              </div>
            ))}
          </div>
        </div>}

        {/* ── ROUND HISTOGRAM + HP TRAJECTORY ── */}
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
          {b.roundHistArr && <div style={panelStyle}>
            <div style={{ fontSize: 11, color: C.goldDim, textTransform: "uppercase", letterSpacing: 1, marginBottom: 10 }}>Combat Length (rounds)</div>
            {(() => { const maxC = Math.max(...b.roundHistArr.map(r => r.count)); return b.roundHistArr.map((r, i) => (
              <div key={i} style={{ display: "flex", alignItems: "center", gap: 8, padding: "2px 0" }}>
                <span style={{ fontSize: 12, color: C.textDim, width: 20, textAlign: "right" }}>R{r.round}</span>
                <div style={{ flex: 1, position: "relative", height: 14 }}>
                  <div style={{ width: `${(r.count / maxC * 100)}%`, height: "100%", background: r.round <= 5 ? C.green + "66" : r.round <= 10 ? C.gold + "66" : C.red + "66", borderRadius: 2 }} />
                </div>
                <span style={{ fontSize: 11, color: C.textDim, width: 35, textAlign: "right" }}>{r.count}</span>
              </div>
            )); })()}
            <div style={{ fontSize: 11, color: C.textDim, marginTop: 8 }}>Healthy: R5-8 · Fast: R1-4 · Grind: R9+</div>
          </div>}

          {b.hpTrajectory && <div style={panelStyle}>
            <div style={{ fontSize: 11, color: C.goldDim, textTransform: "uppercase", letterSpacing: 1, marginBottom: 10 }}>HP Trajectory (avg per node)</div>
            {b.hpTrajectory.map((h, i) => (
              <div key={i} style={{ display: "flex", alignItems: "center", gap: 8, padding: "2px 0" }}>
                <span style={{ fontSize: 11, color: C.textDim, width: 20, textAlign: "right" }}>{i}</span>
                <div style={{ flex: 1, display: "flex", gap: 4, alignItems: "center" }}>
                  {h.winHP && <div style={{ display: "flex", alignItems: "center", gap: 4, flex: 1 }}>
                    <div style={{ width: `${(h.winHP / 25 * 100)}%`, height: 8, background: C.green + "88", borderRadius: 2 }} />
                    <span style={{ fontSize: 10, color: C.green }}>{h.winHP}</span>
                  </div>}
                  {h.lossHP && <div style={{ display: "flex", alignItems: "center", gap: 4, flex: 1 }}>
                    <div style={{ width: `${(h.lossHP / 25 * 100)}%`, height: 8, background: C.red + "88", borderRadius: 2 }} />
                    <span style={{ fontSize: 10, color: C.red }}>{h.lossHP}</span>
                  </div>}
                </div>
              </div>
            ))}
            <div style={{ fontSize: 11, marginTop: 6 }}><span style={{ color: C.green }}>■</span> Wins <span style={{ color: C.red, marginLeft: 12 }}>■</span> Losses</div>
          </div>}
        </div>

        {/* ── ARCHETYPES + FLOOP + MANA CURVE ── */}
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12 }}>
          {b.archetypeData && <div style={panelStyle}>
            <div style={{ fontSize: 11, color: C.purple, textTransform: "uppercase", letterSpacing: 1, marginBottom: 10 }}>Archetype Win Rates</div>
            {b.archetypeData.map((a, i) => {
              const wrN = parseFloat(a.wr);
              const wrCol = wrN > 10 ? C.green : wrN > 3 ? C.gold : C.red;
              return (
                <div key={i} style={{ display: "flex", justifyContent: "space-between", padding: "4px 0", borderBottom: `1px solid ${C.panelBorder}22` }}>
                  <span style={{ fontSize: 13, color: C.text }}>{a.name}</span>
                  <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                    <span style={{ fontSize: 11, color: C.textDim }}>{a.total} runs</span>
                    <span style={{ fontSize: 13, fontWeight: 600, color: wrCol, width: 42, textAlign: "right" }}>{a.wr}%</span>
                  </div>
                </div>
              );
            })}
          </div>}

          {b.floopStats && <div style={panelStyle}>
            <div style={{ fontSize: 11, color: C.blue, textTransform: "uppercase", letterSpacing: 1, marginBottom: 10 }}>Floop Usage</div>
            <div style={{ fontSize: 24, color: C.green, fontWeight: 600 }}>{b.floopStats.winAvg}</div>
            <div style={{ fontSize: 11, color: C.textDim, marginBottom: 12 }}>avg floops/run (wins)</div>
            <div style={{ fontSize: 24, color: C.red, fontWeight: 600 }}>{b.floopStats.lossAvg}</div>
            <div style={{ fontSize: 11, color: C.textDim }}>avg floops/run (losses)</div>
          </div>}

          {b.manaCurve && <div style={panelStyle}>
            <div style={{ fontSize: 11, color: C.goldDim, textTransform: "uppercase", letterSpacing: 1, marginBottom: 10 }}>Mana Curve</div>
            <div style={{ fontSize: 11, color: C.textDim, marginBottom: 6 }}>Cost distribution %</div>
            <div style={{ display: "flex", gap: 4, marginBottom: 8 }}>
              {b.manaCurve.wins.map((c, i) => (
                <div key={i} style={{ flex: 1, textAlign: "center" }}>
                  <div style={{ background: C.green + "44", height: Math.max(4, c.pct * 1.5), borderRadius: 2, marginBottom: 2 }} />
                  <div style={{ fontSize: 10, color: C.green }}>{c.pct}%</div>
                </div>
              ))}
            </div>
            <div style={{ display: "flex", gap: 4 }}>
              {b.manaCurve.losses.map((c, i) => (
                <div key={i} style={{ flex: 1, textAlign: "center" }}>
                  <div style={{ background: C.red + "44", height: Math.max(4, c.pct * 1.5), borderRadius: 2, marginBottom: 2 }} />
                  <div style={{ fontSize: 10, color: C.red }}>{c.pct}%</div>
                </div>
              ))}
            </div>
            <div style={{ display: "flex", gap: 4, marginTop: 4 }}>
              {b.manaCurve.wins.map((c, i) => (
                <div key={i} style={{ flex: 1, textAlign: "center", fontSize: 10, color: C.textDim }}>{c.cost}</div>
              ))}
            </div>
            <div style={{ fontSize: 11, marginTop: 6 }}><span style={{ color: C.green }}>■</span> Wins <span style={{ color: C.red, marginLeft: 8 }}>■</span> Losses</div>
          </div>}
        </div>

        <div style={panelStyle}>
          <div style={{ fontSize: 11, color: C.goldDim, textTransform: "uppercase", letterSpacing: 1, marginBottom: 10 }}>Sample Runs (click to expand)</div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
            {b.results.slice(0, 40).map((run, i) => (
              <button key={i} onClick={() => { setSingleRun(run); setView("single"); }}
                style={{ ...btnStyle(run.won ? C.green : C.red), padding: "3px 8px", fontSize: 11, minWidth: 0 }}>
                #{i + 1} {run.won ? "W" : "L"} A{run.acts}
              </button>
            ))}
          </div>
        </div>
      </div>
    );
  };

  return (
    <div style={{
      fontFamily: "'Crimson Pro', 'Palatino', 'Georgia', serif",
      background: C.bg, color: C.text, minHeight: "100vh",
      padding: "20px 24px", maxWidth: 900, margin: "0 auto", lineHeight: 1.5,
    }}>
      <link href="https://fonts.googleapis.com/css2?family=Crimson+Pro:wght@300;400;600&display=swap" rel="stylesheet" />
      {view === "menu" && renderMenu()}
      {view === "single" && renderSingle()}
      {view === "batch" && renderBatch()}
    </div>
  );
}
