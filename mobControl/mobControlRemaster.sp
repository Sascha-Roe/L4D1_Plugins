#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Mob Control Remade",
    author      = "Sascha R.",
    description = "Remake of Olj's Mob Control, without infinite mob bug",
};

ConVar g_hMegaMobSize;
ConVar g_hMobMinSize;
ConVar g_hMobMaxSize;
ConVar g_hCommonLimit;

ConVar g_hMobSpawnMinIntervalEasy;
ConVar g_hMobSpawnMinIntervalNormal;
ConVar g_hMobSpawnMinIntervalHard;
ConVar g_hMobSpawnMinIntervalExpert;

ConVar g_hMobSpawnMaxIntervalEasy;
ConVar g_hMobSpawnMaxIntervalNormal;
ConVar g_hMobSpawnMaxIntervalHard;
ConVar g_hMobSpawnMaxIntervalExpert;

int    g_iBaseMobValues[3];
int    g_iBaseCommonLimit;

ConVar g_hPrintLogs;
ConVar g_hZombiesPerSurvivor;
ConVar g_hIncludeBots;
ConVar g_hMobMinSpawnInterval;
ConVar g_hMobMaxSpawnInterval;

// TODO: Tank HP?
public OnPluginStart()
{
    LogMessage("Mob Control Remade started!");

    g_hMegaMobSize               = FindConVar("z_mega_mob_size");
    g_hMobMinSize                = FindConVar("z_mob_spawn_min_size");
    g_hMobMaxSize                = FindConVar("z_mob_spawn_max_size");
    g_hCommonLimit               = FindConVar("z_common_limit");

    g_hMobSpawnMinIntervalEasy   = FindConVar("z_mob_spawn_min_interval_easy");
    g_hMobSpawnMinIntervalNormal = FindConVar("z_mob_spawn_min_interval_normal");
    g_hMobSpawnMinIntervalHard   = FindConVar("z_mob_spawn_min_interval_hard");
    g_hMobSpawnMinIntervalExpert = FindConVar("z_mob_spawn_min_interval_expert");

    g_hMobSpawnMaxIntervalEasy   = FindConVar("z_mob_spawn_max_interval_easy");
    g_hMobSpawnMaxIntervalNormal = FindConVar("z_mob_spawn_max_interval_normal");
    g_hMobSpawnMaxIntervalHard   = FindConVar("z_mob_spawn_max_interval_hard");
    g_hMobSpawnMaxIntervalExpert = FindConVar("z_mob_spawn_max_interval_expert");

    g_hPrintLogs                 = CreateConVar("l4d_mobcontrol_zombiestoadd_print_logs", "0", "Set to 1 if you want plugin to print log messages", FCVAR_PLUGIN | FCVAR_NOTIFY);
    // e. g. sm_cvar l4d_mobcontrol_zombiestoadd 12
    g_hZombiesPerSurvivor        = CreateConVar("l4d_mobcontrol_zombiestoadd", "8", "Sets how much zombies to add per survivor", FCVAR_PLUGIN | FCVAR_NOTIFY);
    // e. g. sm_cvar l4d_mobcontrol_includebots 1
    g_hIncludeBots               = CreateConVar("l4d_mobcontrol_includebots", "1", "Set to 1 if you want plugin to process bots too.", FCVAR_PLUGIN | FCVAR_NOTIFY);

    g_hMobMinSpawnInterval       = CreateConVar("l4d_mobcontrol_min_spawn_interval", "90", "Sets minimum time that has to pass before next mob can spawn", FCVAR_PLUGIN | FCVAR_NOTIFY);
    HookConVarChange(g_hMobMinSpawnInterval, UpdateMobMinInterval);

    g_hMobMaxSpawnInterval = CreateConVar("l4d_mobcontrol_max_spawn_interval", "180", "Sets maximum time that has to pass before next mob can spawn", FCVAR_PLUGIN | FCVAR_NOTIFY);
    HookConVarChange(g_hMobMaxSpawnInterval, UpdateMobMaxInterval);

    char temp[16];
    GetConVarDefault(g_hMegaMobSize, temp, sizeof(temp));
    g_iBaseMobValues[0] = StringToInt(temp);
    GetConVarDefault(g_hMobMinSize, temp, sizeof(temp));
    g_iBaseMobValues[1] = StringToInt(temp);
    GetConVarDefault(g_hMobMaxSize, temp, sizeof(temp));
    g_iBaseMobValues[2] = StringToInt(temp);
    GetConVarDefault(g_hCommonLimit, temp, sizeof(temp));
    g_iBaseCommonLimit = StringToInt(temp);

    if (g_hPrintLogs.BoolValue)
    {
        LogMessage("Basevalues loaded: Mega=%d Min=%d Max=%d CommonLimit=%d", g_iBaseMobValues[0], g_iBaseMobValues[1], g_iBaseMobValues[2], g_iBaseCommonLimit);
    }

    UpdateMobSizes();

    CreateTimer(90.0, Timer_UpdateMobSizes, _, TIMER_REPEAT);

    AutoExecConfig(true, "mobControl_remade");
}

public Action Timer_UpdateMobSizes(Handle timer)
{
    UpdateMobSizes();
    return Plugin_Continue;
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

void UpdateMobSizes()
{
    int survivorCount      = GetSurvivorCount(g_hIncludeBots.BoolValue);
    int zombiesPerSurvivor = g_hZombiesPerSurvivor.IntValue;

    int mobValues[3];
    for (int i = 0; i < 3; i++)
    {
        mobValues[i] = g_iBaseMobValues[i] + survivorCount * zombiesPerSurvivor;
    }

    float bonus       = float(survivorCount) * (float(zombiesPerSurvivor) / 6.0);
    int   commonLimit = g_iBaseCommonLimit + RoundToCeil(bonus);

    SetConVarSafe(g_hMegaMobSize, mobValues[0]);
    SetConVarSafe(g_hMobMinSize, mobValues[1]);
    SetConVarSafe(g_hMobMaxSize, mobValues[2]);

    SetConVarSafe(g_hCommonLimit, commonLimit);

    if (g_hPrintLogs.BoolValue)
    {
        int newMegaMobValue = GetConVarInt(g_hMegaMobSize);
        int newMobMinValue  = GetConVarInt(g_hMobMinSize);
        int newMobMaxValue  = GetConVarInt(g_hMobMaxSize);
        int newCommonLimit  = GetConVarInt(g_hCommonLimit);

        LogMessage("Survivors: %d -> MobSizes: Mega=%d Min=%d Max=%d CommonLimit=%d", survivorCount, newMegaMobValue, newMobMinValue, newMobMaxValue, newCommonLimit);
    }
}

void UpdateMobMinInterval(ConVar convar, const char[] oldValue, const char[] newValue)
{
    int newVal = StringToInt(newValue);

    SetConVarSafe(g_hMobSpawnMinIntervalEasy, newVal);
    SetConVarSafe(g_hMobSpawnMinIntervalNormal, newVal);
    SetConVarSafe(g_hMobSpawnMinIntervalHard, newVal);
    SetConVarSafe(g_hMobSpawnMinIntervalExpert, newVal);

    if (g_hPrintLogs.BoolValue)
    {
        int newMinEasy   = GetConVarInt(g_hMobSpawnMinIntervalEasy);
        int newMinNormal = GetConVarInt(g_hMobSpawnMinIntervalNormal);
        int newMinHard   = GetConVarInt(g_hMobSpawnMinIntervalHard);
        int newMinExpert = GetConVarInt(g_hMobSpawnMinIntervalExpert);

        LogMessage("z_mob_spawn_min_interval set: Easy=%d Normal=%d Hard=%d Expert=%d", newMinEasy, newMinNormal, newMinHard, newMinExpert);
    }
}

void UpdateMobMaxInterval(ConVar convar, const char[] oldValue, const char[] newValue)
{
    int newVal = StringToInt(newValue);

    SetConVarSafe(g_hMobSpawnMaxIntervalEasy, newVal);
    SetConVarSafe(g_hMobSpawnMaxIntervalNormal, newVal);
    SetConVarSafe(g_hMobSpawnMaxIntervalHard, newVal);
    SetConVarSafe(g_hMobSpawnMaxIntervalExpert, newVal);

    if (g_hPrintLogs.BoolValue)
    {
        int newMaxEasy   = GetConVarInt(g_hMobSpawnMaxIntervalEasy);
        int newMaxNormal = GetConVarInt(g_hMobSpawnMaxIntervalNormal);
        int newMaxHard   = GetConVarInt(g_hMobSpawnMaxIntervalHard);
        int newMaxExpert = GetConVarInt(g_hMobSpawnMaxIntervalExpert);

        LogMessage("z_mob_spawn_max_interval set: Easy=%d Normal=%d Hard=%d Expert=%d", newMaxEasy, newMaxNormal, newMaxHard, newMaxExpert);
    }
}

void SetConVarSafe(ConVar cvar, int value)
{
    char name[64];
    cvar.GetName(name, sizeof(name));

    int oldFlags = GetCommandFlags(name);
    SetCommandFlags(name, oldFlags & ~FCVAR_CHEAT);

    cvar.IntValue = value;
    SetCommandFlags(name, oldFlags);
}