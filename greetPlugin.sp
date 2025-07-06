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
    "!hi",
    "!hello",
    "!hey",
    "!yo",

    "!hallo",
    "!servus",
    "!moin",

    "!hola",
    "!buenas",

    "!salut",
    "!bonjour",

    "!ciao",
    "!buongiorno",

    "!hej",
    "!hei",

    "!ola",
    "!olá",
};

static const char healItems[][] = {
    //"weapon_first_aid_kit",
    "weapon_pain_pills",
};

static const char nadeItems[][] = { "weapon_molotov", "weapon_pipe_bomb" };

public OnPluginStart()
{
    LogMessage("[greetPlugin.smx] Greet Plugin started!");
    PrintToServer("Greet Plugin started!");
    RegConsoleCmd("say", Command_Say);
}

public void OnClientPutInServer(int client)
{
    if (!isValidClient(client)) return;
    CreateTimer(5.0, Timer_GreetPlayer, client);
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
            GiveRandomFreeItem(client);
            canGreet[client] = false;
            return Plugin_Handled;
        }
    }

    return Plugin_Continue;
}

void GiveRandomFreeItem(int client)
{
    // Slot 3 = Heal-Items
    bool hasHeal = isSlotOccupied(client, 3, healItems, sizeof(healItems));
    // Slot 2 = Throwables
    bool hasNade = isSlotOccupied(client, 2, nadeItems, sizeof(nadeItems));

    int  health  = GetClientHealth(client);

    char givenItem[64];
    givenItem[0] = '\0';
    int itemIndex;
    if (!hasHeal)
    {
        if (health <= 20)
        {
            GiveItem(client, "weapon_first_aid_kit");
            strcopy(givenItem, sizeof(givenItem), "weapon_first_aid_kit");
        }
        else {
            itemIndex = GetRandomInt(0, sizeof(healItems) - 1);
            GiveItem(client, healItems[itemIndex]);
            strcopy(givenItem, sizeof(givenItem), healItems[itemIndex]);
        }
    }
    else if (!hasNade) {
        itemIndex = GetRandomInt(0, sizeof(nadeItems) - 1);
        GiveItem(client, nadeItems[itemIndex]);
        strcopy(givenItem, sizeof(givenItem), nadeItems[itemIndex]);
    }
    else {
        PrintToChat(client, "\x04[EVIL DEAD] \x01Unfortunately all your item slots are occupied!");
        return;
    }

    PrintToChat(client, "\x04[EVIL DEAD] \x01You received the following item: \x04%s", givenItem);
}

public Action Timer_GreetPlayer(Handle timer, int client)
{
    if (!IsClientInGame(client)) return Plugin_Continue;

    if (!HasAtLeastTwoPlayers()) return Plugin_Handled;

    char name[64];
    GetClientName(client, name, sizeof(name));
    PrintToChat(client, "\x04[EVIL DEAD]\x01 Welcome to EVIL DEAD \x04%s\x01! Greet your teammates to receive a reward! (type !hi, !hallo, !hola, etc...)", name);

    // für alle außer neu gejointen Spieler
    for (int i = 1; i <= MaxClients; i++)
    {
        if (i == client || !IsClientInGame(i) || IsFakeClient(i)) continue;
        PrintToChat(i, "\x04[EVIL DEAD] %s \x01has joined the game! Greet your new teammate to receive a reward! (type !hi, !hallo, !hola, etc...)", name);
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

void GiveItem(int client, const char[] itemName)
{
    int entity = CreateEntityByName(itemName);
    if (entity != -1)
    {
        DispatchSpawn(entity);
        TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
        EquipPlayerWeapon(client, entity);
    }
}

bool isSlotOccupied(int client, int slot, const char[][] validItems, int itemCount)
{
    int weapon = GetPlayerWeaponSlot(client, slot);
    if (weapon == -1) return false;

    char classname[64];
    GetEdictClassname(weapon, classname, sizeof(classname));

    for (int i = 0; i < itemCount; i++)
    {
        if (StrEqual(classname, validItems[i])) return true;
    }

    return false;
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