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
//           was charged when it was last fired (0 to 15).
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
	add_kit( 4,  "swbf2_ee3",         "m2_flamethrower_zombie",  false );  // Boba Fett
	add_kit( 5,  "swbf2_bowcaster",   "swbf2_launcher",          false );  // Chewbacca
	add_kit( 6,  "swbf2_sporting",    undefined,                 false );  // Leia
	add_kit( 7,  "swbf2_saber",       undefined,                 true  );  // Luke, Obi-Wan, Mace Windu, Darth Maul
	add_kit( 8,  "swbf2_saber",       undefined,                 true  );  // Aayla Secura
	add_kit( 9,  "swbf2_saber",       undefined,                 true  );  // Anakin, Darth Vader
	add_kit( 10, "swbf2_saber",       undefined,                 true  );  // Yoda
	add_kit( 11, "swbf2_saber",       undefined,                 true  );  // the Emperor, Count Dooku
	add_kit( 12, "swbf2_saber",       undefined,                 true  );  // General Grievous

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

	// Boba Fett's wrist rocket leaves this long after the button, as it does
	// in Battlefront II.
	level.wawbf_rocket_delay = 0.46;
	level.wawbf_rockets = 5;

	// The bowcaster. It charges for as long as the trigger is held (a full
	// charge takes 1.25 s, and the ring round Battlefront II's crosshair shows
	// it) and fires when the trigger is let go: a fan of seven bolts, each
	// this many degrees from the next, that hit harder the longer it was
	// held, up to twice as hard; or, charged all the way, one heavy bolt. The
	// fan and a light bolt's damage are Battlefront II's; its heavy bolt does
	// 300 there, and goes through nobody.
	level.wawbf_bowcaster_full = 0.9;
	level.wawbf_bowcaster_fan = 0.7;
	level.wawbf_bowcaster_bolt = 75;
	level.wawbf_bowcaster_slug = 1000;
	level.wawbf_bowcaster_through = 5;


	// What a wall charges to fill everything the player carries.
	level.wawbf_ammo_cost = 250;
	level.wawbf_grenades = 4;

	numbers = GetArrayKeys( level.wawbf_kit );
	for( i = 0; i < numbers.size; i++ )
	{
		kit = level.wawbf_kit[numbers[i]];
		PrecacheItem( kit.first );
		if( IsDefined( kit.second ) )
		{
			PrecacheItem( kit.second );
		}
	}

	level thread run();
}

add_kit( number, first, second, saber )
{
	kit = SpawnStruct();
	kit.first = first;
	kit.second = second;
	kit.saber = saber;
	kit.abilities = [];
	kit.fallback = undefined;  // the ability to assume while the bridge says nothing about which
	level.wawbf_kit[number] = kit;
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

	for( i = 0; i < players.size; i++ )
	{
		players[i].wawbf_grenades = level.wawbf_grenades;
		players[i].wawbf_rockets = level.wawbf_rockets;
		players[i].wawbf_hand = 0;
		players[i].wawbf_clip = [];
		players[i].wawbf_stock = [];
		players[i] AllowProne( false );  // Battlefront II's characters are not shown lying down
		players[i] thread follow_kit();
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
	unhurt = false;
	for( ;; )
	{
		wait( 0.05 );

		// For testing: started with  +set wawbf_god 1  the player cannot be
		// hurt. (The game switches this off itself now and then, hence every
		// time round.)
		if( GetDvarInt( "wawbf_god" ) != 0 )
		{
			self EnableInvulnerability();
			unhurt = true;
		}
		else if( unhurt )
		{
			self DisableInvulnerability();
			unhurt = false;
		}

		says = self.count;
		if( !IsDefined( says ) || says < 0 )
		{
			says = 0;
		}
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
		if( self maps\_laststand::player_is_in_laststand() )
		{
			self.dmg = 0;
			continue;  // down: the game has given them its own pistol for now
		}

		kit = level.wawbf_kit[want];
		if( want != have || !self HasWeapon( kit.first ) )
		{
			self give_kit( kit );
			have = want;
			uses = undefined;
			swings = undefined;
		}
		self keep_full( kit.first );
		self keep_full( kit.second );

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
		if( self GetCurrentWeapon() == "swbf2_bowcaster" )
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
		if( current == kit.first )
		{
			self.wawbf_hand = 1;
		}
		else if( IsDefined( kit.second ) && current == kit.second )
		{
			self.wawbf_hand = 2;
		}
		say = self.wawbf_hand;
		if( self ability_ready( ability ) )
		{
			say += 4;
		}
		if( current == kit.first || ( IsDefined( kit.second ) && current == kit.second ) )
		{
			clip = self GetWeaponAmmoClip( current );
			if( clip == 0 && self GetWeaponAmmoStock( current ) == 0 )
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
	self give_weapon( kit.first );
	if( IsDefined( kit.second ) )
	{
		self give_weapon( kit.second );
	}

	self SwitchToWeapon( kit.first );
	self.wawbf_hand = 1;
	self.wawbf_bolts = undefined;
	self AllowProne( false );
	self AllowMelee( !kit.saber );  // a lightsaber is swung with fire, not the knife
	self AllowADS( !kit.saber );    // and is not aimed: that button works the Force
	self.wawbf_kit = kit;
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
		MagicBullet( "panzerschrek", eye + ahead * 40, eye + ahead * 6000, self );
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
			self hurt( zombies[i], level.wawbf_choke_damage, ( 0, 0, 40 ) );
		}
	}
	else if( ability == "lightning" )
	{
		zombies = self in_front( level.wawbf_lightning_reach, level.wawbf_lightning_arc, level.wawbf_lightning_most );
		for( i = 0; i < zombies.size; i++ )
		{
			self hurt( zombies[i], level.wawbf_lightning_damage, undefined );
		}
	}
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
		if( Length( away ) > level.wawbf_saber_reach )
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
// The rounds are counted here too, one for each of Battlefront II's shots.
// Pulling the trigger fires this game's stand-in as well, which takes a
// round of its own; that is put back.
bowcaster( fired, charge )
{
	clip = self GetWeaponAmmoClip( "swbf2_bowcaster" );
	if( !IsDefined( self.wawbf_bolts ) || clip > self.wawbf_bolts )
	{
		self.wawbf_bolts = clip;  // just handed over, or reloaded
	}

	if( fired && self.wawbf_bolts > 0 )
	{
		self.wawbf_bolts--;

		eye = self GetEye();
		angles = VectorToAngles( self aim_ahead() );
		if( charge >= level.wawbf_bowcaster_full )
		{
			self bolt( eye, AnglesToForward( angles ), level.wawbf_bowcaster_slug, level.wawbf_bowcaster_through );
		}
		else
		{
			for( across = -3; across <= 3; across++ )
			{
				self bolt( eye, AnglesToForward( ( angles[0], angles[1] + across * level.wawbf_bowcaster_fan, 0 ) ), level.wawbf_bowcaster_bolt * ( 1 + charge ), 1 );
			}
		}
	}

	if( clip != self.wawbf_bolts )
	{
		self SetWeaponAmmoClip( "swbf2_bowcaster", self.wawbf_bolts );
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
// carrying, and the weapon cabinet and the mystery box stay shut. build.ps1
// has the game's own weapons script call this in place of setting up its
// shops.
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

	shut = GetEntArray( "weapon_cabinet_use", "targetname" );
	for( i = 0; i < shut.size; i++ )
	{
		shut[i] trigger_off();
	}
	shut = GetEntArray( "treasure_chest_use", "targetname" );
	for( i = 0; i < shut.size; i++ )
	{
		shut[i] trigger_off();
	}
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
			self PlaySound( "no_purchase" );
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
