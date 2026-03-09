GuildCraftDB = GuildCraftDB or {}
GuildCraftDB_Meta = GuildCraftDB_Meta or {}
local SafeLower
local RecipeExists
local IsRecipeExcluded
local IsRecipeInvalid


local frame = CreateFrame("Frame")
local delayedSender = CreateFrame("Frame")
local refreshButtonTimer = CreateFrame("Frame")
local guildHelloSender = CreateFrame("Frame")

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("CRAFT_SHOW")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")

local DEBUG = false
local SEND_COOLDOWN = 60
local RECIPE_SEPARATOR = "||"
local pendingSend = nil
local pendingGuildHello = nil
local lastHelloTime = 0

local uiFrame = nil
local uiRows = {}
local uiDisplayRows = {}
local minimapButton = nil
local ToggleUI
local ShowRecipeTooltip
local RefreshUI

local function GetCurrentRealmName()
    local realm = GetRealmName and GetRealmName() or nil
    if not realm or realm == "" then
        realm = "UnknownRealm"
    end
    return realm
end

local function GetCurrentGuildName()
    local guild = GetGuildInfo and GetGuildInfo("player") or nil
    if not guild or guild == "" then
        guild = "NoGuild"
    end
    return guild
end

local function GetCurrentProfileDB()
    local realm = GetCurrentRealmName()
    local guild = GetCurrentGuildName()

    GuildCraftDB.Profiles = GuildCraftDB.Profiles or {}
    GuildCraftDB.Profiles[realm] = GuildCraftDB.Profiles[realm] or {}
    GuildCraftDB.Profiles[realm][guild] = GuildCraftDB.Profiles[realm][guild] or {}

    return GuildCraftDB.Profiles[realm][guild]
end

local function GetCurrentProfileMeta()
    local realm = GetCurrentRealmName()
    local guild = GetCurrentGuildName()

    GuildCraftDB_Meta.Profiles = GuildCraftDB_Meta.Profiles or {}
    GuildCraftDB_Meta.Profiles[realm] = GuildCraftDB_Meta.Profiles[realm] or {}
    GuildCraftDB_Meta.Profiles[realm][guild] = GuildCraftDB_Meta.Profiles[realm][guild] or {}
    GuildCraftDB_Meta.Profiles[realm][guild].Players = GuildCraftDB_Meta.Profiles[realm][guild].Players or {}
    GuildCraftDB_Meta.Profiles[realm][guild].Sync = GuildCraftDB_Meta.Profiles[realm][guild].Sync or {}
    GuildCraftDB_Meta.Profiles[realm][guild].ItemLinks = GuildCraftDB_Meta.Profiles[realm][guild].ItemLinks or {}

    return GuildCraftDB_Meta.Profiles[realm][guild]
end

local function GetCurrentProfilePlayers()
    return GetCurrentProfileDB()
end

local function UpdateWindowTitle()
    if not uiFrame or not uiFrame.title then
        return
    end

    local guildName = GetCurrentGuildName()
    uiFrame.title:SetText("GuildCraftDB - " .. guildName)
end

local function LearnRecipeItemLink(professionName, recipeName, itemLink)
    if not professionName or not recipeName or not itemLink or itemLink == "" then
        return
    end

    local profileMeta = GetCurrentProfileMeta()
    profileMeta.ItemLinks[professionName] = profileMeta.ItemLinks[professionName] or {}
    profileMeta.ItemLinks[professionName][recipeName] = itemLink
end

local function GetLearnedRecipeItemLink(professionName, recipeName)
    if not professionName or not recipeName then
        return nil
    end

    local profileMeta = GetCurrentProfileMeta()
    if profileMeta.ItemLinks[professionName] then
        return profileMeta.ItemLinks[professionName][recipeName]
    end

    return nil
end

local EXCLUDED_PROFESSIONS = {
    ["First Aid"] = true,
    ["Survival"] = true,
    ["Herbalism"] = true,
    ["Mining"] = true,
}

local EXCLUDED_COOKING_RECIPES = {
    ["Spotted Yellowtail"] = true,
    ["Roast Raptor"] = true,
    ["Bristle Whisker Catfish"] = true,
    ["Curiously Tasty Omelet"] = true,
    ["Boiled Clams"] = true,
    ["Coyote Steak"] = true,
    ["Crab Cake"] = true,
    ["Dry Pork Ribs"] = true,
    ["Longjaw Mud Snapper"] = true,
    ["Rainbow Fin Albacore"] = true,
    ["Herb Baked Egg"] = true,
    ["Roasted Boar Meat"] = true,
    ["Spiced Wolf Meat"] = true,
    ["Brilliant Smallfish"] = true,
    ["Charred Wolf Meat"] = true,

    ["Beer Basted Boar Ribs"] = true,
    ["Blood Sausage"] = true,
    ["Cooked Crab Claw"] = true,
    ["Crocolisk Gumbo"] = true,
    ["Crocolisk Steak"] = true,
    ["Egg Nog"] = true,
    ["Gingerbread Cookie"] = true,
    ["Goblin Deviled Clams"] = true,
    ["Gooey Spider Cake"] = true,
    ["Goretusk Liver Pie"] = true,
    ["Hot Wolf Ribs"] = true,
    ["Jungle Stew"] = true,
    ["Redridge Goulash"] = true,
    ["Rockscale Cod"] = true,
    ["Sagefish Delight"] = true,
    ["Seasoned Wolf Kabob"] = true,
    ["Slitherskin Mackerel"] = true,
    ["Smoked Sagefish"] = true,
    ["Spider Sausage"] = true,
    ["Undermine Clam Chowder"] = true,
    ["Westfall Stew"] = true,
}

local PROFESSION_ORDER = {
    "Alchemy",
    "Blacksmithing",
    "Cooking",
    "Enchanting",
    "Engineering",
    "Leatherworking",
    "Tailoring",
}

local CLASS_TOKEN_FALLBACK = {
    ["warrior"] = "WARRIOR",
    ["mage"] = "MAGE",
    ["rogue"] = "ROGUE",
    ["druid"] = "DRUID",
    ["hunter"] = "HUNTER",
    ["shaman"] = "SHAMAN",
    ["priest"] = "PRIEST",
    ["warlock"] = "WARLOCK",
    ["paladin"] = "PALADIN",
}

local function DebugMessage(text)
    if DEBUG then
        DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB: " .. text)
    end
end

SafeLower = function(text)
    if not text then
        return ""
    end
    return string.lower(text)
end

local function EnsureMetaTables()
    GuildCraftDB_Meta.UI = GuildCraftDB_Meta.UI or {}
    GuildCraftDB_Meta.UI.Collapsed = GuildCraftDB_Meta.UI.Collapsed or {}
    GuildCraftDB_Meta.UI.Pos = GuildCraftDB_Meta.UI.Pos or {}
    GuildCraftDB_Meta.UI.Minimap = GuildCraftDB_Meta.UI.Minimap or { angle = 220, hide = false }
    GuildCraftDB_Meta.Players = GuildCraftDB_Meta.Players or {}
    GuildCraftDB_Meta.Sync = GuildCraftDB_Meta.Sync or {}
    GuildCraftDB.Profiles = GuildCraftDB.Profiles or {}
    GuildCraftDB_Meta.Profiles = GuildCraftDB_Meta.Profiles or {}
end

local function IsProfessionExcluded(profession)
    if not profession then
        return true
    end

    return EXCLUDED_PROFESSIONS[profession] == true
end

IsRecipeExcluded = function(profession, recipeName)
    if not profession or not recipeName then
        return false
    end

    if profession == "Cooking" and EXCLUDED_COOKING_RECIPES[recipeName] then
        return true
    end

    return false
end

local function NormalizeRecipeName(recipeName)
    if not recipeName then
        return nil
    end

    recipeName = tostring(recipeName)
    recipeName = string.gsub(recipeName, "|c%x%x%x%x%x%x%x%x", "")
    recipeName = string.gsub(recipeName, "|r", "")
    recipeName = string.gsub(recipeName, "^%s+", "")
    recipeName = string.gsub(recipeName, "%s+$", "")
    recipeName = string.gsub(recipeName, "~item:%d+:[^%s]*", "")
    recipeName = string.gsub(recipeName, "~spell:%d+:[^%s]*", "")
    recipeName = string.gsub(recipeName, "~item:%d+.*$", "")
    recipeName = string.gsub(recipeName, "~spell:%d+.*$", "")
    recipeName = string.gsub(recipeName, "~+$", "")
    recipeName = string.gsub(recipeName, "%s+$", "")
    return recipeName
end

local function NormalizeRecipeLookupName(recipeName)
    recipeName = NormalizeRecipeName(recipeName)
    if not recipeName or recipeName == "" then
        return nil
    end

    recipeName = string.gsub(recipeName, "^Recipe:%s*", "")
    recipeName = string.gsub(recipeName, "^Formula:%s*", "")
    recipeName = string.gsub(recipeName, "^Plans:%s*", "")
    recipeName = string.gsub(recipeName, "^Pattern:%s*", "")
    recipeName = string.gsub(recipeName, "^Design:%s*", "")
    recipeName = string.gsub(recipeName, "^Schematic:%s*", "")
    recipeName = string.gsub(recipeName, "^%s+", "")
    recipeName = string.gsub(recipeName, "%s+$", "")
    return recipeName
end

local function GetLibRecipeSpellID(professionName, recipeName)
    if not GuildCraftLib then
        return nil
    end

    local lookupName = NormalizeRecipeLookupName(recipeName)
    if not lookupName or lookupName == "" then
        return nil
    end

    local key = SafeLower(lookupName)

    if GuildCraftLib.SpellIndexByProfession and professionName and GuildCraftLib.SpellIndexByProfession[professionName] then
        return GuildCraftLib.SpellIndexByProfession[professionName][key]
    end

    if GuildCraftLib.SpellIndex then
        return GuildCraftLib.SpellIndex[key]
    end

    return nil
end

local function GetSafeLibItemLink(professionName, recipeName)
    local lookupName = NormalizeRecipeLookupName(recipeName)
    if not lookupName or lookupName == "" then
        return nil
    end

    if GuildCraftSafeLib and GuildCraftSafeLib.CraftItems then
        local craftItemID = GuildCraftSafeLib.CraftItems[lookupName]
        if craftItemID then
            return "item:" .. craftItemID .. ":0:0:0"
        end
    end

    if GuildCraftSafeLib and GuildCraftSafeLib.EnchantItems then
        local enchantItemID = GuildCraftSafeLib.EnchantItems[lookupName]
        if enchantItemID then
            return "item:" .. enchantItemID .. ":0:0:0"
        end
    end

    if professionName == "Enchanting" and GetItemInfo then
        local _, formulaLink = GetItemInfo("Formula: " .. lookupName)
        if formulaLink then
            return formulaLink
        end
    end

    return nil
end

local function SanitizeStoredRecipeNames()
    local db = GetCurrentProfilePlayers()
    local player, professions, profession, recipes, keptRecipes, i, recipeName

    for player, professions in pairs(db) do
        for profession, recipes in pairs(professions) do
            if recipes and table.getn(recipes) > 0 then
                keptRecipes = {}

                for i = 1, table.getn(recipes) do
                    recipeName = NormalizeRecipeName(recipes[i])
                    if recipeName and recipeName ~= "" and not IsRecipeExcluded(profession, recipeName) and not IsRecipeInvalid(profession, recipeName) then
                        if not RecipeExists(keptRecipes, recipeName) then
                            table.insert(keptRecipes, recipeName)
                        end
                    end
                end

                db[player][profession] = keptRecipes
            end
        end
    end
end

local function IsBrokenEnchantingRecipe(recipeName)
    recipeName = NormalizeRecipeName(recipeName)
    if not recipeName or recipeName == "" then
        return true
    end

    if string.find(recipeName, ",", 1, true) or string.find(recipeName, "	", 1, true) or string.find(recipeName, RECIPE_SEPARATOR, 1, true) then
        return true
    end

    if string.sub(recipeName, -1) == "," or string.sub(recipeName, -1) == "-" then
        return true
    end

    if not string.find(recipeName, " ") then
        return true
    end

    return false
end

IsRecipeInvalid = function(profession, recipeName)
    recipeName = NormalizeRecipeName(recipeName)

    if not recipeName or recipeName == "" then
        return true
    end

    if profession == "Enchanting" and IsBrokenEnchantingRecipe(recipeName) then
        return true
    end

    return false
end

local function RemoveBrokenRecipesFromDB()
    local db = GetCurrentProfilePlayers()
    local player, professions, profession, recipes, keptRecipes, i, recipeName
    local removedCount = 0

    for player, professions in pairs(db) do
        for profession, recipes in pairs(professions) do
            if recipes and table.getn(recipes) > 0 then
                keptRecipes = {}

                for i = 1, table.getn(recipes) do
                    recipeName = NormalizeRecipeName(recipes[i])
                    if not IsRecipeExcluded(profession, recipeName) and not IsRecipeInvalid(profession, recipeName) then
                        table.insert(keptRecipes, recipeName)
                    else
                        removedCount = removedCount + 1
                    end
                end

                db[player][profession] = keptRecipes
            end
        end
    end

    return removedCount
end


local function RemoveExcludedRecipesFromDB()
    local db = GetCurrentProfilePlayers()
    local player, professions, profession, recipes, keptRecipes, i, recipeName
    local removedCount = 0

    for player, professions in pairs(db) do
        for profession, recipes in pairs(professions) do
            if recipes and table.getn(recipes) > 0 then
                keptRecipes = {}

                for i = 1, table.getn(recipes) do
                    recipeName = recipes[i]
                    if not IsRecipeExcluded(profession, recipeName) then
                        table.insert(keptRecipes, recipeName)
                    else
                        removedCount = removedCount + 1
                    end
                end

                db[player][profession] = keptRecipes
            end
        end
    end

    return removedCount
end

local function GetShortName(name)
    if not name then
        return nil
    end

    local dashPos = string.find(name, "-")
    if dashPos then
        return string.sub(name, 1, dashPos - 1)
    end

    return name
end

local function IsInMyGuildByName(nameToCheck)
    if not nameToCheck or nameToCheck == "" then
        return false
    end

    if not IsInGuild() then
        return false
    end

    local shortName = GetShortName(nameToCheck)
    local i

    for i = 1, GetNumGuildMembers() do
        local guildName = GetGuildRosterInfo(i)
        if guildName == shortName then
            return true
        end
    end

    return false
end

local function GetClassTokenFromClassName(className)
    if not className then
        return nil
    end

    if LOCALIZED_CLASS_NAMES_MALE then
        local token, localized
        for token, localized in pairs(LOCALIZED_CLASS_NAMES_MALE) do
            if localized == className then
                return token
            end
        end
    end

    if LOCALIZED_CLASS_NAMES_FEMALE then
        local token, localized
        for token, localized in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
            if localized == className then
                return token
            end
        end
    end

    return CLASS_TOKEN_FALLBACK[SafeLower(className)]
end

local function UpdateGuildRosterMetadata()
    EnsureMetaTables()

    local profileMeta = GetCurrentProfileMeta()
    local playerName, playerMeta
    for playerName, playerMeta in pairs(profileMeta.Players) do
        if playerMeta then
            playerMeta.online = 0
        end
    end

    if not IsInGuild() then
        return
    end

    local i
    for i = 1, GetNumGuildMembers() do
        local name, rank, rankIndex, level, className, zone, note, officerNote, online, status = GetGuildRosterInfo(i)

        if name and name ~= "" then
            local shortName = GetShortName(name)
            local meta = profileMeta.Players[shortName] or {}

            meta.className = className
            meta.classToken = GetClassTokenFromClassName(className)
            meta.online = online and 1 or 0

            profileMeta.Players[shortName] = meta
        end
    end
end

local function GetPlayerClassToken(playerName)
    EnsureMetaTables()

    local shortName = GetShortName(playerName)
    local profileMeta = GetCurrentProfileMeta()
    local meta = profileMeta.Players[shortName]

    if meta and meta.classToken then
        return meta.classToken
    end

    return nil
end

local function IsPlayerOnline(playerName)
    EnsureMetaTables()

    local shortName = GetShortName(playerName)
    if not shortName or shortName == "" then
        return false
    end

    if IsInGuild() then
        local i
        for i = 1, GetNumGuildMembers() do
            local guildName, rank, rankIndex, level, className, zone, note, officerNote, online, status = GetGuildRosterInfo(i)
            if guildName and GetShortName(guildName) == shortName then
                return online and true or false
            end
        end
    end

    local profileMeta = GetCurrentProfileMeta()
    local meta = profileMeta.Players[shortName]
    if meta and meta.online == 1 then
        return true
    end

    return false
end

local function GetColorizedPlayerName(playerName)
    local shortName = GetShortName(playerName)
    local classToken = GetPlayerClassToken(shortName)

    if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
        local c = RAID_CLASS_COLORS[classToken]
        local r = math.floor(c.r * 255)
        local g = math.floor(c.g * 255)
        local b = math.floor(c.b * 255)
        return string.format("|cff%02x%02x%02x%s|r", r, g, b, shortName)
    end

    return shortName or ""
end


RecipeExists = function(tbl, name)
    if not tbl then return false end
    local i
    for i = 1, table.getn(tbl) do
        if tbl[i] == name then
            return true
        end
    end
    return false
end

local function AddRecipe(player, profession, recipeName)
    if not player or not profession or not recipeName or recipeName == "" then
        return
    end

    if IsProfessionExcluded(profession) then
        return
    end

    local db = GetCurrentProfilePlayers()
    db[player] = db[player] or {}
    db[player][profession] = db[player][profession] or {}

    if not RecipeExists(db[player][profession], recipeName) then
        table.insert(db[player][profession], recipeName)
    end
end

local function BuildProfessionHash(player, profession)
    local db = GetCurrentProfilePlayers()
    if not db[player] or not db[player][profession] then
        return ""
    end

    return table.concat(db[player][profession], RECIPE_SEPARATOR)
end

local function ShouldSendProfession(player, profession, forceSend)
    local profileMeta = GetCurrentProfileMeta()
    profileMeta.Sync[player] = profileMeta.Sync[player] or {}
    profileMeta.Sync[player][profession] = profileMeta.Sync[player][profession] or {}

    local meta = profileMeta.Sync[player][profession]
    local newHash = BuildProfessionHash(player, profession)

    if forceSend then
        meta.lastHash = newHash
        meta.lastSentTime = GetTime()
        return true
    end

    if meta.lastHash == newHash then
        DebugMessage("no change for " .. profession)
        return false
    end

    local now = GetTime()
    if meta.lastSentTime and (now - meta.lastSentTime) < SEND_COOLDOWN then
        DebugMessage("throttled " .. profession)
        return false
    end

    meta.lastHash = newHash
    meta.lastSentTime = now
    return true
end

local function SendChunkedProfessionData(player, profession, forceSend)
    if not IsInGuild() then
        return
    end

    if IsProfessionExcluded(profession) then
        return
    end

    local db = GetCurrentProfilePlayers()
    if not db[player] or not db[player][profession] then
        return
    end

    if not ShouldSendProfession(player, profession, forceSend) then
        return
    end

    local recipes = db[player][profession]
    local total = table.getn(recipes)

    if total == 0 then
        return
    end

    local sentCount = 0
    local i

    for i = 1, total do
        local recipeName = recipes[i]
        local isFirst = "0"
        local isLast = "0"

        if i == 1 then
            isFirst = "1"
        end

        if i == total then
            isLast = "1"
        end

        local payload = "DATA~" .. player .. "~" .. profession .. "~" .. isFirst .. "~" .. isLast .. "~" .. recipeName
        SendAddonMessage("GCDB", payload, "GUILD")
        sentCount = sentCount + 1
    end

    DebugMessage("sent " .. profession .. " in " .. sentCount .. " recipe messages")
end

local function SendAllMyStoredProfessions(forceSend)
    local player = UnitName("player")
    local db = GetCurrentProfilePlayers()

    if not db[player] then
        return
    end

    local profession, recipes
    for profession, recipes in pairs(db[player]) do
        if not IsProfessionExcluded(profession) and recipes and table.getn(recipes) > 0 then
            SendChunkedProfessionData(player, profession, forceSend)
        end
    end
end


local function SendGuildHello()
    if not IsInGuild() then
        return
    end

    local now = GetTime()
    if lastHelloTime and (now - lastHelloTime) < 5 then
        return
    end

    SendAddonMessage("GCDB", "HELLO", "GUILD")
    lastHelloTime = now
    DebugMessage("sent HELLO")
end

local function ScheduleGuildHello(delaySeconds)
    if pendingGuildHello then
        return
    end

    pendingGuildHello = {
        time = GetTime() + (delaySeconds or 8)
    }

    guildHelloSender:SetScript("OnUpdate", function()
        if not pendingGuildHello then
            return
        end

        if GetTime() >= pendingGuildHello.time then
            pendingGuildHello = nil
            guildHelloSender:SetScript("OnUpdate", nil)
            SendGuildHello()
        end
    end)
end

local function ScheduleProfessionSend()
    if pendingSend then
        return
    end

    local delay = math.random(2, 7)

    pendingSend = {
        time = GetTime() + delay
    }

    delayedSender:SetScript("OnUpdate", function()
        if not pendingSend then
            return
        end

        if GetTime() >= pendingSend.time then
            pendingSend = nil
            delayedSender:SetScript("OnUpdate", nil)
            SendAllMyStoredProfessions(true)
        end
    end)
end

local function ScanTradeSkill()
    local player = UnitName("player")
    local profession = GetTradeSkillLine()

    if not profession or profession == "" or profession == "UNKNOWN" then
        DebugMessage("no trade skill detected")
        return
    end

    if IsProfessionExcluded(profession) then
        return
    end

    local db = GetCurrentProfilePlayers()
    db[player] = db[player] or {}
    db[player][profession] = {}

    local i
    for i = 1, GetNumTradeSkills() do
        local name, skillType = GetTradeSkillInfo(i)
        if name and skillType ~= "header" then
            AddRecipe(player, profession, name)
            if GetTradeSkillItemLink then
                local itemLink = GetTradeSkillItemLink(i)
                if itemLink then
                    LearnRecipeItemLink(profession, name, itemLink)
                end
            end
        end
    end

    SendChunkedProfessionData(player, profession, false)
    if uiFrame and uiFrame:IsShown() then
        RefreshUI()
    end
end

local function ScanCraft()
    local player = UnitName("player")
    local profession = GetCraftDisplaySkillLine()

    if not profession or profession == "" or profession == "UNKNOWN" then
        DebugMessage("no craft skill detected")
        return
    end

    recipeName = NormalizeRecipeName(recipeName)

    if IsProfessionExcluded(profession) then
        return
    end

    if IsRecipeExcluded(profession, recipeName) or IsRecipeInvalid(profession, recipeName) then
        return
    end

    local db = GetCurrentProfilePlayers()
    db[player] = db[player] or {}
    db[player][profession] = {}

    local i
    for i = 1, GetNumCrafts() do
        local name, _, craftType = GetCraftInfo(i)
        if name and craftType ~= "header" then
            AddRecipe(player, profession, name)
            if GetCraftItemLink then
                local itemLink = GetCraftItemLink(i)
                if itemLink then
                    LearnRecipeItemLink(profession, name, itemLink)
                end
            end
        end
    end

    SendChunkedProfessionData(player, profession, false)
    if uiFrame and uiFrame:IsShown() then
        RefreshUI()
    end
end


local function SplitSuspiciousRecipeString(str)
    if not str then
        return nil
    end

    if string.len(str) < 100 then
        return nil
    end

    local results = {}
    for part in string.gfind(str, "([A-Z][^A-Z]+)") do
        part = string.gsub(part, "^%s+", "")
        part = string.gsub(part, "%s+$", "")
        if part ~= "" then
            table.insert(results, part)
        end
    end

    if table.getn(results) > 1 then
        return results
    end

    return nil
end

local function ImportProfessionChunk(sender, profession, recipeString, chunkIndex, isLast)
    if not sender or not profession then
        return
    end

    if IsProfessionExcluded(profession) then
        return
    end

    sender = GetShortName(sender)

    local db = GetCurrentProfilePlayers()
    db[sender] = db[sender] or {}

    if chunkIndex == "1" then
        db[sender][profession] = {}
    elseif not db[sender][profession] then
        db[sender][profession] = {}
    end

    if recipeString and recipeString ~= "" then
        local recipeName = NormalizeRecipeName(recipeString)

        if not IsRecipeExcluded(profession, recipeName) and not IsRecipeInvalid(profession, recipeName) then
            if not RecipeExists(db[sender][profession], recipeName) then
                table.insert(db[sender][profession], recipeName)
            end
        end
    end

    if isLast == "1" then
        DebugMessage("imported " .. profession .. " from " .. sender)

        if uiFrame and uiFrame:IsShown() then
            RefreshUI()

            local i
            for i = 1, table.getn(uiRows) do
                local row = uiRows[i]
                if row and row:IsVisible() and MouseIsOver(row) and row.data and row.data.rowType == "recipe" then
                    ShowRecipeTooltip(row)
                    break
                end
            end
        end
    end
end

local function PruneNonGuildData()
    if not IsInGuild() then
        return
    end

    local me = GetShortName(UnitName("player"))
    local db = GetCurrentProfilePlayers()
    local profileMeta = GetCurrentProfileMeta()
    local playerName

    for playerName in pairs(db) do
        if playerName ~= me and not IsInMyGuildByName(playerName) then
            db[playerName] = nil
            profileMeta.Players[playerName] = nil
        end
    end
end

local function GetUICollapsedTable()
    EnsureMetaTables()
    return GuildCraftDB_Meta.UI.Collapsed
end

local function GetProfessionIndex()
    local index = {}
    local db = GetCurrentProfilePlayers()

    -- Always seed the full recipe catalog first.
    if GuildCraftLib and GuildCraftLib.Catalog then
        for profession, recipes in pairs(GuildCraftLib.Catalog) do
            index[profession] = index[profession] or {}

            for recipeName in pairs(recipes) do
                index[profession][recipeName] = index[profession][recipeName] or {}
            end
        end
    end

    -- Then attach guild members who know the recipe.
    for player, professions in pairs(db) do
        for profession, recipes in pairs(professions) do
            index[profession] = index[profession] or {}

            for _, recipeName in ipairs(recipes) do
                recipeName = NormalizeRecipeName(recipeName)
                if recipeName and recipeName ~= "" then
                    index[profession][recipeName] = index[profession][recipeName] or {}
                    if not RecipeExists(index[profession][recipeName], player) then
                        table.insert(index[profession][recipeName], player)
                    end
                end
            end
        end
    end

    return index
end

local function SortNames(nameList)
    table.sort(nameList, function(a, b)
        return SafeLower(a) < SafeLower(b)
    end)
end

local function GetSortedProfessionList(index)
    local result = {}
    local seen = {}
    local i, profession

    for i = 1, table.getn(PROFESSION_ORDER) do
        profession = PROFESSION_ORDER[i]
        if index[profession] then
            table.insert(result, profession)
            seen[profession] = true
        end
    end

    for profession in pairs(index) do
        if not seen[profession] then
            table.insert(result, profession)
        end
    end

    return result
end

local function GetSortedRecipeList(recipeTable)
    local result = {}
    local recipe

    for recipe in pairs(recipeTable) do
        table.insert(result, recipe)
    end

    table.sort(result, function(a, b)
        return SafeLower(a) < SafeLower(b)
    end)

    return result
end

local function BuildUIDisplayRows(searchText)
    local rows = {}
    local collapsed = GetUICollapsedTable()
    local index = GetProfessionIndex()
    local professionList = GetSortedProfessionList(index)
    local filter = SafeLower(searchText)
    local i, profession

    for i = 1, table.getn(professionList) do
        profession = professionList[i]

        local recipeTable = index[profession]
        local sortedRecipes = GetSortedRecipeList(recipeTable)
        local matchedRecipes = {}
        local r, recipeName

        for r = 1, table.getn(sortedRecipes) do
            recipeName = sortedRecipes[r]
            if filter == "" or string.find(SafeLower(recipeName), filter) then
                table.insert(matchedRecipes, recipeName)
            end
        end

        if table.getn(matchedRecipes) > 0 then
            table.insert(rows, {
                rowType = "header",
                profession = profession,
                recipeCount = table.getn(matchedRecipes),
            })

            if not collapsed[profession] then
                for r = 1, table.getn(matchedRecipes) do
                    recipeName = matchedRecipes[r]
                    local rawCrafterList = {}
                    local c

                    for c = 1, table.getn(recipeTable[recipeName]) do
                        table.insert(rawCrafterList, recipeTable[recipeName][c])
                    end

                    SortNames(rawCrafterList)

                    table.insert(rows, {
                        rowType = "recipe",
                        profession = profession,
                        recipe = recipeName,
                        rawCrafters = rawCrafterList,
                    })
                end
            end
        end
    end

    return rows
end


local function AddRecipeInfoToTooltip(recipeName)
    if not recipeName or recipeName == "" then
        return
    end

    if not GetItemInfo then
        return
    end

    local itemName, itemLink, itemQuality, itemLevel, reqLevel, itemType, itemSubType, stackCount, equipLoc, texture = GetItemInfo(recipeName)
    if not itemName then
        return
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Recipe info:", 0.9, 0.9, 0.9)

    if itemLink then
        GameTooltip:AddLine(itemLink, 1.0, 1.0, 1.0)
    else
        GameTooltip:AddLine(itemName, 1.0, 1.0, 1.0)
    end

    if itemType and itemType ~= "" then
        if itemSubType and itemSubType ~= "" then
            GameTooltip:AddLine(itemType .. " - " .. itemSubType, 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine(itemType, 0.7, 0.7, 0.7)
        end
    end

    if reqLevel and reqLevel > 0 then
        GameTooltip:AddLine("Requires level " .. reqLevel, 0.7, 0.7, 0.7)
    end
end



local COOKING_ITEM_IDS = {
    ["Baked Salmon"] = 13935,
    ["Beer Basted Boar Ribs"] = 2888,
    ["Big Bear Steak"] = 3726,
    ["Blood Sausage"] = 3679,
    ["Boiled Clams"] = 5525,
    ["Brilliant Smallfish"] = 6290,
    ["Bristle Whisker Catfish"] = 6291,
    ["Charred Wolf Meat"] = 2679,
    ["Cooked Crab Claw"] = 2682,
    ["Coyote Steak"] = 2684,
    ["Crab Cake"] = 2683,
    ["Crocolisk Gumbo"] = 3664,
    ["Crocolisk Steak"] = 3662,
    ["Curiously Tasty Omelet"] = 3665,
    ["Danonzo's Tel'Abim Delight"] = 60977,
    ["Danonzo's Tel'Abim Medley"] = 60978,
    ["Danonzo's Tel'Abim Surprise"] = 60976,
    ["Dig Rat Stew"] = 5478,
    ["Dry Pork Ribs"] = 2687,
    ["Filet of Redgill"] = 13930,
    ["Goblin Deviled Clams"] = 5527,
    ["Gooey Spider Cake"] = 3666,
    ["Goretusk Liver Pie"] = 724,
    ["Grilled Squid"] = 13928,
    ["Hot Lion Chops"] = 3727,
    ["Hot Smoked Bass"] = 3729,
    ["Hot Wolf Ribs"] = 13851,
    ["Jungle Stew"] = 12212,
    ["Lean Venison"] = 12210,
    ["Lobster Stew"] = 13929,
    ["Mightfish Steak"] = 13934,
    ["Monster Omelet"] = 12218,
    ["Mystery Stew"] = 12214,
    ["Longjaw Mud Snapper"] = 4592,
    ["Nightfin Soup"] = 13931,
    ["Poached Sunscale Salmon"] = 13932,
    ["Rainbow Fin Albacore"] = 5095,
    ["Redridge Goulash"] = 1082,
    ["Roast Raptor"] = 1727,
    ["Roasted Boar Meat"] = 2681,
    ["Rockscale Cod"] = 4594,
    ["Sagefish Delight"] = 21217,
    ["Seasoned Wolf Kabob"] = 1017,
    ["Slitherskin Mackerel"] = 787,
    ["Spotted Yellowtail"] = 6888,
    ["Smoked Bear Meat"] = 6890,
    ["Smoked Desert Dumplings"] = 20452,
    ["Smoked Sagefish"] = 21072,
    ["Soothing Turtle Bisque"] = 3728,
    ["Spider Sausage"] = 17222,
    ["Spiced Chili Crab"] = 12216,
    ["Spiced Wolf Meat"] = 2680,
    ["Strider Stew"] = 5468,
    ["Tender Wolf Steak"] = 18045,
    ["Undermine Clam Chowder"] = 5526,
    ["Westfall Stew"] = 733,
}

local JEWELCRAFTING_ITEM_IDS = {
}

local RECIPE_ITEM_OVERRIDES = {
    ["Lobster Stew"] = 13933,
    ["Danonzo's Tel'Abim Surprise"] = 60976,
    ["Danonzo's Tel'Abim Delight"] = 60977,
    ["Danonzo's Tel'Abim Medley"] = 60978,

    ["Le Fishe Au Chocolat"] = 84040,
    ["Mithril Headed Trout"] = 8364,
    ["Murloc Fin Soup"] = 3663,
    ["Savory Deviate Delight"] = 6657,
    ["Succulent Pork Ribs"] = 2685,
}

local function ResolveRecipeItemLink(recipeName, professionName)
    if not recipeName or recipeName == "" then
        return nil
    end

    local learnedLink = GetLearnedRecipeItemLink(professionName, recipeName)
    if learnedLink then
        return learnedLink
    end

    local itemID = RECIPE_ITEM_OVERRIDES[recipeName]

    if not itemID then
        if professionName == "Cooking" then
            itemID = COOKING_ITEM_IDS[recipeName]
        elseif professionName == "Jewelcrafting" then
            itemID = JEWELCRAFTING_ITEM_IDS[recipeName]
        end
    end

    if itemID then
        return "item:" .. itemID .. ":0:0:0"
    end

    if GetItemInfo then
        local itemName, itemLink = GetItemInfo(recipeName)
        if itemLink then
            return itemLink
        end
    end

    return nil
end

local function TrySetFullRecipeTooltip(row, recipeName, professionName)
    if not row or not recipeName or recipeName == "" then
        return false
    end

    local safeItemLink = GetSafeLibItemLink(professionName, recipeName)
    if safeItemLink then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(safeItemLink)
        return true
    end

    if professionName == "Enchanting" then
        return false
    end

    local itemLink = ResolveRecipeItemLink(recipeName, professionName)
    if not itemLink then
        return false
    end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(itemLink)
    return true
end

ShowRecipeTooltip = function(row)
    if not row or not row.data or row.data.rowType ~= "recipe" then
        return
    end

    local online = {}
    local offline = {}
    local i, name

    if row.data.rawCrafters then
        for i = 1, table.getn(row.data.rawCrafters) do
            name = row.data.rawCrafters[i]
            if IsPlayerOnline(name) then
                table.insert(online, name)
            else
                table.insert(offline, name)
            end
        end
    end

    if not TrySetFullRecipeTooltip(row, row.data.recipe, row.data.profession) then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(row.data.recipe, 1.0, 0.82, 0.0)
        GameTooltip:AddLine(row.data.profession, 0.6, 0.8, 1.0)
        if row.data.profession == "Enchanting" then
            GameTooltip:AddLine("No item or formula tooltip found for this enchant.", 0.7, 0.7, 0.7)
        elseif row.data.profession == "Jewelcrafting" then
            GameTooltip:AddLine("Full item tooltip shows when this recipe is mapped or cached.", 0.7, 0.7, 0.7)
        end
    else
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(row.data.profession, 0.6, 0.8, 1.0)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Online Crafters:", 0.3, 1.0, 0.3)
    if table.getn(online) == 0 then
        GameTooltip:AddLine("None", 0.7, 0.7, 0.7)
    else
        for i = 1, table.getn(online) do
            name = online[i]
            local classToken = GetPlayerClassToken(name)
            if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
                local c = RAID_CLASS_COLORS[classToken]
                GameTooltip:AddLine(GetShortName(name), c.r, c.g, c.b)
            else
                GameTooltip:AddLine(GetShortName(name), 1.0, 1.0, 1.0)
            end
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Offline Crafters:", 0.8, 0.8, 0.8)
    if table.getn(offline) == 0 then
        GameTooltip:AddLine("None", 0.7, 0.7, 0.7)
    else
        for i = 1, table.getn(offline) do
            name = offline[i]
            local classToken = GetPlayerClassToken(name)
            if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
                local c = RAID_CLASS_COLORS[classToken]
                GameTooltip:AddLine(GetShortName(name), c.r, c.g, c.b)
            else
                GameTooltip:AddLine(GetShortName(name), 1.0, 1.0, 1.0)
            end
        end
    end

    GameTooltip:Show()
end

RefreshUI = function()
    if not uiFrame then
        return
    end

    local searchText = ""
    if uiFrame.searchBox and uiFrame.searchBox:GetText() then
        searchText = uiFrame.searchBox:GetText()
    end

    uiDisplayRows = BuildUIDisplayRows(searchText)

    local totalRows = table.getn(uiDisplayRows)
    FauxScrollFrame_Update(uiFrame.scrollFrame, totalRows, table.getn(uiRows), 18)

    local offset = FauxScrollFrame_GetOffset(uiFrame.scrollFrame)
    local i

    for i = 1, table.getn(uiRows) do
        local row = uiRows[i]
        local dataIndex = i + offset
        local data = uiDisplayRows[dataIndex]

        if data then
            row:Show()
            row.data = data

            if data.rowType == "header" then
                local collapsed = GetUICollapsedTable()
                local prefix = "[-] "
                if collapsed[data.profession] then
                    prefix = "[+] "
                end

                row.text:SetText(prefix .. data.profession .. " (" .. data.recipeCount .. ")")
                row.text:SetTextColor(1.0, 0.82, 0.0)
            else
                row.text:SetText("    " .. data.recipe)

                local onlineCount = 0
                local offlineCount = 0
                local c, crafterName

                if data.rawCrafters then
                    for c = 1, table.getn(data.rawCrafters) do
                        crafterName = data.rawCrafters[c]
                        if crafterName and crafterName ~= "" then
                            if IsPlayerOnline(crafterName) then
                                onlineCount = onlineCount + 1
                            else
                                offlineCount = offlineCount + 1
                            end
                        end
                    end
                end

                if onlineCount > 0 then
                    row.text:SetTextColor(0.2, 1.0, 0.2)
                elseif offlineCount > 0 then
                    row.text:SetTextColor(1.0, 0.82, 0.2)
                else
                    row.text:SetTextColor(1.0, 0.2, 0.2)
                end
            end
        else
            row:Hide()
            row.data = nil
        end
    end

    if uiFrame.emptyText then
        if totalRows == 0 then
            uiFrame.emptyText:Show()
        else
            uiFrame.emptyText:Hide()
        end
    end
end

local function ToggleProfession(profession)
    local collapsed = GetUICollapsedTable()
    collapsed[profession] = not collapsed[profession]
    RefreshUI()
end

local function CreateUIRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(18)
    row:SetWidth(360)

    if index == 1 then
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    else
        row:SetPoint("TOPLEFT", uiRows[index - 1], "BOTTOMLEFT", 0, 0)
    end

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.text:SetWidth(350)
    row.text:SetJustifyH("LEFT")

    row:SetScript("OnClick", function()
        if row.data and row.data.rowType == "header" then
            ToggleProfession(row.data.profession)
        end
    end)

    row:SetScript("OnEnter", function()
        if row.data and row.data.rowType == "recipe" then
            ShowRecipeTooltip(row)
        end
    end)

    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    local highlight = row:GetHighlightTexture()
    if highlight then
        highlight:SetBlendMode("ADD")
    end

    return row
end

local function SaveUIPosition()
    if not uiFrame then
        return
    end

    EnsureMetaTables()

    local point, relativeTo, relativePoint, xOfs, yOfs = uiFrame:GetPoint()
    GuildCraftDB_Meta.UI.Pos.point = point
    GuildCraftDB_Meta.UI.Pos.relativePoint = relativePoint
    GuildCraftDB_Meta.UI.Pos.xOfs = xOfs
    GuildCraftDB_Meta.UI.Pos.yOfs = yOfs
end

local function RestoreUIPosition()
    EnsureMetaTables()

    if not uiFrame then
        return
    end

    local pos = GuildCraftDB_Meta.UI.Pos
    uiFrame:ClearAllPoints()

    if pos and pos.point and pos.relativePoint and pos.xOfs and pos.yOfs then
        uiFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        uiFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function RequestGuildRosterRefresh()
    GuildRoster()

    if uiFrame and uiFrame.refreshButton then
        uiFrame.refreshButton:Disable()
    end

    refreshButtonTimer.endTime = GetTime() + 3
    refreshButtonTimer:SetScript("OnUpdate", function()
        if refreshButtonTimer.endTime and GetTime() >= refreshButtonTimer.endTime then
            refreshButtonTimer.endTime = nil
            refreshButtonTimer:SetScript("OnUpdate", nil)

            if uiFrame and uiFrame.refreshButton then
                uiFrame.refreshButton:Enable()
            end

            UpdateGuildRosterMetadata()

            if uiFrame and uiFrame:IsShown() then
                RefreshUI()

                local i
                for i = 1, table.getn(uiRows) do
                    local row = uiRows[i]
                    if row and row:IsVisible() and MouseIsOver(row) and row.data and row.data.rowType == "recipe" then
                        ShowRecipeTooltip(row)
                        break
                    end
                end
            end
        end
    end)
end

local function CreateUI()
    if uiFrame then
        return
    end

    local f = CreateFrame("Frame", "GuildCraftDB_MainFrame", UIParent)
    f:SetWidth(420)
    f:SetHeight(504)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        f:StartMoving()
    end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        SaveUIPosition()
    end)
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", f, "TOP", 0, -16)
    f.title:SetText("GuildCraftDB - " .. GetCurrentGuildName())

    local closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

    local searchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -38)
    searchLabel:SetText("Search:")

    local searchBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    searchBox:SetWidth(290)
    searchBox:SetHeight(20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEnterPressed", function()
        RefreshUI()
        searchBox:ClearFocus()
    end)
    f.searchBox = searchBox

    local searchButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    searchButton:SetWidth(70)
    searchButton:SetHeight(22)
    searchButton:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -66)
    searchButton:SetText("Search")
    searchButton:SetScript("OnClick", function()
        RefreshUI()
    end)

    local clearButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearButton:SetWidth(60)
    clearButton:SetHeight(22)
    clearButton:SetPoint("LEFT", searchButton, "RIGHT", 6, 0)
    clearButton:SetText("Clear")
    clearButton:SetScript("OnClick", function()
        searchBox:SetText("")
        RefreshUI()
    end)

    local refreshButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    refreshButton:SetWidth(65)
    refreshButton:SetHeight(22)
    refreshButton:SetPoint("LEFT", clearButton, "RIGHT", 6, 0)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", function()
        RequestGuildRosterRefresh()
    end)
    f.refreshButton = refreshButton

    local collapseAllButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    collapseAllButton:SetWidth(80)
    collapseAllButton:SetHeight(22)
    collapseAllButton:SetPoint("LEFT", refreshButton, "RIGHT", 6, 0)
    collapseAllButton:SetText("Collapse")
    collapseAllButton:SetScript("OnClick", function()
        local collapsed = GetUICollapsedTable()
        local index = GetProfessionIndex()
        local profession
        for profession in pairs(index) do
            collapsed[profession] = true
        end
        RefreshUI()
    end)

    local helpText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    helpText:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -96)
    helpText:SetText("Click a profession header to expand or collapse it. Hover a recipe for details.")
    helpText:SetWidth(320)
    helpText:SetJustifyH("LEFT")

    local scrollFrame = CreateFrame("ScrollFrame", "GuildCraftDB_ScrollFrame", f, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -126)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 16)
    scrollFrame:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(18, RefreshUI)
    end)
    f.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, f)
    content:SetWidth(360)
    content:SetHeight(350)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -130)
    f.content = content

    local i
    for i = 1, 19 do
        uiRows[i] = CreateUIRow(content, i)
    end

    local emptyText = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", content, "CENTER", 0, 0)
    emptyText:SetText("No matching recipes found.")
    f.emptyText = emptyText
    emptyText:Hide()

    uiFrame = f
    RestoreUIPosition()
end


local function UpdateMinimapButtonPosition()
    if not minimapButton then
        return
    end

    EnsureMetaTables()

    local angle = GuildCraftDB_Meta.UI.Minimap.angle or 220
    local radius = 78
    local x = math.cos(math.rad(angle)) * radius
    local y = math.sin(math.rad(angle)) * radius

    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CreateMinimapButton()
    if minimapButton then
        return
    end

    EnsureMetaTables()

    if GuildCraftDB_Meta.UI.Minimap.hide then
        return
    end

    local b = CreateFrame("Button", "GuildCraftDB_MinimapButton", Minimap)
    b:SetWidth(31)
    b:SetHeight(31)
    b:SetFrameStrata("MEDIUM")
    b:EnableMouse(true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    b:RegisterForDrag("LeftButton")

    local background = b:CreateTexture(nil, "BACKGROUND")
    background:SetWidth(20)
    background:SetHeight(20)
    background:SetPoint("CENTER", b, "CENTER", 0, 0)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.background = background

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(16)
    icon:SetHeight(16)
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    b.icon = icon

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetWidth(53)
    border:SetHeight(53)
    border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b.border = border

    b:SetScript("OnClick", function()
        if arg1 == "LeftButton" then
            ToggleUI()
        elseif arg1 == "RightButton" then
            RequestGuildRosterRefresh()
        elseif arg1 == "MiddleButton" then
            if IsInGuild() then
                SendAddonMessage("GCDB", "HELLO", "GUILD")
            end
        end
    end)

    b:SetScript("OnDragStart", function()
        b:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()

            px = px / scale
            py = py / scale

            local angle = math.deg(math.atan2(py - my, px - mx))
            GuildCraftDB_Meta.UI.Minimap.angle = angle
            UpdateMinimapButtonPosition()
        end)
    end)

    b:SetScript("OnDragStop", function()
        b:SetScript("OnUpdate", nil)
    end)

    b:SetScript("OnEnter", function()
        if b.border then
            b.border:SetVertexColor(1.0, 0.82, 0.0)
        end
        GameTooltip:SetOwner(b, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("GuildCraftDB", 1.0, 0.82, 0.0)
        GameTooltip:AddLine("Left-click: Open window", 1.0, 1.0, 1.0)
        GameTooltip:AddLine("Right-click: Refresh guild roster", 1.0, 1.0, 1.0)
        GameTooltip:AddLine("Middle-click: Sync guild data", 1.0, 1.0, 1.0)
        GameTooltip:AddLine("Drag: Move button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    b:SetScript("OnLeave", function()
        if b.border then
            b.border:SetVertexColor(1.0, 1.0, 1.0)
        end
        GameTooltip:Hide()
    end)

    minimapButton = b
    UpdateMinimapButtonPosition()
end

ToggleUI = function()
    if not uiFrame then
        CreateUI()
    end

    if uiFrame:IsShown() then
        uiFrame:Hide()
    else
        uiFrame:Show()
        UpdateWindowTitle()
        RefreshUI()
    end
end

frame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" then
        math.randomseed(time())
        EnsureMetaTables()

        if RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix("GCDB")
        end

        GuildRoster()
        UpdateGuildRosterMetadata()
        RemoveExcludedRecipesFromDB()
        RemoveBrokenRecipesFromDB()
        SanitizeStoredRecipeNames()
        CreateUI()
        UpdateWindowTitle()
        CreateMinimapButton()

        if IsInGuild() then
            SendGuildHello()
            ScheduleGuildHello(8)
        end

    elseif event == "TRADE_SKILL_SHOW" then
        ScanTradeSkill()
        if IsInGuild() then
            ScheduleGuildHello(2)
        end

        if uiFrame and uiFrame:IsShown() then
            UpdateWindowTitle()
            RefreshUI()
        end

    elseif event == "CRAFT_SHOW" then
        ScanCraft()
        if uiFrame and uiFrame:IsShown() then
            RefreshUI()
        end

    elseif event == "GUILD_ROSTER_UPDATE" then
        refreshButtonTimer.endTime = nil
        refreshButtonTimer:SetScript("OnUpdate", nil)

        UpdateGuildRosterMetadata()

        if uiFrame and uiFrame.refreshButton then
            uiFrame.refreshButton:Enable()
        end

        if uiFrame and uiFrame:IsShown() then
            RefreshUI()

            local i
            for i = 1, table.getn(uiRows) do
                local row = uiRows[i]
                if row and row:IsVisible() and MouseIsOver(row) and row.data and row.data.rowType == "recipe" then
                    ShowRecipeTooltip(row)
                    break
                end
            end
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix = arg1
        local message = arg2
        local channel = arg3
        local sender = arg4

        if prefix ~= "GCDB" then
            return
        end

        if channel ~= "GUILD" then
            return
        end

        if sender == UnitName("player") then
            return
        end

        if not IsInMyGuildByName(sender) then
            return
        end

        sender = GetShortName(sender)

        if message == "PING" then
            DebugMessage("received ping from " .. sender)
            return
        end

        if message == "HELLO" then
            DebugMessage("received HELLO from " .. sender)
            ScheduleProfessionSend()
            return
        end

        local _, _, command, playerName, profession, chunkIndex, isLast, recipeString =
            string.find(message, "^([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~?(.*)$")

        if command == "DATA" then
            ImportProfessionChunk(playerName, profession, recipeString, chunkIndex, isLast)

            if uiFrame and uiFrame:IsShown() and isLast == "1" then
                RefreshUI()
            end
        end
    end
end)

SLASH_GUILDCRAFT1 = "/guildcraft"

SlashCmdList["GUILDCRAFT"] = function(msg)
    if not msg or msg == "" then
        DEFAULT_CHAT_FRAME:AddMessage("Usage:")
        DEFAULT_CHAT_FRAME:AddMessage("/guildcraft ui")
        DEFAULT_CHAT_FRAME:AddMessage("/guildcraft <recipe>")
        DEFAULT_CHAT_FRAME:AddMessage("/guildcraft sendtest")
        DEFAULT_CHAT_FRAME:AddMessage("/guildcraft hello")
        DEFAULT_CHAT_FRAME:AddMessage("/guildcraft prune")
        DEFAULT_CHAT_FRAME:AddMessage("/guildcraft debug")
        DEFAULT_CHAT_FRAME:AddMessage("/guildcraft resynchash")
        DEFAULT_CHAT_FRAME:AddMessage("/guildcraft minimap")
        DEFAULT_CHAT_FRAME:AddMessage("/guildcraft profile")
        DEFAULT_CHAT_FRAME:AddMessage("/guildcraft cleanup")
        DEFAULT_CHAT_FRAME:AddMessage("/guildcraft clearlinks")
        return
    end

    if msg == "ui" then
        ToggleUI()
        return
    end

    if msg == "sendtest" then
        if not IsInGuild() then
            DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB: you are not in a guild")
            return
        end

        SendAddonMessage("GCDB", "PING", "GUILD")
        DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB: hidden guild test sent")
        return
    end

    if msg == "hello" then
        if not IsInGuild() then
            DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB: you are not in a guild")
            return
        end

        SendAddonMessage("GCDB", "HELLO", "GUILD")
        DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB: hidden HELLO sent")
        return
    end

    if msg == "prune" then
        PruneNonGuildData()
        DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB: pruned non-guild saved data")
        if uiFrame and uiFrame:IsShown() then
            RefreshUI()
        end
        return
    end


    if msg == "minimap" then
        EnsureMetaTables()
        GuildCraftDB_Meta.UI.Minimap.hide = not GuildCraftDB_Meta.UI.Minimap.hide

        if GuildCraftDB_Meta.UI.Minimap.hide then
            if minimapButton then
                minimapButton:Hide()
            end
            DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB: minimap button hidden")
        else
            if not minimapButton then
                CreateMinimapButton()
            end
            if minimapButton then
                minimapButton:Show()
                UpdateMinimapButtonPosition()
            end
            DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB: minimap button shown")
        end
        return
    end

    if msg == "debug" then
        if DEBUG then
            DEBUG = false
            DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB debug off")
        else
            DEBUG = true
            DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB debug on")
        end
        return
    end

    if msg == "profile" then
        local realmName = GetCurrentRealmName()
        local guildName = GetCurrentGuildName()
        local db = GetCurrentProfilePlayers()
        local count = 0
        local playerName

        for playerName in pairs(db) do
            count = count + 1
        end

        DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB profile: " .. realmName .. " / " .. guildName)
        DEFAULT_CHAT_FRAME:AddMessage("Stored players: " .. count)
        return
    end

    if msg == "cleanup" then
        local removedExcluded = RemoveExcludedRecipesFromDB()
        local removedBroken = RemoveBrokenRecipesFromDB()
        DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB: removed " .. (removedExcluded + removedBroken) .. " recipes from current profile")
        if uiFrame and uiFrame:IsShown() then
            RefreshUI()
        end
        return
    end

    if msg == "clearlinks" then
        local profileMeta = GetCurrentProfileMeta()
        profileMeta.ItemLinks = {}
        DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB: cleared learned item links for current profile")
        return
    end

    if msg == "resynchash" then
        EnsureMetaTables()
        local profileMeta = GetCurrentProfileMeta()
        profileMeta.Sync = {}
        DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB: cleared sync hash cache")
        return
    end

    local query = SafeLower(msg)
    local found = false

    local db = GetCurrentProfilePlayers()
    local player, professions, profession, recipes, _, recipe
    for player, professions in pairs(db) do
        for profession, recipes in pairs(professions) do
            if not IsProfessionExcluded(profession) then
                for _, recipe in ipairs(recipes) do
                    if string.find(SafeLower(recipe), query) then
                        DEFAULT_CHAT_FRAME:AddMessage(recipe .. " -> " .. GetColorizedPlayerName(player) .. " (" .. profession .. ")")
                        found = true
                    end
                end
            end
        end
    end

    if not found then
        DEFAULT_CHAT_FRAME:AddMessage("No recipes found for: " .. msg)
    end
end
