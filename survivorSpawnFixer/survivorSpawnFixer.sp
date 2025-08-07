#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Survivor Spawn Fixer",
    author      = "Sascha R.",
    description = "Gives newly joined players a weapon if they spawn without one and teleports if necessary",
};

public void OnPluginStart()
{
    LogMessage("Survivor Spawn Fixer started!");
    HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
}

public Action OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Continue;

    if (GetClientTeam(client) != 2)
        return Plugin_Continue;

    CreateTimer(3.0, Timer_CheckWeaponsAndTeleport, client, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Continue;
}

public Action Timer_CheckWeaponsAndTeleport(Handle timer, any client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) return Plugin_Stop;

    bool hasPistol   = false;
    bool hasPrimary  = false;

    int  pistolSlot  = GetPlayerWeaponSlot(client, 1);
    int  primarySlot = GetPlayerWeaponSlot(client, 0);

    if (pistolSlot != -1)
    {
        char classname[64];
        GetEdictClassname(pistolSlot, classname, sizeof(classname));
        if (StrContains(classname, "pistol") != -1)
            hasPistol = true;
    }

    if (primarySlot != -1)
    {
        char classname[64];
        GetEdictClassname(primarySlot, classname, sizeof(classname));
        if (StrContains(classname, "smg") != -1 || StrContains(classname, "shotgun") != -1 || StrContains(classname, "rifle") != -1)
            hasPrimary = true;
    }

    if (!hasPistol)
    {
        LogMessage("Giving new client pistol");
        GiveWeaponToPlayer(client, "weapon_pistol");
    }

    if (!hasPrimary)
    {
        LogMessage("Giving new client shotgun");
        GiveWeaponToPlayer(client, "weapon_pumpshotgun");
        GivePlayerItem(client, "weapon_pumpshotgun");
    }

    if (IsFarFromTeam(client))
        TeleportToTeammate(client);

    return Plugin_Stop;
}

bool IsFarFromTeam(int client, float threshold = 1000.0)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return false;

    float originA[3];
    GetClientAbsOrigin(client, originA);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (i == client)
            continue;

        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2)
        {
            float originB[3];
            GetClientAbsOrigin(i, originB);

            float distance = GetVectorDistance(originA, originB);
            if (distance < threshold)
            {
                return false;
            }
        }
    }
    LogMessage("New Client is more than %d units from team.", threshold);
    return true;
}

void GiveWeaponToPlayer(int client, const char[] weaponName)
{
    int entity = CreateEntityByName(weaponName);

    if (entity == -1)
    {
        LogError("Failed to create weapon entity: %s", weaponName);
        return;
    }

    DispatchSpawn(entity);
    TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
    EquipPlayerWeapon(client, entity);

    LogMessage("Gave %s to client %N", weaponName, client);
}

void TeleportToTeammate(int client)
{
    float targetPos[3];

    for (int i = 1; i <= MaxClients; i++)
    {
        if (i != client && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2)
        {
            GetClientAbsOrigin(i, targetPos);
            TeleportEntity(client, targetPos, NULL_VECTOR, NULL_VECTOR);
            LogMessage("Teleporting client %d to teammates.", client);
            PrintToChat(client, "[Info] You have been teleported to your teammates.");
            return;
        }
    }
}