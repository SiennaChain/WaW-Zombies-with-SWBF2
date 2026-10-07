// Reverse-engineering aid, not part of the mod. Moves the player between known
// spots and publishes where it ended up as a marked string in a dvar, so an
// outside scanner can find that string in memory and then look for the same
// numbers stored as floats.
wawbf_probe()
{
	wait( 8 );

	players = get_players();
	player = players[0];
	player EnableInvulnerability();
	// Stick or mouse input between a publish and a scan would make the numbers disagree.
	player FreezeControls( true );
	base = player.origin;

	offsets = [];
	offsets[0] = ( 0, 0, 0 );
	offsets[1] = ( 24, 0, 0 );
	offsets[2] = ( 24, 24, 0 );
	offsets[3] = ( 0, 24, 0 );
	offsets[4] = ( -24, 0, 0 );
	offsets[5] = ( 0, -24, 0 );

	angles = [];
	angles[0] = ( -20, 10, 0 );
	angles[1] = ( 10, 100, 0 );
	angles[2] = ( 30, -170, 0 );
	angles[3] = ( -5, 45, 0 );
	angles[4] = ( 15, -60, 0 );
	angles[5] = ( 0, 135, 0 );

	for( step = 1; ; step++ )
	{
		i = step % offsets.size;
		player SetOrigin( base + offsets[i] );
		player SetPlayerAngles( angles[i] );
		wait( 1 );

		// Whole hundredths, because script floats lose digits when turned into text.
		o = player.origin;
		a = player GetPlayerAngles();
		setDvar( "wawbf_probe", "WAWBFPROBE|" + step + "|" + int( o[0] * 100 ) + "|" + int( o[1] * 100 ) + "|" + int( o[2] * 100 ) + "|" + int( a[0] * 100 ) + "|" + int( a[1] * 100 ) + "|" );
		wait( 8 );
	}
}
