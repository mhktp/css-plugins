#include <sourcemod>
#include <cstrike>
#include <sdktools_functions>
#include <sdktools_entinput>

#define LOOSE_INVICIBILITY 3.2
#define RESPAWN_ONJOIN 5.0
#define RESPAWN_AFTER_DEATH 1.1

#define HEALTH_REGEN_PLAYER_REPEAT 5.0
#define HEALTH_REGEN_COOLDOWN 4.5
#define HEALTH_PER_ACTION 15

#define REMOVE_ITEM_ON_GROUND 20.0
#define REMOVE_WEAPON_ON_GROUND 30.0

public Plugin myinfo =
{
	name = "CSS Deathmatch Plugin",
	author = "tomhk",
	description = "Deathmatch mod for CS:S : auto respawn, weapons and items cleaner, healh regen ,auto armor/money, awp/autos/grenades disablers and physics props removal.",
	version = "1.0",
	url = "https://tomhk.fr"
};

/*
	char output[256];
	Format(output,sizeof(output),"");
	PrintToServer(output);
*/

int gfspi_collisionGroups;
int gfspi_WeaponParent;
int gfspi_GrenadeWillExplode;
int gfspi_PlayerHelmet;
int gfspi_PlayerArmor;
int gfspi_Currency;
int gfspi_Health;

bool areWoundedRecently[MAXPLAYERS + 1];

ConVar gcvar_maxMoney = null;
ConVar gcvar_restrictedWeapons = null;
ConVar gcvar_restrictedGrenades = null;
ConVar gcvar_collisions = null;
ConVar gcvar_armor = null;
ConVar gcvar_autoregen = null;

public void OnPluginStart()
{
	PrintToServer("TOMHK DEATHMATCH PLUGIN - Init...");
	
	HookEvent("player_death",event_PlayerDeath);
	HookEvent("player_spawn",event_PlayerSpawn);
	HookEvent("player_team",event_OnTeam);
	HookEvent("player_hurt",event_OnHurt);
	
	gcvar_maxMoney = CreateConVar("toggle_maxmoney_on_spawn","1","When a player spawn, the player has automatically the max amount of money."); // max money is True
	gcvar_restrictedWeapons = CreateConVar("toggle_cant_buy_restricted_weapons","0","AWP/AUTOS are enabled/disabled."); // we can buy restricted weapons
	gcvar_restrictedGrenades = CreateConVar("toggle_cant_buy_grenades","0","Greandes are enabled/disabled.") // restricted is False
	gcvar_collisions = CreateConVar("toggle_collisions","1","Toggle collisions between players."); // collisions are False
	gcvar_armor = CreateConVar("toggle_armor",  "1", "When a pplayer spawn, the player has automatically an armor."); // armor is True 
	gcvar_autoregen = CreateConVar("toggle_regen", "1", "Auto regen players"); // restricted weapons is False
	
	RegAdminCmd("dmmod_destroy_physics_objects",cmd_DestroyPhysicsObjects,ADMFLAG_SLAY,"Destroy all unnamed physics props.");
	
	LoadTranslations("common.phrases.txt"); // Required for FindTarget fail reply
	
	// GLOBAL VARIABLES
	gfspi_collisionGroups = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");
	gfspi_Currency = FindSendPropInfo("CCSPlayer", "m_iAccount");
	gfspi_PlayerHelmet = FindSendPropInfo("CCSPlayer", "m_bHasHelmet");
	gfspi_PlayerArmor = FindSendPropInfo("CCSPlayer", "m_ArmorValue"); 
	gfspi_WeaponParent = FindSendPropInfo("CBaseCombatWeapon", "m_hOwnerEntity");
	gfspi_GrenadeWillExplode = FindSendPropInfo("CBaseCSGrenadeProjectile","m_flDetonateTime"); 
	gfspi_Health = FindSendPropInfo("CBasePlayer", "m_iHealth");
	
	ServerCommand("mp_ignore_round_win_conditions 1");
	
	// Remove item on ground
	CreateTimer(REMOVE_ITEM_ON_GROUND, Timer_RemoveItemOnGround, _, TIMER_REPEAT);
	
	// Regenerate wounded players
	CreateTimer(HEALTH_REGEN_PLAYER_REPEAT, Timer_RegenPlayer, _, TIMER_REPEAT);
	
	
	PrintToServer("TOMHK DEATHMATCH PLUGIN - Running...");
}

public void OnConfigsExecuted() { // DEAR LORD DO NOT USE OnMapStart THIS IS A TRAP DO NOT USE IT !!!

	// Disable C4 and hostages rescue.
	DisableWinConditions();
	
	// Disable certain maps properties like cs_havana random doors
	
	char mapname[32];
	GetCurrentMap(mapname, sizeof(mapname));
	DisableSpecificConditons(mapname);
}

//========= Events Functions =========


public void event_OnTeam(Event event, const char[] name, bool dontBreadcast)  {

	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (IsPlayerAlive(client) || GetClientCount(true) < 2)  // true because we don't count player connecting... 
		return;
	
	PrintHintText(client, "You'll spawn in 5 seconds");
	CreateTimer(RESPAWN_ONJOIN, async_ForceSpawnPlayer,client);
}


public void event_PlayerDeath(Event event, const char[] name, bool dontBreadcast) {
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if(!GetConVarBool(gcvar_maxMoney) && !(client == attacker)) { // I don't want suicides to make money...
		int money = GetEntProp(client, Prop_Send, "m_iAccount");
		SetEntData(client, gfspi_Currency, min(money + 800,16000));
	}
	CreateTimer(RESPAWN_AFTER_DEATH, async_ForceSpawnPlayer,client);	// timer because it's asynchronous for some reasons
}

public void event_PlayerSpawn(Event event, const char[] name, bool dontBreadcast) {

	int client = GetClientOfUserId(event.GetInt("userid")); 
	SetEntProp(client, Prop_Data, "m_takedamage", 0, 1); // No damage
	SetEntityRenderFx (client,RENDERFX_DISTORT); // render transparent
	CreateTimer(LOOSE_INVICIBILITY, async_LooseInvincibility ,client);	
	
	if(GetConVarBool(gcvar_collisions)) 
		SetEntData(client, gfspi_collisionGroups, 2, 4, true);
	
	// Money and armor :
	if(GetConVarBool(gcvar_maxMoney)) {
		SetEntData(client, gfspi_Currency, 16000); // eveytime he spawns, he will have this amount of money.
	}
	
	if(GetConVarBool(gcvar_armor)) {
		SetEntData(client, gfspi_PlayerHelmet, true);
		SetEntData(client, gfspi_PlayerArmor, 100);
	}
}

public void event_OnHurt(Event event, const char[] name, bool dontBreadcast) {

	int client = GetClientOfUserId(event.GetInt("userid")); 
	if(!IsPlayerAlive(client)) return;
	
	areWoundedRecently[client] = true;
	CreateTimer(HEALTH_REGEN_COOLDOWN, async_CanRegen ,client); // take some time before regen 
}

//========= Command Functions =========

public Action cmd_DestroyPhysicsObjects(int client, int args) {

	char classname[32];
	int maxEnt = GetMaxEntities();
	for (int entity = MaxClients +1; entity <= maxEnt; entity++)
	{
		if (!IsValidEntity(entity) || !IsValidEdict(entity))
			continue;
			
		GetEntityClassname(entity, classname, sizeof(classname));

		if(strcmp(classname, "prop_physics_multiplayer", false)) 
			continue;
		
		char entityName[MAX_NAME_LENGTH];
		int entityExist = GetEntPropString(entity,Prop_Data,"m_iName",entityName,sizeof(entityName));
		
		if (entityExist != 0 && !StrEqual(entityName,"oildrums")) // we want only unnamed props
			continue;
			
		RemoveEdict(entity);
	}	
	return Plugin_Handled;
}

//========= Action Async Functions =========

public Action async_ForceSpawnPlayer(Handle timer, int client) {

	if (!IsValidEntity(client) || !IsValidEdict(client)) return Plugin_Handled;
	
	if (GetClientTeam(client) == CS_TEAM_SPECTATOR) return Plugin_Handled; //and we don't want to spawn spectators
	
	CS_RespawnPlayer(client);
	return Plugin_Handled;
}

public Action async_LooseInvincibility(Handle timer, int client) {

	if (!IsValidEntity(client) || !IsValidEdict(client)) return Plugin_Handled;
	SetEntProp(client, Prop_Data, "m_takedamage", 2, 1);
	SetEntityRenderFx (client,RENDERFX_NONE);
	return Plugin_Handled;
}

public Action async_CanRegen(Handle timer, int client) {

	// No validation of entity because he might have quit and the new plyare with the same player index won't get regen or whatever.
	areWoundedRecently[client] = false;
	return Plugin_Handled;
}

public Action async_DeleteWeapon(Handle timer, int entity) { 
	
	if (IsValidEntity(entity) && IsValidEdict(entity)) {
		if( GetEntDataEnt2(entity, gfspi_WeaponParent) == -1) {
			RemoveEdict(entity);
		}
	}
	return Plugin_Handled;
}

//========= Action Forwards =========

public Action CS_OnCSWeaponDrop(int client, int weaponIndex) { 

	CreateTimer(REMOVE_WEAPON_ON_GROUND, async_DeleteWeapon,weaponIndex); 
	return Plugin_Continue;
}

public Action CS_OnGetWeaponPrice(int client, const char[] weapon, int& price) {
	
	if(!GetConVarBool(gcvar_restrictedWeapons)) 
		return Plugin_Continue;
	
	if (StrContains(weapon,"awp") != -1 || StrContains(weapon,"sg550") != -1 || StrContains(weapon,"g3sg1") != -1) {
		price = 17000;
		PrintHintText(client,"The weapon you chose is forbidden.\n To change this, use '/votemenu' and choose 'toggle_cant_buy_restricted_weapons'.");
	}
	
	if (!GetConVarBool(gcvar_restrictedGrenades)) 
		return Plugin_Changed;
	
	if (StrContains(weapon,"flashbang") != -1 || StrContains(weapon,"hegrenade") != -1 || StrContains(weapon,"smokegrenade") != -1) {
		price = 17000;
		PrintHintText(client,"Grenades are forbidden.\n To change this, use '/votemenu' and choose 'toggle_cant_buy_grenades'.");
	}
	
	return Plugin_Changed; // otherwise the plugin fails and the prices don't change
}

//========= Action Repeat Timers =========

public Action Timer_RemoveItemOnGround(Handle timer) {
	char item[64];
	int maxEnt = GetMaxEntities();
	for (int i = MaxClients +1; i <= maxEnt; i++)
	{
		if ( IsValidEdict(i) && IsValidEntity(i) ) {
			GetEdictClassname (i, item, sizeof(item));
			if (  (StrContains(item,"item_defuser") != -1) || ((StrContains(item, "item_") != -1)  && ((GetEntDataEnt2(i, gfspi_WeaponParent) == -1 ) || (GetEntDataEnt2(i, gfspi_GrenadeWillExplode) == -1 ) ))) {
				RemoveEdict(i);
			}
		}
	}	
}

public Action Timer_RegenPlayer(Handle timer) {

	if (!GetConVarBool(gcvar_autoregen)) return Plugin_Handled;
	
	for (int player = 1 ;player<=MaxClients;player++) // entity 0 is server
	{
		if ( IsValidEdict(player) && IsValidEntity(player) ) {
			if (IsPlayerAlive(player)) {
				int health = GetEntProp(player, Prop_Data, "m_iHealth", 2, 0);
				if (health < 100 && !areWoundedRecently[player]) 
					SetEntData(player, gfspi_Health, min(health + HEALTH_PER_ACTION,100)); 
			}	
		}
	}	
	return Plugin_Handled;
}

//========= Other =========

public void DisableWinConditions() {

	char classname[32];
	int maxEnt = GetMaxEntities();
	for (int entity = MaxClients + 1; entity <= maxEnt; entity++) // looping because it may have multiple entities with the same class.
	{
		if (!IsValidEntity(entity) || !IsValidEdict(entity))
			continue;
			
		GetEntityClassname(entity, classname, sizeof(classname));
		
		if (!strcmp(classname, "func_bomb_target", false))
			AcceptEntityInput(entity, "Disable");
		else if (!strcmp(classname, "func_hostage_rescue", false))
			AcceptEntityInput(entity, "Disable");
	}
}

public void DisableSpecificConditons(const char[] mapname) {

	char classname[32];
	int maxEnt = GetMaxEntities();
	for (int entity = MaxClients + 1; entity <= maxEnt; entity++) 
	{
		if (!IsValidEntity(entity) || !IsValidEdict(entity))
			continue;
		GetEntityClassname(entity, classname, sizeof(classname));
		if(!strcmp(mapname, "cs_havana", false)) {
			if (!strcmp(classname, "func_brush", false)) 
				AcceptEntityInput(entity, "Kill");
		}
	}
}

//========= Math Functions =========

public int min(int a, int b) {
	return a < b ? a : b; 
}