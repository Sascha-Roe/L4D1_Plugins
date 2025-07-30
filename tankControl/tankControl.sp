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
}

ConVar g_hIncludeBots;

ConVar g_iPlayerThreshold1;
ConVar g_iPlayerThreshold2;

ConVar g_iTankBaseHealth;
ConVar g_iTankBonusHealthPerSurvivor;

bool   g_bIsFireTank[MAXPLAYERS + 1];

int    g_iMaxTanks = 1;

public void OnPluginStart()
{
    LogMessage("Tank Control started!");

    g_hIncludeBots                = CreateConVar("tankcontrol_includebots", "1", "Set to 1 if you want plugin to process bots too.", FCVAR_PLUGIN | FCVAR_NOTIFY);
    g_iPlayerThreshold1           = CreateConVar("tankcontrol_playerThreshold_1", "6", "Set player threshold value when 2 tanks should spawn", FCVAR_PLUGIN | FCVAR_NOTIFY);
    g_iPlayerThreshold2           = CreateConVar("tankcontrol_playerThreshold_2", "8", "Set player threshold value when 3 tanks should spawn", FCVAR_PLUGIN | FCVAR_NOTIFY);
    g_iTankBaseHealth             = CreateConVar("tankcontrol_tankBaseHealth", "10000", "Set the base health of tank", FCVAR_PLUGIN | FCVAR_NOTIFY);
    g_iTankBonusHealthPerSurvivor = CreateConVar("tankcontrol_tankBonusHealthPerSurvivor", "1500", "Set the bonus health each tank gets for each survivor", FCVAR_PLUGIN | FCVAR_NOTIFY);

    AutoExecConfig(true, "tankControl");

    HookEvent("tank_spawn", onTankSpawn);
}

public void onTankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    SetTankHealth();

    int      client = GetClientOfUserId(event.GetInt("userid"));
    TankType type   = GetRandomSpecialTankType();
    int      packed = (view_as<int>(type) << 8) | client;
    if (type != Tank_Default)
    {
        CreateTimer(0.1, Timer_ApplySpecialTankEffects, packed);
    }

    int aliveTanks = GetAliveTankCount();
    LogMessage("Currently alive tanks: %i", aliveTanks);

    int survivorCount = GetSurvivorCount(g_hIncludeBots.BoolValue);

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

    // 50% chance for special tank
    if (roll > 50)
    {
        LogMessage("Normal tank rolled!");
        return Tank_Default;
    }

    int selection = GetRandomInt(1, 1);

    switch (selection)
    {
        case 1:
        {
            LogMessage("Fire tank rolled!");
            return Tank_Fire;
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
            PrintToChatAll("Fire tank spawned!");
        }
    }

    return Plugin_Stop;
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
    CreateTimer(0.1, CheckRockThrowLater, ref);

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
    else
    {
        LogMessage("Rock owner is not valid or not a FireTank.");
    }
    return Plugin_Stop;
}

public Action OnRockTouch(int entity, int other)
{
    if (!IsValidEntity(entity))
        return Plugin_Continue;

    float pos[3];
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
    CreateFireGridAtPosition(pos);

    SDKUnhook(entity, SDKHook_Touch, OnRockTouch);
    return Plugin_Continue;
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
            SpawnFire(firePos);
        }
    }

    EmitSoundToAll("weapons/molotov/explode.wav", .origin = center);
}

public void SpawnFire(float pos[3])
{
    int fire = CreateEntityByName("env_fire");
    if (fire == -1)
    {
        LogMessage("Feuer konnte nicht erzeugt werden!");
        return;
    }

    DispatchKeyValue(fire, "health", "10");           // fire duration in seconds
    DispatchKeyValue(fire, "firesize", "32");         // visible size
    DispatchKeyValue(fire, "fireattack", "1");        // damage per tick
    DispatchKeyValue(fire, "damagescale", "0.25");    // damage
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