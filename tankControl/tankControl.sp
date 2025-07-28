#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Tank Control",
    author      = "Sascha R.",
    description = "Controls the amount of tanks spawning and their health",

};

ConVar g_hIncludeBots;

ConVar g_iPlayerThreshold1;
ConVar g_iPlayerThreshold2;

ConVar g_iTankBaseHealth;
ConVar g_iTankBonusHealthPerSurvivor;

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
    LogMessage("Tank spawn triggered!");

    SetTankHealth();

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

    LogMessage("Spawning extra tank...");

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