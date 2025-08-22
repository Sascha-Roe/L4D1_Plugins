#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

public Plugin myinfo =
{
    name        = "Tank Control",
    author      = "Sascha R.",
    description = "Controls the amount of tanks spawning and their health",

};

enum TankType
{
    Tank_Default = 0,
    Tank_Fire,
    Tank_Speed,
    Tank_Teleport,
}

ConVar g_hIncludeBots;
ConVar g_iSpecialTankChance;

ConVar g_iPlayerThreshold1;
ConVar g_iPlayerThreshold2;

ConVar g_iTankBaseHealth;
ConVar g_iTankBonusHealthPerSurvivor;

ConVar g_fSpeedTankBaseSpeedMultiplier;
ConVar g_fSpeedTankBoostMultiplier;
ConVar g_fSpeedTankBoostDuration;
ConVar g_hSpeedTankBoostCooldownInterval;

bool   g_bIsFireTank[MAXPLAYERS + 1];

bool   g_bIsSpeedTank[MAXPLAYERS + 1];
bool   g_bIsBoosted[MAXPLAYERS + 1];
int    g_BoostCooldown[MAXPLAYERS + 1];
char   g_szBoostSoundPath[MAXPLAYERS + 1][PLATFORM_MAX_PATH];

bool   g_bIsTeleportTank[MAXPLAYERS + 1];

int    g_iMaxTanks = 1;

public void OnPluginStart()
{
    LogMessage("Tank Control started!");

    g_hIncludeBots                    = CreateConVar("tankcontrol_includebots", "0", "Set to 1 if you want plugin to process bots too.", FCVAR_PLUGIN | FCVAR_NOTIFY);
    g_iSpecialTankChance              = CreateConVar("tankcontrol_specialTankChance", "65", "Set chance for a special tank to spawn in percent.", FCVAR_PLUGIN | FCVAR_NOTIFY);
    g_iPlayerThreshold1               = CreateConVar("tankcontrol_playerThreshold_1", "6", "Set player threshold value when 2 tanks should spawn", FCVAR_PLUGIN | FCVAR_NOTIFY);
    g_iPlayerThreshold2               = CreateConVar("tankcontrol_playerThreshold_2", "8", "Set player threshold value when 3 tanks should spawn", FCVAR_PLUGIN | FCVAR_NOTIFY);
    g_iTankBaseHealth                 = CreateConVar("tankcontrol_tankBaseHealth", "10000", "Set the base health of tank", FCVAR_PLUGIN | FCVAR_NOTIFY);
    g_iTankBonusHealthPerSurvivor     = CreateConVar("tankcontrol_tankBonusHealthPerSurvivor", "1500", "Set the bonus health each tank gets for each survivor", FCVAR_PLUGIN | FCVAR_NOTIFY);

    g_fSpeedTankBaseSpeedMultiplier   = CreateConVar("tankcontrol_speedTankBaseSpeedMultiplier", "0.875", "Set the Speed Tank's base speed multiplier (1.0 = normal speed, 0.9 = 90% of normal speed, etc.)", FCVAR_PLUGIN | FCVAR_NOTIFY);
    g_fSpeedTankBoostMultiplier       = CreateConVar("tankcontrol_speedTankBoostMultiplier", "1.2", "Set the Speed Tank's boost speed multiplier (1.0 = normal speed, 1.1 = 110% of normal speed, etc.)", FCVAR_PLUGIN | FCVAR_NOTIFY);
    g_fSpeedTankBoostDuration         = CreateConVar("tankcontrol_speedTankBoostDuration", "15.0", "Set the Speed Tank's boost duration in seconds", FCVAR_PLUGIN | FCVAR_NOTIFY);
    g_hSpeedTankBoostCooldownInterval = CreateConVar("tankcontrol_speedTankBoostCooldownInterval", "10-30", "Set the Speed Tank's cooldown interval (e. g. 10-30 = cooldown for speed boost lasts somewhere between 10 and 30 seconds)", FCVAR_PLUGIN | FCVAR_NOTIFY);

    AutoExecConfig(true, "tankControl");

    PrecacheSound("weapons/hegrenade/explode3.wav", true);

    HookEvent("tank_spawn", onTankSpawn);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            OnClientPutInServer(i);
        }
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnSurvivorDamaged);
}

public void onTankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    SetTankHealth();

    int client = GetClientOfUserId(event.GetInt("userid"));

    // reset flag to prevent normal tank from throwing burning rocks
    resetFlags(client);

    TankType type   = GetRandomSpecialTankType();
    int      packed = (view_as<int>(type) << 8) | client;
    if (type != Tank_Default && !IsSpecialTankAlive())
    {
        CreateTimer(0.1, Timer_ApplySpecialTankEffects, packed);
    }
    else
    {
        PrintToChatAll("\x04[Mutant Tanks] \x01Normal tank spawned!");
    }

    int survivorCount = GetSurvivorCount(g_hIncludeBots.BoolValue);

    if (survivorCount < g_iPlayerThreshold1.IntValue)
    {
        g_iMaxTanks = 1;
        LogMessage("survivorCount=%d, g_iPlayerThreshold1=%d -> g_iMaxTanks=%d", survivorCount, g_iPlayerThreshold1.IntValue, g_iMaxTanks);
    }
    if (survivorCount >= g_iPlayerThreshold1.IntValue)
    {
        g_iMaxTanks = 2;
        LogMessage("survivorCount=%d, g_iPlayerThreshold1=%d -> g_iMaxTanks=%d", survivorCount, g_iPlayerThreshold1.IntValue, g_iMaxTanks);
    }
    if (survivorCount >= g_iPlayerThreshold2.IntValue)
    {
        g_iMaxTanks = 3;
        LogMessage("survivorCount=%d, g_iPlayerThreshold1=%d -> g_iMaxTanks=%d", survivorCount, g_iPlayerThreshold2.IntValue, g_iMaxTanks);
    }

    int aliveTanks = GetAliveTankCount();
    LogMessage("Currently alive tanks: %i", aliveTanks);

    if (aliveTanks >= g_iMaxTanks)
    {
        LogMessage("Too many tanks alive (%d/%d), skipping spawn!", aliveTanks, g_iMaxTanks);
        return;
    }

    int tank = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(tank) || !IsTank(tank))
    {
        return;
    }

    CreateTimer(1.0, SpawnExtraTank, tank);
}

public Action SpawnExtraTank(Handle timer, any existingTankClient)
{
    int aliveTanks = GetAliveTankCount();

    if (aliveTanks >= g_iMaxTanks)
    {
        LogMessage("Too many tanks alive (%d/%d), skipping spawn!", aliveTanks, g_iMaxTanks);
        return Plugin_Stop;
    }

    if (!IsValidClient(existingTankClient) || !IsTank(existingTankClient))
    {
        return Plugin_Stop;
    }

    int commandClient = GetAnyRealPlayer();
    if (commandClient == 0)
    {
        return Plugin_Stop;
    }

    int flags = GetCommandFlags("z_spawn");
    SetCommandFlags("z_spawn", flags & ~FCVAR_CHEAT);
    FakeClientCommand(commandClient, "z_spawn tank auto");
    SetCommandFlags("z_spawn", flags);

    int updatedAliveTanks = GetAliveTankCount();
    LogMessage("New tank spawned, (%d/%d) tanks alive!", updatedAliveTanks, g_iMaxTanks);

    return Plugin_Stop;
}

TankType GetRandomSpecialTankType()
{
    int roll = GetRandomInt(1, 100);

    // 35% chance for default tank by default
    if (roll <= (100 - g_iSpecialTankChance.IntValue))
    {
        LogMessage("Normal tank rolled!");
        return Tank_Default;
    }

    int selection = GetRandomInt(1, 3);

    switch (selection)
    {
        case 1:
        {
            LogMessage("Fire tank rolled!");
            return Tank_Fire;
        }
        case 2:
        {
            return Tank_Speed;
        }
        case 3:
        {
            return Tank_Teleport;
        }
    }

    return Tank_Default;
}

public Action Timer_ApplySpecialTankEffects(Handle timer, any packed)
{
    int      client = packed & 0xFF;
    TankType type   = view_as<TankType>(packed >> 8);

    if (!IsValidClient(client) || !IsTank(client))
    {
        return Plugin_Stop;
    }

    LogMessage("Apply Special Effects: %d", type);

    switch (type)
    {
        case Tank_Fire:
        {
            g_bIsFireTank[client] = true;
            SetEntityRenderColor(client, 255, 0, 0, 255);
            SDKHook(client, SDKHook_OnTakeDamage, OnFireTankDamage);
            CreateTimer(0.2, FireTank_TrailTimer, GetClientUserId(client), TIMER_REPEAT);
            PrintToChatAll("\x04[Mutant Tanks] \x01Fire tank spawned!");
        }
        case Tank_Speed:
        {
            g_bIsSpeedTank[client] = true;
            SetEntityRenderColor(client, 0, 255, 0, 255);
            SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", g_fSpeedTankBaseSpeedMultiplier.FloatValue);
            CreateTimer(1.0, SpeedTank_BoostTimer, GetClientUserId(client), TIMER_REPEAT);
            PrintToChatAll("\x04[Mutant Tanks] \x01Speed tank spawned!");
        }
        case Tank_Teleport:
        {
            g_bIsTeleportTank[client] = true;
            SetEntityRenderColor(client, 128, 0, 128, 255);
            PrintToChatAll("\x04[Mutant Tanks] \x01Teleport tank spawned!");
        }
    }

    return Plugin_Stop;
}

public Action SpeedTank_BoostTimer(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client) || !IsTank(client) || !IsPlayerAlive(client))
        return Plugin_Stop;

    if (g_bIsBoosted[client])
    {
        PrintHintTextToAll("[Speed Tank] Boost active!");
        return Plugin_Continue;
    }

    if (g_BoostCooldown[client] > 0)
    {
        PrintHintTextToAll("[Speed Tank] Boost in %d...", g_BoostCooldown[client]);
        g_BoostCooldown[client]--;
        return Plugin_Continue;
    }

    g_bIsBoosted[client] = true;
    SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", g_fSpeedTankBoostMultiplier.FloatValue);
    CreateTimer(1.0, SpeedTank_SoundLoop, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(g_fSpeedTankBoostDuration.FloatValue, ResetSpeedTankSpeed, GetClientUserId(client));

    return Plugin_Continue;
}

public Action ResetSpeedTankSpeed(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client) || !IsTank(client) || !IsPlayerAlive(client))
        return Plugin_Stop;

    SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", g_fSpeedTankBaseSpeedMultiplier.FloatValue);

    // stop emitting sounds
    if (g_szBoostSoundPath[client][0] != '\0')
    {
        StopSound(client, SNDCHAN_STATIC, g_szBoostSoundPath[client]);
        g_szBoostSoundPath[client][0] = '\0'
    }

    g_bIsBoosted[client]    = false;

    int delay               = GetRandomCooldownFromConVar(g_hSpeedTankBoostCooldownInterval);

    g_BoostCooldown[client] = delay;

    return Plugin_Stop;
}

public Action SpeedTank_SoundLoop(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client) || !IsPlayerAlive(client) || !IsTank(client) || !g_bIsBoosted[client])
        return Plugin_Stop;

    int soundIndex = GetRandomInt(1, 7);
    Format(g_szBoostSoundPath[client], sizeof(g_szBoostSoundPath[]), "player/tank/voice/pain/tank_fire_0%d.wav", soundIndex);

    EmitSoundToAll(g_szBoostSoundPath[client], client, SNDCHAN_STATIC, SNDLEVEL_SCREAMING, SND_NOFLAGS, 1.0);
    return Plugin_Continue;
}

// sawn fire trail where tank is walking
public Action FireTank_TrailTimer(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsValidClient(client) || !IsPlayerAlive(client) || !g_bIsFireTank[client]) return Plugin_Stop;

    float pos[3];
    GetClientAbsOrigin(client, pos);

    SpawnFire(pos, "4", "1");
    return Plugin_Continue;
}

// prevent fire tank from getting fire damage
public Action OnFireTankDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (IsValidClient(victim) && IsTank(victim))
    {
        if (damagetype & DMG_BURN || damagetype & DMG_SLOWBURN)
        {
            damage = 0.0;
            return Plugin_Handled;
        }
    }
    return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (StrEqual(classname, "tank_rock"))
    {
        SDKHook(entity, SDKHook_SpawnPost, OnRockSpawned);
    }
}

public Action OnRockSpawned(int entity)
{
    int ref = EntIndexToEntRef(entity);
    CreateTimer(0.3, CheckRockThrowLater, ref);

    return Plugin_Continue;
}

public Action CheckRockThrowLater(Handle timer, any ref)
{
    int entity = EntRefToEntIndex(ref);
    if (entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity))
    {
        return Plugin_Stop;
    }

    int owner = GetEntPropEnt(entity, Prop_Send, "m_hThrower");

    if (IsValidClient(owner) && g_bIsFireTank[owner])
    {
        SDKHook(entity, SDKHook_Touch, OnRockTouch);
    }
    else if (IsValidClient(owner) && g_bIsBoosted[owner]) {
        float velocity[3];
        GetEntPropVector(entity, Prop_Data, "m_vecVelocity", velocity);

        float speed = GetVectorLength(velocity);
        if (speed < 50.0)
        {
            CreateTimer(0.05, CheckRockThrowLater, ref);
            return Plugin_Stop;
        }

        ScaleVector(velocity, 1.75);
        TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, velocity);
    }
    else if (IsValidClient(owner) && g_bIsTeleportTank[owner]) {
        SDKHook(entity, SDKHook_Touch, OnRockTouch);
    }
    else
    {
        LogMessage("Rock owner is not valid or not a FireTank.");
    }
    return Plugin_Stop;
}

// spawn fire where the fire tank rock hits
public Action OnRockTouch(int entity, int other)
{
    int owner = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
    if (!IsValidEntity(entity) || !IsTank(owner))
        return Plugin_Continue;

    float pos[3];
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);

    if (g_bIsFireTank[owner])
    {
        CreateFireGridAtPosition(pos);
    }

    if (g_bIsTeleportTank[owner])
    {
        float ang[3];
        GetClientAbsAngles(owner, ang);
        TeleportEntity(owner, pos, ang, NULL_VECTOR);
        EmitSoundToAll("ambient/energy/zap9.wav", owner, SNDCHAN_AUTO, SNDLEVEL_RAIDSIREN, SND_NOFLAGS, 1.0);
    }

    SDKUnhook(entity, SDKHook_Touch, OnRockTouch);
    return Plugin_Continue;
}

public Action OnSurvivorDamaged(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (!IsValidClient(attacker) || !IsTank(attacker)) return Plugin_Continue;

    if (g_bIsFireTank[attacker])
    {
        CreateTimer(0.5, DealFireTankDoT, GetClientUserId(victim));
    }
    if (g_bIsTeleportTank[attacker] && IsValidEntity(inflictor))
    {
        char cls[32];
        GetEdictClassname(inflictor, cls, sizeof(cls));
        if (StrEqual(cls, "tank_rock"))
        {
            float pos[3], ang[3];
            GetEntPropVector(inflictor, Prop_Send, "m_vecOrigin", pos);
            GetClientAbsAngles(attacker, ang);
            TeleportEntity(attacker, pos, ang, NULL_VECTOR);
            EmitSoundToAll("ambient/energy/zap9.wav", attacker, SNDCHAN_AUTO, SNDLEVEL_RAIDSIREN, SND_NOFLAGS, 1.0);
        }
    }

    return Plugin_Continue;
}

// deal fire damage to player if hit by fire tank
public Action DealFireTankDoT(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client) || !IsPlayerAlive(client)) return Plugin_Stop;

    int   attacker  = 0;
    int   inflictor = 0;
    float damage    = 5.0;
    int   dmgType   = DMG_BURN;

    LogMessage("inflicting fire damage!");

    SDKHooks_TakeDamage(client, inflictor, attacker, damage, dmgType);
    return Plugin_Stop;
}

void CreateFireGridAtPosition(float center[3], float spread = 25.0)
{
    for (int x = -2; x <= 2; x++)
    {
        for (int y = -2; y <= 2; y++)
        {
            float firePos[3];
            firePos[0] = center[0] + (x * spread);
            firePos[1] = center[1] + (y * spread);
            firePos[2] = center[2];
            SpawnFire(firePos, "32", "10");
        }
    }

    EmitSoundToAll("weapons/hegrenade/explode3.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_SCREAMING, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, -1, center);
}

public void SpawnFire(float pos[3], char[] fireSize, char[] duration)
{
    int fire = CreateEntityByName("env_fire");
    if (fire == -1)
    {
        LogMessage("Feuer konnte nicht erzeugt werden!");
        return;
    }

    DispatchKeyValue(fire, "health", duration);      // fire duration in seconds
    DispatchKeyValue(fire, "firesize", fireSize);    // visible size
    DispatchKeyValue(fire, "fireattack", "1");       // damage per tick
    DispatchKeyValue(fire, "damagescale", "0.1");    // damage
    DispatchKeyValue(fire, "spawnflags", "132");

    DispatchSpawn(fire);
    TeleportEntity(fire, pos, NULL_VECTOR, NULL_VECTOR);
    AcceptEntityInput(fire, "StartFire");
}

public void SetTankHealth()
{
    int survivorCount = GetSurvivorCount(g_hIncludeBots.BoolValue);

    int tankHealth    = g_iTankBaseHealth.IntValue + (survivorCount * g_iTankBonusHealthPerSurvivor.IntValue);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsTank(i) && IsPlayerAlive(i))
        {
            SetEntProp(i, Prop_Send, "m_iHealth", tankHealth);
            SetEntProp(i, Prop_Send, "m_iMaxHealth", tankHealth);
            LogMessage("Tank #%d health set to %d", i, tankHealth);
        }
    }
    return;
}

int GetAnyRealPlayer()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            return i;
        }
    }
    return 0;
}

int GetSurvivorCount(bool includeBots = true)
{
    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && GetClientTeam(i) == 2)    // Team 2 = Survivors
        {
            if (!IsFakeClient(i) || includeBots)
            {
                count++;
            }
        }
    }
    return count;
}

int GetAliveTankCount()
{
    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsTank(i)
            && IsPlayerAlive(i))
        {
            count++;
        }
    }
    return count;
}

bool IsTank(int client)
{
    return (IsClientInGame(client)
            && GetClientTeam(client) == 3
            && GetEntProp(client, Prop_Send, "m_zombieClass") == 5);
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

bool IsSpecialTankAlive()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && IsTank(i))
        {
            if (g_bIsFireTank[i] || g_bIsSpeedTank[i] || g_bIsTeleportTank[i])
            {
                return true;
            }
        }
    }
    return false;
}

public void resetFlags(int client)
{
    g_bIsFireTank[client]         = false;
    g_bIsSpeedTank[client]        = false;
    g_bIsBoosted[client]          = false;
    g_bIsTeleportTank[client]     = false;
    g_BoostCooldown[client]       = 0;
    g_szBoostSoundPath[client][0] = '\0';
}

int GetRandomCooldownFromConVar(ConVar convar)
{
    char buffer[32];
    convar.GetString(buffer, sizeof(buffer));

    char parts[2][16];
    ExplodeString(buffer, "-", parts, sizeof(parts), sizeof(parts[]));

    int min = StringToInt(parts[0]);
    int max = StringToInt(parts[1]);

    return GetRandomInt(min, max);
}
