//Category Five VScript
//by Braindawg
//thanks to Orin for the help early on

PrecacheSound("buttons/button9.wav");
PrecacheSound("items/ammocrate_open.wav");
PrecacheSound("vo/taunts/engy/taunt_engineer_lounge_button_press.mp3");

//get a few entities that are guaranteed to exist for attaching think funcs to
local resource; resource = Entities.FindByClassname(resource, "tf_objective_resource"); //this entity is responsible for a lot of the scoreboard/wavebar/other MvM HUD elements
local gamerules; gamerules = Entities.FindByClassname(gamerules, "tf_gamerules");
local mvmlogic; mvmlogic = Entities.FindByClassname(mvmlogic, "tf_logic_mann_vs_machine");
local monsterresource; monsterresource = Entities.FindByClassname(monsterresource, "monster_resource"); //this entity is responsible for the halloween bar
local bomb; bomb = Entities.FindByName(bomb, "bomb1_timed")
local cooldowntime = 3;
local specdelay = 3;
local cooldowntime2 = 40;
local popname = NetProps.GetPropString(resource, "m_iszMvMPopfileName"); //default pop name before we change it to something better looking on the scoreboard
local timeractive = false;
local lastattack = 0;
local players = {};

//TODO: attach a copy of this array to each player and set it alongside AwardWeapons
//local sequenceArray = [];
local sequenceArray = []

const COOLDOWN_TIME = 3; //cooldown for button pressing
//const TIMER_MINUTES = 1.0;
//const TIMER_INTERVAL = (TIMER_MINUTES / 60) / 255;
const TIMER_INTERVAL = 0.2352941176470588; // no point doing ((1/60) / 255).
const BUTTON_RADIUS = 96;

// "OnPressed" "tf_objective_resource$setprop$m_nMannVsMachineWaveClassFlags$003060-1"
// "OnPressed" "tf_objective_resource$setprop$m_nMannVsMachineWaveClassFlags$002060-1"

//big fat player loop for making rev work
::reverseTeams <- function()
{
	for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++) //player loop
	{
		local player = PlayerInstanceFromIndex(i);

 		//???
		if (player == null) continue;

		//force bots to spec between waves
		if (IsPlayerABot(player) && NetProps.GetPropBool(resource, "m_bMannVsMachineBetweenWaves"))
			player.SetTeam(1);

		//blue player stuff
		if (!IsPlayerABot(player))
		{
			//remove footsteps
			if (!NetProps.GetPropBool(player, "m_bIsMiniBoss"))
			{
				NetProps.SetPropBool(player, "m_bIsMiniBoss", true); //allows use of "override footstep sound set"
				player.AddCustomAttribute("override foostep sound set", 0, 0);
			}

			//switch teams
			if (player.GetTeam() != Constants.ETFTeam.TF_TEAM_PVE_INVADERS)
				NetProps.SetPropInt(player, "m_iTeamNum", Constants.ETFTeam.TF_TEAM_PVE_INVADERS);

			//simple ammo hack
			local activeGun = NetProps.GetPropEntity(player, "m_hActiveWeapon");
			if (activeGun == null) continue;
			local ammoslot = NetProps.GetPropIntArray(player, "m_iAmmo", activeGun.GetSlot() + 1);
//			printl(activeGun.GetSequence())

			//remove 1 ammo when the designated sequence plays.  
			//This doesn't account for weapons like FaN/Soda Popper/Huo, widowmaker will also need something completely different.
			if (lastattack != NetProps.GetPropFloat(activeGun, "m_flNextPrimaryAttack") && ammoslot > 0 && sequenceArray.find(activeGun.GetSequence()) != null)
			{
				NetProps.SetPropIntArray(player, "m_iAmmo", ammoslot - 1, activeGun.GetSlot() + 1);
				lastattack = NetProps.GetPropFloat(activeGun, "m_flNextPrimaryAttack");
			}
			//ammo/health/money? drops
			for (local packs; packs = Entities.FindByClassnameWithin(packs, "item_*", player.GetLocalOrigin(), 24); )
			{
				if (packs.GetClassname() == "item_teamflag")
					return;
	
				if (packs.GetClassname() == "item_currencypack_custom" || (player.GetHealth() < player.GetMaxHealth() && (packs.GetClassname() == "item_healthkit_medium" || packs.GetClassname() == "item_healthkit_full" || packs.GetClassname() == "item_healthkit_small")))
					NetProps.SetPropInt(player,"m_iTeamNum", Constants.ETFTeam.TF_TEAM_PVE_DEFENDERS);
	
				//remove 1 ammo before pickup to stop from pack cheesing, add 1 ammo back with OnPlayerTouch
				//shitty hack, will leave players with -1 ammo on pickup
				//ammo penalty attribs also don't properly set the reserve ammo on equip.
				if (packs.GetClassname() == "item_ammopack_medium" || packs.GetClassname() == "item_ammopack_full")
				{
					local activeGun = NetProps.GetPropEntity(player, "m_hActiveWeapon");
					if (activeGun == null) continue;
					local slot = activeGun.GetSlot() + 1;
					local ammoslot = NetProps.GetPropIntArray(player, "m_iAmmo", slot);
					NetProps.SetPropIntArray(player, "m_iAmmo", ammoslot - 1, slot);
					NetProps.SetPropInt(player,"m_iTeamNum", Constants.ETFTeam.TF_TEAM_PVE_DEFENDERS);
					//add the 1 ammo back on pickup (lmao)
					//doesn't work
				//	EntityOutputs.AddOutput(packs, "OnPlayerTouch","!activator", "RunScriptCode", "NetProps.SetPropIntArray(self, "m_iAmmo", NetProps.GetPropIntArray(self, "m_iAmmo",(NetProps.GetPropEntity(self, "m_hActiveWeapon").GetSlot() + 1) + 1,(NetProps.GetPropEntity(self, "m_hActiveWeapon").GetSlot() + 1)))", 0, -1);
				}
				EntityOutputs.AddOutput(packs, "OnPlayerTouch","!activator", "CallScriptFunction", "packswitch(self)", 0, -1);
				EntityOutputs.AddOutput(packs, "OnPlayerTouch","!self", "RunScriptCode", "self.SetLocalOrigin(self.GetLocalOrigin() - Vector(0 0 4000))", 0, -1); //teleport away so players can't abuse for team switch
				EntityOutputs.AddOutput(packs, "OnPlayerTouch","!self", "RunScriptCode", "self.SetLocalOrigin(self.GetLocalOrigin() + Vector(0 0 4000))", 8, -1);
			}
	
			//pre-round uber/attack block
			//also handles ready-up
			//note: return here means this must go last
			if (NetProps.GetPropBool(resource, "m_bMannVsMachineBetweenWaves"))
			{
				if (IsPlayerABot(player) && NetProps.GetPropInt(spawner, "m_PlayerClass.m_iClass") != 1)
				{
					player.SetTeam(1);
					return;
				}

				player.AddCustomAttribute("no_attack", 1 , 0);
				player.AddCond(51);
				stripWeapons(player);
				for (local i = 1; i <= 32; i++)
				{
					local ready = NetProps.GetPropBoolArray(gamerules, "m_bPlayerReady", i)
					if (ready)
					{
						NetProps.SetPropFloat(gamerules, "m_flRestartRoundTime", 5.0)
					}
				}
				return;
			}
			player.RemoveCustomAttribute("no_attack");
			player.RemoveCond(51);
		}

		//manually open upgrade stations when players get near
		//interestingly, this respects enabled/disabled state
		for (local stations; stations = Entities.FindByClassnameWithin(stations, "func_upgradestation", player.GetLocalOrigin(), 32); )
		{
			NetProps.SetPropBool(player, "m_bInUpgradeZone", true);
		}

	//force red money since I'm too lazy to get players to properly pick up cash
	//DOES NOT WORK
		for (local money; money = Entities.FindByClassname(money, "item_currencypack_custom"); )
		{
			if (!NetProps.GetPropBool(money, "m_bDistributed"))
			{
				NetProps.SetPropBool(money, "m_bDistributed", true)
			}
		}
	}
}

//needs to be its own function to stop from switching bots to the wrong team
function packswitch(player)
{
	if (IsPlayerABot(player))
		return;
		
	NetProps.SetPropInt(player, "m_iTeamNum", 3);
}

//player spawn stuff
//bots need to go through the regular spawning routines before being switched to red, so it cannot be done in the think function above
//conversely, attempting to switch players here seems to not work
function OnGameEvent_player_spawn(params)
{
    local spawner = GetPlayerFromUserID( params.userid );

	//bluebot tag seems to not work?
	// if (!IsPlayerABot(spawner) || spawner.HasBotTag("bluebot"))
	//		return;

	if (!IsPlayerABot(spawner))
		return;

	//we don't use scouts and no luck messing with tags, so we can hard code this
	if (NetProps.GetPropInt(spawner, "m_PlayerClass.m_iClass") == 1) 
		spawner.AddCond(66);
	
	NetProps.SetPropInt(spawner, "m_iTeamNum" , Constants.ETFTeam.TF_TEAM_PVE_DEFENDERS);

	//Sniper is used and custom model doesn't exist yet.
	if (NetProps.GetPropInt(spawner, "m_PlayerClass.m_iClass") != 2)
		setModels(spawner, NetProps.GetPropInt(spawner, "m_PlayerClass.m_iClass"));

	spawner.AddCustomAttribute("voice pitch scale", 0.4 , 0)
	spawner.AddCustomAttribute("cannot pick up intelligence", 1 , 0) // first bot spawn is still given bomb regardless of this attrib
	spawner.AddCustomAttribute("health from packs decreased", 0 , 0) 
	spawner.AddCustomAttribute("damage force reduction", 0 , 0)
	spawner.AddCustomAttribute("crit mod disabled", 0 , 0)
	spawner.AddCustomAttribute("ammo regen", 999 , 0)

	//doesn't work
	local botGun = NetProps.GetPropEntity(spawner, "m_hActiveWeapon");
	botGun.AddAttribute("ammo regen", 999 , 0) //red bots dont get inf ammo
	botGun.AddAttribute("crit mod disabled", 0, 0)
	botGun.ReapplyProvision()
}

//player death stuff

function OnGameEvent_player_death(params)
{
    local victim = GetPlayerFromUserID( params.userid );

	// Switch back to BLU on death.  Then move to spec
	if (IsPlayerABot(victim))
	{
		NetProps.SetPropInt(victim, "m_iTeamNum", 3);
		victim.SetTeam(1);
		return;
	}
	NetProps.SetPropBool(victim, "m_bIsMiniBoss", false); // Stop the giant explosion death sound, not really necessary anymore since we changed the script file

	//HACK: switch players to spec in pre-wave on death to avoid endlessly incrementing the red team counter by spamming team switches
	if (!NetProps.GetPropBool(resource, "m_bMannVsMachineBetweenWaves"))
			try {
				EntFire( "startcrystals" , "Trigger" , null , 0 , null);
			} catch (err) {
				return;
			}
	NetProps.SetPropInt(victim, "m_iTeamNum", 2);
}

// //when player connects and loaded in?
// function OnGameEvent_player_activate(params) 
// {
//     local player = GetPlayerFromUserID(params.userid);
//     players[player] <- { //handle
// 		sequenceArray = []
//     };
// }

// function OnGameEvent_player_disconnect(params) 
// {
//     local player = GetPlayerFromUserID(params.userid);
//     delete players[player];
// }
__CollectGameEventCallbacks( this );

//ty ficool
::GiveWeapon <- function(player, className, itemID)
{
	local weapon = Entities.CreateByClassname(className);
	local clientcommand = Entities.CreateByClassname("point_clientcommand");
	Entities.DispatchSpawn(clientcommand);

	NetProps.SetPropInt(weapon, "m_AttributeManager.m_Item.m_iItemDefinitionIndex", itemID);
	NetProps.SetPropBool(weapon, "m_AttributeManager.m_Item.m_bInitialized", true);
	NetProps.SetPropBool(weapon, "m_bValidatedAttachedEntity", true);
	Entities.DispatchSpawn(weapon);
//	weapon.SetClip1(weapon.Clip1() * 3)
	for (local i = 0; i < 7; i++)
    {
        local heldWeapon = NetProps.GetPropEntityArray(player, "m_hMyWeapons", i);

        if (heldWeapon == null) 
			continue;
        if (heldWeapon.GetSlot() != weapon.GetSlot()) 
			continue;

        heldWeapon.Destroy();
        NetProps.SetPropEntityArray(player, "m_hMyWeapons", weapon, i);
        break;
    }
	//reduce primary ammo

	if (weapon.GetSlot() == 0)
		weapon.AddAttribute("hidden primary max ammo bonus", 0.2, 0.0)
		weapon.ReapplyProvision()

	player.Weapon_Equip(weapon);
	
	if (weapon != "tf_weapon_rocketlauncher" || weapon != "tf_weapon_minigun")
		weapon.SetTeam(player.GetTeam());
		

	//force slot switch after equip
//	EntFireByHandle(clientcommand , "Command" , "slot3" , 0.0 , player , null );
	clientcommand.Destroy();

	return weapon;
}
::stripWeapons <- function(player)
{
//	local clientcommand = Entities.CreateByClassname("point_clientcommand");
//	Entities.DispatchSpawn(clientcommand);

	for (local i = 0; i < 7; i++)
	{
		local guns = NetProps.GetPropEntityArray(player, "m_hMyWeapons", i);

		if (guns == null) continue;

		if (guns.GetSlot() != 2) //strip non-melee weapons
			guns.Destroy();
	}
//	EntFireByHandle(clientcommand , "Command" , "slot3" , 0.0 , player , null );
//	clientcommand.Destroy();
}

//huge switch case for rolling weapons
//refer to https://wiki.alliedmods.net/Team_fortress_2_item_definition_indexes for modifying the rolls
::AwardWeapons <- function(player, classindex)
{
	local randomguns = RandomInt(1, 5);
	local medicguns = RandomInt(1, 7); //used for more than just medic

//note: m_iClass index order.
// 1 - Scout
// 2 - Sniper
// 3 - Soldier
// 4 - Demoman
// 5 - Medic
// 6 - Heavy
// 7 - Pyro
// 8 - Spy
// 9 - Engineer
// 10 - Civilian

	if (!classindex || classindex < 1 || IsPlayerABot(player))
		return;

	switch(classindex)
	{

	case 1: //SCOUT

		switch(randomguns)
		{
		
		case 1: //MILK/SCATTER

			//give secondaries first in an attempt to make the game switch players to primary weapons
			//doesn't always work lol

			GiveWeapon( player,"tf_weapon_scattergun", 888 );
			GiveWeapon( player,"tf_weapon_jar_milk", 222 );
			sequenceArray.clear()
			sequenceArray = [29];
			break;

		case 2: //BFB POCKET PISTOL

			GiveWeapon( player,"tf_weapon_handgun_scout_secondary", 773 );
			GiveWeapon( player,"tf_weapon_scattergun", 772 );
			sequenceArray.clear()
			//sequenceArray = [19, 29];
			sequenceArray = [19, 27];
			break;

		case 3: //PISTOL/FAN

			GiveWeapon( player,"tf_weapon_pistol", 23 );
			GiveWeapon( player,"tf_weapon_scattergun", 45 );
			sequenceArray.clear()
			sequenceArray = [19, 37];
			break;

		case 4: //GUILLOTINE/SHORTSTOP

			GiveWeapon( player,"tf_weapon_handgun_scout_primary", 220 );
			GiveWeapon( player,"tf_weapon_cleaver", 812 );
			sequenceArray.clear()
			sequenceArray = [23];
			break;

		case 5: //WINGER/BACKSCATTER

			GiveWeapon( player,"tf_weapon_handgun_scout_secondary", 449 );
			GiveWeapon( player,"tf_weapon_scattergun", 1103 );
			sequenceArray.clear()
			//sequenceArray = [19, 29];
			sequenceArray = [19, 27];
			break;
		}
	return sequenceArray
	break;

	case 2: //SNIPER

		switch(randomguns)
		{
		case 1: //STOCK SNIPER

			GiveWeapon( player , "tf_weapon_smg" , 16 );
			GiveWeapon( player ,"tf_weapon_sniperrifle" , 881 );
			sequenceArray = [4, 29];
			break;

		case 2: //HEATMAKER/COZY CAMPER

			GiveWeapon( player , "tf_weapon_sniperrifle" , 752 );
			GiveWeapon( player , "tf_werable" , 642 );
			sequenceArray = [29];
			break;

		case 3: //JARATE/SYDNEY

			GiveWeapon( player , "tf_weapon_sniperrifle" , 230 );
			GiveWeapon( player , "tf_weapon_jar" , 58 );
			sequenceArray = [29];
			break;

		case 4: //BOW/CARBINE

			GiveWeapon( player, "tf_weapon_compound_bow" , 1092 );
			GiveWeapon( player, "tf_weapon_charged_smg" , 751 );
			sequenceArray = [23, 4];
			break;

		case 5: //MACHINA/DARWINS

			GiveWeapon( player, "tf_weapon_sniperrifle" , 526 )
			GiveWeapon( player, "tf_wearable" , 231 )
			sequenceArray = [29];
			break;
		}
	break;

	case 3: //SOLDIER

		switch(randomguns)
		{
		case 1: //STOCK SOLDIER

			GiveWeapon( player , "tf_weapon_rocketlauncher" , 889 );
			GiveWeapon( player , "tf_weapon_shotgun_soldier" , 10 );
			//sequenceArray = [6, 32];
			sequenceArray = [3, 30]
			break;

		case 2: //DH/BISON

			GiveWeapon( player , "tf_weapon_rocketlauncher_directhit" , 127 );
			GiveWeapon( player , "tf_weapon_raygun" , 442 );
			sequenceArray = [6];
			break;

		case 3: //RS/LL

			GiveWeapon( player , "tf_weapon_rocketlauncher" , 414 );
			GiveWeapon( player , "tf_weapon_shotgun_soldier" , 415 );
			//sequenceArray = [6, 32];
			sequenceArray = [3, 30]
			break;

		case 4: //BBOX/FB

			GiveWeapon( player, "tf_weapon_rocketlauncher" , 228 );
			GiveWeapon( player, "tf_weapon_shotgun_soldier" , 425 );
			sequenceArray = [9, 32];
			break;

		case 5: //BEGGARS/PANIC
			GiveWeapon( player, "tf_weapon_rocketlauncher" , 730 )
			GiveWeapon( player, "tf_weapon_shotgun_soldier" , 1153 )
			//sequenceArray = [6, 32];
			sequenceArray = [3, 30]
			break;
		}
	break;

	case 4: //DEMO
		local demoguns = RandomInt(1 , 9)
		switch(demoguns)
		{
		case 1: //IB/TIDE/CLAID

			GiveWeapon( player , "tf_weapon_grenadelauncher" , 1151 );
			GiveWeapon( player , "tf_wearable_demoshield" , 1099 );
			GiveWeapon( player , "tf_weapon_sword" , 327 );
			sequenceArray = [29];
			break;

		case 2: //LC/TIDE/PERSIAN

			GiveWeapon( player , "tf_weapon_cannon" , 996 );
			GiveWeapon( player , "tf_wearable_demoshield" , 1099 );
			GiveWeapon( player , "tf_weapon_sword" , 404 );
			sequenceArray = [29];
			break;

		case 3: //BOOTIES/TARGE/EYELANDER

			GiveWeapon( player , "tf_wearable" , 405 );
			GiveWeapon( player , "tf_wearable_demoshield" , 131 );
			GiveWeapon( player , "tf_weapon_sword" , 132 );
			break;

		case 4: //BOOTLEGGER/SKULL/TIDE

			GiveWeapon( player , "tf_wearable" , 608 );
			GiveWeapon( player , "tf_wearable_demoshield" , 1099 );
			GiveWeapon( player , "tf_weapon_sword" , 172 );
			break;

		case 5: //BOOTLEGGER/ZAT/SCREEN

			GiveWeapon( player , "tf_wearable" , 608 );
			GiveWeapon( player , "tf_wearable_demoshield" , 406 );
			GiveWeapon( player , "tf_weapon_katana" , 357 );
			break;

		case 6: //STICKIES/BOOTIES

			GiveWeapon( player , "tf_wearable" , 608 );
			GiveWeapon( player, "tf_weapon_pipebomblauncher" , 886 );
			sequenceArray = [22];
			break;

		case 7: //STOCK/SCREEN

			GiveWeapon( player, "tf_weapon_grenadelauncher" , 19 )
			GiveWeapon( player, "tf_wearable_demoshield" , 406 )
			sequenceArray = [29];
			break;

		case 8: //QUICKIE/LOCH

			GiveWeapon( player, "tf_weapon_grenadelauncher" , 308 )
			GiveWeapon( player, "tf_weapon_pipebomblauncher" , 1150 )
			sequenceArray = [22, 37];
			break;

		case 9: //SCOTRES/PARACHUTE

			GiveWeapon( player, "tf_weapon_parachute" , 1101 )
			GiveWeapon( player, "tf_weapon_pipebomblauncher" , 130 )
			sequenceArray = [22];
			break;
		}
	break;

	case 5: //MEDIC
		switch(medicguns)
		{
		case 1: //STOCK SYRINGE

			GiveWeapon( player , "tf_weapon_syringegun_medic" , 17 );
			sequenceArray = [9];
			break;

		case 2: //BLUT

			GiveWeapon( player , "tf_weapon_syringegun_medic" , 36 );
			sequenceArray = [9];
			break;

		case 3: //OD

			GiveWeapon( player , "tf_weapon_syringegun_medic" , 412 );
			sequenceArray = [9];
			break;

		case 4: //XBOW/STOCK

			GiveWeapon( player , "tf_weapon_crossbow" , 305 );
			GiveWeapon( player , "tf_weapon_medigun" , 885 );
			sequenceArray = [10];
			break;

		case 5: //XBOW/KRITZ

			GiveWeapon( player , "tf_weapon_crossbow" , 305 );
			GiveWeapon( player , "tf_weapon_medigun" , 35 );
			sequenceArray = [10];
			break;

		case 6: //XBOW/QF

			GiveWeapon( player , "tf_weapon_crossbow" , 305 );
			GiveWeapon( player , "tf_weapon_medigun" , 411 );
			sequenceArray = [10];
			break;

		case 7: //XBOW/VACC

			GiveWeapon( player , "tf_weapon_crossbow" , 305 );
			GiveWeapon( player , "tf_weapon_medigun" , 998 );
			sequenceArray = [10];
			break;
		}
	break;
	case 6: //HEAVY
		switch(medicguns) //heavy and engi also have 7 guns
		{
		case 1: //STOCK HEAVY

			GiveWeapon( player , "tf_weapon_minigun" , 882 );
			GiveWeapon( player , "tf_weapon_shotgun_hwg" , 11 );
			sequenceArray = [21, 18];
			break;

		case 2: //FB/TOMI

			GiveWeapon( player , "tf_weapon_minigun" , 424 );
			GiveWeapon( player , "tf_weapon_shotgun_hwg" , 425 );
			sequenceArray = [21, 18];
			break;

		case 3: //HUO/PA

			GiveWeapon( player , "tf_weapon_minigun" , 811 );
			GiveWeapon( player , "tf_weapon_shotgun_hwg" , 1153 );
			sequenceArray = [21, 18];
			break;

		case 4: //NAT

			GiveWeapon( player , "tf_weapon_minigun" , 41 );
			GiveWeapon( player , "tf_weapon_shotgun_hwg" , 11 );
			sequenceArray = [21, 18];
			break;

		case 5: //BRASS/PA

			GiveWeapon( player , "tf_weapon_minigun" , 312 );
			GiveWeapon( player , "tf_weapon_shotgun_hwg" , 425 );
			sequenceArray = [21, 18];
			break;

		case 6: //STEAK

			GiveWeapon( player , "tf_weapon_lunchbox", 311 );
			break;

		case 7: //CURTAIN/RS

			GiveWeapon( player , "tf_weapon_minigun" , 298 );
			GiveWeapon( player , "tf_weapon_shotgun_hwg" , 415 );
			sequenceArray = [21, 18];
			break;
		}
	break;
	case 7: //PYRO
		switch(medicguns) //heavy engi pyro also have 7 guns
		{
		case 1: //STOCK PYRO

			GiveWeapon( player , "tf_weapon_flamethrower" , 887 );
			GiveWeapon( player , "tf_weapon_shotgun_pyro" , 12 );
			sequenceArray = [11, 18];
			break;

		case 2: //DEG/FLARE

			GiveWeapon( player , "tf_weapon_flamethrower" , 215 );
			GiveWeapon( player , "tf_weapon_flaregun" , 39 );
			sequenceArray = [11, 9];
			break;

		case 3: //DF/SCORCH

			GiveWeapon( player , "tf_weapon_rocketlauncher_fireball" , 1178 );
			GiveWeapon( player , "tf_weapon_flaregun" , 740 );
			sequenceArray = [11, 9];
			break;

		case 4: //RS/BACKBURNER

			GiveWeapon( player , "tf_weapon_flamethrower" , 40 );
			GiveWeapon( player , "tf_weapon_shotgun_pyro" , 415 );
			sequenceArray = [11, 18];
			break;

		case 5: //PHLOG/MANMELTER

			GiveWeapon( player , "tf_weapon_flamethrower" , 594 );
			GiveWeapon( player , "tf_weapon_flaregun_revenge" , 595 );
			sequenceArray = [11];
			break;

		case 6: //GAS/FLAMER

			GiveWeapon( player , "tf_weapon_jar_gas", 1180 );
			GiveWeapon( player , "tf_weapon_flamethrower", 30474 );
			sequenceArray = [11];
			break;

		case 7: //RAINBLOWER/FB

			GiveWeapon( player , "tf_weapon_flamethrower" , 741 );
			GiveWeapon( player , "tf_weapon_shotgun_pyro" , 425 );
			sequenceArray = [11, 18];
			break;
		}
	break;
	case 8: //SPY

		switch(randomguns)
		{
		case 1: //STOCK SPY

			GiveWeapon( player , "tf_weapon_revolver" , 24 );
			GiveWeapon( player ,"tf_weapon_invis" , 30 );
			sequenceArray = [4];
			break;

		case 2: //ENFORCER/QUACKEN

			GiveWeapon( player , "tf_weapon_revolver" , 460 );
			GiveWeapon( player ,"tf_weapon_invis" , 947 );
			sequenceArray = [4];
			break;

		case 3: //DB/ENTHUSAISTS

			GiveWeapon( player , "tf_weapon_revolver" , 525 );
			GiveWeapon( player ,"tf_weapon_invis" , 297 );
			sequenceArray = [4];
			break;

		case 4: //DR/AMBY

			GiveWeapon( player , "tf_weapon_revolver" , 61 );
			GiveWeapon( player ,"tf_weapon_invis" , 59 );
			sequenceArray = [4];
			break;

		case 5: //L'ET/CLOAK

			GiveWeapon( player , "tf_weapon_revolver" , 224 );
			GiveWeapon( player ,"tf_weapon_invis" , 60 );
			sequenceArray = [4];
			break;
		}
	break;

	case 9: //ENGI

		switch(medicguns) //heavy engi pyro also have 7 guns
		{
		case 1: //STOCK ENGI

			GiveWeapon( player , "tf_weapon_shotgun_primary" , 9 );
			GiveWeapon( player , "tf_weapon_pistol" , 22 );
			sequenceArray = [6, 27];
			break;

		case 2: //WIDOW/PDA/STOCK WRENCH

			GiveWeapon( player , "tf_weapon_shotgun_primary" , 527 );
			GiveWeapon( player , "tf_weapon_pda_engineer_build" , 25 );
			GiveWeapon( player , "tf_weapon_pda_engineer_destroy" , 26 );
			GiveWeapon( player , "tf_weapon_wrench" , 884 );
			sequenceArray = [8];
			break;

		case 3: //PBPP/FJ

			GiveWeapon( player , "tf_weapon_handgun_scout_secondary" , 773 );
			GiveWeapon( player , "tf_weapon_sentry_revenge" , 141 );
			sequenceArray = [6, 27];
			break;

		case 4: //POMSON/SC

			GiveWeapon( player , "tf_weapon_drg_pomson" , 588 );
			GiveWeapon( player , "tf_weapon_mechanical_arm" , 528 );
			sequenceArray = [27];
			break;

		case 5: //RR/WRANGLER/PDA/GUNSLINGER

			GiveWeapon( player , "tf_weapon_shotgun_building_rescue" , 997 );
			GiveWeapon( player , "tf_weapon_laser_pointer" , 140 );
			GiveWeapon( player , "tf_weapon_pda_engineer_build" , 25 );
			GiveWeapon( player , "tf_weapon_pda_engineer_destroy" , 26 );
			GiveWeapon( player , "tf_weapon_robot_arm" , 142 );
			sequenceArray = [6];
			break;

		case 6: //PBPP/RS

			GiveWeapon( player , "tf_weapon_shotgun_primary", 415 );
			GiveWeapon( player , "tf_weapon_handgun_scout_secondary", 773 );
			sequenceArray = [6, 27];
			break;

		case 7: //WINGER/FB

			GiveWeapon( player , "tf_weapon_handgun_scout_secondary" , 449 );
			GiveWeapon( player , "tf_weapon_shotgun_primary" , 425 );
			sequenceArray = [6, 27];
			break;
		}
	break;
	}
}
::waveStart <- function()
{
	blockNavs()
	DoEntFire("gamerules","SetBlueTeamRespawnWaveTime","9999", 0 , null, null)    
	players = {};

    for(local i = 1; i <= Constants.Server.MAX_PLAYERS; i++) {
        local player = PlayerInstanceFromIndex(i);
        if(player == null) continue;
        if(IsPlayerABot(player)) continue;

        //filters out specs
        if(player.GetTeam() != 3)
			return;

        players[player] <- {};
	}
}

//block navs here since func_door is apparently unreliable

::blockNavs <- function()
{
	navArray <- array(5);
	navArray[0] = 4257; //courtyard -> middle building
	navArray[1] = 62; //middle building
	navArray[2] = 16; //roof
	navArray[3] = 371; //roof connection
	navArray[4] = 148; //roof connection?
	
	for (local j = 0; j < navArray.len(); j++)
	{
		NavMesh.GetNavAreaByID(navArray[j]).MarkAsBlocked(2); //block middle building
	}
}
//this function fires on wave init
::cFive <- function()
{
	local soundscape; soundscape = Entities.FindByClassname(soundscape, "env_soundscape");
	local capturezone; capturezone = Entities.FindByClassname(capturezone, "func_capturezone");
	local startrelay; startrelay = Entities.FindByName(startrelay, "wave_start_relay")
	EntityOutputs.RemoveOutput(soundscape , "OnPlay" , "bots_win_red" , "RoundWin", ""); //remove win logic
	EntityOutputs.AddOutput(startrelay,"OnTrigger","gamerules","CallScriptFunction","waveStart", 0 , 1)
	NetProps.SetPropString(resource, "m_iszMvMPopfileName", "Downpour: Category Five");

	//force every bot to spectator on wave init incase the wave is interrupted
//	NetProps.SetPropIntArray(resource, "m_nMannVsMachineWaveClassFlags", 0, 010);
	Convars.SetValue("mp_humans_must_join_team", "blue") //useless
	Convars.SetValue("mp_forceautoteam", 1) //useless
	Convars.SetValue("mp_allowspectators", 0)
//	Convars.SetValue("tf_bot_flag_escort_give_up_range", 99999)
	Convars.SetValue("tf_bot_flag_escort_range", 99999)
	Convars.SetValue("tf_bot_flag_escort_max_count", 1)

	NetProps.SetPropInt(resource, "m_iBossHealthPercentageByte", 0);
	NetProps.SetPropInt(resource, "m_flMvMBaseBombUpgradeTime", 99999)

	EntityOutputs.RemoveOutput(capturezone , "OnCapture" , "bomb_deploy_relay" , "Trigger" , null); //remove bomb deploy win
	EntityOutputs.RemoveOutput(soundscape , "OnPlay" , "gamerules" , "CallScriptFunction", "findOutdoorSoundScapes"); //remove storm slow logic
	DoEntFire("lock_buttons", "Trigger", "", 0.0, null, null)
}


::cFiveEnd <- function()
{
	//map rotation breaks on victory if this isn't set back to default
	NetProps.SetPropString(resource,"m_iszMvMPopfileName", popname);
}

//button pressing stuff + weapon boxes
//reverseTeams() ended up being the bigger think

function theBigThink()
{
	for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
	{
		local player = PlayerInstanceFromIndex(i);

		if (player == null) continue;
		
		if (IsPlayerABot(player))
			return;

		for (local button; button = Entities.FindByClassnameWithin(button, "func_rot_button", player.GetLocalOrigin(), BUTTON_RADIUS); )
		{
			//BUG: locked netprop is not set with the "start locked" flag
			//the lock_buttons relay is a workaround for this
			if (!player.IsUsingActionSlot() || (Time() - cooldowntime < COOLDOWN_TIME) || NetProps.GetPropBool(button, "m_bLocked"))
				return;

			EntFireByHandle(button, "Use" , "" , 0 , null , player);
			cooldowntime = Time();

			if(button.GetName().len() > 19 )
			{
				if (button.GetName().slice(0, 19) == "PT_SWITCHGUNBUTTON2")
				{
					button.EmitSound("items/ammocrate_open.wav");
//					printl(NetProps.GetPropInt(player, "m_PlayerClass.m_iClass"));
					AwardWeapons(player, NetProps.GetPropInt(player, "m_PlayerClass.m_iClass"));
					return;
				}
			}
			button.EmitSound("buttons/button9.wav");
		}
	}
}
::beginCount <- function()
{
	NetProps.SetPropInt(monsterresource, "m_iBossHealthPercentageByte", 255);
	timeractive = true;
	AddThinkToEnt(mvmlogic, "ffCountdown");
}
function ffCountdown()
{
	local bossbar = NetProps.GetPropInt(monsterresource, "m_iBossHealthPercentageByte");

	if (bossbar < 1)
	{
		timeractive = false;
		AddThinkToEnt(mvmlogic, null);
		return;
	}

	if (timeractive)
	{
		NetProps.SetPropInt(monsterresource, "m_iBossHealthPercentageByte", bossbar - 1);
		return;
	}
	return TIMER_INTERVAL;
}

function bombTimer()
{
	EntityOutputs.AddOutput(bomb, "OnReturn", "!self", "RunScriptCode", "AddThinkToEnt(self , null)", 0, -1)
	bomb.EmitSound("vo/taunts/engy/taunt_engineer_lounge_button_press.mp3");
	return 1.66;
}

function startBomb()
{
	bomb.ValidateScriptScope();
	bomb.GetScriptScope().bombTimer <- bombTimer;
	AddThinkToEnt(bomb, "bombTimer");
}

//triggered twice before the cooldown ends to toggle buffs on/off
::crystalBuff <- function()
{
	for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
	{
		local player = PlayerInstanceFromIndex(i);

		if (player == null) continue;

		if (IsPlayerABot(player))
		{
			return;
		}
		if ((Time() - cooldowntime2 < 6))
		{
			player.RemoveCond(73);
			player.RemoveCond(32);
			player.RemoveCond(16);
			return;
		}
		player.AddCond(73);
		player.AddCond(32);
		player.AddCond(16);
		cooldowntime2 = Time();

		if (NetProps.GetPropInt(player, "m_lifeState") == 1 && (Time - cooldowntime2() > 5))
		{
			player.ForceRespawn();
			ClientPrint(null, 4 , msg);
			ClientPrint(null, 3 , "\x00071337ADDEAD PLAYERS REVIVED!\x0007");
		}
	}
}

::wavebarHack <- function()
{
	NetProps.SetPropIntArray(resource, "m_nMannVsMachineWaveClassFlags", 0, 011)
	NetProps.SetPropIntArray(resource, "m_nMannVsMachineWaveClassFlags", 0, 004)
}

::restartGens <- function()
{
	//supposed to loop through every generator button and remove every output, doesn't work lol
	
	for (local gen; gen = Entities.FindByName(gen, "PT_GENERATORBUTTON*"); )
	{
		local outputs; outputs = EntityOutputs.GetOutputTable(gen, "OnPressed" , tbl , index)

		printl(tbl)
		printl(index)

		for (local i = 0; i <= tbl.len(); i++)
		{
			EntityOutputs.RemoveOutput(gen , "OnPressed" , null , null , null);
		}
	}
	for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
	{
		local player = PlayerInstanceFromIndex(i);

		if (player == null) continue;

		if (!IsPlayerABot(player) || !player.HasBotTag("bot_tunnel2") || !player.HasBotTag("bot_tunnel3") || !player.HasBotTag("bot_tunnel4") )
			return;

		player.AddCustomAttribute("health regen", 1, 0);
	}
}

//trigger_multiples in every building is cringe, Tindall already did the work with env_soundscapes.
::findOutdoorSoundScapes <- function()
{
	for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
	{
		local player = PlayerInstanceFromIndex(i);

		if (player == null) continue;

		if (IsPlayerABot(player))
		{
			return;
		}

		if (NetProps.GetPropInt(player, "m_Local.m_audio.soundscapeIndex") != 34 ) //34 = sawmill.outside
		{
			player.RemoveCond(15);
			player.RemoveCustomAttribute("major move speed bonus");
			EntFireByHandle(player, "SetFogController" , "mist" , 0 , null , null);
			return;
		}

		player.AddCond(15);
		player.AddCustomAttribute("major move speed bonus", 0.75, 0);
		EntFireByHandle(player, "SetFogController" , "mist2" , 0 , null , null);
	}
}

//sets the gibby models for bots
//not all of these models may exist yet, as it's an ongoing project by trigger_hurt
//soldier/demo/heavy/pyro common and giant models have been packed into the map, others will need to be provided separately.

::setModels <- function(player, classindex)
{
	if (!IsPlayerABot(player))
	{
		return;
	}
	local ctable = {};
	ctable[1] <- "scout";
	ctable[2] <- "sniper";
	ctable[3] <- "soldier";
	ctable[4] <- "demo";
	ctable[5] <- "medic";
	ctable[6] <- "heavy";
	ctable[7] <- "pyro";
	ctable[8] <- "spy";
	ctable[9] <- "engineer";

	local cstring = ctable[classindex];
	local common = "models/bots/" + cstring + "/bot_"+ cstring + "_gibby.mdl"
	local giant = "models/bots/" + cstring + "_boss/bot_"+ cstring + "_boss_gibby.mdl"
	if(!NetProps.GetPropBool(player, "m_bIsMiniBoss") || player.GetHealth() < 1200)
	{
		EntFireByHandle(player, "SetCustomModelWithClassAnimations", common, 0.01, null, null);
		return;
	}
	EntFireByHandle(player, "SetCustomModelWithClassAnimations", giant, 0.01, null, null);
}
resource.ValidateScriptScope();
gamerules.ValidateScriptScope();
mvmlogic.ValidateScriptScope();

resource.GetScriptScope().theBigThink <- theBigThink;
gamerules.GetScriptScope().reverseTeams <- reverseTeams;
mvmlogic.GetScriptScope().ffCountdown <- ffCountdown;

AddThinkToEnt(resource, "theBigThink");
AddThinkToEnt(gamerules, "reverseTeams");