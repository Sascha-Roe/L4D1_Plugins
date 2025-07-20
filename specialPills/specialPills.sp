#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Special Pills",
    author      = "Sascha R.",
    description = "Using pills gives the player temporary special effects",

};

#define BOOST_DURATION 60.0

bool g_speedBoostEnabled[MAXPLAYERS + 1]

    public OnPluginStart()
{
    LogMessage("Special Pills Plugin started!");
    HookEvent("pills_used", Event_PillsUsed);
    RegConsoleCmd("sm_specialPills", Cmd_ToggleSpecialPills, "Toggles special pills")
}

public Action Cmd_ToggleSpecialPills(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client)) return Plugin_Handled;

    g_speedBoostEnabled[client] = !g_speedBoostEnabled[client];

    if (g_speedBoostEnabled[client])
    {
        PrintToChat(client, "[specialPills] Special Pills is now \x04activated\x01.");
    }
    else {
        PrintToChat(client, "[specialPills] Special Pills is now \x04deactivated\x01.");
    }

    return Plugin_Handled;
}

public void Event_PillsUsed(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client)) return;

    if (!g_speedBoostEnabled[client]) return;

    SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.25);
    CreateTimer(BOOST_DURATION, Timer_ResetSpeed, client);
}

public Action Timer_ResetSpeed(Handle timer, int client)
{
    if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client))
    {
        SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
    }
    return Plugin_Stop;
}