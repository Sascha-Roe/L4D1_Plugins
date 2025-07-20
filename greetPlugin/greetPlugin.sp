#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Greet Plugin",
    author      = "Sascha R.",
    description = "Rewards player for greeting newly joined players",
};

bool              g_bTestMode   = false;
bool              canGreet      = false;

static const char greetings[][] = {
    "hi",
    "hello",
    "hey",
    "yo",

    "hallo",
    "servus",
    "moin",

    "hola",
    "buenas",

    "salut",
    "bonjour",

    "ciao",
    "buongiorno",

    "hej",
    "hei",

    "ola",
    "olá",
};

static const char throwableItems[][] = { "weapon_molotov", "weapon_pipe_bomb" };

static const char healItems[][]      = { "weapon_pain_pills" };

public OnPluginStart()
{
    LogMessage("Greet Plugin started!");
    HookEvent("player_first_spawn", playerSpawned, EventHookMode_Post);
    RegConsoleCmd("say", Command_Say);

    RegAdminCmd("sm_testGreetPlugin", Command_TestGreet, ADMFLAG_GENERIC);
}

public Action playerSpawned(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!isValidClient(client)) return Plugin_Continue;
    CreateTimer(2.5, Timer_GreetPlayer, client);
    return Plugin_Continue;
}

public Action Command_Say(int client, int args)
{
    if (!canGreet) return Plugin_Continue;

    char text[192];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);

    for (int i = 0; i < sizeof(greetings); i++)
    {
        if (StrEqual(text, greetings[i], false))
        {
            GiveItem(client);
            canGreet = false;
            return Plugin_Continue;
        }
    }

    return Plugin_Continue;
}

void GiveItem(int client)
{
    // Throwables
    int  slot2   = GetPlayerWeaponSlot(client, 2);
    // pills
    int  slot4   = GetPlayerWeaponSlot(client, 4);

    bool hasHeal = false;
    bool hasNade = false;

    if (slot4 != -1)
    {
        hasHeal = true;
    }

    if (slot2 != -1)
    {
        hasNade = true;
    }

    char givenItem[64];
    if (!hasHeal && !hasNade)
    {
        int itemIndex = GetRandomInt(0, sizeof(throwableItems) - 1);
        strcopy(givenItem, sizeof(givenItem), throwableItems[itemIndex]);
    }
    else if (hasHeal && !hasNade)
    {
        int itemIndex = GetRandomInt(0, sizeof(throwableItems) - 1);
        strcopy(givenItem, sizeof(givenItem), throwableItems[itemIndex]);
    }
    else if (!hasHeal && hasNade) {
        int itemIndex = GetRandomInt(0, sizeof(healItems) - 1);
        strcopy(givenItem, sizeof(givenItem), healItems[itemIndex]);
    }
    else {
        PrintToChat(client, "\x04[Greet Plugin] \x01You must have a free pills or throwable slot to receive an item!");
        return;
    }

    int entity = CreateEntityByName(givenItem);

    if (entity != -1)
    {
        DispatchSpawn(entity);
        TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
        EquipPlayerWeapon(client, entity);
        PrintToChat(client, "\x04[Greet Plugin] \x01You received the following item: \x04%s", givenItem);
    }
}

public Action Timer_GreetPlayer(Handle timer, int client)
{
    if (!IsClientInGame(client)) return Plugin_Continue;

    if (!HasAtLeastTwoPlayers()) return Plugin_Handled;

    // reset testMode if active
    g_bTestMode = false;

    char name[64];
    GetClientName(client, name, sizeof(name));
    PrintToChat(client, "\x04[Greet Plugin]\x01 Welcome to EVIL DEAD \x04%s\x01!\nGreet your teammates to receive a reward! (type hi, hallo, hola, ...)", name);
    PrintHintText(client, "Welcome to EVIL DEAD %s!\nGreet your teammates to receive a reward! (type hi, hallo, hola, ...)", name);

    // für alle außer neu gejointen Spieler
    for (int i = 1; i <= MaxClients; i++)
    {
        if (i == client || !IsClientInGame(i) || IsFakeClient(i)) continue;
        PrintToChat(i, "\x04[Greet Plugin] %s \x01has joined the game!", name);
    }

    canGreet = true;
    CreateTimer(60.0, Timer_DisableGreet, client);
    return Plugin_Handled;
}

public Action Timer_DisableGreet(Handle timer, int client)
{
    canGreet = false;
    return Plugin_Handled;
}

bool HasAtLeastTwoPlayers()
{
    if (g_bTestMode) return true;
    int count = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            count++;
            if (count >= 2) return true;
        }
    }

    return false;
}

bool isValidClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}

public Action Command_TestGreet(int client, int args)
{
    PrintToChat(client, "\x04[Greet Plugin]\x01 Running test!");
    g_bTestMode = true;
    CreateTimer(2.5, Timer_GreetPlayer, client);
    return Plugin_Handled;
}