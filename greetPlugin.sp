#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Greet Plugin",
    author      = "Sascha R.",
    description = "Rewards player for greeting newly joined players",
};

bool              canGreet[MAXPLAYERS + 1];

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

static const char items[][] = { "weapon_pain_pills", "weapon_molotov", "weapon_pipe_bomb" }

public OnPluginStart()
{
    LogMessage("[greetPlugin.smx] Greet Plugin started!");
    PrintToServer("Greet Plugin started!");
    RegConsoleCmd("say", Command_Say);
}

public void OnClientPutInServer(int client)
{
    if (!isValidClient(client)) return;
    CreateTimer(10.0, Timer_GreetPlayer, client);
}

public Action Command_Say(int client, int args)
{
    if (!canGreet[client]) return Plugin_Continue;

    char text[192];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);

    for (int i = 0; i < sizeof(greetings); i++)
    {
        if (StrEqual(text, greetings[i], false))
        {
            GiveItem(client);
            canGreet[client] = false;
            return Plugin_Continue;
        }
    }

    return Plugin_Continue;
}

void GiveItem(int client)
{
    int  itemIndex = GetRandomInt(0, sizeof(items) - 1);
    char givenItem[64];
    strcopy(givenItem, sizeof(givenItem), items[itemIndex]);
    int entity = CreateEntityByName(givenItem);

    if (entity != -1)
    {
        DispatchSpawn(entity);
        TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
        EquipPlayerWeapon(client, entity);
        PrintToChat(client, "\x07[EVIL DEAD] \x01You received the following item: \x07%s", givenItem);
    }
}

public Action Timer_GreetPlayer(Handle timer, int client)
{
    if (!IsClientInGame(client)) return Plugin_Continue;

    if (!HasAtLeastTwoPlayers()) return Plugin_Handled;

    char name[64];
    GetClientName(client, name, sizeof(name));
    PrintToChat(client, "\x07[EVIL DEAD]\x01 Welcome to EVIL DEAD \x07%s\x01! Greet your teammates to receive a reward! (type hi, hallo, hola, etc...)", name);

    // für alle außer neu gejointen Spieler
    for (int i = 1; i <= MaxClients; i++)
    {
        if (i == client || !IsClientInGame(i) || IsFakeClient(i)) continue;
        PrintToChat(i, "\x07[EVIL DEAD] %s \x01has joined the game!", name);
    }

    canGreet[client] = true;
    CreateTimer(60.0, Timer_DisableGreet, client);
    return Plugin_Handled;
}

public Action Timer_DisableGreet(Handle timer, int client)
{
    canGreet[client] = false;
    return Plugin_Handled;
}

bool HasAtLeastTwoPlayers()
{
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