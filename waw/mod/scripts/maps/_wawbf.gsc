#include common_scripts\utility;
#include maps\_utility;

// World at War's half of "the character's own weapons".
//
// The player is a Battlefront II character, and that character has its own
// weapons and abilities. World at War still does the hurting (its shots are
// the ones that hit zombies), so the player here is handed whichever of this
// mod's weapons matches what the character carries: the same kind of weapon,
// firing at the same rate, in the same bursts, from the same size of
// magazine. And whatever the character does that is not a shot (throws its
// lightsaber, uses the Force, fires a rocket from its wrist) is made to
// happen to the zombies from here. docs/PHASE3.md has the list and how each
// was matched.
//
// The bridge and these scripts talk through two numbers on the player's
// entity that mean nothing on a player:
//
//   count   the bridge writes, read here as self.count. From the low end:
//           five bits of kit (0 is "not known": Battlefront II is not
//           running, or the character is one nobody has matched yet, and the
//           player is left with whatever they have), three of which ability
//           is selected (its place among the Battlefront unit's weapons),
//           one of "the ability is in use this moment", one of "the weapon
//           in hand is in use this moment" (a lightsaber mid-swing), then
//           seven of a count of the times an ability has been used, seven of
//           a count of the times the weapon has, four of how far the weapon
//           was charged when it was last fired (0 to 15), and one of the
//           player's own: the button for what is fitted to the weapon in
//           hand is held.
//   dmg     written here, read by the bridge: which of the character's
//           weapons is in hand (1 or 2, or 0 for neither), plus 4 if the
//           ability may be used, plus 8 if the weapon in hand has run dry,
//           plus 16 times the rounds in its magazine, plus 4096 times the
//           rounds the magazine holds (0 for a weapon whose magazine
//           Battlefront II is not to be kept in step with), plus 1048576
//           times how far it is from the player's eyes to what they are
//           aiming at, in steps of 16 of the game's units (1 to 255; 0 for
//           a character with nothing to aim). The bridge draws the crosshair
//           there when the view is from behind the character.
//
// build.ps1 in waw/mod puts a call to init() into the map's own script, ahead
// of the game's start-up, which is the only time weapons can be precached,
// and a call to shops() into the game's weapons script.

init()
{
	level.wawbf_kit = [];

	//       kit  first weapon         second weapon              lightsaber
	add_kit( 1,  "swbf2_dl44",        undefined,                 false );  // Han Solo
	add_kit( 2,  "swbf2_rifle",       "swbf2_pistol",            false );  // a clone trooper, a stormtrooper
	add_kit( 3,  "swbf2_rifle",       "swbf2_launcher",          false );  // a battle droid
	add_kit( 4,  "swbf2_ee3",         "swbf2_flame",             false );  // Boba Fett
	add_kit( 5,  "swbf2_bowcaster",   undefined,                 false );  // Chewbacca
	add_kit( 6,  "swbf2_sporting",    undefined,                 false );  // Leia
	add_kit( 7,  "swbf2_saber",       undefined,                 true  );  // Luke, Obi-Wan, Mace Windu, Darth Maul
	add_kit( 8,  "swbf2_saber",       undefined,                 true  );  // Aayla Secura
	add_kit( 9,  "swbf2_saber",       undefined,                 true  );  // Anakin, Darth Vader
	add_kit( 10, "swbf2_saber",       undefined,                 true  );  // Yoda
	add_kit( 11, "swbf2_saber",       undefined,                 true  );  // Count Dooku
	add_kit( 12, "swbf2_saber",       undefined,                 true  );  // General Grievous
	add_kit( 13, "swbf2_saber",       undefined,                 true  );  // the Emperor (as Count Dooku; the bridge tells them apart)

	// Boba Fett's second weapon is fitted to his first: in Battlefront II the
	// flamethrower is part of his rifle. Here it is fitted to the rifle as
	// this game fits a grenade launcher to one (build.ps1), so it is not a
	// weapon he changes to with the button for that: a button of its own
	// changes between the two (left on a controller's d-pad, 5 on the
	// keyboard; the bridge says when it is pressed: change_fitted). And
	// wherever the rifle goes, into the Pack-a-Punch and out of it, the
	// flamethrower goes too.
	level.wawbf_part_of = [];
	fit_kit( 4 );

	// What each kit can do besides shoot, by the place the ability has among
	// the Battlefront unit's weapons (the first weapon is place 0).
	//           kit  place  ability
	add_ability( 1,   2,     "grenade" );
	add_ability( 2,   2,     "grenade" );
	add_ability( 3,   2,     "grenade" );
	add_ability( 4,   2,     "rocket" );
	add_ability( 4,   3,     "grenade" );
	add_ability( 5,   2,     "grenade" );
	add_ability( 6,   1,     "grenade" );
	add_ability( 7,   1,     "throw" );
	add_ability( 7,   2,     "push" );
	add_ability( 8,   1,     "throw" );
	add_ability( 8,   2,     "pull" );
	add_ability( 9,   1,     "throw" );
	add_ability( 9,   2,     "choke" );
	add_ability( 10,  1,     "pull" );
	add_ability( 10,  2,     "push" );
	add_ability( 11,  1,     "lightning" );
	add_ability( 11,  2,     "choke" );
	add_ability( 13,  1,     "lightning" );
	add_ability( 13,  2,     "choke" );

	// Weapons that never run out and never reload. In Battlefront II these
	// have no magazine: they heat up instead, or are a blade. The number is
	// what the magazine here is kept topped up to.
	level.wawbf_endless = [];
	level.wawbf_endless["swbf2_dl44"] = 24;
	level.wawbf_endless["swbf2_pistol"] = 30;
	level.wawbf_endless["swbf2_sporting"] = 12;
	level.wawbf_endless["swbf2_saber"] = 100;

	// Weapons with a magazine in both games. World at War counts the rounds,
	// and the bridge keeps Battlefront II's magazine at the same number and
	// reloads it when this one is reloaded, so that the two stop and start
	// together.
	level.wawbf_magazine = [];
	level.wawbf_magazine["swbf2_rifle"] = true;
	level.wawbf_magazine["swbf2_ee3"] = true;
	level.wawbf_magazine["swbf2_bowcaster"] = true;
	level.wawbf_magazine["swbf2_launcher"] = true;

	// Distances are in the game's inches, 39 to the metre. An arc is the
	// least cosine of the angle between where the player looks and where the
	// zombie is: 1 is dead ahead, 0 square to the side.

	// A lightsaber's swing: everything within reach (player to zombie) and
	// inside the arc is cut down. -0.2 is a little behind square to either
	// side.
	level.wawbf_saber_reach = 125;
	level.wawbf_saber_arc = -0.2;
	level.wawbf_saber_height = 90;
	level.wawbf_saber_again = 0.15;  // seconds between cuts while one swing lasts

	// A thrown lightsaber flies this far, this fast, and cuts down what is
	// within this much of its path.
	level.wawbf_throw_reach = 1575;
	level.wawbf_throw_speed = 1180;
	level.wawbf_throw_width = 45;

	// The Force. Reach, arc and how many at once are Battlefront II's own;
	// the damage is not, because there the Force only knocks soldiers down.
	// Choke and lightning are held, and hurt this much every tenth of a
	// second for as long as they are.
	level.wawbf_push_reach = 790;
	level.wawbf_push_arc = 0.5;
	level.wawbf_push_most = 4;
	level.wawbf_push_damage = 1000;
	// Pull is push the other way: it kills as push does, and what it kills
	// is thrown towards the player, harder the further off it was (between
	// these two, for each unit of distance this much).
	level.wawbf_pull_reach = 1575;
	level.wawbf_pull_arc = 0.9;
	level.wawbf_pull_most = 3;
	level.wawbf_pull_throw_least = 160;
	level.wawbf_pull_throw_most = 450;
	level.wawbf_pull_throw_each = 0.5;
	level.wawbf_choke_reach = 790;
	level.wawbf_choke_arc = 0.94;
	level.wawbf_choke_damage = 250;
	level.wawbf_lightning_reach = 590;
	level.wawbf_lightning_arc = 0.77;
	level.wawbf_lightning_most = 10;
	level.wawbf_lightning_damage = 125;
	// On a zombie, lightning looks and sounds as the Wunderwaffe's shot does
	// when it lands (shock, further down). This map has no Wunderwaffe;
	// build.ps1 brings these in from Shi No Numa.
	level.wawbf_fx_shock = LoadFX( "maps/zombie/fx_zombie_tesla_shock" );
	level.wawbf_fx_shock_next = LoadFX( "maps/zombie/fx_zombie_tesla_shock_secondary" );
	level.wawbf_fx_shock_eyes = LoadFX( "maps/zombie/fx_zombie_tesla_shock_eyes" );
	level.wawbf_fx_shock_bolt = LoadFX( "maps/zombie/fx_zombie_tesla_bolt_secondary" );
	PrecacheModel( "tag_origin" );
	level.wawbf_shock_again = 900;       // milliseconds before a zombie still being struck shows it again
	level.wawbf_shock_apart = 0.06;      // seconds between one zombie showing it and the next
	level.wawbf_shock_bolt_least = 64;   // no bolt between two zombies closer together than this
	level.wawbf_shock_bolt_time = 0.2;   // seconds a bolt takes from one to the next
	level.wawbf_shock_head = 50;         // chances in 100 that one killed by it loses its head

	// Boba Fett's wrist rocket leaves this long after the button, as it does
	// in Battlefront II.
	level.wawbf_rocket_delay = 0.46;
	level.wawbf_rockets = 5;

	// The bowcaster. It charges for as long as the trigger is held (a full
	// charge takes 1.25 s, and the ring round Battlefront II's crosshair shows
	// it) and fires when the trigger is let go: a fan of seven bolts, each
	// this many degrees from the next, that hit harder the longer it was
	// held, up to twice as hard; or, charged all the way, one heavy bolt. The
	// fan is Battlefront II's, and so is what a shot takes from the magazine
	// of thirty-five: a round for each bolt of the fan, so five fans and a
	// reload (measured there: 35, 28, 21), and one round for the heavy bolt. A
	// light bolt does 75 there and its heavy bolt 300, going through nobody;
	// here the user wanted a rifle's reach with more behind it than a rifle
	// has, so a light bolt is worth two of Battlefront II's.
	level.wawbf_bowcaster_full = 0.9;
	level.wawbf_bowcaster_fan = 0.7;
	level.wawbf_bowcaster_bolts = 7;
	level.wawbf_bowcaster_bolt = 150;
	level.wawbf_bowcaster_slug = 1000;
	level.wawbf_bowcaster_through = 5;

	// What a wall charges to fill everything the player carries.
	level.wawbf_ammo_cost = 250;
	level.wawbf_grenades = 4;

	// How hard the guns hit: this many times Battlefront II's own numbers.
	// The weapons' files have it already (build.ps1 -GunDamage, which also
	// writes the number here); the shots worked out in this script, the
	// bowcaster's, are multiplied by it. Not the Ray Gun under Leia's blaster.
	level.wawbf_gun_damage = 1;

	// How much the player can take is the WaW bridge's to set, not this
	// script's: 200, so that a zombie's fourth blow puts them down where the
	// game's own 100 makes it the second ([waw] player_health in its
	// settings). A script can change the number its own sums are done with
	// (self.maxhealth) but not the one the game gets a player back to after
	// a blow, which is kept somewhere else: with only the first changed the
	// player was "healed" down to 100 after the first blow and then left near
	// death for good, with the breathing that goes with it.
	//
	// With more to take there is a third blow to survive, and surviving it
	// brings up the game's "you are hurt, get to cover" for the first time in
	// this map; its routine asks something of the map that only the campaign's
	// maps can answer, and fails. It is told not to ask.
	level.enable_cover_warning = false;

	// Pack-a-Punch, at the mystery box (pack_a_punch, further down). What it
	// gives back hits this many times as hard (build.ps1 -PackDamage) and
	// carries more ammunition. Not a lightsaber: there is nothing to improve.
	level.wawbf_pack_damage = 1;
	level.wawbf_pack_cost = 5000;
	level.wawbf_pack_time = 3;       // seconds the weapon is in there
	level.wawbf_pack_wait = 15;      // and seconds it then waits to be taken, before it is lost
	level.wawbf_fx_pack = LoadFX( "maps/zombie/fx_zombie_packapunch" );
	PrecacheModel( "zombie_vending_packapunch_on" );
	PrecacheModel( "zombie_vending_revive_on" );
	// What the player's own hands do at each machine, as in the maps that
	// have them: these are weapons whose only use is to be taken in hand.
	level.wawbf_hands_pack = "zombie_knuckle_crack";
	level.wawbf_hands_revive = "zombie_perk_bottle_revive";
	PrecacheItem( level.wawbf_hands_pack );
	PrecacheItem( level.wawbf_hands_revive );

	// Quick Revive (quick_revive, last_stand). Alone, it is what gets the
	// player back up: the blow that would have put them down puts them on
	// one knee instead, where they stay this many seconds, unable to move but
	// able to fight, with nothing able to hurt them; then they are up again.
	// It is used up by that, and can be bought this many times in a game.
	level.wawbf_revive_cost = 1500;
	level.wawbf_revive_most = 3;
	level.wawbf_revive_time = 10;
	level.wawbf_revive_grace = 1.5;  // seconds more, once up, before anything can hurt them
	level.wawbf_revive_far = 8;      // while they are down the zombies walk off, to one of this many places (keep_away),
	level.wawbf_revive_least = 250;  // each at least this far from the player
	level.wawbf_revive_reach = 1100; // and no further than this, nor more than this much above or below them:
	level.wawbf_revive_floor = 90;   // the part of the map the player is in
	level.wawbf_revive_look = 500;   // how far across the room from the cabinet its machine's pillar is looked for
	level.wawbf_revive_aside = 54;   // and how far to either side of straight ahead
	level.wawbf_box_height = 19;     // the mystery box, floor to lid: the Pack-a-Punch machine stands on the floor it is on
	level.wawbf_use_clear = 8;       // how far in front of a machine's solid blocks its "use" place is put (stand_solid)
	PrecacheShader( "specialty_quickrevive_zombies" );

	// Power-ups as the later maps have them: a picture at the bottom of the
	// screen while double points or insta-kill lasts, that flashes as it runs
	// out, and the voice that says which one was picked up.
	PrecacheShader( "specialty_doublepoints_zombies" );
	PrecacheShader( "specialty_instakill_zombies" );
	level.wawbf_powerup_icons_y = 6;    // how far below the top of the screen they sit, in the middle (of 480 down it)

	names = GetArrayKeys( level.wawbf_endless );
	for( i = 0; i < names.size; i++ )
	{
		level.wawbf_endless[names[i] + "_upgraded"] = level.wawbf_endless[names[i]];
	}
	names = GetArrayKeys( level.wawbf_magazine );
	for( i = 0; i < names.size; i++ )
	{
		level.wawbf_magazine[names[i] + "_upgraded"] = true;
	}

	numbers = GetArrayKeys( level.wawbf_kit );
	for( i = 0; i < numbers.size; i++ )
	{
		kit = level.wawbf_kit[numbers[i]];
		precache_weapon( kit.first );
		precache_weapon( kit.second );
	}

	level thread run();
}

// A kit's weapon, and for one of this mod's own the one Pack-a-Punch gives
// back for it.
precache_weapon( weapon )
{
	if( !IsDefined( weapon ) )
	{
		return;
	}
	PrecacheItem( weapon );
	if( can_be_packed( weapon ) )
	{
		PrecacheItem( weapon + "_upgraded" );
	}
}

// One of this mod's own weapons that Pack-a-Punch has a second form of:
// every one but the lightsaber.
can_be_packed( weapon )
{
	return GetSubStr( weapon, 0, 6 ) == "swbf2_" && weapon != "swbf2_saber";
}

add_kit( number, first, second, saber )
{
	kit = SpawnStruct();
	kit.first = first;
	kit.second = second;
	kit.saber = saber;
	kit.fitted = false;  // the second weapon is part of the first
	kit.abilities = [];
	kit.fallback = undefined;  // the ability to assume while the bridge says nothing about which
	level.wawbf_kit[number] = kit;
}

// This kit's second weapon is fitted to its first.
fit_kit( number )
{
	kit = level.wawbf_kit[number];
	kit.fitted = true;
	level.wawbf_part_of[kit.second] = kit.first;
}

add_ability( number, place, ability )
{
	kit = level.wawbf_kit[number];
	kit.abilities[place] = ability;
	if( !IsDefined( kit.fallback ) )
	{
		kit.fallback = ability;
	}
}

has_ability( kit, ability )
{
	places = GetArrayKeys( kit.abilities );
	for( i = 0; i < places.size; i++ )
	{
		if( kit.abilities[places[i]] == ability )
		{
			return true;
		}
	}
	return false;
}

run()
{
	// The players are there once the map has finished starting up.
	for( ;; )
	{
		players = get_players();
		if( IsDefined( players ) && players.size > 0 )
		{
			break;
		}
		wait( 0.25 );
	}

	// Every blow to a player comes through here first, for Quick Revive.
	level.wawbf_stock_damage = level.overridePlayerDamage;
	level.overridePlayerDamage = ::player_damage;

	level thread powerup_icons();
	players[0] thread tally();

	// What the game gives a player to take (its own 100, or what the bridge
	// has made of it). The game's scripts write 100 into a player as their
	// most whatever that is, and their sums about how hurt a player is are
	// done with it; follow_kit keeps it the same as the game's.
	level.wawbf_most_health = GetDvarInt( "g_player_maxhealth" );

	for( i = 0; i < players.size; i++ )
	{
		players[i].wawbf_grenades = level.wawbf_grenades;
		players[i].wawbf_rockets = level.wawbf_rockets;
		players[i].wawbf_hand = 0;
		players[i].wawbf_idle = 0;
		players[i].wawbf_unchanged = 0;
		players[i].wawbf_clip = [];
		players[i].wawbf_stock = [];
		players[i].wawbf_packed = [];
		players[i].wawbf_away = [];
		players[i].wawbf_revives = 0;
		players[i].wawbf_revives_bought = 0;
		players[i] thread test_start();
		players[i] AllowProne( false );  // Battlefront II's characters are not shown lying down
		players[i] thread follow_kit();
	}
}

// For testing, and no part of the mod as played: this is in the way the game
// is started, nowhere else.
//
//   +set wawbf_points 50000   the player begins with that many points (after
//                             a moment: the game hands out its own five
//                             hundred as it starts).
//
// (Beginning unable to be hurt was here too, and is the bridge's now: [debug]
// god_at_start in its settings. What a script can switch on is not what "god"
// typed into the console switches, so nothing typed there could undo it.)
test_start()
{
	self endon( "disconnect" );

	points = GetDvarInt( "wawbf_points" );
	if( points <= 0 )
	{
		return;
	}
	wait( 3 );
	self maps\_zombiemode_score::add_to_player_score( points - self.score );
}

// What the Tab key (or a controller's Back button) brings up. Played alone,
// this game has no scoreboard there: it shows "Mission Objectives", and
// zombies has none, so the screen is empty. The player's tally is put on it
// as objectives: the round, their points, their kills, how often they went
// down. Rewritten only when one of them changes, and by the routine that
// does not announce it.
tally()
{
	self endon( "disconnect" );

	wait( 5 );
	said = [];
	for( line = 1; line <= 4; line++ )
	{
		said[line] = "";
	}
	for( ;; )
	{
		says = [];
		says[1] = "Round " + level.round_number;
		says[2] = "Points: " + self.score + "   Earned in all: " + self.score_total;
		says[3] = "Kills: " + self.kills;
		says[4] = "Times down: " + self.downs;
		for( line = 1; line <= 4; line++ )
		{
			if( says[line] == said[line] )
			{
				continue;
			}
			if( said[line] == "" )
			{
				state = "active";
				if( line == 1 )
				{
					state = "current";
				}
				Objective_Add( line, state, says[line] );
			}
			else
			{
				Objective_String_NoMessage( line, says[line] );
			}
			said[line] = says[line];
		}
		wait( 1 );
	}
}

// Hands the player the weapons of whatever kit the bridge says, each time it
// changes, and again if the game has since taken them away; does what the
// character's abilities do; and tells the bridge what it needs to know.
follow_kit()
{
	self endon( "disconnect" );

	have = 0;
	uses = undefined;
	swings = undefined;
	held_for = 0;
	swung_for = 0;
	fit_held = false;
	for( ;; )
	{
		wait( 0.05 );

		says = self.count;
		if( !IsDefined( says ) || says < 0 )
		{
			says = 0;
		}
		// (The top one first, and taken off: the rest are got at by dividing,
		// which makes a fraction of the number, and a fraction has not the
		// room for one this big.)
		fit = ( says >= 268435456 );
		if( fit )
		{
			says -= 268435456;
		}
		fit_pressed = ( fit && !fit_held );
		fit_held = fit;
		want = says % 32;
		place = int( says / 32 ) % 8;
		in_use = int( says / 256 ) % 2;
		swinging = int( says / 512 ) % 2;
		used = int( says / 1024 ) % 128;
		swung = int( says / 131072 ) % 128;
		charge = ( int( says / 16777216 ) % 16 ) / 15;

		if( !IsDefined( level.wawbf_kit[want] ) )
		{
			have = 0;
			uses = undefined;
			swings = undefined;
			self.wawbf_kit = undefined;
			self.dmg = 0;
			continue;
		}
		if( self maps\_laststand::player_is_in_laststand() || ( IsDefined( self.intermission ) && self.intermission ) )
		{
			self.dmg = 0;
			continue;  // down (the game has given them its own pistol for now), or the game is over
		}
		if( IsDefined( self.wawbf_may_lie ) )
		{
			self.wawbf_may_lie = undefined;  // back on their feet (player_damage)
			self AllowProne( false );
		}
		if( level.wawbf_most_health > 0 && self.maxhealth != level.wawbf_most_health && IsAlive( self ) )
		{
			self.maxhealth = level.wawbf_most_health;
		}

		kit = level.wawbf_kit[want];
		first = self held( kit.first );
		second = self held( kit.second );
		// (A weapon that is in the Pack-a-Punch, or was left there, is not
		// one the game has taken away: it is not handed back.)
		if( want != have || ( !self HasWeapon( first ) && !IsDefined( self.wawbf_away[kit.first] ) ) )
		{
			self give_kit( kit );
			have = want;
			uses = undefined;
			swings = undefined;
		}
		self keep_full( first );
		self keep_full( second );

		// What is fitted to the weapon: its button changes to it, and back.
		if( kit.fitted && fit_pressed && !IsDefined( self.wawbf_hands ) && !IsDefined( level.wawbf_own_slot ) )
		{
			self thread change_fitted( first, second );
		}

		// A lightsaber cuts when Battlefront II's character swings it, and at
		// no other time: at the start of each swing, and again every so often
		// for as long as the swing lasts, for whatever has walked into it.
		if( !IsDefined( swings ) )
		{
			swings = swung;
		}
		fired = ( swung != swings );
		swings = swung;
		swung_for += 0.05;
		if( kit.saber && ( fired || ( swinging && swung_for >= level.wawbf_saber_again ) ) )
		{
			swung_for = 0;
			self saber_cut();
		}
		if( self GetCurrentWeapon() == self held( "swbf2_bowcaster" ) )
		{
			self bowcaster( fired, charge );
		}

		// The ability selected, and each use of it.
		ability = kit.abilities[place];
		if( place == 0 )
		{
			ability = kit.fallback;
		}
		self carry_grenades( IsDefined( ability ) && ability == "grenade" );
		if( !IsDefined( uses ) )
		{
			uses = used;
		}
		if( used != uses )
		{
			uses = used;
			if( IsDefined( ability ) )
			{
				self thread use_ability( ability );
			}
		}
		held_for += 0.05;
		if( in_use && IsDefined( ability ) && held_for >= 0.1 )
		{
			held_for = 0;
			self hold_ability( ability );
		}

		// What the bridge is told.
		current = self GetCurrentWeapon();
		if( current == first )
		{
			self.wawbf_hand = 1;
		}
		else if( IsDefined( second ) && current == second )
		{
			self.wawbf_hand = 2;
		}
		say = self.wawbf_hand;
		if( IsDefined( self.wawbf_hands ) )
		{
			say = 3;  // neither: the player's own hands are busy (hands, below)
		}
		else if( self.wawbf_away.size > 0 && current != first && ( !IsDefined( second ) || current != second ) )
		{
			say = 3;  // neither: they are empty, the weapon being in the Pack-a-Punch or lost to it
		}
		if( self ability_ready( ability ) )
		{
			say += 4;
		}
		overheated = false;
		if( kit.fitted && IsDefined( second ) && current == second )
		{
			overheated = self held_back();
		}
		else
		{
			self.wawbf_idle = 0;
		}
		if( current == first || ( IsDefined( second ) && current == second ) )
		{
			clip = self GetWeaponAmmoClip( current );
			if( ( clip == 0 && self GetWeaponAmmoStock( current ) == 0 ) || overheated )
			{
				say += 8;
			}
			if( IsDefined( level.wawbf_magazine[current] ) )
			{
				size = WeaponClipSize( current );
				if( size > 0 && size < 256 && clip < 256 )
				{
					say += 16 * clip + 4096 * size;
				}
			}
		}
		// From behind the character a shot has to be pointed at what the
		// middle of the screen shows, and the camera is not where the
		// player's eyes are. The bridge says where the line through the
		// middle of the screen runs; what it meets first is found here, and
		// how far along the line that is goes back to the bridge, which
		// points the shot there.
		far = self look_along( self.spawnflags );
		if( !kit.saber )
		{
			say += 1048576 * far;
		}
		self.dmg = say;
	}
}

// Changes between a weapon and what is fitted to it, whichever is in hand.
// If it is asked twice and nothing has come of it either time, the game will
// not have it done from a script, and its own button for it is put back to
// work for the rest of the game, what it shows on the screen and all.
change_fitted( first, second )
{
	self endon( "disconnect" );

	if( IsDefined( self.wawbf_changing ) )
	{
		return;
	}
	was = self GetCurrentWeapon();
	to = undefined;
	if( was == first && self HasWeapon( second ) )
	{
		to = second;
	}
	else if( was == second && self HasWeapon( first ) )
	{
		to = first;
	}
	if( !IsDefined( to ) )
	{
		return;
	}
	self.wawbf_changing = true;
	self SwitchToWeapon( to );
	wait( 1 );
	self.wawbf_changing = undefined;
	if( self GetCurrentWeapon() != was || IsDefined( self.wawbf_hands ) || !self HasWeapon( to ) )
	{
		self.wawbf_unchanged = 0;
		return;
	}
	self.wawbf_unchanged++;
	if( self.wawbf_unchanged >= 2 )
	{
		level.wawbf_own_slot = true;
		self SetActionSlot( 3, "altMode" );
	}
}

// The trigger is held and the weapon in hand is not firing, nor has been for
// a moment: the flamethrower has overheated. Battlefront II is then told the
// weapon has nothing to fire, as for an empty one, and lets go of its own
// trigger. Its flamethrower fires a burst for each pull and wants a new pull
// for the next, so without this a trigger held through this game's cooling
// off had this game burning again and Battlefront II, whose flame is the one
// seen, doing nothing; with it, Battlefront II's trigger is pulled afresh the
// moment this game's fire comes back. (Nothing is said until the weapon has
// been seen firing once: if the game ever answers "not firing" for a
// flamethrower that is, Battlefront II's is not to be stopped for good.)
held_back()
{
	if( !self AttackButtonPressed() )
	{
		self.wawbf_idle = 0;
		return false;
	}
	if( self IsFiring() )
	{
		self.wawbf_fires = true;
		self.wawbf_idle = 0;
		return false;
	}
	self.wawbf_idle += 0.05;
	return IsDefined( self.wawbf_fires ) && self.wawbf_idle >= 0.15;
}

// The line through the middle of the screen, from the bridge: where it
// crosses the plane through the player's eyes (to the right of them and
// above, in half units), and how its direction differs from the way they
// look (to the right and up, in eighths of a degree): 8 bits, 8, 7 and 7 from
// the low end, and a bit above them to say the number is there. Leaves
// self.wawbf_aim_at as the first thing on that line, or undefined when the
// view is through the player's eyes, and returns how far along the line it
// is, in steps of 2 units (0 for "not from behind").
//
// (The number is taken apart with whole numbers only. Divided as it stands
// it would first be made a fraction, which has not the room for all of it.)
look_along( line )
{
	self.wawbf_aim_at = undefined;
	if( !IsDefined( line ) || line < 1073741824 )
	{
		return 0;
	}
	side = line % 256;
	line = int( ( line - side ) / 256 );
	rise = line % 256;
	line = int( ( line - rise ) / 256 );
	turn = line % 128;
	line = int( ( line - turn ) / 128 );
	lift = line % 128;
	side = ( side - 128 ) * 0.5;
	rise = ( rise - 128 ) * 0.5;
	turn = ( turn - 64 ) * 0.125;
	lift = ( lift - 64 ) * 0.125;

	angles = self GetPlayerAngles();
	across = AnglesToRight( angles );
	above = AnglesToUp( angles );
	from = self GetEye() + across * side + above * rise;
	along = VectorNormalize( AnglesToForward( angles ) + across * ( sin( turn ) / cos( turn ) ) + above * ( sin( lift ) / cos( lift ) ) );
	trace = BulletTrace( from, from + along * 4000, true, self );
	self.wawbf_aim_at = trace["position"];

	far = int( Distance( from, trace["position"] ) / 2 );
	if( far < 1 )
	{
		far = 1;
	}
	if( far > 2047 )
	{
		far = 2047;
	}
	return far;
}

// The way something sent from the player's eyes has to go to land on what
// they are aiming at: the way they look, or from behind the character,
// towards what the middle of the screen shows.
aim_ahead()
{
	if( IsDefined( self.wawbf_aim_at ) )
	{
		away = self.wawbf_aim_at - self GetEye();
		if( Length( away ) > 8 )
		{
			return VectorNormalize( away );
		}
	}
	return AnglesToForward( self GetPlayerAngles() );
}

ability_ready( ability )
{
	if( !IsDefined( ability ) )
	{
		return false;
	}
	if( ability == "grenade" )
	{
		return self HasWeapon( "stielhandgranate" ) && self GetWeaponAmmoClip( "stielhandgranate" ) > 0;
	}
	if( ability == "rocket" )
	{
		return self.wawbf_rockets > 0;
	}
	return true;
}

keep_full( weapon )
{
	if( !IsDefined( weapon ) || !IsDefined( level.wawbf_endless[weapon] ) || !self HasWeapon( weapon ) )
	{
		return;
	}
	self GiveMaxAmmo( weapon );
	self SetWeaponAmmoClip( weapon, level.wawbf_endless[weapon] );
}

// The player holds grenades only while a grenade is the ability selected:
// the game throws one whenever its grenade button is pressed, and that
// button is the ability button whatever the ability. How many there are is
// kept while they are put away. (The game also hands everyone grenades at the
// start and after each round, whether they are holding any or not.)
carry_grenades( carry )
{
	have = self HasWeapon( "stielhandgranate" );
	if( have )
	{
		held = self GetWeaponAmmoClip( "stielhandgranate" );
		if( carry || held > self.wawbf_grenades )
		{
			self.wawbf_grenades = held;
		}
	}
	if( carry && !have )
	{
		self GiveWeapon( "stielhandgranate" );
		self SetWeaponAmmoClip( "stielhandgranate", self.wawbf_grenades );
	}
	else if( !carry && have )
	{
		self TakeWeapon( "stielhandgranate" );
	}
}

give_kit( kit )
{
	// What is left in the weapons being put down is there when they are
	// picked up again: changing character is not a way to fill them.
	weapons = self GetWeaponsListPrimaries();
	for( i = 0; i < weapons.size; i++ )
	{
		self.wawbf_clip[weapons[i]] = self GetWeaponAmmoClip( weapons[i] );
		self.wawbf_stock[weapons[i]] = self GetWeaponAmmoStock( weapons[i] );
	}
	self carry_grenades( false );

	self TakeAllWeapons();
	self.wawbf_away = [];  // a weapon left in the Pack-a-Punch comes back with the character, as it was
	self give_weapon( self held( kit.first ) );
	if( IsDefined( kit.second ) )
	{
		self give_weapon( self held( kit.second ) );
	}

	self SwitchToWeapon( self held( kit.first ) );
	// The game has a button of its own for changing to what is fitted to a
	// weapon, and back. It is given nothing to do: while it has that to do,
	// the game shows the fitted weapon at the bottom of the screen (for the
	// flamethrower a blank picture, a number that means nothing and the
	// button's name, which the user asked to be rid of), and on a PC nothing
	// hides that. The bridge says when the button is pressed instead, and the
	// change is made here (change_fitted, which goes back to the game's own
	// way if this one turns out not to work).
	if( IsDefined( level.wawbf_own_slot ) )
	{
		self SetActionSlot( 3, "altMode" );
	}
	else
	{
		self SetActionSlot( 3, "" );
	}
	self.wawbf_hand = 1;
	self.wawbf_bolts = undefined;
	self AllowProne( false );
	self AllowMelee( !kit.saber );  // a lightsaber is swung with fire, not the knife
	self AllowADS( !kit.saber );    // and is not aimed: that button works the Force
	self.wawbf_kit = kit;
}

// The weapon the player has for one of a kit's: the kit's own, or what
// Pack-a-Punch gave back for it.
held( weapon )
{
	if( !IsDefined( weapon ) || !IsDefined( self.wawbf_packed ) )
	{
		return weapon;
	}
	whole = weapon;
	if( IsDefined( level.wawbf_part_of[weapon] ) )
	{
		whole = level.wawbf_part_of[weapon];  // fitted to another: as that one is
	}
	if( IsDefined( self.wawbf_packed[whole] ) )
	{
		return weapon + "_upgraded";
	}
	return weapon;
}

// How much more a character's own blows count for once that weapon has been
// through Pack-a-Punch.
packed_times( weapon, times )
{
	if( IsDefined( self.wawbf_packed ) && IsDefined( self.wawbf_packed[weapon] ) )
	{
		return times;
	}
	return 1;
}

give_weapon( weapon )
{
	self GiveWeapon( weapon );
	if( IsDefined( self.wawbf_stock[weapon] ) )
	{
		self SetWeaponAmmoClip( weapon, self.wawbf_clip[weapon] );
		self SetWeaponAmmoStock( weapon, self.wawbf_stock[weapon] );
	}
	else
	{
		self GiveMaxAmmo( weapon );
	}
}

// ---------------------------------------------------------------------------
// Abilities
// ---------------------------------------------------------------------------

// Battlefront II's character has just used the ability selected.
use_ability( ability )
{
	self endon( "disconnect" );

	if( ability == "rocket" )
	{
		if( self.wawbf_rockets <= 0 )
		{
			return;
		}
		self.wawbf_rockets--;
		wait( level.wawbf_rocket_delay );
		eye = self GetEye();
		ahead = self aim_ahead();
		MagicBullet( "swbf2_launcher", eye + ahead * 40, eye + ahead * 6000, self );  // a kit weapon: hits as hard as they do
	}
	else if( ability == "throw" )
	{
		self throw_saber();
	}
	else if( ability == "push" )
	{
		ahead = AnglesToForward( self GetPlayerAngles() );
		zombies = self in_front( level.wawbf_push_reach, level.wawbf_push_arc, level.wawbf_push_most );
		for( i = 0; i < zombies.size; i++ )
		{
			self hurt( zombies[i], level.wawbf_push_damage, ahead * 160 + ( 0, 0, 70 ) );
		}
	}
	else if( ability == "pull" )
	{
		zombies = self in_front( level.wawbf_pull_reach, level.wawbf_pull_arc, level.wawbf_pull_most );
		for( i = 0; i < zombies.size; i++ )
		{
			here = ( self.origin[0] - zombies[i].origin[0], self.origin[1] - zombies[i].origin[1], 0 );
			hard = Length( here ) * level.wawbf_pull_throw_each;
			if( hard < level.wawbf_pull_throw_least )
			{
				hard = level.wawbf_pull_throw_least;
			}
			if( hard > level.wawbf_pull_throw_most )
			{
				hard = level.wawbf_pull_throw_most;
			}
			self hurt( zombies[i], level.wawbf_push_damage, VectorNormalize( here ) * hard + ( 0, 0, 70 ) );
		}
	}
}

// Battlefront II's character is using the ability selected, and has been for
// another tenth of a second.
hold_ability( ability )
{
	if( ability == "choke" )
	{
		zombies = self in_front( level.wawbf_choke_reach, level.wawbf_choke_arc, 1 );
		for( i = 0; i < zombies.size; i++ )
		{
			// What the choke kills, it kills by the head: always.
			if( zombies[i].health <= level.wawbf_choke_damage )
			{
				zombies[i] maps\_zombiemode_spawner::zombie_head_gib( self );
			}
			self hurt( zombies[i], level.wawbf_choke_damage, ( 0, 0, 40 ) );
		}
	}
	else if( ability == "lightning" )
	{
		damage = level.wawbf_lightning_damage;
		zombies = self in_front( level.wawbf_lightning_reach, level.wawbf_lightning_arc, level.wawbf_lightning_most );
		before = undefined;
		for( i = 0; i < zombies.size; i++ )
		{
			zombies[i] thread shock( before, i * level.wawbf_shock_apart );
			before = zombies[i];
			if( zombies[i].health <= damage && RandomInt( 100 ) < level.wawbf_shock_head )
			{
				zombies[i] maps\_zombiemode_spawner::zombie_head_gib( self );
			}
			self hurt( zombies[i], damage, undefined );
		}
	}
}

// What Force lightning looks and sounds like on the zombie it strikes: what
// the Wunderwaffe's shot does when it lands (the game's own
// maps\_zombiemode_tesla.gsc), without the Wunderwaffe. Sparks over the body
// and in the eyes and the crack of it; from the second zombie on, the bolt
// that jumps there from the one before, with its own sound. A zombie the
// lightning stays on shows it again every so often, not every tenth of a
// second. Runs on the zombie, which may be dead by the time it is its turn.
shock( before, after )
{
	now = GetTime();
	if( IsDefined( self.wawbf_shocked ) && now - self.wawbf_shocked < level.wawbf_shock_again )
	{
		return;
	}
	self.wawbf_shocked = now;
	if( after > 0 )
	{
		wait( after );
	}
	if( !IsDefined( self ) )
	{
		return;
	}

	sparks = level.wawbf_fx_shock;
	if( IsDefined( before ) )
	{
		sparks = level.wawbf_fx_shock_next;
		level thread shock_bolt( before, self );
	}
	PlayFxOnTag( sparks, self, "J_SpineUpper" );
	if( !IsDefined( self.head_gibbed ) || !self.head_gibbed )
	{
		PlayFxOnTag( level.wawbf_fx_shock_eyes, self, "J_Eyeball_LE" );
	}
	self PlaySound( "imp_tesla" );
}

shock_bolt( from, to )
{
	if( !IsDefined( from ) || !IsDefined( to ) )
	{
		return;
	}
	here = from GetTagOrigin( "J_SpineUpper" );
	there = to GetTagOrigin( "J_SpineUpper" );
	if( DistanceSquared( here, there ) < level.wawbf_shock_bolt_least * level.wawbf_shock_bolt_least )
	{
		return;
	}
	bolt = Spawn( "script_model", here );
	bolt SetModel( "tag_origin" );
	PlayFxOnTag( level.wawbf_fx_shock_bolt, bolt, "tag_origin" );
	PlaySoundAtPosition( "tesla_bounce", here );
	bolt MoveTo( there, level.wawbf_shock_bolt_time );
	bolt waittill( "movedone" );
	bolt Delete();
}

// The zombies in front of the player: within reach, inside the arc, with
// nothing solid in the way; nearest first, and no more than `most`.
in_front( reach, arc, most )
{
	eye = self GetEye();
	ahead = AnglesToForward( self GetPlayerAngles() );

	found = [];
	zombies = GetAiArray( "axis" );
	for( i = 0; i < zombies.size; i++ )
	{
		zombie = zombies[i];
		if( !IsDefined( zombie ) || !IsAlive( zombie ) )
		{
			continue;
		}
		middle = zombie.origin + ( 0, 0, 40 );
		away = middle - eye;
		far = Length( away );
		if( far > reach )
		{
			continue;
		}
		if( far > 30 && VectorDot( ahead, VectorNormalize( away ) ) < arc )
		{
			continue;
		}
		if( !BulletTracePassed( eye, middle, false, undefined ) )
		{
			continue;
		}
		zombie.wawbf_far = far;
		found[found.size] = zombie;
	}

	for( i = 0; i < found.size; i++ )
	{
		for( j = i + 1; j < found.size; j++ )
		{
			if( found[j].wawbf_far < found[i].wawbf_far )
			{
				nearer = found[j];
				found[j] = found[i];
				found[i] = nearer;
			}
		}
	}
	if( found.size <= most )
	{
		return found;
	}
	nearest = [];
	for( i = 0; i < most; i++ )
	{
		nearest[i] = found[i];
	}
	return nearest;
}

// Hurts a zombie in the player's name. One that dies of it is thrown, if
// there is a way to throw it.
hurt( zombie, damage, thrown )
{
	if( !IsDefined( zombie ) || !IsAlive( zombie ) )
	{
		return;
	}
	if( IsDefined( thrown ) && zombie.health <= damage )
	{
		zombie StartRagdoll();
		zombie LaunchRagdoll( thrown );
	}
	zombie DoDamage( damage, zombie.origin, self );
}

// A thrown lightsaber: out along where the player looks, as far as the first
// wall, cutting down whatever is close to its path as it gets there.
throw_saber()
{
	eye = self GetEye();
	ahead = AnglesToForward( self GetPlayerAngles() );
	trace = BulletTrace( eye, eye + ahead * level.wawbf_throw_reach, false, self );
	reach = Distance( eye, trace["position"] );

	zombies = GetAiArray( "axis" );
	for( i = 0; i < zombies.size; i++ )
	{
		zombie = zombies[i];
		if( !IsDefined( zombie ) || !IsAlive( zombie ) )
		{
			continue;
		}
		away = zombie.origin + ( 0, 0, 40 ) - eye;
		along = VectorDot( away, ahead );
		if( along < 0 || along > reach + level.wawbf_throw_width )
		{
			continue;
		}
		if( Length( away - ahead * along ) > level.wawbf_throw_width )
		{
			continue;
		}
		self thread cut_down_after( zombie, along / level.wawbf_throw_speed );
	}
}

cut_down_after( zombie, seconds )
{
	if( seconds > 0.05 )
	{
		wait( seconds );
	}
	if( IsDefined( zombie ) && IsAlive( zombie ) )
	{
		zombie thread saber_gib( self );
		zombie DoDamage( zombie.health + 666, zombie.origin, self );
	}
}

// ---------------------------------------------------------------------------
// The lightsaber
// ---------------------------------------------------------------------------

// A lightsaber is swung, not aimed. A swing cuts down every zombie within the
// blade's reach that is in front of the player or to either side, and that
// nothing solid stands in front of.
//
// The swing is Battlefront II's: the bridge says when its character starts
// one and while one lasts (follow_kit). The weapon in the player's hands here
// is only a name on the screen. It was first made to do the cutting itself,
// each time it fired, but it fires for as long as its trigger is held and
// Battlefront II swings once for each pull, so zombies fell to a blade that
// was not moving.
saber_cut()
{
	eye = self GetEye();
	angles = self GetPlayerAngles();
	facing = AnglesToForward( ( 0, angles[1], 0 ) );
	reach = level.wawbf_saber_reach;

	zombies = GetAiArray( "axis" );
	for( i = 0; i < zombies.size; i++ )
	{
		zombie = zombies[i];
		if( !IsDefined( zombie ) || !IsAlive( zombie ) )
		{
			continue;
		}
		away = zombie.origin - self.origin;
		if( abs( away[2] ) > level.wawbf_saber_height )
		{
			continue;
		}
		away = ( away[0], away[1], 0 );
		if( Length( away ) > reach )
		{
			continue;
		}
		// One standing on the player is in the arc whichever way they face.
		if( Length( away ) > 24 && VectorDot( facing, VectorNormalize( away ) ) < level.wawbf_saber_arc )
		{
			continue;
		}
		if( !BulletTracePassed( eye, zombie.origin + ( 0, 0, 50 ), false, undefined ) && !BulletTracePassed( eye, zombie.origin + ( 0, 0, 20 ), false, undefined ) )
		{
			continue;
		}
		// One blow kills, whatever the round, and takes something off.
		zombie thread saber_gib( self );
		zombie DoDamage( zombie.health + 666, zombie.origin, self );
	}
}

// What a lightsaber takes off the zombie it kills: an arm, a leg, both legs,
// the middle, or the head, by chance. The game does this itself for a zombie
// killed by enough firepower, but by its own rules (three times in four, not
// too soon after the last, and never for a hurt that comes from a script, as
// this one does), and it makes its choice afresh as the zombie dies. So it is
// done here, by the game's own routines, while the zombie is still standing:
// one that has already lost something is then left as it is when it falls.
// On its own thread: if the game objects to any of it, that is all that stops.
saber_gib( player )
{
	if( !IsDefined( self ) || !IsAlive( self ) || !IsDefined( self.a ) )
	{
		return;
	}
	if( IsDefined( self.gibbed ) && self.gibbed )
	{
		return;
	}
	refs = [];
	refs[refs.size] = "head";
	refs[refs.size] = "right_arm";
	refs[refs.size] = "left_arm";
	refs[refs.size] = "guts";
	refs[refs.size] = "no_legs";
	refs[refs.size] = "right_leg";
	refs[refs.size] = "left_leg";
	ref = refs[RandomInt( refs.size )];
	if( ref == "head" )
	{
		self maps\_zombiemode_spawner::zombie_head_gib( player );
		return;
	}
	self.a.gib_ref = ref;
	self thread animscripts\death::do_gib();
}

// ---------------------------------------------------------------------------
// The bowcaster
// ---------------------------------------------------------------------------

// In Battlefront II the bowcaster charges while the trigger is held and fires
// when it is let go. No weapon of this game's does that, so the one in the
// player's hands only stands for it: it has the magazine, the reload and the
// name on the screen, and its own shot reaches nothing. The shots that count
// are Battlefront II's. The bridge says when its bowcaster has fired and how
// far it had been charged, and the shot is worked out here: each bolt is a
// line from the player's eye, and hurts what it meets. Nothing is drawn for
// them; the bolts on screen are Battlefront II's.
//
// The rounds are counted here too, as Battlefront II counts them: one for
// each bolt of a fan (so a fan is seven, or what is left if that is less,
// the middle of the fan first as there), one for the heavy bolt. Pulling the
// trigger fires this game's stand-in as well, which takes a round of its own;
// that is put back.
bowcaster( fired, charge )
{
	weapon = self held( "swbf2_bowcaster" );
	clip = self GetWeaponAmmoClip( weapon );
	if( !IsDefined( self.wawbf_bolts ) || clip > self.wawbf_bolts )
	{
		self.wawbf_bolts = clip;  // just handed over, or reloaded
	}

	if( fired && self.wawbf_bolts > 0 )
	{
		times = level.wawbf_gun_damage * self packed_times( "swbf2_bowcaster", level.wawbf_pack_damage );
		eye = self GetEye();
		angles = VectorToAngles( self aim_ahead() );
		if( charge >= level.wawbf_bowcaster_full )
		{
			self.wawbf_bolts--;
			self bolt( eye, AnglesToForward( angles ), level.wawbf_bowcaster_slug * times, level.wawbf_bowcaster_through );
		}
		else
		{
			bolts = level.wawbf_bowcaster_bolts;
			if( bolts > self.wawbf_bolts )
			{
				bolts = self.wawbf_bolts;
			}
			self.wawbf_bolts -= bolts;
			// 0, then one step to the left, one to the right, two to the left ...
			for( i = 0; i < bolts; i++ )
			{
				across = int( ( i + 1 ) / 2 );
				if( i % 2 == 1 )
				{
					across *= -1;
				}
				self bolt( eye, AnglesToForward( ( angles[0], angles[1] + across * level.wawbf_bowcaster_fan, 0 ) ), level.wawbf_bowcaster_bolt * ( 1 + charge ) * times, 1 );
			}
		}
	}

	if( clip != self.wawbf_bolts )
	{
		self SetWeaponAmmoClip( weapon, self.wawbf_bolts );
	}
}
// One bolt: hurts the first `through` zombies on its line.
bolt( from, ahead, damage, through )
{
	end = from + ahead * 8000;
	ignore = self;
	for( hit = 0; hit < through; hit++ )
	{
		trace = BulletTrace( from, end, true, ignore );
		victim = trace["entity"];
		if( !IsDefined( victim ) || !IsAlive( victim ) || IsPlayer( victim ) )
		{
			return;
		}
		victim DoDamage( damage, trace["position"], self );
		ignore = victim;
		from = trace["position"] + ahead * 4;
	}
}

// ---------------------------------------------------------------------------
// The shops
// ---------------------------------------------------------------------------

// The character keeps its own weapons, so nothing in the map hands out any:
// the outlines on the walls sell ammunition for whatever the player is
// carrying, the mystery box is where a weapon is Pack-a-Punched, and the
// weapon cabinet sells Quick Revive. (The box and the cabinet are part of the
// map as it was built, not things a script can take away, so they stay as
// they look and it is what they do that changes.) build.ps1 has the game's own
// weapons script call this in place of setting up its shops.
shops()
{
	walls = GetEntArray( "weapon_upgrade", "targetname" );
	for( i = 0; i < walls.size; i++ )
	{
		walls[i] SetHintString( "Press & hold &&1 to buy Ammo [Cost: " + level.wawbf_ammo_cost + "]" );
		walls[i] SetCursorHint( "HINT_NOICON" );
		walls[i] UseTriggerRequireLookAt();
		walls[i] thread sell_ammo();

		// The weapon that hangs there once it has been bought.
		if( IsDefined( walls[i].target ) )
		{
			model = GetEnt( walls[i].target, "targetname" );
			if( IsDefined( model ) )
			{
				model Hide();
			}
		}
	}

	cabinets = GetEntArray( "weapon_cabinet_use", "targetname" );
	for( i = 0; i < cabinets.size; i++ )
	{
		cabinets[i] SetHintString( "Press & hold &&1 to buy Quick Revive [Cost: " + level.wawbf_revive_cost + "]" );
		cabinets[i] SetCursorHint( "HINT_NOICON" );
		cabinets[i] UseTriggerRequireLookAt();
		cabinets[i] thread quick_revive();
	}
	// The rifles that hang in the cabinet: it does not sell them any more.
	rifles = GetEntArray( "script_model", "classname" );
	for( i = 0; i < rifles.size; i++ )
	{
		if( IsDefined( rifles[i].model ) && rifles[i].model == "weapon_mp_kar98_scoped_rifle" )
		{
			rifles[i] Hide();
		}
	}

	boxes = GetEntArray( "treasure_chest_use", "targetname" );
	for( i = 0; i < boxes.size; i++ )
	{
		boxes[i] SetHintString( "Press & hold &&1 to Pack-a-Punch the weapon in your hands [Cost: " + level.wawbf_pack_cost + "]" );
		boxes[i] SetCursorHint( "HINT_NOICON" );
		boxes[i] thread pack_a_punch();
	}
}

// ---------------------------------------------------------------------------
// Power-ups
// ---------------------------------------------------------------------------

// This map's power-ups look and sound in the world as the later maps' do
// already. What those have and this had not is on the screen and in the air:
// a picture at the bottom of the screen for as long as double points or
// insta-kill lasts, in place of a line of text with a number counting down,
// and a voice that says which was picked up. build.ps1 takes the text out of
// the game's own power-up script and has it call announce(); the pictures are
// drawn from here, off the same numbers that script keeps.
powerup_icons()
{
	icons = [];
	for( i = 0; i < 2; i++ )
	{
		icons[i] = NewHudElem();
		icons[i].foreground = true;
		icons[i].sort = 2;
		icons[i].hidewheninmenu = false;
		icons[i].alignX = "center";
		icons[i].alignY = "top";
		icons[i].horzAlign = "center";
		icons[i].vertAlign = "top";
		icons[i].x = 0;
		icons[i].y = level.wawbf_powerup_icons_y;
		icons[i].alpha = 0;
	}
	icons[0] SetShader( "specialty_doublepoints_zombies", 32, 32 );
	icons[1] SetShader( "specialty_instakill_zombies", 32, 32 );

	on = [];
	left = [];
	blink = 0;
	for( ;; )
	{
		wait( 0.1 );
		blink++;

		on[0] = level.zombie_vars["zombie_powerup_point_doubler_on"];
		left[0] = level.zombie_vars["zombie_powerup_point_doubler_time"];
		on[1] = level.zombie_vars["zombie_powerup_insta_kill_on"];
		left[1] = level.zombie_vars["zombie_powerup_insta_kill_time"];

		// Side by side when both are running. (At the top of the screen, in
		// the middle, where the later maps have them at the bottom of it:
		// Battlefront II's picture is drawn over everything, and at the
		// bottom there is its character seen from behind, or its weapon seen
		// through the eyes.)
		if( on[0] && on[1] )
		{
			icons[0].x = -24;
			icons[1].x = 24;
		}
		else
		{
			icons[0].x = 0;
			icons[1].x = 0;
		}
		for( i = 0; i < 2; i++ )
		{
			shown = on[i];
			// Flashing for the last ten seconds, faster for the last five.
			if( shown && left[i] < 5 )
			{
				shown = ( blink % 2 == 0 );
			}
			else if( shown && left[i] < 10 )
			{
				shown = ( blink % 4 < 2 );
			}
			if( shown )
			{
				icons[i].alpha = 1;
			}
			else
			{
				icons[i].alpha = 0;
			}
		}
	}
}

// The voice that says which power-up it was: one at a time, as the later
// maps have it.
announce( sound, after )
{
	if( IsDefined( after ) )
	{
		wait( after );
	}
	if( IsDefined( level.wawbf_announcing ) && level.wawbf_announcing )
	{
		return;
	}
	level.wawbf_announcing = true;
	voice = Spawn( "script_origin", ( 0, 0, 0 ) );
	voice PlaySound( sound );
	wait( 2.5 );
	voice Delete();
	level.wawbf_announcing = false;
}

// ---------------------------------------------------------------------------
// Pack-a-Punch
// ---------------------------------------------------------------------------

// Where the mystery box is, which has nothing to hand out here, a
// Pack-a-Punch machine takes the weapon in the player's hands and gives it
// back better: the kit's own weapon swapped for its second form (build.ps1
// makes one for each), which the character then has for the rest of the game,
// whoever else they play as in between. Not a lightsaber.
//
// The machine is the game's own from the map that has one (build.ps1 brings
// the model in), stood over the box and facing as the box does, so that it is
// used from the same place looking the same way. The box itself is part of
// the map as it was built and cannot be taken away; the machine is wider one
// way and narrower the other, so the box's two ends show at its feet. Its lid
// is the map's to move and a script's to hide. The show is that map's too:
// the weapon goes in, the sparks, the two sounds.
pack_a_punch()
{
	lid = undefined;
	inside = undefined;
	spot = self.origin;
	out = ( 0, 0, 0 );
	if( IsDefined( self.target ) )
	{
		lid = GetEnt( self.target, "targetname" );
	}
	if( IsDefined( lid ) && IsDefined( lid.target ) )
	{
		inside = GetEnt( lid.target, "targetname" );
	}
	wait( 1 );  // the map is still being set up when this is started

	machine = undefined;
	if( IsDefined( inside ) )
	{
		out = AnglesToForward( inside.angles );  // out of the box, towards whoever is using it
		// The lid's place is the top of the box at the back; the place inside
		// it is its middle.
		machine = Spawn( "script_model", ( inside.origin[0], inside.origin[1], lid.origin[2] - level.wawbf_box_height ) );
		machine.angles = ( 0, inside.angles[1] + 90, 0 );  // the machine's front is to its right
		machine SetModel( "zombie_vending_packapunch_on" );
		lid Hide();
		spot = machine.origin + ( 0, 0, 35 );  // where a weapon goes into it
		// 86 units wide, 50 deep, 86 high: three blocks along it. And the
		// box's "use" place, which this is, moved out to just in front of them.
		reach = stand_solid( machine.origin + out * 2, ( out[1], out[0] * -1, 0 ), out, 3, 20, 23, 86 );
		in_front = machine.origin + out * ( 2 + reach + level.wawbf_use_clear );
		self.origin = ( in_front[0], in_front[1], self.origin[2] );
		level thread solid_check( "pack", machine.origin + out * 90 + ( 0, 0, 2 ), machine.origin + ( 0, 0, 2 ) );
	}

	for( ;; )
	{
		self waittill( "trigger", player );

		if( !maps\_zombiemode_utility::is_player_valid( player ) || player maps\_zombiemode_utility::in_revive_trigger() )
		{
			wait( 0.5 );
			continue;
		}
		weapon = player packable();
		if( !IsDefined( weapon ) || player.score < level.wawbf_pack_cost )
		{
			self PlaySound( "no_cha_ching" );
			wait( 0.5 );
			continue;
		}
		player maps\_zombiemode_score::minus_to_player_score( level.wawbf_pack_cost );
		player PlaySound( "cha_ching" );
		self trigger_off();

		// In from in front of the machine, lying across it; then out again.
		// The player cracks their knuckles meanwhile.
		// The weapon is the machine's now, not the player's: it is out of
		// their hands until they take it back. With another weapon of their
		// character's they are left holding that one, and cannot put it
		// away; with none, they have nothing in their hands.
		other = player other_weapon( weapon );
		player.wawbf_away[weapon] = "in";
		player.wawbf_locked = true;
		player TakeWeapon( weapon );
		fitted = player fitted_to( weapon );
		if( IsDefined( fitted ) && player HasWeapon( fitted ) )
		{
			player TakeWeapon( fitted );  // what is fitted to it goes in with it
		}
		player thread hands( level.wawbf_hands_pack, other );
		PlaySoundAtPosition( "mx_packa_sting", spot );
		gun = Spawn( "script_model", spot + out * 25 );
		gun.angles = ( 0, player.angles[1], 0 );
		gun SetModel( GetWeaponModel( weapon ) );
		if( IsDefined( machine ) )
		{
			gun RotateTo( machine.angles, 0.35, 0, 0 );
			PlayFX( level.wawbf_fx_pack, machine.origin + ( 0, 0, 1 ), out * -1 );
		}
		wait( 0.5 );
		gun MoveTo( spot, 0.5, 0, 0 );
		PlaySoundAtPosition( "packa_weap_upgrade", spot );
		wait( 0.5 );
		gun Hide();

		wait( level.wawbf_pack_time );

		// Out it comes, to be taken; and slides slowly back in as the time
		// to take it runs out.
		PlaySoundAtPosition( "packa_weap_ready", spot );
		gun Show();
		gun MoveTo( spot + out * 25, 0.5, 0, 0 );
		wait( 0.5 );
		gun MoveTo( spot, level.wawbf_pack_wait, 0, 0 );
		self SetHintString( "Press & hold &&1 to take your weapon" );
		self trigger_on();
		taken = self taken_by( player, level.wawbf_pack_wait );
		self trigger_off();
		gun Delete();
		if( IsDefined( player ) )
		{
			player.wawbf_locked = undefined;
			player EnableWeaponCycling();
			if( taken )
			{
				player pack( weapon );
			}
			else
			{
				// Left in there: gone, until the character is changed or a wall
				// is paid to fill everything up, which hand it back as it was.
				player.wawbf_away[weapon] = "lost";
			}
		}
		wait( 1 );
		self SetHintString( "Press & hold &&1 to Pack-a-Punch the weapon in your hands [Cost: " + level.wawbf_pack_cost + "]" );
		self trigger_on();
	}
}

// Waits for `player` to use this (anyone else's use counts for nothing), for
// `seconds` at most. True if they did.
taken_by( player, seconds )
{
	self thread time_is_up( seconds );
	for( ;; )
	{
		self waittill( "trigger", who );
		if( who == level )
		{
			return false;
		}
		if( IsDefined( player ) && who == player )
		{
			self notify( "wawbf_taken" );
			return true;
		}
	}
}

time_is_up( seconds )
{
	self endon( "wawbf_taken" );

	wait( seconds );
	self notify( "trigger", level );
}

// The other of the character's two weapons, as the player holds it, if they
// have one. (Not one that is fitted to the first: that is the same weapon.)
other_weapon( weapon )
{
	kit = self.wawbf_kit;
	if( !IsDefined( kit ) || !IsDefined( kit.second ) || kit.fitted )
	{
		return undefined;
	}
	other = kit.first;
	if( weapon == kit.first )
	{
		other = kit.second;
	}
	other = self held( other );
	if( !self HasWeapon( other ) )
	{
		return undefined;
	}
	return other;
}

// The weapon in the player's hands, if it is one of their character's own
// that Pack-a-Punch has a second form of (so not a lightsaber) and has not
// been through yet.
packable()
{
	kit = self.wawbf_kit;
	if( !IsDefined( kit ) || kit.saber || self IsSwitchingWeapons() || self IsThrowingGrenade() )
	{
		return undefined;
	}
	current = self GetCurrentWeapon();
	if( current == kit.first && can_be_packed( kit.first ) )
	{
		return kit.first;
	}
	if( IsDefined( kit.second ) && current == kit.second )
	{
		if( kit.fitted && can_be_packed( kit.first ) )
		{
			return kit.first;  // what it is fitted to: the two are one weapon
		}
		if( !kit.fitted && can_be_packed( kit.second ) )
		{
			return kit.second;
		}
	}
	return undefined;
}

// What is fitted to this weapon of the character's, if anything is: it goes
// where the weapon goes.
fitted_to( weapon )
{
	kit = self.wawbf_kit;
	if( IsDefined( kit ) && kit.fitted && weapon == kit.first )
	{
		return kit.second;
	}
	return undefined;
}

// The player takes their weapon back out of the machine, in its second form,
// and it goes straight into their hands.
pack( weapon )
{
	self.wawbf_packed[weapon] = true;
	self.wawbf_away[weapon] = undefined;
	kit = self.wawbf_kit;
	if( !IsDefined( kit ) || ( kit.first != weapon && ( !IsDefined( kit.second ) || kit.second != weapon ) ) )
	{
		return;  // playing someone else by now: it is waiting for when they come back
	}
	packed = weapon + "_upgraded";
	fitted = self fitted_to( weapon );
	if( self HasWeapon( weapon ) )
	{
		self TakeWeapon( weapon );  // handed back as it was in the meantime (the character was changed and changed back)
	}
	if( IsDefined( fitted ) && self HasWeapon( fitted ) )
	{
		self TakeWeapon( fitted );
	}
	self GiveWeapon( packed );
	self GiveMaxAmmo( packed );
	if( IsDefined( fitted ) )
	{
		self GiveWeapon( fitted + "_upgraded" );  // what is fitted to it comes back better too
	}
	self SwitchToWeapon( packed );
	self.wawbf_bolts = undefined;
}

// A weapon left in the Pack-a-Punch too long, handed back as it was. True if
// there was one.
recover( weapon )
{
	if( !IsDefined( weapon ) || !IsDefined( self.wawbf_away[weapon] ) || self.wawbf_away[weapon] != "lost" )
	{
		return false;
	}
	self.wawbf_away[weapon] = undefined;
	back = self held( weapon );
	self GiveWeapon( back );
	self GiveMaxAmmo( back );
	fitted = self fitted_to( weapon );
	if( IsDefined( fitted ) )
	{
		self GiveWeapon( self held( fitted ) );
	}
	self SwitchToWeapon( back );
	return true;
}

// ---------------------------------------------------------------------------
// Quick Revive
// ---------------------------------------------------------------------------

// A Quick Revive machine sells it, the game's own from the later maps
// (build.ps1 brings the model in). The user wanted it where the weapon cabinet
// is; the cabinet is part of the map as it was built and cannot be taken
// away, and the machine is too small to stand over it and hide it, so it
// stands where they pointed instead: against the pillar that faces the
// cabinet across the room, looking back at it. What is used to buy from it is
// the cabinet's own "use" place, moved there. (If the pillar is not found,
// the cabinet sells it where it stands, and its doors open the first time as
// they did for the rifle.)
quick_revive()
{
	wait( 1 );  // the map is still being set up when this is started
	machine = self stand_revive();
	opened = IsDefined( machine );
	for( ;; )
	{
		self waittill( "trigger", player );

		if( !maps\_zombiemode_utility::is_player_valid( player ) || player maps\_zombiemode_utility::in_revive_trigger() )
		{
			wait( 0.5 );
			continue;
		}
		if( player.wawbf_revives > 0 || player.wawbf_revives_bought >= level.wawbf_revive_most || player.score < level.wawbf_revive_cost )
		{
			self PlaySound( "no_cha_ching" );
			wait( 0.5 );
			continue;
		}
		player maps\_zombiemode_score::minus_to_player_score( level.wawbf_revive_cost );
		player PlaySound( "cha_ching" );
		PlaySoundAtPosition( "mx_revive_sting", self.origin );
		if( !opened && IsDefined( self.target ) )
		{
			opened = true;
			doors = GetEntArray( self.target, "targetname" );
			for( i = 0; i < doors.size; i++ )
			{
				if( doors[i].model == "dest_test_cabinet_ldoor_dmg0" )
				{
					doors[i] RotateYaw( 120, 0.3, 0.2, 0.1 );
				}
				else if( doors[i].model == "dest_test_cabinet_rdoor_dmg0" )
				{
					doors[i] RotateYaw( -120, 0.3, 0.2, 0.1 );
				}
			}
		}
		player.wawbf_revives_bought++;
		player hands( level.wawbf_hands_revive );  // they drink it; this waits for them
		if( IsDefined( player ) )
		{
			player.wawbf_revives = 1;
			player SetPerk( "specialty_quickrevive" );  // with others playing: gets them up in half the time
			player revive_icon( true );
		}
		wait( 0.5 );
	}
}

// Stands the machine against the pillar opposite the cabinet and moves the
// cabinet's "use" place (self) to it. Where the pillar is, is looked for: from
// the front of the cabinet, lines are followed straight out across the room,
// a hand's width apart, and the ones stopped soonest, all at the same
// distance and by something that faces back this way, have found its face.
// The machine goes at the middle of that face. Returns the machine, or
// undefined if nothing that could be the pillar was there.
stand_revive()
{
	if( !IsDefined( self.target ) )
	{
		return undefined;
	}
	doors = GetEntArray( self.target, "targetname" );
	if( doors.size < 2 )
	{
		return undefined;
	}
	// The cabinet's front: the middle of it is between its two doors, and it
	// faces square to the line through them, on the side its "use" place is.
	middle = ( doors[0].origin + doors[1].origin ) * 0.5;
	along = VectorNormalize( ( doors[1].origin[0] - doors[0].origin[0], doors[1].origin[1] - doors[0].origin[1], 0 ) );
	face = ( along[1], along[0] * -1, 0 );
	if( VectorDot( face, self.origin - middle ) < 0 )
	{
		face = face * -1;
	}
	height = ( 0, 0, self.origin[2] - middle[2] );  // the "use" place is at about the middle of the cabinet's height

	nearest = level.wawbf_revive_look;
	found = [];
	for( aside = level.wawbf_revive_aside * -1; aside <= level.wawbf_revive_aside; aside += 6 )
	{
		from = middle + height + face * 24 + along * aside;
		trace = BulletTrace( from, from + face * level.wawbf_revive_look, false, undefined );
		far = Distance( from, trace["position"] );
		if( trace["fraction"] >= 1 || far < 80 || VectorDot( trace["normal"], face ) > -0.7 )
		{
			continue;
		}
		spot = SpawnStruct();
		spot.far = far;
		spot.aside = aside;
		spot.at = trace["position"];
		found[found.size] = spot;
		if( far < nearest )
		{
			nearest = far;
		}
	}
	first = undefined;
	last = undefined;
	wide = 0;
	for( i = 0; i < found.size; i++ )
	{
		if( found[i].far < nearest + 4 )
		{
			if( !IsDefined( first ) )
			{
				first = found[i];
			}
			last = found[i];
			wide++;
		}
	}
	if( wide < 3 )
	{
		return undefined;  // nothing, or something too narrow to stand a machine against
	}
	at = ( first.at + last.at ) * 0.5;

	// Down to the floor from just in front of the face.
	floor = BulletTrace( at - face * 20, at - face * 20 - ( 0, 0, 200 ), false, undefined );
	machine = Spawn( "script_model", ( at[0], at[1], floor["position"][2] ) - face * 12.5 );  // its back is 12 from its middle
	machine.angles = VectorToAngles( face ) - ( 0, 90, 0 );  // its front, which is to its right, looks back at the cabinet
	machine SetModel( "zombie_vending_revive_on" );
	// 49 units wide, 36 deep (more of it in front of its middle than behind),
	// 86 high: two blocks side by side.
	reach = stand_solid( machine.origin - face * 6, ( face[1], face[0] * -1, 0 ), face * -1, 2, 12, 19, 86 );
	level thread solid_check( "revive", machine.origin - face * 90 + ( 0, 0, 2 ), machine.origin + ( 0, 0, 2 ) );

	// The cabinet's "use" place, moved to just in front of the blocks.
	self.origin = machine.origin - face * ( 6 + reach + level.wawbf_use_clear ) + ( 0, 0, 45 );
	return machine;
}

// Something a script has stood in the map is only a picture: there is nothing
// to walk into. What the map's own furniture is walked into is worked out
// when the map is built, and a model made by a script has none of it: the
// game stops a player at such a model only where the model's own file says
// to, and these machines' files say nowhere here.
//
// But the game also stops whatever moves at the box round any entity that is
// not a model and whose "contents" say solid, and a script can make one of
// those: a trigger (the kind that is a box of a given width and height, with
// no shape drawn), told that what it holds is solid instead of "a trigger".
// From then on it is a block: players, zombies and shots stop at it as they do
// at a wall, and it sets nothing off.
//
// A block is square and stands square to the map, whichever way the thing it
// is for faces, so a thing that is long one way gets a row of them: `blocks`
// of them, each `half` to either side of its middle, spread `spread` apart
// along `across`.
//
// (Tried before this. Putting a player found inside the thing back outside
// it, twenty times a second: they bounced off it, and could be put through a
// wall. And a model with nothing to draw, its box and contents filled in from
// outside by the bridge: the game does not look at a model's box at all.)
//
// Returns how far in front of `middle` the row reaches, `front` being the way
// the thing faces. What the thing is used by has to be further out than
// that: the game offers a player something to use only if it can see the
// middle of it from their eyes, and a block is as good as a wall for hiding
// it. (Both machines' "use" places were inside their blocks at first, and
// neither could be used.)
stand_solid( middle, across, front, blocks, spread, half, tall )
{
	reach = 0;
	for( i = 0; i < blocks; i++ )
	{
		at = middle + across * ( ( i - ( blocks - 1 ) * 0.5 ) * spread );
		block = Spawn( "trigger_radius", at, 0, half, tall );
		block SetContents( 1 );  // solid, and no longer a trigger
		out = VectorDot( at - middle, front ) + half * ( abs( front[0] ) + abs( front[1] ) );
		if( out > reach )
		{
			reach = out;
		}
	}
	return reach;
}

// Says, in a setting of this mod's own (wawbf_solid_<name>, which the console
// shows when its name is typed), how far something the size of a player gets
// going from `from` towards `to`, times 1000, plus how far it is: the first
// less than the second by about the thing's half depth and the player's own,
// when the thing is solid.
solid_check( name, from, to )
{
	wait( 12 );
	stopped = PlayerPhysicsTrace( from, to );
	SetDvar( "wawbf_solid_" + name, int( Distance( from, stopped ) ) * 1000 + int( Distance( from, to ) ) );
}

// The player's own hands, World at War's, are busy for a moment with
// something Battlefront II has no picture of: drinking what a perk machine
// hands over, cracking their knuckles while the Pack-a-Punch works. The game
// does these as weapons whose only use is to be taken in hand (the taking is
// the drinking); the bridge is told "neither weapon" meanwhile (follow_kit),
// shows this game's hands in place of Battlefront II's picture as it does for
// the knife, and keeps Battlefront II from firing. Waits until it is over.
//
// Afterwards the player is holding `then`, if that is given and they have
// it, or else what they were holding before.
hands( weapon, then )
{
	self endon( "disconnect" );

	back = self GetCurrentWeapon();
	if( IsDefined( then ) )
	{
		back = then;
	}
	self.wawbf_hands = weapon;
	self DisableOffhandWeapons();
	self DisableWeaponCycling();
	self AllowSprint( false );
	self GiveWeapon( weapon );
	self SwitchToWeapon( weapon );

	self thread hands_too_long( 6 );
	self waittill_any( "fake_death", "death", "player_downed", "weapon_change_complete", "wawbf_hands_up" );
	self notify( "wawbf_hands_done" );

	self EnableOffhandWeapons();
	if( !IsDefined( self.wawbf_locked ) )
	{
		self EnableWeaponCycling();  // (not while their weapon is in the Pack-a-Punch: they keep the one they have)
	}
	self AllowSprint( true );
	self TakeWeapon( weapon );
	if( self HasWeapon( back ) )
	{
		self SwitchToWeapon( back );
	}
	self.wawbf_hands = undefined;
}

// In case the game never says the weapon came up: the player must not be
// left without their hands.
hands_too_long( seconds )
{
	self endon( "disconnect" );
	self endon( "wawbf_hands_done" );

	wait( seconds );
	self notify( "wawbf_hands_up" );
}

// The perk's picture, where the game's own maps put a player's perks.
revive_icon( show )
{
	if( IsDefined( self.wawbf_revive_icon ) )
	{
		self.wawbf_revive_icon Destroy();
		self.wawbf_revive_icon = undefined;
	}
	if( !show )
	{
		return;
	}
	icon = NewClientHudElem( self );
	icon.foreground = true;
	icon.sort = 1;
	icon.hidewheninmenu = false;
	icon.alignX = "left";
	icon.alignY = "bottom";
	icon.horzAlign = "left";
	icon.vertAlign = "bottom";
	icon.x = 4;
	icon.y = -70;
	icon.alpha = 1;
	icon SetShader( "specialty_quickrevive_zombies", 24, 24 );
	self.wawbf_revive_icon = icon;
}

// Every blow to a player comes here before it lands (run() puts this in the
// game's own place for such a routine, and it hands on to the one that was
// there). The game's ends the game when the blow would put down the last
// player standing. With Quick Revive bought, that blow does not land: this
// never comes back from it, which is how the game's own stops a blow, and the
// player goes into a last stand instead (last_stand).
player_damage( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, modelIndex, psOffsetTime )
{
	if( iDamage >= self.health && IsDefined( self.wawbf_revives ) && self.wawbf_revives > 0 && self last_standing() )
	{
		self thread last_stand();
		level waittill( "wawbf_never" );
	}
	if( iDamage >= self.health )
	{
		// The blow that puts them down. The game lays a player who is down on
		// the ground, and its script then forbids standing and crouching; with
		// lying down forbidden as well (as it is for everyone here: Battlefront
		// II's characters are not shown lying down) the game stops dead, "All
		// stances disallowed for player", and the player is back at the main
		// menu. So lying down is allowed again from here.
		self AllowProne( true );
		self.wawbf_may_lie = true;
	}
	if( IsDefined( level.wawbf_stock_damage ) )
	{
		self [[level.wawbf_stock_damage]]( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, modelIndex, psOffsetTime );
	}
}

// Nobody else is on their feet to help.
last_standing()
{
	players = get_players();
	for( i = 0; i < players.size; i++ )
	{
		if( players[i] == self )
		{
			continue;
		}
		if( IsAlive( players[i] ) && players[i].sessionstate != "spectator" && !players[i] maps\_laststand::player_is_in_laststand() )
		{
			return false;
		}
	}
	return true;
}

// Quick Revive for a player on their own, as the later games have it: the
// blow that would have put them down leaves them in a last stand, from which
// they get up by themselves. There a player lies on the ground with a
// pistol. Here nobody lies down (Battlefront II's characters have no way to),
// so they go down on one knee: crouched and unable to move from the spot,
// still able to turn, shoot or swing a lightsaber, and nothing can hurt them.
// When the time is up they stand, whole, with a moment's grace.
last_stand()
{
	self endon( "disconnect" );

	self.wawbf_revives = 0;
	self UnsetPerk( "specialty_quickrevive" );
	self revive_icon( false );
	self.wawbf_down = true;
	self.ignoreme = true;
	self EnableInvulnerability();
	self.health = self.maxhealth;

	// What someone reviving another player is shown, the word and the bar
	// that fills as it is done (the game's own, from its last-stand script),
	// for the time this takes. At the top of the screen, not below the
	// middle where the game has it: Battlefront II's character is drawn over
	// that.
	says = NewClientHudElem( self );
	says.foreground = true;
	says.alignX = "center";
	says.alignY = "top";
	says.horzAlign = "center";
	says.vertAlign = "top";
	says.y = 50;
	says.fontScale = 1.8;
	says.alpha = 1;
	says SetText( "Reviving" );
	bar = self maps\_hud_util::createPrimaryProgressBar();
	bar maps\_hud_util::setPoint( "TOP", undefined, 0, 76 );
	bar maps\_hud_util::updateBar( 0.01, 1 / level.wawbf_revive_time );

	self AllowStand( false );
	self AllowJump( false );
	self AllowSprint( false );
	self SetStance( "crouch" );
	self SetMoveSpeedScale( 0.01 );

	// And the zombies leave them be, and walk off (keep_away). What the game's
	// zombies go by in choosing whom to make for has no "is down" of this
	// kind in it; "is a zombie" is in it, and means nothing else to this map's
	// scripts for as long as this lasts.
	self.is_zombie = true;
	self thread keep_away();

	// (The game takes invulnerability away by itself now and then, and the
	// player can try to stand.)
	for( down = 0; down < level.wawbf_revive_time; down += 0.1 )
	{
		self EnableInvulnerability();
		if( self GetStance() != "crouch" )
		{
			self SetStance( "crouch" );
		}
		wait( 0.1 );
	}

	self.is_zombie = false;
	self notify( "wawbf_up" );
	says Destroy();
	bar maps\_hud_util::destroyElem();
	self SetMoveSpeedScale( 1 );
	self AllowStand( true );
	self AllowJump( true );
	self AllowSprint( true );
	self SetStance( "stand" );
	self.health = self.maxhealth;
	for( up = 0; up < level.wawbf_revive_grace; up += 0.1 )
	{
		self EnableInvulnerability();
		wait( 0.1 );
	}
	self.ignoreme = false;
	self.wawbf_down = undefined;
	self DisableInvulnerability();  // (they could be hurt, or they would not have been put down)
}

// While a player is down the zombies walk away from them, as in the later
// games, and come back when they are up. Every second, each zombie that has
// got into the building and has not been sent yet is sent to one of the
// places furthest from the player (the game's own path nodes) among those
// near enough to be in the part of the map the player is in: a zombie cannot
// be sent somewhere there is no way to, and nothing here can ask whether
// there is one. If there turns out not to be, it tries the next.
keep_away()
{
	self endon( "disconnect" );
	self endon( "wawbf_up" );

	for( ;; )
	{
		far = self far_from();
		zombies = GetAiArray( "axis" );
		for( i = 0; i < zombies.size && far.size > 0; i++ )
		{
			if( IsAlive( zombies[i] ) && !IsDefined( zombies[i].wawbf_leaving ) && zombies[i] maps\_zombiemode_utility::in_playable_area() )
			{
				zombies[i] thread walk_away( self, far, i );
			}
		}
		wait( 1 );
	}
}

// The path nodes within reach of this player and on their floor, furthest
// from them first: as many as level.wawbf_revive_far.
far_from()
{
	if( !IsDefined( level.wawbf_nodes ) )
	{
		level.wawbf_nodes = inside_nodes();
	}
	far = [];
	taken = [];
	for( n = 0; n < level.wawbf_revive_far; n++ )
	{
		best = undefined;
		best_away = level.wawbf_revive_least * level.wawbf_revive_least;
		for( i = 0; i < level.wawbf_nodes.size; i++ )
		{
			at = level.wawbf_nodes[i].origin;
			if( IsDefined( taken[i] ) || abs( at[2] - self.origin[2] ) > level.wawbf_revive_floor )
			{
				continue;
			}
			away = DistanceSquared( at, self.origin );
			if( away > best_away && away < level.wawbf_revive_reach * level.wawbf_revive_reach )
			{
				best_away = away;
				best = i;
			}
		}
		if( !IsDefined( best ) )
		{
			break;
		}
		taken[best] = true;
		far[far.size] = level.wawbf_nodes[best];
	}
	return far;
}

// The map's path nodes that are inside the building: the zombies' own ways up
// to its windows have nodes too, and one that has climbed in cannot get back
// to those.
inside_nodes()
{
	nodes = GetAllNodes();
	areas = GetEntArray( "playable_area", "targetname" );
	if( areas.size == 0 )
	{
		return nodes;
	}
	inside = [];
	probe = Spawn( "script_origin", ( 0, 0, 0 ) );
	for( i = 0; i < nodes.size; i++ )
	{
		probe.origin = nodes[i].origin + ( 0, 0, 16 );
		for( a = 0; a < areas.size; a++ )
		{
			if( probe IsTouching( areas[a] ) )
			{
				inside[inside.size] = nodes[i];
				break;
			}
		}
	}
	probe Delete();
	return inside;
}

// One zombie, sent away from a player who is down until they are up.
walk_away( player, far, first )
{
	self endon( "death" );
	player endon( "disconnect" );
	player endon( "wawbf_up" );

	self.wawbf_leaving = true;
	self thread come_back( player );
	self notify( "zombie_acquire_enemy" );  // which stops its own making for the player (the game's find_flesh)
	for( tried = 0; tried < far.size; tried++ )
	{
		self.goalradius = 48;
		self SetGoalNode( far[( first + tried ) % far.size] );
		self waittill( "bad_path" );  // no way there: the next
	}
	self SetGoalPos( self.origin );
}

come_back( player )
{
	self endon( "death" );

	player waittill_any( "wawbf_up", "disconnect" );
	self.wawbf_leaving = undefined;
	self.goalradius = 32;  // as the game's own seeking has it; it takes over within a second
}

sell_ammo()
{
	for( ;; )
	{
		self waittill( "trigger", player );

		if( !maps\_zombiemode_utility::is_player_valid( player ) )
		{
			wait( 0.5 );
			continue;
		}
		if( player maps\_zombiemode_utility::in_revive_trigger() )
		{
			wait( 0.1 );
			continue;
		}
		if( player.score < level.wawbf_ammo_cost )
		{
			self PlaySound( "no_cha_ching" );
			wait( 0.5 );
			continue;
		}
		if( player fill_up() )
		{
			player maps\_zombiemode_score::minus_to_player_score( level.wawbf_ammo_cost );
			player PlaySound( "cha_ching" );
		}
		wait( 0.5 );
	}
}

// Fills everything the player carries. False if there was nothing to fill,
// and so nothing to charge for.
fill_up()
{
	filled = false;

	// A weapon left in the Pack-a-Punch too long is handed back, as it was.
	kit = self.wawbf_kit;
	if( IsDefined( kit ) )
	{
		if( self recover( kit.first ) )
		{
			filled = true;
		}
		if( self recover( kit.second ) )
		{
			filled = true;
		}
	}

	weapons = self GetWeaponsListPrimaries();
	for( i = 0; i < weapons.size; i++ )
	{
		if( self GetWeaponAmmoStock( weapons[i] ) < WeaponMaxAmmo( weapons[i] ) )
		{
			self GiveMaxAmmo( weapons[i] );
			filled = true;
		}
	}

	kit = self.wawbf_kit;
	if( !IsDefined( kit ) || has_ability( kit, "grenade" ) )
	{
		if( !IsDefined( kit ) && !self HasWeapon( "stielhandgranate" ) )
		{
			self GiveWeapon( "stielhandgranate" );
			self SetWeaponAmmoClip( "stielhandgranate", 0 );
		}
		if( self HasWeapon( "stielhandgranate" ) )
		{
			self.wawbf_grenades = self GetWeaponAmmoClip( "stielhandgranate" );
		}
		if( self.wawbf_grenades < level.wawbf_grenades )
		{
			self.wawbf_grenades = level.wawbf_grenades;
			if( self HasWeapon( "stielhandgranate" ) )
			{
				self SetWeaponAmmoClip( "stielhandgranate", level.wawbf_grenades );
			}
			filled = true;
		}
	}
	if( IsDefined( kit ) && has_ability( kit, "rocket" ) && self.wawbf_rockets < level.wawbf_rockets )
	{
		self.wawbf_rockets = level.wawbf_rockets;
		filled = true;
	}

	return filled;
}
