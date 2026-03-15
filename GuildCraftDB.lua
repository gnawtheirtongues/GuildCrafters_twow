GuildCraftDB = GuildCraftDB or {}
GuildCraftDB_Meta = GuildCraftDB_Meta or {}
GuildCraftDB_Export = GuildCraftDB_Export or {}
local SafeLower
local NormalizeRecipeName
local NormalizeRecipeList
local RebuildRecipeExport
local RecipeExists
local IsRecipeExcluded
local IsRecipeInvalid
local ShouldRunBulkMetaCache
local StartBulkMetaCacheJob
local frame = CreateFrame("Frame")
local delayedSender = CreateFrame("Frame")
local refreshButtonTimer = CreateFrame("Frame")
local guildHelloSender = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_UPDATE")
frame:RegisterEvent("CRAFT_SHOW")
frame:RegisterEvent("CRAFT_UPDATE")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
local DEBUG = false
local SEND_COOLDOWN = 60
local RECIPE_SEPARATOR = "||"
local pendingSend = nil
local pendingGuildHello = nil
local lastHelloTime = 0
local pendingTradeSkillScan = nil
local pendingCraftScan = nil
local pendingImportBuffers = {}
local AUTO_BULK_META_CACHE = true
local BULK_META_CACHE_LIMIT = 20
local BULK_META_CACHE_INTERVAL = 5
local bulkMetaCacheJobs = {}
local bulkMetaCacheTicker = CreateFrame("Frame")
local previewResolveTicker = CreateFrame("Frame")
local uiFrame = nil
local uiProfessionRows = {}
local uiRows = {}
local uiDisplayRows = {}
local uiCrafterButtons = {}
local minimapButton = nil
local safeLibCraftItemsLower = nil
local safeLibEnchantItemsLower = nil
local safeLibSpellToItem = nil
local ToggleUI
local ShowRecipeTooltip
local RefreshUI
local ScanTradeSkill
local ScanCraft
local ResolveRecipeItemLink
local GetSelectedRecipeLink
local CacheTradeSkillRecipeMeta
local CacheCraftRecipeMeta
local SetSyncStatus
local SetCacheStatus
local selectedProfession = nil
local selectedRecipe = nil
local selectedRecipeData = nil
local pendingPreviewResolve = nil
local syncStatusTextValue = "Sync: idle"
local cacheStatusTextValue = ""
local RECIPE_ROW_HEIGHT = 20
local PREVIEW_RESOLVE_INTERVAL = 0.25
local PREVIEW_RESOLVE_MAX_ATTEMPTS = 60
local ALWAYS_USE_PREDEFINED_CATEGORIES = true
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
    GuildCraftDB_Meta.Profiles[realm][guild].RecipeMeta = GuildCraftDB_Meta.Profiles[realm][guild].RecipeMeta or {}
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
    ["Poisons"] = true,
    ["Poison"] = true,
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
local PROFESSION_REQUIRES_FALLBACK = {
    ["Jewelcrafting"] = "Requires: Precision Jewelers Kit, Jewelry Lens",
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
SetSyncStatus = function(text)
    if not text or text == "" then
        return
    end

    syncStatusTextValue = text
    if uiFrame and uiFrame.syncStatusText then
        uiFrame.syncStatusText:SetText(syncStatusTextValue)
    end
end
SetCacheStatus = function(text)
    cacheStatusTextValue = text or ""
    if uiFrame and uiFrame.crafterCacheStatus then
        uiFrame.crafterCacheStatus:SetText(cacheStatusTextValue)
    end
end
SafeLower = function(text)
    if not text then
        return ""
    end
    return string.lower(text)
end
local function MatchCapture(text, pattern)
    if not text or not pattern then
        return nil
    end
    local _, _, cap = string.find(text, pattern)
    return cap
end
local function MatchToken(text, pattern)
    if not text or not pattern then
        return nil
    end
    local s, e = string.find(text, pattern)
    if s and e then
        return string.sub(text, s, e)
    end
    return nil
end
local function SafePairs(tbl)
    if type(tbl) ~= "table" then
        return function() return nil end
    end

    local key = nil
    return function()
        local ok, nextKey, nextValue = pcall(next, tbl, key)
        if not ok then
            return nil
        end
        key = nextKey
        return nextKey, nextValue
    end
end
local function EnsureMetaTables()
    GuildCraftDB = GuildCraftDB or {}
    GuildCraftDB_Meta = GuildCraftDB_Meta or {}
    GuildCraftDB_Export = GuildCraftDB_Export or {}
    GuildCraftDB_Meta.UI = GuildCraftDB_Meta.UI or {}
    GuildCraftDB_Meta.UI.Collapsed = GuildCraftDB_Meta.UI.Collapsed or {}
    GuildCraftDB_Meta.UI.Pos = GuildCraftDB_Meta.UI.Pos or {}
    GuildCraftDB_Meta.UI.Minimap = GuildCraftDB_Meta.UI.Minimap or { angle = 220, hide = false }
    GuildCraftDB_Meta.Players = GuildCraftDB_Meta.Players or {}
    GuildCraftDB_Meta.Sync = GuildCraftDB_Meta.Sync or {}
    GuildCraftDB.Profiles = GuildCraftDB.Profiles or {}
    GuildCraftDB_Meta.Profiles = GuildCraftDB_Meta.Profiles or {}
    GuildCraftDB_Export.Profiles = GuildCraftDB_Export.Profiles or {}
end
local function IsProfessionExcluded(profession)
    if not profession then
        return true
    end
    profession = tostring(profession)
    profession = string.gsub(profession, "^%s+", "")
    profession = string.gsub(profession, "%s+$", "")
    return EXCLUDED_PROFESSIONS[profession] == true
end
IsRecipeExcluded = function(profession, recipeName)
    if not profession or not recipeName then
        return false
    end
    profession = tostring(profession)
    profession = string.gsub(profession, "^%s+", "")
    profession = string.gsub(profession, "%s+$", "")
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
    if profession == "Cooking" and EXCLUDED_COOKING_RECIPES[recipeName] then
        return true
    end
    return false
end
NormalizeRecipeName = function(recipeName)
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
NormalizeRecipeList = function(recipes)
    if type(recipes) == "table" then
        return recipes
    end
    if type(recipes) == "string" then
        local fixed = {}
        local part
        for part in string.gfind(recipes, "([^,]+)") do
            part = NormalizeRecipeName(part)
            if part and part ~= "" and not RecipeExists(fixed, part) then
                table.insert(fixed, part)
            end
        end
        return fixed
    end
    return {}
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
local function BuildItemHyperlinkFromID(itemID, label)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then
        return nil
    end
    if GetItemInfo then
        local _, itemLink = GetItemInfo(itemID)
        if itemLink and string.find(itemLink, "|H", 1, true) then
            return itemLink
        end
    end
    return "|cff71d5ff|Hitem:" .. itemID .. ":0:0:0:0:0:0:0|h[" .. (label or ("item:" .. tostring(itemID))) .. "]|h|r"
end
local function BuildLowerItemIndex(src)
    local index = {}
    if type(src) ~= "table" then
        return index
    end
    local name, itemID
    for name, itemID in SafePairs(src) do
        if type(name) == "string" and tonumber(itemID) then
            index[SafeLower(name)] = tonumber(itemID)
        end
    end
    return index
end
local function BuildSpellToItemIndex()
    local index = {}
    if not GuildCraftLib or not GuildCraftLib.SpellIndexByProfession then
        return index
    end
    if GuildCraftSafeLib and GuildCraftSafeLib.CraftItems and not safeLibCraftItemsLower then
        safeLibCraftItemsLower = BuildLowerItemIndex(GuildCraftSafeLib.CraftItems)
    end
    if GuildCraftSafeLib and GuildCraftSafeLib.EnchantItems and not safeLibEnchantItemsLower then
        safeLibEnchantItemsLower = BuildLowerItemIndex(GuildCraftSafeLib.EnchantItems)
    end

    local professionName, spellMap, lookupName, spellID, itemID
    for professionName, spellMap in SafePairs(GuildCraftLib.SpellIndexByProfession) do
        if type(spellMap) == "table" then
            for lookupName, spellID in SafePairs(spellMap) do
                if lookupName and spellID then
                    itemID = nil
                    local lowerLookup = SafeLower(tostring(lookupName))
                    if safeLibCraftItemsLower then
                        itemID = safeLibCraftItemsLower[lowerLookup]
                    end
                    if not itemID and safeLibEnchantItemsLower then
                        itemID = safeLibEnchantItemsLower[lowerLookup]
                    end
                    if itemID then
                        index[tonumber(spellID)] = tonumber(itemID)
                    end
                end
            end
        end
    end
    return index
end
local function GetSafeLibItemIDBySpell(professionName, recipeName)
    if not professionName or professionName == "Enchanting" then
        return nil
    end
    local spellID = GetLibRecipeSpellID(professionName, recipeName)
    if not spellID then
        local lookupName = NormalizeRecipeLookupName(recipeName)
        if GuildCraftLib and GuildCraftLib.ProductItemsByProfession and GuildCraftLib.ProductItemsByProfession[professionName] and lookupName then
            return GuildCraftLib.ProductItemsByProfession[professionName][lookupName]
                or GuildCraftLib.ProductItemsByProfession[professionName][SafeLower(lookupName)]
        end
        return nil
    end
    if GuildCraftLib and GuildCraftLib.ProductItemsBySpell and GuildCraftLib.ProductItemsBySpell[tonumber(spellID)] then
        return GuildCraftLib.ProductItemsBySpell[tonumber(spellID)]
    end
    if GuildCraftLib and GuildCraftLib.ProductItemsByProfession and GuildCraftLib.ProductItemsByProfession[professionName] then
        local lookupName = NormalizeRecipeLookupName(recipeName)
        if lookupName and lookupName ~= "" then
            local mapped = GuildCraftLib.ProductItemsByProfession[professionName][lookupName]
                or GuildCraftLib.ProductItemsByProfession[professionName][SafeLower(lookupName)]
            if mapped then
                return mapped
            end
        end
    end
    if not safeLibSpellToItem then
        safeLibSpellToItem = BuildSpellToItemIndex()
    end
    return safeLibSpellToItem[tonumber(spellID)]
end
local function GetSafeLibItemID(lookupName)
    if not lookupName or lookupName == "" then
        return nil
    end
    if not GuildCraftSafeLib then
        return nil
    end

    local itemID = nil
    if GuildCraftSafeLib.CraftItems then
        itemID = GuildCraftSafeLib.CraftItems[lookupName]
    end
    if not itemID and GuildCraftSafeLib.EnchantItems then
        itemID = GuildCraftSafeLib.EnchantItems[lookupName]
    end
    if itemID then
        return tonumber(itemID)
    end

    local lowerName = SafeLower(lookupName)
    if GuildCraftSafeLib.CraftItems then
        if not safeLibCraftItemsLower then
            safeLibCraftItemsLower = BuildLowerItemIndex(GuildCraftSafeLib.CraftItems)
        end
        itemID = safeLibCraftItemsLower[lowerName]
    end
    if not itemID and GuildCraftSafeLib.EnchantItems then
        if not safeLibEnchantItemsLower then
            safeLibEnchantItemsLower = BuildLowerItemIndex(GuildCraftSafeLib.EnchantItems)
        end
        itemID = safeLibEnchantItemsLower[lowerName]
    end

    if itemID then
        return tonumber(itemID)
    end
    return nil
end
local function SanitizeStoredRecipeNames()
    local db = GetCurrentProfilePlayers()
    local player, professions, profession, recipes, keptRecipes, i, recipeName
    for player, professions in SafePairs(db) do
        for profession, recipes in SafePairs(professions) do
            local recipeList = NormalizeRecipeList(recipes)
            if recipeList and table.getn(recipeList) > 0 then
                keptRecipes = {}
                for i = 1, table.getn(recipeList) do
                    recipeName = NormalizeRecipeName(recipeList[i])
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
    for player, professions in SafePairs(db) do
        for profession, recipes in SafePairs(professions) do
            local recipeList = NormalizeRecipeList(recipes)
            if recipeList and table.getn(recipeList) > 0 then
                keptRecipes = {}
                for i = 1, table.getn(recipeList) do
                    recipeName = NormalizeRecipeName(recipeList[i])
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
    for player, professions in SafePairs(db) do
        for profession, recipes in SafePairs(professions) do
            local recipeList = NormalizeRecipeList(recipes)
            if recipeList and table.getn(recipeList) > 0 then
                keptRecipes = {}
                for i = 1, table.getn(recipeList) do
                    recipeName = recipeList[i]
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
        for token, localized in SafePairs(LOCALIZED_CLASS_NAMES_MALE) do
            if localized == className then
                return token
            end
        end
    end
    if LOCALIZED_CLASS_NAMES_FEMALE then
        local token, localized
        for token, localized in SafePairs(LOCALIZED_CLASS_NAMES_FEMALE) do
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
    for playerName, playerMeta in SafePairs(profileMeta.Players) do
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
local function GetPlayerOnlineFlag(playerName)
    local shortName = GetShortName(playerName)
    local profileMeta = GetCurrentProfileMeta()
    if profileMeta and profileMeta.Players and profileMeta.Players[shortName] and profileMeta.Players[shortName].online == 1 then
        return 1
    end
    return 0
end
local function SortArrayAscending(values)
    if not values then
        return
    end
    table.sort(values, function(a, b)
        return tostring(a) < tostring(b)
    end)
end
RebuildRecipeExport = function()
    EnsureMetaTables()
    GuildCraftDB = GuildCraftDB or {}
    GuildCraftDB_Meta = GuildCraftDB_Meta or {}
    GuildCraftDB_Export = GuildCraftDB_Export or {}
    local realm = GetCurrentRealmName()
    local guild = GetCurrentGuildName()
    local db = GetCurrentProfilePlayers()
    GuildCraftDB_Export.Profiles = GuildCraftDB_Export.Profiles or {}
    GuildCraftDB_Export.Profiles[realm] = GuildCraftDB_Export.Profiles[realm] or {}
    local exportProfile = {
        GeneratedAt = time(),
        Realm = realm,
        Guild = guild,
        Recipes = {},
    }
    local player, professions, profession, recipes, i, recipeName
    for player, professions in SafePairs(db) do
        for profession, recipes in SafePairs(professions) do
            if not IsProfessionExcluded(profession) then
                exportProfile.Recipes[profession] = exportProfile.Recipes[profession] or {}
                local recipeList = NormalizeRecipeList(recipes)
                for i = 1, table.getn(recipeList) do
                    recipeName = NormalizeRecipeName(recipeList[i])
                    if recipeName and recipeName ~= "" and not IsRecipeExcluded(profession, recipeName) and not IsRecipeInvalid(profession, recipeName) then
                        exportProfile.Recipes[profession][recipeName] = exportProfile.Recipes[profession][recipeName] or {
                            crafters = {},
                            online = {},
                        }
                        if not RecipeExists(exportProfile.Recipes[profession][recipeName].crafters, player) then
                            table.insert(exportProfile.Recipes[profession][recipeName].crafters, player)
                        end
                        exportProfile.Recipes[profession][recipeName].online[player] = GetPlayerOnlineFlag(player)
                    end
                end
            end
        end
    end
    for profession, recipeTable in SafePairs(exportProfile.Recipes) do
        for recipeName, entry in SafePairs(recipeTable) do
            SortArrayAscending(entry.crafters)
        end
    end
    GuildCraftDB_Export.Profiles[realm][guild] = exportProfile
    return exportProfile
end
local function RewriteSavedVariablesNow()
    local exportProfile = RebuildRecipeExport()
    DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB: rebuilt recipe export for " .. exportProfile.Guild .. ". Use /reload or relog to write the WTF file to disk.")
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
    db[player][profession] = NormalizeRecipeList(db[player][profession])
    return table.concat(NormalizeRecipeList(db[player][profession]), RECIPE_SEPARATOR)
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
    local recipes = NormalizeRecipeList(db[player][profession])
    db[player][profession] = recipes
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
    SetSyncStatus("Sync out: " .. profession .. " (" .. sentCount .. " msgs)")
    DebugMessage("sent " .. profession .. " in " .. sentCount .. " recipe messages")
end
local function SendAllMyStoredProfessions(forceSend)
    local player = UnitName("player")
    local db = GetCurrentProfilePlayers()
    if not db[player] then
        return
    end
    local removeProfessions = {}
    local removeCount = 0
    local profession, recipes
    for profession, recipes in SafePairs(db[player]) do
        local recipeList = NormalizeRecipeList(recipes)
        if IsProfessionExcluded(profession) then
            removeCount = removeCount + 1
            removeProfessions[removeCount] = profession
        elseif recipeList and table.getn(recipeList) > 0 then
            db[player][profession] = recipeList
            SendChunkedProfessionData(player, profession, forceSend)
        else
            removeCount = removeCount + 1
            removeProfessions[removeCount] = profession
        end
    end
    local i
    for i = 1, removeCount do
        profession = removeProfessions[i]
        if profession then
            db[player][profession] = nil
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
    SetSyncStatus("Sync: HELLO sent")
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
        if pendingSend and GetTime() >= pendingSend.time then
            pendingSend = nil
            SendAllMyStoredProfessions(true)
        end
        if pendingTradeSkillScan and GetTime() >= pendingTradeSkillScan.time then
            pendingTradeSkillScan = nil
            ScanTradeSkill(true)
        end
        if pendingCraftScan and GetTime() >= pendingCraftScan.time then
            pendingCraftScan = nil
            ScanCraft(true)
        end
        if not pendingSend and not pendingTradeSkillScan and not pendingCraftScan then
            delayedSender:SetScript("OnUpdate", nil)
        end
    end)
end
local function ScheduleTradeSkillRescan(delaySeconds)
    pendingTradeSkillScan = {
        time = GetTime() + (delaySeconds or 0.5)
    }
    delayedSender:SetScript("OnUpdate", function()
        if pendingSend and GetTime() >= pendingSend.time then
            pendingSend = nil
            SendAllMyStoredProfessions(true)
        end
        if pendingTradeSkillScan and GetTime() >= pendingTradeSkillScan.time then
            pendingTradeSkillScan = nil
            ScanTradeSkill(true)
        end
        if pendingCraftScan and GetTime() >= pendingCraftScan.time then
            pendingCraftScan = nil
            ScanCraft(true)
        end
        if not pendingSend and not pendingTradeSkillScan and not pendingCraftScan then
            delayedSender:SetScript("OnUpdate", nil)
        end
    end)
end
local function ScheduleCraftRescan(delaySeconds)
    pendingCraftScan = {
        time = GetTime() + (delaySeconds or 0.5)
    }
    delayedSender:SetScript("OnUpdate", function()
        if pendingSend and GetTime() >= pendingSend.time then
            pendingSend = nil
            SendAllMyStoredProfessions(true)
        end
        if pendingTradeSkillScan and GetTime() >= pendingTradeSkillScan.time then
            pendingTradeSkillScan = nil
            ScanTradeSkill(true)
        end
        if pendingCraftScan and GetTime() >= pendingCraftScan.time then
            pendingCraftScan = nil
            ScanCraft(true)
        end
        if not pendingSend and not pendingTradeSkillScan and not pendingCraftScan then
            delayedSender:SetScript("OnUpdate", nil)
        end
    end)
end
ScanTradeSkill = function(forceSend)
    local player = UnitName("player")
    local profession = GetTradeSkillLine()
    local total = GetNumTradeSkills and GetNumTradeSkills() or 0
    local freshRecipes = {}
    local i, name, skillType, itemLink
    if not profession or profession == "" or profession == "UNKNOWN" then
        DebugMessage("no trade skill detected")
        return
    end
    if IsProfessionExcluded(profession) then
        return
    end
    if total == 0 then
        DebugMessage("trade skill window opened before recipes loaded for " .. profession)
        ScheduleTradeSkillRescan(0.75)
        return
    end
    for i = 1, total do
        name, skillType = GetTradeSkillInfo(i)
        if name and skillType ~= "header" then
            name = NormalizeRecipeName(name)
            if name and name ~= "" and not IsRecipeExcluded(profession, name) and not IsRecipeInvalid(profession, name) then
                table.insert(freshRecipes, name)
            end
        end
    end
    if table.getn(freshRecipes) == 0 then
        DebugMessage("trade skill scan for " .. profession .. " returned no usable recipes")
        ScheduleTradeSkillRescan(0.75)
        return
    end
    local db = GetCurrentProfilePlayers()
    db[player] = db[player] or {}
    db[player][profession] = {}
    for i = 1, table.getn(freshRecipes) do
        name = freshRecipes[i]
        AddRecipe(player, profession, name)
        if GetTradeSkillItemLink then
            itemLink = GetTradeSkillItemLink(i)
            if itemLink then
                LearnRecipeItemLink(profession, name, itemLink)
            end
        end
    end
    if CacheTradeSkillRecipeMeta and ShouldRunBulkMetaCache(profession) then
        StartBulkMetaCacheJob("trade", profession)
    end
    RebuildRecipeExport()
    SendChunkedProfessionData(player, profession, forceSend and true or false)
    if IsInGuild() then
        SendGuildHello()
    end
    if uiFrame and uiFrame:IsShown() then
        RefreshUI()
    end
end
ScanCraft = function(forceSend)
    local player = UnitName("player")
    local profession = GetCraftDisplaySkillLine()
    local total = GetNumCrafts and GetNumCrafts() or 0
    local freshRecipes = {}
    local i, name, craftType, itemLink
    if not profession or profession == "" or profession == "UNKNOWN" then
        DebugMessage("no craft skill detected")
        return
    end
    if IsProfessionExcluded(profession) then
        return
    end
    if total == 0 then
        DebugMessage("craft window opened before recipes loaded for " .. profession)
        ScheduleCraftRescan(0.75)
        return
    end
    for i = 1, total do
        name, _, craftType = GetCraftInfo(i)
        if name and craftType ~= "header" then
            name = NormalizeRecipeName(name)
            if name and name ~= "" and not IsRecipeExcluded(profession, name) and not IsRecipeInvalid(profession, name) then
                table.insert(freshRecipes, name)
            end
        end
    end
    if table.getn(freshRecipes) == 0 then
        DebugMessage("craft scan for " .. profession .. " returned no usable recipes")
        ScheduleCraftRescan(0.75)
        return
    end
    local db = GetCurrentProfilePlayers()
    db[player] = db[player] or {}
    db[player][profession] = {}
    for i = 1, table.getn(freshRecipes) do
        name = freshRecipes[i]
        AddRecipe(player, profession, name)
        if GetCraftItemLink then
            itemLink = GetCraftItemLink(i)
            if itemLink then
                LearnRecipeItemLink(profession, name, itemLink)
            end
        end
    end
    if CacheCraftRecipeMeta and ShouldRunBulkMetaCache(profession) then
        StartBulkMetaCacheJob("craft", profession)
    end
    RebuildRecipeExport()
    SendChunkedProfessionData(player, profession, forceSend and true or false)
    if IsInGuild() then
        SendGuildHello()
    end
    if uiFrame and uiFrame:IsShown() then
        RefreshUI()
    end
end
local function GetImportBuffer(sender, profession, reset)
    pendingImportBuffers[sender] = pendingImportBuffers[sender] or {}
    if reset or not pendingImportBuffers[sender][profession] then
        pendingImportBuffers[sender][profession] = {
            recipes = {},
            seen = {},
            validCount = 0,
        }
    end
    return pendingImportBuffers[sender][profession]
end
local function ClearImportBuffer(sender, profession)
    if pendingImportBuffers[sender] then
        pendingImportBuffers[sender][profession] = nil
    end
end
local function ImportProfessionChunk(sender, profession, recipeString, chunkIndex, isLast)
    if not sender or not profession then
        return
    end
    sender = GetShortName(sender)
    profession = tostring(profession)
    profession = string.gsub(profession, "^%s+", "")
    profession = string.gsub(profession, "%s+$", "")
    if profession == "" or IsProfessionExcluded(profession) then
        ClearImportBuffer(sender, profession)
        return
    end
    if chunkIndex ~= "0" and chunkIndex ~= "1" then
        DebugMessage("ignored malformed chunk index from " .. sender .. " for " .. profession)
        return
    end
    if isLast ~= "0" and isLast ~= "1" then
        DebugMessage("ignored malformed last-flag from " .. sender .. " for " .. profession)
        return
    end
    local importBuffer = GetImportBuffer(sender, profession, chunkIndex == "1")
    local recipeList
    local i, recipeName
    if recipeString and recipeString ~= "" then
        if string.find(recipeString, RECIPE_SEPARATOR, 1, true) then
            recipeString = string.gsub(recipeString, RECIPE_SEPARATOR, ",")
        end
        recipeList = NormalizeRecipeList(recipeString)
        if recipeList and table.getn(recipeList) > 0 then
            for i = 1, table.getn(recipeList) do
                recipeName = NormalizeRecipeName(recipeList[i])
                if recipeName then
                    if string.find(recipeName, "~") or string.find(recipeName, "	") or string.len(recipeName) > 120 then
                        recipeName = nil
                    end
                end
                if recipeName and recipeName ~= "" and not IsRecipeExcluded(profession, recipeName) and not IsRecipeInvalid(profession, recipeName) then
                    if not importBuffer.seen[recipeName] then
                        importBuffer.seen[recipeName] = true
                        table.insert(importBuffer.recipes, recipeName)
                        importBuffer.validCount = importBuffer.validCount + 1
                    end
                end
            end
        end
    end
    if isLast == "1" then
        local db = GetCurrentProfilePlayers()
        db[sender] = db[sender] or {}
        if importBuffer.validCount > 0 then
            db[sender][profession] = importBuffer.recipes
            SetSyncStatus("Sync in: " .. sender .. " -> " .. profession .. " (" .. importBuffer.validCount .. ")")
            DebugMessage("imported " .. profession .. " from " .. sender .. " (" .. importBuffer.validCount .. " recipes)")
            RebuildRecipeExport()
            if uiFrame and uiFrame:IsShown() then
                RefreshUI()
            end
        else
            SetSyncStatus("Sync in: ignored invalid " .. profession .. " from " .. sender)
            DebugMessage("ignored empty or invalid sync for " .. profession .. " from " .. sender)
        end
        ClearImportBuffer(sender, profession)
    end
end
local function PruneNonGuildData()
    if not IsInGuild() then
        return
    end
    local me = GetShortName(UnitName("player"))
    local db = GetCurrentProfilePlayers()
    local profileMeta = GetCurrentProfileMeta()
    local removePlayers = {}
    local removeCount = 0
    local playerName
    for playerName in SafePairs(db) do
        if playerName ~= me and not IsInMyGuildByName(playerName) then
            removeCount = removeCount + 1
            removePlayers[removeCount] = playerName
        end
    end
    local i
    for i = 1, removeCount do
        playerName = removePlayers[i]
        if playerName then
            db[playerName] = nil
            profileMeta.Players[playerName] = nil
        end
    end
end
local function GetUICollapsedTable()
    EnsureMetaTables()
    return GuildCraftDB_Meta.UI.Collapsed
end
local function GetUICategoryCacheTable()
    EnsureMetaTables()
    GuildCraftDB_Meta.UI.CategoryCache = GuildCraftDB_Meta.UI.CategoryCache or {}
    return GuildCraftDB_Meta.UI.CategoryCache
end
local function IsCategoryCollapsed(profession, category)
    local collapsed = GetUICollapsedTable()
    local key = "cat:" .. tostring(profession or "") .. ":" .. tostring(category or "")
    if collapsed[key] == nil then
        return true
    end
    return collapsed[key] and true or false
end
local function GetProfessionIndex()
    local index = {}
    local db = GetCurrentProfilePlayers()

    if GuildCraftLib and GuildCraftLib.Catalog then
        local profession, recipes, recipeName
        for profession, recipes in SafePairs(GuildCraftLib.Catalog) do
            if not IsProfessionExcluded(profession) then
                index[profession] = index[profession] or {}
                for recipeName in SafePairs(recipes) do
                    recipeName = NormalizeRecipeName(recipeName)
                    if recipeName and recipeName ~= "" and not IsRecipeExcluded(profession, recipeName) and not IsRecipeInvalid(profession, recipeName) then
                        index[profession][recipeName] = index[profession][recipeName] or {}
                    end
                end
            end
        end
    end

    for player, professions in SafePairs(db) do
        for profession, recipes in SafePairs(professions) do
            if not IsProfessionExcluded(profession) then
                index[profession] = index[profession] or {}
                local recipeList = NormalizeRecipeList(recipes)
                for _, recipeName in ipairs(recipeList) do
                    recipeName = NormalizeRecipeName(recipeName)
                    if recipeName and recipeName ~= "" and not IsRecipeExcluded(profession, recipeName) and not IsRecipeInvalid(profession, recipeName) then
                        index[profession][recipeName] = index[profession][recipeName] or {}
                        if not RecipeExists(index[profession][recipeName], player) then
                            table.insert(index[profession][recipeName], player)
                        end
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
    for profession in SafePairs(index) do
        if not seen[profession] then
            table.insert(result, profession)
        end
    end
    return result
end
local function GetSortedRecipeList(recipeTable)
    local result = {}
    local recipe
    for recipe in SafePairs(recipeTable) do
        table.insert(result, recipe)
    end
    table.sort(result, function(a, b)
        return SafeLower(a) < SafeLower(b)
    end)
    return result
end
local function BuildProfessionDisplayList(index, searchText)
    local result = {}
    local professionList = GetSortedProfessionList(index)
    local filter = SafeLower(searchText)
    local i, profession

    for i = 1, table.getn(professionList) do
        profession = professionList[i]
        local recipeTable = index[profession]
        local sortedRecipes = GetSortedRecipeList(recipeTable)
        local r, recipeName
        local hasMatch = false

        for r = 1, table.getn(sortedRecipes) do
            recipeName = sortedRecipes[r]
            if filter == "" or string.find(SafeLower(recipeName), filter) then
                hasMatch = true
                break
            end
        end

        if hasMatch then
            table.insert(result, profession)
        end
    end

    return result
end

local function BuildRecipeRowsForProfession(index, profession, searchText)
    local rows = {}
    if not profession or not index[profession] then
        return rows
    end

    local recipeTable = index[profession]
    local sortedRecipes = GetSortedRecipeList(recipeTable)
    local filter = SafeLower(searchText)
    local r, recipeName

    local function BuildRawCrafterListForRecipe(name)
        local rawCrafterList = {}
        local c
        for c = 1, table.getn(recipeTable[name] or {}) do
            table.insert(rawCrafterList, recipeTable[name][c])
        end
        SortNames(rawCrafterList)
        return rawCrafterList
    end

    local function GetSkillTypePriority(skillType)
        local s = SafeLower(skillType or "")
        if s == "optimal" or s == "orange" then
            return 1
        end
        if s == "medium" or s == "yellow" then
            return 2
        end
        if s == "easy" or s == "green" then
            return 3
        end
        if s == "trivial" or s == "gray" or s == "grey" then
            return 4
        end
        return 5
    end

    local function BuildLiveRecipeMeta(profName)
        local meta = {}
        local headerOrder = {}
        local seenHeaders = {}
        local currentHeader = nil
        local hasLive = false
        local i, name, skillType

        local function RememberHeader(headerName)
            if not headerName or headerName == "" then
                headerName = "Other"
            end
            if not seenHeaders[headerName] then
                seenHeaders[headerName] = true
                table.insert(headerOrder, headerName)
            end
            return headerName
        end

        if GetTradeSkillLine and GetTradeSkillLine() == profName and GetNumTradeSkills and GetTradeSkillInfo then
            hasLive = true
            for i = 1, GetNumTradeSkills() do
                name, skillType = GetTradeSkillInfo(i)
                if name then
                    if skillType == "header" then
                        currentHeader = RememberHeader(NormalizeRecipeName(name) or "Other")
                    else
                        meta[NormalizeRecipeName(name)] = {
                            category = currentHeader or "Other",
                            skillType = skillType,
                            priority = GetSkillTypePriority(skillType),
                        }
                    end
                end
            end
            return meta, headerOrder, hasLive
        end

        if GetCraftDisplaySkillLine and GetCraftDisplaySkillLine() == profName and GetNumCrafts and GetCraftInfo then
            hasLive = true
            local craftType
            for i = 1, GetNumCrafts() do
                name, _, craftType = GetCraftInfo(i)
                if name then
                    if craftType == "header" then
                        currentHeader = RememberHeader(NormalizeRecipeName(name) or "Other")
                    else
                        meta[NormalizeRecipeName(name)] = {
                            category = currentHeader or "Other",
                            skillType = craftType,
                            priority = GetSkillTypePriority(craftType),
                        }
                    end
                end
            end
        end

        return meta, headerOrder, hasLive
    end

    local function NormalizeCategoryForProfession(profName, categoryValue, recipeNameValue)
        local preferredByProfession = {
            ["Alchemy"] = { ["Consumable"] = true, ["Trade Goods"] = true, ["Miscellaneous"] = true, ["Other"] = true },
            ["Blacksmithing"] = { ["Equipment"] = true, ["Trade Goods"] = true, ["Miscellaneous"] = true, ["Other"] = true },
            ["Cooking"] = { ["Consumable"] = true, ["Miscellaneous"] = true, ["Other"] = true },
            ["Enchanting"] = { ["Consumable"] = true, ["Trade Goods"] = true, ["Miscellaneous"] = true, ["Other"] = true },
            ["Engineering"] = { ["Equipment"] = true, ["Consumable"] = true, ["Trade Goods"] = true, ["Miscellaneous"] = true, ["Other"] = true },
            ["Jewelcrafting"] = { ["Consumable"] = true, ["Equipment"] = true, ["Trade Goods"] = true, ["Miscellaneous"] = true, ["Other"] = true },
            ["Leatherworking"] = { ["Equipment"] = true, ["Consumable"] = true, ["Trade Goods"] = true, ["Miscellaneous"] = true, ["Other"] = true },
            ["Tailoring"] = { ["Cloth"] = true, ["Equipment"] = true, ["Trade Goods"] = true, ["Miscellaneous"] = true, ["Other"] = true },
        }
        local allowed = preferredByProfession[profName] or { ["Consumable"] = true, ["Equipment"] = true, ["Trade Goods"] = true, ["Miscellaneous"] = true, ["Other"] = true }
        local category = tostring(categoryValue or "")
        local lowerCategory = SafeLower(category)
        local lowerRecipe = SafeLower(NormalizeRecipeName(recipeNameValue) or "")

        if category ~= "" and allowed[category] then
            return category
        end

        if lowerCategory == "mail" or lowerCategory == "plate" or lowerCategory == "staves" or lowerCategory == "staff" or lowerCategory == "weapon" or lowerCategory == "armor" or lowerCategory == "leather" then
            if allowed["Equipment"] then
                return "Equipment"
            end
        end
        if lowerCategory == "cloth" then
            if allowed["Cloth"] then
                return "Cloth"
            end
            if allowed["Equipment"] then
                return "Equipment"
            end
        end
        if lowerCategory == "junk" or lowerCategory == "misc" or lowerCategory == "miscellaneous" then
            if allowed["Miscellaneous"] then
                return "Miscellaneous"
            end
        end
        if lowerCategory == "trade goods" then
            if allowed["Trade Goods"] then
                return "Trade Goods"
            end
        end
        if lowerCategory == "consumable" then
            if allowed["Consumable"] then
                return "Consumable"
            end
        end

        if string.find(lowerRecipe, "potion", 1, true)
            or string.find(lowerRecipe, "elixir", 1, true)
            or string.find(lowerRecipe, "flask", 1, true)
            or string.find(lowerRecipe, "oil", 1, true)
            or string.find(lowerRecipe, "food", 1, true)
            or string.find(lowerRecipe, "bandage", 1, true)
            or string.find(lowerRecipe, "gemstone", 1, true) then
            if allowed["Consumable"] then
                return "Consumable"
            end
        end
        if string.find(lowerRecipe, "cloth", 1, true) or string.find(lowerRecipe, "robe", 1, true) then
            if allowed["Cloth"] then
                return "Cloth"
            end
            if allowed["Equipment"] then
                return "Equipment"
            end
        end
        if string.find(lowerRecipe, "mail", 1, true)
            or string.find(lowerRecipe, "plate", 1, true)
            or string.find(lowerRecipe, "boots", 1, true)
            or string.find(lowerRecipe, "helm", 1, true)
            or string.find(lowerRecipe, "belt", 1, true)
            or string.find(lowerRecipe, "leggings", 1, true)
            or string.find(lowerRecipe, "gloves", 1, true)
            or string.find(lowerRecipe, "bracers", 1, true)
            or string.find(lowerRecipe, "shoulders", 1, true)
            or string.find(lowerRecipe, "sword", 1, true)
            or string.find(lowerRecipe, "axe", 1, true)
            or string.find(lowerRecipe, "gun", 1, true)
            or string.find(lowerRecipe, "shotgun", 1, true) then
            if allowed["Equipment"] then
                return "Equipment"
            end
        end
        if string.find(lowerRecipe, "bar", 1, true)
            or string.find(lowerRecipe, "bolt", 1, true)
            or string.find(lowerRecipe, "thread", 1, true)
            or string.find(lowerRecipe, "wire", 1, true)
            or string.find(lowerRecipe, "leather", 1, true) then
            if allowed["Trade Goods"] then
                return "Trade Goods"
            end
        end

        return "Other"
    end

    local function InferFallbackCategory(profName, recipeNameValue)
        local normalizedRecipe = NormalizeRecipeName(recipeNameValue)
        local lowerRecipe = SafeLower(normalizedRecipe or "")
        local preferredByProfession = {
            ["Alchemy"] = { ["Consumable"] = true, ["Trade Goods"] = true, ["Miscellaneous"] = true, ["Other"] = true },
            ["Blacksmithing"] = { ["Equipment"] = true, ["Trade Goods"] = true, ["Miscellaneous"] = true, ["Other"] = true },
            ["Cooking"] = { ["Consumable"] = true, ["Miscellaneous"] = true, ["Other"] = true },
            ["Enchanting"] = { ["Consumable"] = true, ["Trade Goods"] = true, ["Miscellaneous"] = true, ["Other"] = true },
            ["Engineering"] = { ["Equipment"] = true, ["Consumable"] = true, ["Trade Goods"] = true, ["Miscellaneous"] = true, ["Other"] = true },
            ["Jewelcrafting"] = { ["Consumable"] = true, ["Equipment"] = true, ["Trade Goods"] = true, ["Miscellaneous"] = true, ["Other"] = true },
            ["Leatherworking"] = { ["Equipment"] = true, ["Consumable"] = true, ["Trade Goods"] = true, ["Miscellaneous"] = true, ["Other"] = true },
            ["Tailoring"] = { ["Cloth"] = true, ["Equipment"] = true, ["Trade Goods"] = true, ["Miscellaneous"] = true, ["Other"] = true },
        }
        local allowed = preferredByProfession[profName] or { ["Consumable"] = true, ["Equipment"] = true, ["Trade Goods"] = true, ["Miscellaneous"] = true, ["Other"] = true }
        local function NormalizeCategory(cat)
            if not cat or cat == "" then
                return "Other"
            end
            if allowed[cat] then
                return cat
            end
            if cat == "Armor" or cat == "Weapon" or cat == "Staves" or cat == "Mail" or cat == "Plate" or cat == "Leather" then
                if allowed["Equipment"] then
                    return "Equipment"
                end
                return "Other"
            end
            if cat == "Cloth" then
                if allowed["Cloth"] then
                    return "Cloth"
                end
                if allowed["Equipment"] then
                    return "Equipment"
                end
                return "Other"
            end
            if cat == "Junk" then
                if allowed["Miscellaneous"] then
                    return "Miscellaneous"
                end
                return "Other"
            end
            if cat == "Miscellaneous" then
                if allowed["Miscellaneous"] then
                    return "Miscellaneous"
                end
                return "Other"
            end
            if cat == "Trade Goods" then
                if allowed["Trade Goods"] then
                    return "Trade Goods"
                end
                return "Other"
            end
            if cat == "Consumable" then
                if allowed["Consumable"] then
                    return "Consumable"
                end
                return "Other"
            end
            return "Other"
        end

        local function NormalizeItemCategory(itemType, itemSubType)
            local t = itemType and tostring(itemType) or ""
            local s = itemSubType and tostring(itemSubType) or ""
            if t == "Armor" then
                if s == "Cloth" and profName == "Tailoring" then
                    return "Cloth"
                end
                return "Equipment"
            end
            if t == "Weapon" then
                return "Equipment"
            end
            if t == "Trade Goods" then
                return "Trade Goods"
            end
            if t == "Consumable" then
                return "Consumable"
            end
            if t == "Container" then
                if profName == "Tailoring" then
                    return "Cloth"
                end
                return "Miscellaneous"
            end
            if t == "Miscellaneous" then
                return "Miscellaneous"
            end
            if t == "Junk" then
                return "Miscellaneous"
            end
            return nil
        end

        local productID = nil
        if GuildCraftLib and GuildCraftLib.ProductItemsByProfession and GuildCraftLib.ProductItemsByProfession[profName] then
            productID = GuildCraftLib.ProductItemsByProfession[profName][normalizedRecipe]
                or GuildCraftLib.ProductItemsByProfession[profName][SafeLower(normalizedRecipe or "")]
        end
        if productID and GetItemInfo then
            local _, _, _, _, _, itemType, itemSubType = GetItemInfo(tonumber(productID))
            local categoryFromItem = NormalizeItemCategory(itemType, itemSubType)
            if categoryFromItem and categoryFromItem ~= "" then
                return NormalizeCategoryForProfession(profName, categoryFromItem, recipeNameValue)
            end
        end

        if string.find(lowerRecipe, "gemstone", 1, true)
            or string.find(lowerRecipe, "elixir", 1, true)
            or string.find(lowerRecipe, "flask", 1, true)
            or string.find(lowerRecipe, "potion", 1, true)
            or string.find(lowerRecipe, "oil", 1, true)
            or string.find(lowerRecipe, "bandage", 1, true) then
            return NormalizeCategory("Consumable")
        end
        if string.find(lowerRecipe, "cloth", 1, true) or string.find(lowerRecipe, "robe", 1, true) then
            if profName == "Tailoring" then
                return NormalizeCategory("Cloth")
            end
            return NormalizeCategory("Equipment")
        end
        if string.find(lowerRecipe, "staff", 1, true)
            or string.find(lowerRecipe, "mail", 1, true)
            or string.find(lowerRecipe, "plate", 1, true)
            or string.find(lowerRecipe, "leather", 1, true)
            or string.find(lowerRecipe, "boots", 1, true)
            or string.find(lowerRecipe, "helm", 1, true)
            or string.find(lowerRecipe, "belt", 1, true)
            or string.find(lowerRecipe, "leggings", 1, true)
            or string.find(lowerRecipe, "gloves", 1, true)
            or string.find(lowerRecipe, "bracers", 1, true)
            or string.find(lowerRecipe, "shoulders", 1, true) then
            return NormalizeCategory("Equipment")
        end
        if string.find(lowerRecipe, "rod", 1, true)
            or string.find(lowerRecipe, "bar", 1, true)
            or string.find(lowerRecipe, "bolt", 1, true)
            or string.find(lowerRecipe, "thread", 1, true)
            or string.find(lowerRecipe, "cloth", 1, true) then
            return NormalizeCategory("Trade Goods")
        end
        return NormalizeCategory("Other")
    end

    local function BuildStaticFallbackMeta(profName)
        local meta = {}
        local headers = {}
        local seen = {}
        local preferredByProfession = {
            ["Alchemy"] = { "Consumable", "Trade Goods", "Miscellaneous", "Other" },
            ["Blacksmithing"] = { "Equipment", "Trade Goods", "Miscellaneous", "Other" },
            ["Cooking"] = { "Consumable", "Miscellaneous", "Other" },
            ["Enchanting"] = { "Consumable", "Trade Goods", "Miscellaneous", "Other" },
            ["Engineering"] = { "Equipment", "Consumable", "Trade Goods", "Miscellaneous", "Other" },
            ["Jewelcrafting"] = { "Consumable", "Equipment", "Trade Goods", "Miscellaneous", "Other" },
            ["Leatherworking"] = { "Equipment", "Consumable", "Trade Goods", "Miscellaneous", "Other" },
            ["Tailoring"] = { "Cloth", "Equipment", "Trade Goods", "Miscellaneous", "Other" },
        }
        local preferred = preferredByProfession[profName] or { "Consumable", "Equipment", "Trade Goods", "Miscellaneous", "Other" }
        local r, n
        for r = 1, table.getn(sortedRecipes) do
            n = NormalizeRecipeName(sortedRecipes[r])
            if n and n ~= "" then
                local cat = NormalizeCategoryForProfession(profName, InferFallbackCategory(profName, n), n)
                meta[n] = {
                    category = cat or "Other",
                    skillType = nil,
                    priority = 5,
                }
                seen[cat or "Other"] = true
            end
        end
        local i, catName
        for i = 1, table.getn(preferred) do
            catName = preferred[i]
            if seen[catName] then
                table.insert(headers, catName)
                seen[catName] = nil
            end
        end
        local extra = {}
        for catName in SafePairs(seen) do
            table.insert(extra, catName)
        end
        table.sort(extra, function(a, b) return SafeLower(a) < SafeLower(b) end)
        for i = 1, table.getn(extra) do
            table.insert(headers, extra[i])
        end
        return meta, headers
    end

    local liveSkillMeta = {}
    local liveHeaderOrder = {}
    local hasLiveMeta = false
    liveSkillMeta, liveHeaderOrder, hasLiveMeta = BuildLiveRecipeMeta(profession)
    local staticMeta, staticHeaders = BuildStaticFallbackMeta(profession)
    local categoryCache = GetUICategoryCacheTable()
    categoryCache[profession] = categoryCache[profession] or { headers = {}, recipes = {} }
    local cached = categoryCache[profession]
    local liveMeta = {}
    if ALWAYS_USE_PREDEFINED_CATEGORIES then
        liveHeaderOrder = staticHeaders
        local normalizedName, m, liveSkill
        for normalizedName, m in SafePairs(staticMeta) do
            liveSkill = liveSkillMeta[normalizedName]
            liveMeta[normalizedName] = {
                category = m.category,
                skillType = liveSkill and liveSkill.skillType or nil,
                priority = liveSkill and liveSkill.priority or 5,
            }
        end

        cached.headers = staticHeaders
        cached.recipes = {}
        for normalizedName, m in SafePairs(liveMeta) do
            cached.recipes[normalizedName] = {
                category = m.category,
                skillType = m.skillType,
                priority = m.priority,
            }
        end
    elseif hasLiveMeta then
        liveMeta = liveSkillMeta
        cached.headers = {}
        local i, headerName
        for i = 1, table.getn(liveHeaderOrder or {}) do
            headerName = liveHeaderOrder[i]
            cached.headers[i] = headerName
        end
        cached.recipes = {}
        local normalizedName, m
        for normalizedName, m in SafePairs(liveMeta) do
            if normalizedName and m then
                cached.recipes[normalizedName] = {
                    category = m.category,
                    skillType = m.skillType,
                    priority = m.priority,
                }
            end
        end
    elseif cached and cached.recipes and next(cached.recipes) then
        liveHeaderOrder = cached.headers or {}
        local normalizedName, m
        for normalizedName, m in SafePairs(cached.recipes or {}) do
            if normalizedName and m then
                liveMeta[normalizedName] = {
                    category = m.category,
                    skillType = m.skillType,
                    priority = m.priority,
                }
            end
        end
    else
        liveMeta = staticMeta
        liveHeaderOrder = staticHeaders
    end
    local grouped = {}
    local groupOrder = {}

    for r = 1, table.getn(sortedRecipes) do
        recipeName = sortedRecipes[r]
        if filter == "" or string.find(SafeLower(recipeName), filter) then
            local recipeMeta = liveMeta[NormalizeRecipeName(recipeName)] or {}
            local category = NormalizeCategoryForProfession(profession, recipeMeta.category or "Other", recipeName)
            if category == "" then
                category = "Other"
            end
            if not grouped[category] then
                grouped[category] = {}
                local i
                local addedFromLiveOrder = false
                for i = 1, table.getn(liveHeaderOrder or {}) do
                    if liveHeaderOrder[i] == category then
                        table.insert(groupOrder, category)
                        addedFromLiveOrder = true
                        break
                    end
                end
                if not addedFromLiveOrder then
                    table.insert(groupOrder, category)
                end
            end
            table.insert(grouped[category], {
                rowType = "recipe",
                profession = profession,
                category = category,
                recipe = recipeName,
                rawCrafters = BuildRawCrafterListForRecipe(recipeName),
                skillType = recipeMeta.skillType,
                skillPriority = recipeMeta.priority or 5,
            })
        end
    end

    local orderedGroups = {}
    local seenGroup = {}
    local i, catName
    for i = 1, table.getn(liveHeaderOrder or {}) do
        catName = liveHeaderOrder[i]
        if grouped[catName] and not seenGroup[catName] then
            seenGroup[catName] = true
            table.insert(orderedGroups, catName)
        end
    end
    for i = 1, table.getn(groupOrder) do
        catName = groupOrder[i]
        if grouped[catName] and not seenGroup[catName] then
            seenGroup[catName] = true
            table.insert(orderedGroups, catName)
        end
    end
    groupOrder = orderedGroups

    local g, category
    for g = 1, table.getn(groupOrder) do
        category = groupOrder[g]
        local list = grouped[category]
        if list and table.getn(list) > 0 then
            local collapseKey = "cat:" .. profession .. ":" .. category
            local isCollapsed = IsCategoryCollapsed(profession, category)
            table.insert(rows, {
                rowType = "groupHeader",
                profession = profession,
                title = category,
                collapseKey = collapseKey,
                isCollapsed = isCollapsed,
            })
            if not isCollapsed then
                table.sort(list, function(a, b)
                    if (a.skillPriority or 5) ~= (b.skillPriority or 5) then
                        return (a.skillPriority or 5) < (b.skillPriority or 5)
                    end
                    return SafeLower(a.recipe or "") < SafeLower(b.recipe or "")
                end)
                for r = 1, table.getn(list) do
                    table.insert(rows, list[r])
                end
            end
        end
    end

    if table.getn(rows) > 0 then
        return rows
    end

    for r = 1, table.getn(sortedRecipes) do
        recipeName = sortedRecipes[r]
        if filter == "" or string.find(SafeLower(recipeName), filter) then
            table.insert(rows, {
                rowType = "recipe",
                profession = profession,
                category = nil,
                recipe = recipeName,
                rawCrafters = BuildRawCrafterListForRecipe(recipeName),
            })
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
local previewScanTooltip = nil
local function GetScanTooltipDescription()
    local i
    local greenLines = {}
    local effectLines = {}
    local collectingEffect = false

    for i = 2, 30 do
        local left = getglobal("GuildCraftDB_PreviewScanTooltipTextLeft" .. i)
        if left then
            local txt = left:GetText()
            if txt and txt ~= "" then
                local low = SafeLower(txt)
                if not string.find(low, "binds when", 1, true)
                    and not string.find(low, "unique", 1, true)
                    and not string.find(low, "requires", 1, true)
                    and not string.find(low, "sell price", 1, true)
                    and not string.find(low, "durability", 1, true) then
                    local r, g, b = left:GetTextColor()
                    if r and g and b and g > 0.75 and r < 0.55 and b < 0.55 then
                        table.insert(greenLines, txt)
                    end

                    if string.find(low, "use:", 1, true) or string.find(low, "equip:", 1, true) then
                        collectingEffect = true
                        table.insert(effectLines, txt)
                    elseif collectingEffect then
                        if not string.find(low, "jewelcrafting ", 1, true)
                            and not string.find(low, "engineering ", 1, true)
                            and not string.find(low, "blacksmithing ", 1, true)
                            and not string.find(low, "alchemy ", 1, true)
                            and not string.find(low, "tailoring ", 1, true)
                            and not string.find(low, "leatherworking ", 1, true) then
                            table.insert(effectLines, txt)
                        else
                            collectingEffect = false
                        end
                    end
                end
            end
        end
    end

    if table.getn(effectLines) > 0 then
        local joined = effectLines[1]
        for i = 2, table.getn(effectLines) do
            joined = joined .. "\n" .. effectLines[i]
        end
        return joined
    end

    if table.getn(greenLines) > 0 then
        local joined = greenLines[1]
        for i = 2, table.getn(greenLines) do
            joined = joined .. "\n" .. greenLines[i]
        end
        return joined
    end

    return nil
end
local function GetScanTooltipRequiresLine()
    local i
    for i = 2, 30 do
        local left = getglobal("GuildCraftDB_PreviewScanTooltipTextLeft" .. i)
        if left then
            local txt = left:GetText()
            if txt and txt ~= "" then
                if string.find(txt, "^Requires:") then
                    return txt
                end
            end
        end
    end
    return nil
end
local function NormalizeToItemHyperlink(linkValue, label)
    if not linkValue or linkValue == "" then
        return nil
    end

    local itemID = nil
    if type(linkValue) == "number" then
        itemID = tonumber(linkValue)
    else
        itemID = tonumber(MatchCapture(tostring(linkValue), "item:(%d+)"))
    end
    if not itemID or itemID <= 0 then
        return nil
    end

    if GetItemInfo then
        local _, itemLink = GetItemInfo(itemID)
        if itemLink and string.find(itemLink, "|Hitem:", 1, true) then
            return itemLink
        end
    end

    return "|cff71d5ff|Hitem:" .. itemID .. ":0:0:0:0:0:0:0|h[" .. (label or ("item:" .. tostring(itemID))) .. "]|h|r"
end
local function GetItemDescriptionFromTooltip(itemLink)
    if not itemLink or itemLink == "" then
        return nil
    end

    local safeLink = NormalizeToItemHyperlink(itemLink)
    if not safeLink then
        return nil
    end

    if not previewScanTooltip then
        previewScanTooltip = CreateFrame("GameTooltip", "GuildCraftDB_PreviewScanTooltip", UIParent, "GameTooltipTemplate")
        previewScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end

    previewScanTooltip:ClearLines()
    local ok = pcall(function()
        previewScanTooltip:SetHyperlink(safeLink)
    end)
    if not ok then
        return nil
    end

    return GetScanTooltipDescription()
end
local function GetItemUseEffectFromTooltip(itemLink)
    if not itemLink or itemLink == "" then
        return nil
    end

    local safeLink = NormalizeToItemHyperlink(itemLink)
    if not safeLink then
        return nil
    end

    if not previewScanTooltip then
        previewScanTooltip = CreateFrame("GameTooltip", "GuildCraftDB_PreviewScanTooltip", UIParent, "GameTooltipTemplate")
        previewScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end

    previewScanTooltip:ClearLines()
    local ok = pcall(function()
        previewScanTooltip:SetHyperlink(safeLink)
    end)
    if not ok then
        return nil
    end

    local lines = {}
    local collecting = false
    local i
    for i = 2, 30 do
        local left = getglobal("GuildCraftDB_PreviewScanTooltipTextLeft" .. i)
        if left then
            local txt = left:GetText()
            if txt and txt ~= "" then
                local low = SafeLower(txt)
                if string.find(low, "use:", 1, true)
                    or string.find(low, "equip:", 1, true)
                    or string.find(low, "chance on hit:", 1, true)
                    or string.find(low, "on hit:", 1, true) then
                    collecting = true
                    table.insert(lines, txt)
                elseif collecting then
                    if string.find(low, "requires ", 1, true)
                        or string.find(low, "durability", 1, true)
                        or string.find(low, "sell price", 1, true)
                        or string.find(low, "unique", 1, true)
                        or string.find(low, "binds when", 1, true) then
                        break
                    end
                    table.insert(lines, txt)
                end
            elseif collecting then
                break
            end
        end
    end

    if table.getn(lines) > 0 then
        return table.concat(lines, "\n")
    end

    return GetScanTooltipDescription()
end
local function GetPreferredDescriptionFromTooltipFrame(tooltipFrame)
    if not tooltipFrame then
        return nil
    end

    local lines = {}
    local collecting = false
    local anyText = nil
    local i
    for i = 2, 30 do
        local left = getglobal(tooltipFrame:GetName() .. "TextLeft" .. i)
        if left then
            local txt = left:GetText()
            if txt and txt ~= "" then
                local low = SafeLower(txt)
                if not anyText then
                    anyText = txt
                end
                if string.find(low, "use:", 1, true)
                    or string.find(low, "equip:", 1, true)
                    or string.find(low, "chance on hit:", 1, true)
                    or string.find(low, "on hit:", 1, true) then
                    collecting = true
                    table.insert(lines, txt)
                elseif collecting then
                    if string.find(low, "requires ", 1, true)
                        or string.find(low, "durability", 1, true)
                        or string.find(low, "sell price", 1, true)
                        or string.find(low, "unique", 1, true)
                        or string.find(low, "binds when", 1, true) then
                        break
                    end
                    table.insert(lines, txt)
                end
            elseif collecting then
                break
            end
        end
    end

    if table.getn(lines) > 0 then
        return table.concat(lines, "\n")
    end
    return anyText
end
local function GetPreferredDescriptionFromItemLink(itemLink)
    if not itemLink or itemLink == "" then
        return nil
    end
    local safeLink = NormalizeToItemHyperlink(itemLink)
    if safeLink then
        if not previewScanTooltip then
            previewScanTooltip = CreateFrame("GameTooltip", "GuildCraftDB_PreviewScanTooltip", UIParent, "GameTooltipTemplate")
            previewScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        end
        previewScanTooltip:ClearLines()
        local ok = pcall(function()
            previewScanTooltip:SetHyperlink(safeLink)
        end)
        if ok then
            local fromFrame = GetPreferredDescriptionFromTooltipFrame(previewScanTooltip)
            if fromFrame and fromFrame ~= "" and not string.find(fromFrame, "^Creates%s+") then
                return fromFrame
            end
        end
    end
    local useText = GetItemUseEffectFromTooltip(itemLink)
    if useText and useText ~= "" then
        return useText
    end
    local desc = GetItemDescriptionFromTooltip(itemLink)
    if desc and desc ~= "" and not string.find(desc, "^Creates%s+") then
        return desc
    end
    return nil
end
local function GetPreferredDescriptionForRecipe(recipeName, professionName, fallbackItemLink)
    if not recipeName or recipeName == "" then
        return nil, nil
    end

    local candidates = {}
    local seen = {}
    local function AddCandidate(linkValue)
        local normalized = NormalizeToItemHyperlink(linkValue, recipeName)
        if normalized and normalized ~= "" and not seen[normalized] then
            seen[normalized] = true
            table.insert(candidates, normalized)
        end
    end

    if professionName and professionName ~= "Enchanting" then
        AddCandidate(GetSafeLibItemLink(professionName, recipeName))
        AddCandidate(ResolveRecipeItemLink(recipeName, professionName))
    end
    AddCandidate(fallbackItemLink)
    AddCandidate(GetSelectedRecipeLink(recipeName, professionName))

    local i, text
    for i = 1, table.getn(candidates) do
        text = GetPreferredDescriptionFromItemLink(candidates[i])
        if text and text ~= "" then
            return text, candidates[i]
        end
    end
    return nil, nil
end
local ARMOR_SUBTYPE_SUPPRESS = {
    ["Cloth"] = true,
    ["Leather"] = true,
    ["Mail"] = true,
    ["Plate"] = true,
}
local function IsSuppressedArmorOrWeaponType(itemType, itemSubType)
    if itemType == "Weapon" then
        return true
    end
    if itemType == "Armor" then
        return ARMOR_SUBTYPE_SUPPRESS[itemSubType] and true or false
    end
    return false
end
local GREEN_TEXT_SUPPRESS_BY_CATEGORY = {
    ["Blacksmithing"] = { ["Equipment"] = true, ["Other"] = true },
    ["Engineering"] = { ["Equipment"] = true },
    ["Leatherworking"] = { ["Equipment"] = true },
    ["Tailoring"] = { ["Cloth"] = true, ["Equipment"] = true },
}
local function ShouldSuppressGreenByCategory(professionName, categoryName)
    local byProfession = GREEN_TEXT_SUPPRESS_BY_CATEGORY[professionName]
    if not byProfession then
        return false
    end
    local key = tostring(categoryName or "")
    if key == "" then
        return false
    end
    return byProfession[key] and true or false
end
local function GetItemTypeFromLink(linkValue)
    if not linkValue or linkValue == "" or not GetItemInfo then
        return nil, nil
    end
    local normalized = NormalizeToItemHyperlink(linkValue)
    if not normalized then
        return nil, nil
    end
    local itemID = tonumber(MatchCapture(normalized, "item:(%d+)"))
    if not itemID or itemID <= 0 then
        return nil, nil
    end
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(itemID)
    return itemType, itemSubType
end
local function ShouldSuppressGreenDescription(recipeName, professionName, fallbackItemLink, categoryName)
    if professionName == "Enchanting" then
        return false
    end
    if ShouldSuppressGreenByCategory(professionName, categoryName) then
        return true
    end
    local t, s = GetItemTypeFromLink(fallbackItemLink)
    if IsSuppressedArmorOrWeaponType(t, s) then
        return true
    end
    t, s = GetItemTypeFromLink(GetSafeLibItemLink(professionName, recipeName))
    if IsSuppressedArmorOrWeaponType(t, s) then
        return true
    end
    t, s = GetItemTypeFromLink(ResolveRecipeItemLink(recipeName, professionName))
    if IsSuppressedArmorOrWeaponType(t, s) then
        return true
    end
    t, s = GetItemTypeFromLink(GetSelectedRecipeLink(recipeName, professionName))
    if IsSuppressedArmorOrWeaponType(t, s) then
        return true
    end
    if GetItemInfo then
        local _, _, _, _, _, byNameType, byNameSubType = GetItemInfo(recipeName)
        if IsSuppressedArmorOrWeaponType(byNameType, byNameSubType) then
            return true
        end
    end
    return false
end
local function ShouldHidePreviewGreenText(recipeName, professionName, descriptionText, fallbackItemLink, categoryName)
    if professionName == "Enchanting" then
        return false
    end
    local text = tostring(descriptionText or "")
    if text == "" then
        return false
    end
    if ShouldSuppressGreenDescription(recipeName, professionName, fallbackItemLink, categoryName) then
        return true
    end
    return false
end
local function BuildRequiresFromToolNames(toolA, toolB, toolC, toolD)
    local tools = {}
    local seen = {}
    local function addTool(t)
        if t and type(t) == "string" and t ~= "" and not seen[t] then
            seen[t] = true
            table.insert(tools, t)
        end
    end
    addTool(toolA)
    addTool(toolB)
    addTool(toolC)
    addTool(toolD)
    if table.getn(tools) > 0 then
        return "Requires: " .. table.concat(tools, ", ")
    end
    return nil
end
local function GetDefaultRequiresForProfession(professionName)
    if professionName and PROFESSION_REQUIRES_FALLBACK[professionName] then
        return PROFESSION_REQUIRES_FALLBACK[professionName]
    end
    return nil
end
local function GetRequiresFromTradeSkillTools(recipeIndex)
    if not recipeIndex or not GetTradeSkillTools then
        return nil
    end
    local a, b, c, d = GetTradeSkillTools(recipeIndex)
    if not a and not b and not c and not d then
        return nil
    end
    if type(a) == "number" then
        return BuildRequiresFromToolNames(b, c, d, nil)
    end
    return BuildRequiresFromToolNames(a, b, c, d)
end
local function GetRequiresFromCraftTools(recipeIndex)
    if not recipeIndex then
        return nil
    end
    if GetCraftSpellFocus then
        local focus = GetCraftSpellFocus(recipeIndex)
        if focus and focus ~= "" then
            return "Requires: " .. focus
        end
    end
    return nil
end
local function GetDescriptionFromTradeSkillItem(recipeIndex)
    if not recipeIndex or not SetTradeSkillItem then
        return nil
    end
    if not previewScanTooltip then
        previewScanTooltip = CreateFrame("GameTooltip", "GuildCraftDB_PreviewScanTooltip", UIParent, "GameTooltipTemplate")
        previewScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end

    previewScanTooltip:ClearLines()
    local ok = pcall(function()
        previewScanTooltip:SetTradeSkillItem(recipeIndex)
    end)
    if not ok then
        return nil
    end

    return GetScanTooltipDescription()
end
local function GetRequiresFromTradeSkillItem(recipeIndex)
    local apiReq = GetRequiresFromTradeSkillTools(recipeIndex)
    if apiReq and apiReq ~= "" then
        return apiReq
    end
    if not recipeIndex or not SetTradeSkillItem then
        return nil
    end
    if not previewScanTooltip then
        previewScanTooltip = CreateFrame("GameTooltip", "GuildCraftDB_PreviewScanTooltip", UIParent, "GameTooltipTemplate")
        previewScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end

    previewScanTooltip:ClearLines()
    local ok = pcall(function()
        previewScanTooltip:SetTradeSkillItem(recipeIndex)
    end)
    if not ok then
        return nil
    end
    return GetScanTooltipRequiresLine()
end
local function GetDescriptionFromCraftItem(recipeIndex)
    if not recipeIndex or not SetCraftItem then
        return nil
    end
    if not previewScanTooltip then
        previewScanTooltip = CreateFrame("GameTooltip", "GuildCraftDB_PreviewScanTooltip", UIParent, "GameTooltipTemplate")
        previewScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end

    previewScanTooltip:ClearLines()
    local ok = pcall(function()
        previewScanTooltip:SetCraftItem(recipeIndex)
    end)
    if not ok then
        return nil
    end

    return GetScanTooltipDescription()
end
local function GetRequiresFromCraftItem(recipeIndex)
    local apiReq = GetRequiresFromCraftTools(recipeIndex)
    if apiReq and apiReq ~= "" then
        return apiReq
    end
    if not recipeIndex or not SetCraftItem then
        return nil
    end
    if not previewScanTooltip then
        previewScanTooltip = CreateFrame("GameTooltip", "GuildCraftDB_PreviewScanTooltip", UIParent, "GameTooltipTemplate")
        previewScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end

    previewScanTooltip:ClearLines()
    local ok = pcall(function()
        previewScanTooltip:SetCraftItem(recipeIndex)
    end)
    if not ok then
        return nil
    end
    return GetScanTooltipRequiresLine()
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
ResolveRecipeItemLink = function(recipeName, professionName)
    if not recipeName or recipeName == "" then
        return nil
    end
    if professionName and professionName ~= "Enchanting" then
        local spellItemID = GetSafeLibItemIDBySpell(professionName, recipeName)
        if spellItemID and spellItemID > 0 then
            return "item:" .. spellItemID .. ":0:0:0"
        end
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
local function JoinCrafterNames(nameList)
    if not nameList or table.getn(nameList) == 0 then
        return "None"
    end
    local names = {}
    local i
    for i = 1, table.getn(nameList) do
        local shortName = GetShortName(nameList[i])
        local classToken = GetPlayerClassToken(shortName)
        if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
            local c = RAID_CLASS_COLORS[classToken]
            local r = math.floor(c.r * 255)
            local g = math.floor(c.g * 255)
            local b = math.floor(c.b * 255)
            names[i] = string.format("|cff%02x%02x%02x%s|r", r, g, b, shortName)
        else
            names[i] = shortName
        end
    end
    return table.concat(names, ", ")
end
local function ProfessionHasOnlineCrafter(index, profession)
    if not index or not profession or not index[profession] then
        return false
    end

    local recipeMap = index[profession]
    local recipeName, crafterList, c, crafterName
    for recipeName, crafterList in SafePairs(recipeMap) do
        if type(crafterList) == "table" then
            for c = 1, table.getn(crafterList) do
                crafterName = crafterList[c]
                if crafterName and crafterName ~= "" and IsPlayerOnline(crafterName) then
                    return true
                end
            end
        end
    end

    return false
end

GetSelectedRecipeLink = function(recipeName, professionName)
    if not recipeName or recipeName == "" then
        return nil
    end

    local function NormalizeLinkForChat(linkValue)
        if not linkValue or linkValue == "" then
            return nil
        end
        if string.find(linkValue, "|H", 1, true) then
            return linkValue
        end
        local itemToken = MatchToken(linkValue, "item:[^|%s]+")
        if itemToken then
            local itemID = tonumber(MatchCapture(itemToken, "item:(%d+)"))
            return BuildItemHyperlinkFromID(itemID, recipeName)
        end
        local spellToken = MatchToken(linkValue, "spell:%d+")
        if spellToken then
            return "|cff71d5ff|H" .. spellToken .. "|h[" .. recipeName .. "]|h|r"
        end
        return nil
    end

    local lookupName = NormalizeRecipeLookupName(recipeName)
    local safeItemID = GetSafeLibItemID(lookupName)
    if safeItemID then
        local safeItemLink = BuildItemHyperlinkFromID(safeItemID, recipeName)
        if safeItemLink then
            return safeItemLink
        end
    end

    local safeItemLink = GetSafeLibItemLink(professionName, recipeName)
    if safeItemLink then
        return NormalizeLinkForChat(safeItemLink)
    end

    local itemLink = ResolveRecipeItemLink(recipeName, professionName)
    if itemLink then
        return NormalizeLinkForChat(itemLink)
    end

    local spellID = GetLibRecipeSpellID(professionName, recipeName)
    if spellID then
        return "|cff71d5ff|Hspell:" .. spellID .. "|h[" .. recipeName .. "]|h|r"
    end

    return nil
end

local function InsertRecipeLinkIntoChat(recipeName, professionName)
    local link = GetSelectedRecipeLink(recipeName, professionName)
    local fallbackText = "[" .. (recipeName or "recipe") .. "]"
    local itemToken = link and MatchToken(link, "item:[^|%s]+") or nil
    local itemID = itemToken and tonumber(MatchCapture(itemToken, "item:(%d+)")) or nil
    if itemID and GetItemInfo then
        local _, itemLink = GetItemInfo(itemID)
        if itemLink and string.find(itemLink, "|H", 1, true) then
            link = itemLink
        end
    end
    local editBox = nil

    if ChatEdit_GetActiveWindow then
        editBox = ChatEdit_GetActiveWindow()
    end
    if not editBox and ChatFrameEditBox and ChatFrameEditBox:IsVisible() then
        editBox = ChatFrameEditBox
    end
    if not editBox and ChatFrame_OpenChat then
        ChatFrame_OpenChat("")
        if ChatEdit_GetActiveWindow then
            editBox = ChatEdit_GetActiveWindow()
        end
        if not editBox and ChatFrameEditBox and ChatFrameEditBox:IsVisible() then
            editBox = ChatFrameEditBox
        end
    end
    if not editBox and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox then
        editBox = DEFAULT_CHAT_FRAME.editBox
        editBox:Show()
    end
    if not editBox then
        return false
    end

    if link and link ~= "" then
        if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then
            return true
        end
        if editBox.Insert then
            editBox:Insert(link)
        else
            local currentLink = editBox:GetText() or ""
            editBox:SetText(currentLink .. link)
        end
        return true
    end

    if editBox.Insert then
        editBox:Insert(fallbackText)
    else
        local current = editBox:GetText() or ""
        editBox:SetText(current .. fallbackText)
    end
    return true
end

local function GetWhisperRecipeText(recipeName, professionName)
    local link = GetSelectedRecipeLink(recipeName, professionName)
    if not link or link == "" then
        return "[" .. (recipeName or "recipe") .. "]"
    end

    if string.find(link, "|H", 1, true) then
        return link
    end

    local itemToken = MatchToken(link, "item:[^|%s]+")
    if itemToken then
        if GetItemInfo then
            local _, itemLink = GetItemInfo(itemToken)
            if itemLink and string.find(itemLink, "|H", 1, true) then
                return itemLink
            end
        end
        return "|cff71d5ff|H" .. itemToken .. "|h[" .. (recipeName or "recipe") .. "]|h|r"
    end

    local spellToken = MatchToken(link, "spell:%d+")
    if spellToken then
        return "|cff71d5ff|H" .. spellToken .. "|h[" .. (recipeName or "recipe") .. "]|h|r"
    end

    return "[" .. (recipeName or "recipe") .. "]"
end
local function AppendToEditBox(editBox, text)
    if not editBox or not text or text == "" then
        return
    end
    if editBox.Insert then
        editBox:Insert(text)
    else
        local current = editBox:GetText() or ""
        editBox:SetText(current .. text)
    end
end

ShowRecipeTooltip = function(row)
    if not row or not row.data or row.data.rowType ~= "recipe" then
        return
    end

    local recipeName = row.data.recipe
    local professionName = row.data.profession
    if not recipeName or recipeName == "" then
        return
    end

    local hasFullTooltip = TrySetFullRecipeTooltip(row, recipeName, professionName)
    if not hasFullTooltip then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(recipeName, 1.0, 0.82, 0.0)
        if professionName and professionName ~= "" then
            GameTooltip:AddLine(professionName, 0.6, 0.8, 1.0)
        end
    end

    if row.data.crafters and row.data.crafters ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Crafters: " .. row.data.crafters, 0.7, 1.0, 0.7, true)
    end

    AddRecipeInfoToTooltip(recipeName)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Shift-click to link in chat", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end
RefreshUI = function()
    if not uiFrame then
        return
    end
    UpdateGuildRosterMetadata()
    local searchText = ""
    if uiFrame.searchBox and uiFrame.searchBox:GetText() then
        searchText = uiFrame.searchBox:GetText()
    end

    local index = GetProfessionIndex()
    local professionList = BuildProfessionDisplayList(index, searchText)
    local i

    if table.getn(professionList) == 0 then
        selectedProfession = nil
        selectedRecipe = nil
        selectedRecipeData = nil
    elseif not selectedProfession or not index[selectedProfession] then
        selectedProfession = professionList[1]
        selectedRecipe = nil
        selectedRecipeData = nil
    end

    for i = 1, table.getn(uiProfessionRows) do
        local row = uiProfessionRows[i]
        local profession = professionList[i]

        if profession then
            row:Show()
            row.profession = profession
            row.text:SetText(profession)
            if ProfessionHasOnlineCrafter(index, profession) then
                row.text:SetTextColor(0.2, 1.0, 0.2)
            else
                row.text:SetTextColor(1.0, 0.2, 0.2)
            end

            if profession == selectedProfession then
                row.selectedTexture:Show()
            else
                row.selectedTexture:Hide()
            end
        else
            row:Hide()
            row.profession = nil
            row.selectedTexture:Hide()
        end
    end

    uiDisplayRows = BuildRecipeRowsForProfession(index, selectedProfession, searchText)
    if uiFrame and uiFrame.collapseButton then
        local hasGroupHeader = false
        local hasExpanded = false
        local j, d
        for j = 1, table.getn(uiDisplayRows) do
            d = uiDisplayRows[j]
            if d and d.rowType == "groupHeader" then
                hasGroupHeader = true
                if not d.isCollapsed then
                    hasExpanded = true
                end
            end
        end
        if hasGroupHeader then
            uiFrame.collapseButton:Show()
            if hasExpanded then
                uiFrame.collapseButton:SetText("Collapse")
            else
                uiFrame.collapseButton:SetText("Expand")
            end
        else
            uiFrame.collapseButton:Hide()
        end
    end

    local totalRows = table.getn(uiDisplayRows)
    FauxScrollFrame_Update(uiFrame.scrollFrame, totalRows, table.getn(uiRows), RECIPE_ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(uiFrame.scrollFrame)

    local selectedStillVisible = false

    for i = 1, table.getn(uiRows) do
        local row = uiRows[i]
        local dataIndex = i + offset
        local data = uiDisplayRows[dataIndex]

        if data then
            row:Show()
            row.data = data
            if data.rowType == "groupHeader" then
                local prefix = "[-] "
                if data.isCollapsed then
                    prefix = "[+] "
                end
                row.text:SetText(prefix .. (data.title or "Other"))
                row.text:SetTextColor(1.0, 1.0, 1.0)
                row.selectedTexture:Hide()
            else
                row.text:SetText(data.recipe)

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

                if selectedRecipe and data.recipe == selectedRecipe and data.profession == selectedProfession then
                    row.selectedTexture:Show()
                    selectedRecipeData = data
                    selectedStillVisible = true
                else
                    row.selectedTexture:Hide()
                end
            end
        else
            row:Hide()
            row.data = nil
            row.selectedTexture:Hide()
        end
    end

    if selectedRecipe and not selectedStillVisible then
        selectedRecipe = nil
        selectedRecipeData = nil
    end

    if uiFrame.emptyText then
        if totalRows == 0 then
            uiFrame.emptyText:Show()
        else
            uiFrame.emptyText:Hide()
        end
    end

    if uiFrame.UpdateCrafterPanel then
        uiFrame:UpdateCrafterPanel()
    end
    if uiFrame.UpdatePreviewPanel then
        uiFrame:UpdatePreviewPanel()
    end
end

local function CreateProfessionRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(20)
    row:SetWidth(140)

    if index == 1 then
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    else
        row:SetPoint("TOPLEFT", uiProfessionRows[index - 1], "BOTTOMLEFT", 0, -2)
    end

    row.selectedTexture = row:CreateTexture(nil, "BACKGROUND")
    row.selectedTexture:SetTexture("Interface\\Buttons\\WHITE8x8")
    row.selectedTexture:SetVertexColor(0.25, 0.35, 0.55, 0.25)
    row.selectedTexture:SetAllPoints(row)
    row.selectedTexture:Hide()

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.text:SetWidth(132)
    row.text:SetJustifyH("LEFT")

    row:SetScript("OnClick", function()
        if row.profession then
            selectedProfession = row.profession
            selectedRecipe = nil
            selectedRecipeData = nil
            RefreshUI()
        end
    end)

    return row
end

local function CreateRecipeRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(RECIPE_ROW_HEIGHT)
    row:SetWidth(405)

    if index == 1 then
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    else
        row:SetPoint("TOPLEFT", uiRows[index - 1], "BOTTOMLEFT", 0, 0)
    end

    row.selectedTexture = row:CreateTexture(nil, "BACKGROUND")
    row.selectedTexture:SetTexture("Interface\\Buttons\\WHITE8x8")
    row.selectedTexture:SetVertexColor(0.35, 0.35, 0.35, 0.25)
    row.selectedTexture:SetAllPoints(row)
    row.selectedTexture:Hide()

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.text:SetWidth(397)
    row.text:SetJustifyH("LEFT")

    row:SetScript("OnClick", function()
        if not row.data then
            return
        end
        if row.data.rowType == "groupHeader" then
            if row.data.collapseKey and row.data.collapseKey ~= "" then
                local collapsed = GetUICollapsedTable()
                collapsed[row.data.collapseKey] = not IsCategoryCollapsed(row.data.profession, row.data.title)
                RefreshUI()
            end
            return
        end
        if row.data.rowType ~= "recipe" then
            return
        end

        if IsShiftKeyDown() then
            InsertRecipeLinkIntoChat(row.data.recipe, row.data.profession)
            return
        end

        selectedRecipe = row.data.recipe
        selectedRecipeData = row.data
        RefreshUI()
    end)

    row:SetScript("OnEnter", function()
    end)

    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return row
end

local function AcquireCrafterButton(parent, index)
    if not uiCrafterButtons[index] then
        local button = CreateFrame("Button", nil, parent)
        button:SetHeight(14)
        button:SetWidth(12)
        button:RegisterForClicks("LeftButtonUp")

        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.text:SetPoint("LEFT", button, "LEFT", 0, 0)
        button.text:SetJustifyH("LEFT")

        button:SetScript("OnClick", function()
            if not button.playerName or not selectedRecipeData then
                return
            end

            local target = GetShortName(button.playerName)
            local fallbackText = "[" .. (selectedRecipeData.recipe or "recipe") .. "]"
            local linkText = GetSelectedRecipeLink(selectedRecipeData.recipe, selectedRecipeData.profession)
            local linkItemToken = linkText and MatchToken(linkText, "item:[^|%s]+") or nil
            local linkItemID = linkItemToken and tonumber(MatchCapture(linkItemToken, "item:(%d+)")) or nil
            if linkItemID and GetItemInfo then
                local _, cachedItemLink = GetItemInfo(linkItemID)
                if cachedItemLink and string.find(cachedItemLink, "|H", 1, true) then
                    linkText = cachedItemLink
                end
            end
            local editBox = nil

            if ChatFrame_SendTell then
                ChatFrame_SendTell(target)
            elseif ChatFrame_OpenChat then
                ChatFrame_OpenChat("/w " .. target .. " ")
            end

            if ChatEdit_GetActiveWindow then
                editBox = ChatEdit_GetActiveWindow()
            end
            if not editBox and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox then
                editBox = DEFAULT_CHAT_FRAME.editBox
                editBox:Show()
                editBox:SetText("/w " .. target .. " ")
            end
            if not editBox then
                return
            end

            AppendToEditBox(editBox, "hey can you make this ")

            local inserted = false
            if linkText and ChatEdit_InsertLink then
                inserted = ChatEdit_InsertLink(linkText) and true or false
            end
            if not inserted then
                if linkText and linkText ~= "" then
                    AppendToEditBox(editBox, linkText)
                    inserted = true
                else
                    AppendToEditBox(editBox, fallbackText)
                end
            end

            AppendToEditBox(editBox, " for me")
            if editBox.HighlightText then
                local len = string.len(editBox:GetText() or "")
                if len > 0 then
                    editBox:HighlightText(len, len)
                end
            end
        end)

        uiCrafterButtons[index] = button
    end

    return uiCrafterButtons[index]
end

local function AcquirePreviewReagentRow(parent, index)
    uiFrame.previewReagentRows = uiFrame.previewReagentRows or {}

    if not uiFrame.previewReagentRows[index] then
        local row = CreateFrame("Frame", nil, parent)
        row:SetWidth(200)
        row:SetHeight(18)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(16)
        row.icon:SetHeight(16)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.text:SetWidth(180)
        row.text:SetJustifyH("LEFT")

        uiFrame.previewReagentRows[index] = row
    end

    return uiFrame.previewReagentRows[index]
end

local function FindRecipeInOpenCraftWindow(recipeName, professionName)
    local i, name, skillType
    local normalized = NormalizeRecipeName(recipeName)

    if GetTradeSkillLine and GetTradeSkillLine() == professionName and GetNumTradeSkills then
        for i = 1, GetNumTradeSkills() do
            name, skillType = GetTradeSkillInfo(i)
            if name and skillType ~= "header" and NormalizeRecipeName(name) == normalized then
                return "trade", i
            end
        end
    end

    if GetCraftDisplaySkillLine and GetCraftDisplaySkillLine() == professionName and GetNumCrafts then
        local craftType
        for i = 1, GetNumCrafts() do
            name, _, craftType = GetCraftInfo(i)
            if name and craftType ~= "header" and NormalizeRecipeName(name) == normalized then
                return "craft", i
            end
        end
    end

    return nil, nil
end

local function GetOwnedCountByName(itemName)
    if not itemName or itemName == "" then
        return 0
    end
    local function NormalizeItemKey(name)
        if not name then
            return ""
        end
        name = tostring(name)
        name = string.gsub(name, "^%s+", "")
        name = string.gsub(name, "%s+$", "")
        name = string.gsub(name, "%s+", " ")
        return SafeLower(name)
    end

    if GetItemCount then
        local count = GetItemCount(itemName)
        if count and count > 0 then
            return count
        end
    end

    -- Vanilla-compatible fallback: scan backpack/bags directly.
    if not GetContainerNumSlots or not GetContainerItemInfo or not GetContainerItemLink or not GetItemInfo then
        return 0
    end

    local target = NormalizeItemKey(itemName)
    local total = 0
    local bag, slot
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link and link ~= "" then
                local bagItemName = GetItemInfo(link)
                if (not bagItemName or bagItemName == "") then
                    bagItemName = MatchCapture(link, "%[(.-)%]")
                end
                if bagItemName and NormalizeItemKey(bagItemName) == target then
                    local _, stackCount = GetContainerItemInfo(bag, slot)
                    total = total + (stackCount or 1)
                end
            end
        end
    end

    if total > 0 then
        return total
    end

    return 0
end
local function HasStoredMetaSnapshot(meta)
    if not meta then
        return false
    end
    if meta.icon and meta.icon ~= "" then
        return true
    end
    if meta.itemLink and meta.itemLink ~= "" then
        return true
    end
    if table.getn(meta.reagents or {}) > 0 then
        return true
    end
    if meta.description and meta.description ~= "" then
        return true
    end
    return false
end

ShouldRunBulkMetaCache = function(professionName)
    if not AUTO_BULK_META_CACHE then
        return false
    end
    if not professionName or professionName == "" then
        return false
    end
    return true
end

local function GetStoredRecipeMeta(professionName, recipeName)
    if not professionName or not recipeName then
        return nil
    end
    professionName = tostring(professionName)
    professionName = string.gsub(professionName, "^%s+", "")
    professionName = string.gsub(professionName, "%s+$", "")
    recipeName = NormalizeRecipeName(recipeName)
    if not recipeName or recipeName == "" then
        return nil
    end

    local profileMeta = GetCurrentProfileMeta()
    profileMeta.RecipeMeta = profileMeta.RecipeMeta or {}
    profileMeta.RecipeMeta[professionName] = profileMeta.RecipeMeta[professionName] or {}

    return profileMeta.RecipeMeta[professionName][recipeName]
end

local function SaveStoredRecipeMeta(professionName, recipeName, preview)
    if not professionName or not recipeName or not preview then
        return
    end
    professionName = tostring(professionName)
    professionName = string.gsub(professionName, "^%s+", "")
    professionName = string.gsub(professionName, "%s+$", "")
    recipeName = NormalizeRecipeName(recipeName)
    if not recipeName or recipeName == "" then
        return
    end

    local profileMeta = GetCurrentProfileMeta()
    profileMeta.RecipeMeta = profileMeta.RecipeMeta or {}
    profileMeta.RecipeMeta[professionName] = profileMeta.RecipeMeta[professionName] or {}

    local existing = profileMeta.RecipeMeta[professionName][recipeName]

    if table.getn(preview.reagents or {}) == 0 and existing and table.getn(existing.reagents or {}) > 0 then
        return
    end

    local descriptionText = preview.description or ""
    if descriptionText == "No cached recipe description available." then
        descriptionText = ""
    end
    if string.find(descriptionText, "^Creates%s+") then
        descriptionText = ""
    end

    local stored = {
        icon = preview.icon,
        title = preview.title or recipeName,
        requires = preview.requires or "",
        description = descriptionText,
        itemLink = preview.itemLink or "",
        reagents = {},
        updatedAt = time(),
    }

    local i
    for i = 1, table.getn(preview.reagents or {}) do
        local r = preview.reagents[i]
        if r and r.name and r.name ~= "" then
            table.insert(stored.reagents, {
                name = r.name,
                icon = r.icon,
                required = r.required or 0,
            })
        end
    end

    profileMeta.RecipeMeta[professionName][recipeName] = stored
end

CacheTradeSkillRecipeMeta = function(professionName)
    if not professionName or professionName == "" or not GetNumTradeSkills then
        return true, 0, 0
    end

    local total = GetNumTradeSkills()
    if not total or total <= 0 then
        return true, 0, 0
    end

    local oldIndex = GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex() or nil
    local i, name, skillType
    local totalValid = 0
    local probeName, probeType

    for i = 1, total do
        probeName, probeType = GetTradeSkillInfo(i)
        if probeName and probeType ~= "header" then
            probeName = NormalizeRecipeName(probeName)
            if probeName and probeName ~= "" and not IsRecipeExcluded(professionName, probeName) and not IsRecipeInvalid(professionName, probeName) then
                totalValid = totalValid + 1
            end
        end
    end

    local processed = 0
    local cachedCount = 0

    for i = 1, total do
        name, skillType = GetTradeSkillInfo(i)
        if name and skillType ~= "header" then
            name = NormalizeRecipeName(name)
            if name and name ~= "" and not IsRecipeExcluded(professionName, name) and not IsRecipeInvalid(professionName, name) then
                local existing = GetStoredRecipeMeta(professionName, name)
                if HasStoredMetaSnapshot(existing) then
                    cachedCount = cachedCount + 1
                else
                    if processed < BULK_META_CACHE_LIMIT then
                        local ok = pcall(function()
                            SelectTradeSkill(i)

                            local preview = {
                                icon = nil,
                                title = name,
                                requires = "",
                                description = "",
                                reagents = {},
                            }

                            if GetTradeSkillItemLink and GetItemInfo then
                                local link = GetTradeSkillItemLink(i)
                                if link then
                                    local itemName, _, _, _, _, _, _, _, _, texture = GetItemInfo(link)
                                    preview.title = itemName or name
                                    preview.icon = texture
                                end
                            end

                        if GetTradeSkillDescription then
                            local desc = GetTradeSkillDescription()
                            if desc and desc ~= "" then
                                preview.description = desc
                            end
                        end
                        if preview.description == "" or string.find(preview.description, "^Creates%s+") then
                            local itemDesc = GetDescriptionFromTradeSkillItem(i)
                            if itemDesc and itemDesc ~= "" then
                                preview.description = itemDesc
                            end
                        end
                        local reqLine = GetRequiresFromTradeSkillItem(i)
                        if reqLine and reqLine ~= "" then
                            preview.requires = reqLine
                        end

                        if GetTradeSkillNumReagents then
                                local r
                                for r = 1, GetTradeSkillNumReagents(i) do
                                    local reagentName, reagentTexture, requiredCount, playerCount = GetTradeSkillReagentInfo(i, r)
                                    if reagentName then
                                        local owned = playerCount or GetOwnedCountByName(reagentName) or 0
                                        table.insert(preview.reagents, {
                                            name = reagentName,
                                            icon = reagentTexture,
                                            required = requiredCount or 0,
                                            owned = owned,
                                            text = reagentName .. " " .. tostring(owned or 0) .. "/" .. tostring(requiredCount or 0),
                                        })
                                    end
                                end
                            end

                        if table.getn(preview.reagents) > 0 then
                            if preview.requires == "" then
                                preview.requires = GetDefaultRequiresForProfession(professionName) or "Requires: Profession tools"
                            end
                        elseif professionName == "Enchanting" then
                            if preview.requires == "" then
                                preview.requires = "Requires: Runed Truesilver Rod"
                            end
                        else
                            if preview.requires == "" then
                                preview.requires = "Requires: Profession tools"
                            end
                        end

                            if preview.description == "" then
                                preview.description = "No cached recipe description available."
                            end

                            SaveStoredRecipeMeta(professionName, name, preview)
                            processed = processed + 1
                            cachedCount = cachedCount + 1
                        end)
                        if not ok then
                            DebugMessage("cache skip bad recipe slot " .. tostring(i) .. " for " .. tostring(professionName))
                        end
                    end
                end
            end
        end
    end

    if oldIndex and oldIndex >= 1 and oldIndex <= total then
        SelectTradeSkill(oldIndex)
    end
    if cachedCount >= totalValid then
        SetCacheStatus("Cache: " .. professionName .. " done (" .. cachedCount .. "/" .. totalValid .. ")")
        return true, cachedCount, totalValid
    end
    SetCacheStatus("Cache: " .. professionName .. " " .. cachedCount .. "/" .. totalValid)
    return false, cachedCount, totalValid
end

CacheCraftRecipeMeta = function(professionName)
    if not professionName or professionName == "" or not GetNumCrafts then
        return true, 0, 0
    end

    local total = GetNumCrafts()
    if not total or total <= 0 then
        return true, 0, 0
    end

    local i, name, craftType
    local totalValid = 0
    local probeName, probeType

    for i = 1, total do
        probeName, _, probeType = GetCraftInfo(i)
        if probeName and probeType ~= "header" then
            probeName = NormalizeRecipeName(probeName)
            if probeName and probeName ~= "" and not IsRecipeExcluded(professionName, probeName) and not IsRecipeInvalid(professionName, probeName) then
                totalValid = totalValid + 1
            end
        end
    end

    local processed = 0
    local cachedCount = 0
    for i = 1, total do
        name, _, craftType = GetCraftInfo(i)
        if name and craftType ~= "header" then
            name = NormalizeRecipeName(name)
            if name and name ~= "" and not IsRecipeExcluded(professionName, name) and not IsRecipeInvalid(professionName, name) then
                local existing = GetStoredRecipeMeta(professionName, name)
                if HasStoredMetaSnapshot(existing) then
                    cachedCount = cachedCount + 1
                else
                    if processed < BULK_META_CACHE_LIMIT then
                        local ok = pcall(function()
                            local preview = {
                                icon = nil,
                                title = name,
                                requires = "",
                                description = "",
                                reagents = {},
                            }

                            if GetCraftItemLink and GetItemInfo then
                                local link = GetCraftItemLink(i)
                                if link then
                                    local itemName, _, _, _, _, _, _, _, _, texture = GetItemInfo(link)
                                    preview.title = itemName or name
                                    preview.icon = texture
                                end
                            end

                            if GetCraftDescription then
                                local desc = GetCraftDescription(i)
                                if desc and desc ~= "" then
                                    preview.description = desc
                                end
                            end
                            if preview.description == "" or string.find(preview.description, "^Creates%s+") then
                                local itemDesc = GetDescriptionFromCraftItem(i)
                                if itemDesc and itemDesc ~= "" then
                                    preview.description = itemDesc
                                end
                            end
                            local reqLine = GetRequiresFromCraftItem(i)
                            if reqLine and reqLine ~= "" then
                                preview.requires = reqLine
                            end

                            if GetCraftNumReagents then
                                local r
                                for r = 1, GetCraftNumReagents(i) do
                                    local reagentName, reagentTexture, requiredCount, playerCount = GetCraftReagentInfo(i, r)
                                    if reagentName then
                                        local owned = playerCount or GetOwnedCountByName(reagentName) or 0
                                        table.insert(preview.reagents, {
                                            name = reagentName,
                                            icon = reagentTexture,
                                            required = requiredCount or 0,
                                            owned = owned,
                                            text = reagentName .. " " .. tostring(owned or 0) .. "/" .. tostring(requiredCount or 0),
                                        })
                                    end
                                end
                            end

                            if table.getn(preview.reagents) > 0 then
                                if preview.requires == "" then
                                    preview.requires = GetDefaultRequiresForProfession(professionName) or "Requires: Profession tools"
                                end
                            elseif professionName == "Enchanting" then
                                if preview.requires == "" then
                                    preview.requires = "Requires: Runed Truesilver Rod"
                                end
                            else
                                if preview.requires == "" then
                                    preview.requires = "Requires: Profession tools"
                                end
                            end

                            if preview.description == "" then
                                preview.description = "No cached recipe description available."
                            end

                            SaveStoredRecipeMeta(professionName, name, preview)
                            processed = processed + 1
                            cachedCount = cachedCount + 1
                        end)
                        if not ok then
                            DebugMessage("cache skip bad craft slot " .. tostring(i) .. " for " .. tostring(professionName))
                        end
                    end
                end
            end
        end
    end
    if cachedCount >= totalValid then
        SetCacheStatus("Cache: " .. professionName .. " done (" .. cachedCount .. "/" .. totalValid .. ")")
        return true, cachedCount, totalValid
    end
    SetCacheStatus("Cache: " .. professionName .. " " .. cachedCount .. "/" .. totalValid)
    return false, cachedCount, totalValid
end

local function GetBulkMetaJobKey(mode, professionName)
    return tostring(mode or "") .. ":" .. tostring(professionName or "")
end

StartBulkMetaCacheJob = function(mode, professionName)
    if not AUTO_BULK_META_CACHE then
        return
    end
    if not professionName or professionName == "" then
        return
    end
    local key = GetBulkMetaJobKey(mode, professionName)
    if bulkMetaCacheJobs[key] then
        return
    end
    bulkMetaCacheJobs[key] = {
        mode = mode,
        profession = professionName,
        nextRun = 0,
    }

    bulkMetaCacheTicker:SetScript("OnUpdate", function()
        local now = GetTime and GetTime() or 0
        local hasJobs = false
        local jobKey, job
        for jobKey, job in SafePairs(bulkMetaCacheJobs) do
            hasJobs = true
            if job and now >= (job.nextRun or 0) then
                local done = true
                if job.mode == "trade" and CacheTradeSkillRecipeMeta then
                    local ok, finished = pcall(CacheTradeSkillRecipeMeta, job.profession)
                    if ok then
                        done = finished and true or false
                    else
                        done = false
                        SetCacheStatus("Cache error: " .. tostring(job.profession))
                        DebugMessage("cache trade error for " .. tostring(job.profession))
                    end
                elseif job.mode == "craft" and CacheCraftRecipeMeta then
                    local ok, finished = pcall(CacheCraftRecipeMeta, job.profession)
                    if ok then
                        done = finished and true or false
                    else
                        done = false
                        SetCacheStatus("Cache error: " .. tostring(job.profession))
                        DebugMessage("cache craft error for " .. tostring(job.profession))
                    end
                end

                if done then
                    bulkMetaCacheJobs[jobKey] = nil
                else
                    job.nextRun = now + BULK_META_CACHE_INTERVAL
                end
            end
        end
        if not hasJobs then
            bulkMetaCacheTicker:SetScript("OnUpdate", nil)
        end
    end)
end

local function BuildRecipePreviewData(recipeName, professionName)
    local preview = {
        icon = nil,
        title = recipeName or "",
        requires = "",
        description = "",
        itemLink = nil,
        isEquippable = nil,
        reagents = {},
    }

    if not recipeName or recipeName == "" then
        return preview
    end

    local link = GetSelectedRecipeLink(recipeName, professionName)
    local itemName, itemLink, _, _, _, _, _, _, equipLoc, texture
    local itemID = link and tonumber(MatchCapture(link, "item:(%d+)")) or nil
    local lookupName = NormalizeRecipeLookupName(recipeName)

    if (not itemID) and professionName and professionName ~= "Enchanting" then
        local spellItemID = GetSafeLibItemIDBySpell(professionName, recipeName)
        if spellItemID and spellItemID > 0 then
            itemID = spellItemID
            link = BuildItemHyperlinkFromID(itemID, recipeName) or link
        end
    end

    if (not itemID) and professionName and professionName ~= "Enchanting" then
        local safeItemID = GetSafeLibItemID(lookupName)
        if safeItemID and safeItemID > 0 then
            itemID = safeItemID
            link = BuildItemHyperlinkFromID(itemID, recipeName) or link
        end
    end

    if itemID and GetItemInfo then
        itemName, itemLink, _, _, _, _, _, _, equipLoc, texture = GetItemInfo(itemID)
    elseif GetItemInfo then
        itemName, itemLink, _, _, _, _, _, _, equipLoc, texture = GetItemInfo(recipeName)
    end

    preview.title = itemName or recipeName
    preview.icon = texture
    preview.itemLink = NormalizeToItemHyperlink(itemLink or link, preview.title)
    preview.isEquippable = (equipLoc and equipLoc ~= "") and true or false
    if (not preview.itemLink or preview.itemLink == "") and itemID then
        preview.itemLink = BuildItemHyperlinkFromID(itemID, preview.title or recipeName)
    end
    if (not preview.icon or preview.icon == "") and preview.title and GetItemInfo then
        local _, fallbackLink, _, _, _, _, _, _, fallbackEquipLoc, fallbackTexture = GetItemInfo(preview.title)
        if fallbackTexture and fallbackTexture ~= "" then
            preview.icon = fallbackTexture
        end
        if fallbackEquipLoc and fallbackEquipLoc ~= "" then
            preview.isEquippable = true
        end
        if not preview.itemLink and fallbackLink and fallbackLink ~= "" then
            preview.itemLink = NormalizeToItemHyperlink(fallbackLink, preview.title)
        end
    end

    local storedMeta = GetStoredRecipeMeta(professionName, recipeName)
    if storedMeta then
        if (not preview.icon or preview.icon == "") and storedMeta.icon then
            preview.icon = storedMeta.icon
        end
        if storedMeta.title and storedMeta.title ~= "" then
            preview.title = storedMeta.title
        end
        if (not preview.itemLink or preview.itemLink == "") and storedMeta.itemLink and storedMeta.itemLink ~= "" then
            preview.itemLink = storedMeta.itemLink
        end
        if storedMeta.requires and storedMeta.requires ~= "" then
            preview.requires = storedMeta.requires
        end
        if storedMeta.description and storedMeta.description ~= "" then
            preview.description = storedMeta.description
        end

        local i
        for i = 1, table.getn(storedMeta.reagents or {}) do
            local r = storedMeta.reagents[i]
            if r and r.name and r.name ~= "" then
                local owned = GetOwnedCountByName(r.name)
                table.insert(preview.reagents, {
                    name = r.name,
                    icon = r.icon,
                    required = r.required or 0,
                    owned = owned,
                    text = r.name .. " " .. tostring(owned or 0) .. "/" .. tostring(r.required or 0),
                })
            end
        end
    end

    local mode, recipeIndex = FindRecipeInOpenCraftWindow(recipeName, professionName)
    local liveCapture = false
    if mode == "trade" and recipeIndex then
        liveCapture = true
        preview.reagents = {}
        local oldIndex = GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex() or nil
        SelectTradeSkill(recipeIndex)

        if (not preview.icon or preview.icon == "") and GetTradeSkillIcon then
            local liveIcon = GetTradeSkillIcon(recipeIndex)
            if liveIcon and liveIcon ~= "" then
                preview.icon = liveIcon
            end
        end

        if GetTradeSkillItemLink then
            local liveItemLink = GetTradeSkillItemLink(recipeIndex)
            local normalizedLiveLink = NormalizeToItemHyperlink(liveItemLink, preview.title)
            if normalizedLiveLink then
                preview.itemLink = normalizedLiveLink
                if GetItemInfo then
                    local liveID = tonumber(MatchCapture(normalizedLiveLink, "item:(%d+)"))
                    if liveID then
                        local liveName, _, _, _, _, _, _, _, _, liveTexture = GetItemInfo(liveID)
                        if liveName and liveName ~= "" then
                            preview.title = liveName
                        end
                        if liveTexture and liveTexture ~= "" then
                            preview.icon = liveTexture
                        end
                    end
                end
            end
        end

        if GetTradeSkillDescription then
            local desc = GetTradeSkillDescription()
            if desc and desc ~= "" then
                preview.description = desc
            end
        end
        local reqLine = GetRequiresFromTradeSkillItem(recipeIndex)
        if reqLine and reqLine ~= "" then
            preview.requires = reqLine
        end
        if preview.description == "" or preview.description == "No cached recipe description available." or string.find(preview.description, "^Creates%s+") then
            local itemDesc = GetDescriptionFromTradeSkillItem(recipeIndex)
            if itemDesc and itemDesc ~= "" then
                preview.description = itemDesc
            end
        end

        if GetTradeSkillNumReagents then
            local r
            for r = 1, GetTradeSkillNumReagents(recipeIndex) do
                local reagentName, reagentTexture, requiredCount, playerCount = GetTradeSkillReagentInfo(recipeIndex, r)
                if reagentName then
                    local owned = playerCount or GetOwnedCountByName(reagentName) or 0
                    table.insert(preview.reagents, {
                        name = reagentName,
                        icon = reagentTexture,
                        text = reagentName .. " " .. tostring(owned or 0) .. "/" .. tostring(requiredCount or 0),
                        owned = owned,
                        required = requiredCount or 0,
                    })
                end
            end
        end

        if oldIndex and oldIndex ~= recipeIndex then
            SelectTradeSkill(oldIndex)
        end
    elseif mode == "craft" and recipeIndex then
        liveCapture = true
        preview.reagents = {}
        if (not preview.icon or preview.icon == "") and GetCraftIcon then
            local liveIcon = GetCraftIcon(recipeIndex)
            if liveIcon and liveIcon ~= "" then
                preview.icon = liveIcon
            end
        end
        if GetCraftItemLink then
            local liveItemLink = GetCraftItemLink(recipeIndex)
            local normalizedLiveLink = NormalizeToItemHyperlink(liveItemLink, preview.title)
            if normalizedLiveLink then
                preview.itemLink = normalizedLiveLink
                if GetItemInfo then
                    local liveID = tonumber(MatchCapture(normalizedLiveLink, "item:(%d+)"))
                    if liveID then
                        local liveName, _, _, _, _, _, _, _, _, liveTexture = GetItemInfo(liveID)
                        if liveName and liveName ~= "" then
                            preview.title = liveName
                        end
                        if liveTexture and liveTexture ~= "" then
                            preview.icon = liveTexture
                        end
                    end
                end
            end
        end
        if GetCraftDescription then
            local desc = GetCraftDescription(recipeIndex)
            if desc and desc ~= "" then
                preview.description = desc
            end
        end
        local reqLine = GetRequiresFromCraftItem(recipeIndex)
        if reqLine and reqLine ~= "" then
            preview.requires = reqLine
        end
        if preview.description == "" or preview.description == "No cached recipe description available." or string.find(preview.description, "^Creates%s+") then
            local itemDesc = GetDescriptionFromCraftItem(recipeIndex)
            if itemDesc and itemDesc ~= "" then
                preview.description = itemDesc
            end
        end

        if GetCraftNumReagents then
            local r
            for r = 1, GetCraftNumReagents(recipeIndex) do
                local reagentName, reagentTexture, requiredCount, playerCount = GetCraftReagentInfo(recipeIndex, r)
                if reagentName then
                    local owned = playerCount or GetOwnedCountByName(reagentName) or 0
                    table.insert(preview.reagents, {
                        name = reagentName,
                        icon = reagentTexture,
                        text = reagentName .. " " .. tostring(owned or 0) .. "/" .. tostring(requiredCount or 0),
                        owned = owned,
                        required = requiredCount or 0,
                    })
                end
            end
        end
    end

    if table.getn(preview.reagents) > 0 then
        local hasRod = false
        local r
        for r = 1, table.getn(preview.reagents) do
            local line = preview.reagents[r].text or ""
            if string.find(SafeLower(line), "rod", 1, true) then
                hasRod = true
                break
            end
        end
        if hasRod then
            preview.requires = "Requires: Runed Truesilver Rod"
        else
            preview.requires = GetDefaultRequiresForProfession(professionName) or "Requires: Profession tools"
        end
    elseif professionName == "Enchanting" then
        preview.requires = "Requires: Runed Truesilver Rod"
    else
        preview.requires = GetDefaultRequiresForProfession(professionName) or "Requires: Profession tools"
    end

    local suppressGreenDescription = ShouldSuppressGreenDescription(recipeName, professionName, preview.itemLink, nil)
    if professionName and professionName ~= "Enchanting" then
        local function BuildPreferredNonEnchantCandidates()
            local candidates = {}
            local seen = {}
            local function AddCandidate(linkValue, label)
                local normalized = NormalizeToItemHyperlink(linkValue, label or (preview.title or recipeName))
                if normalized and normalized ~= "" and not seen[normalized] then
                    seen[normalized] = true
                    table.insert(candidates, normalized)
                end
            end

            local lookupName = NormalizeRecipeLookupName(recipeName)
            AddCandidate(preview.itemLink)
            AddCandidate(GetSelectedRecipeLink(recipeName, professionName), recipeName)
            AddCandidate(ResolveRecipeItemLink(recipeName, professionName), recipeName)
            local spellItemID = GetSafeLibItemIDBySpell(professionName, recipeName)
            if spellItemID then
                AddCandidate(spellItemID, recipeName)
            end
            if lookupName and lookupName ~= "" then
                local safeID = GetSafeLibItemID(lookupName)
                if safeID then
                    AddCandidate(safeID, recipeName)
                end
            end
            if GetItemInfo then
                local _, linkFromTitle = GetItemInfo(preview.title or recipeName)
                if linkFromTitle and linkFromTitle ~= "" then
                    AddCandidate(linkFromTitle, preview.title or recipeName)
                end
                local _, linkFromRecipe = GetItemInfo(recipeName)
                if linkFromRecipe and linkFromRecipe ~= "" then
                    AddCandidate(linkFromRecipe, recipeName)
                end
            end
            return candidates
        end

        local function GetPreferredNonEnchantDescription()
            local bestAny = nil
            local candidates = BuildPreferredNonEnchantCandidates()
            local i
            for i = 1, table.getn(candidates) do
                local candidate = candidates[i]
                if candidate and candidate ~= "" then
                    local useText = GetItemUseEffectFromTooltip(candidate)
                    if useText and useText ~= "" then
                        if (not preview.itemLink or preview.itemLink == "") then
                            preview.itemLink = candidate
                        end
                        return useText
                    end
                    local text = GetItemDescriptionFromTooltip(candidate)
                    if text and text ~= "" then
                        if (not preview.itemLink or preview.itemLink == "") then
                            preview.itemLink = candidate
                        end
                        if not bestAny then
                            bestAny = text
                        end
                        if not string.find(text, "^Creates%s+") then
                            return text
                        end
                    end
                end
            end
            return bestAny
        end

        local preferredText = GetPreferredNonEnchantDescription()
        if (not suppressGreenDescription) and preferredText and preferredText ~= "" then
            preview.description = preferredText
        elseif preview.description == "" or preview.description == "No cached recipe description available." or string.find(preview.description, "^Creates%s+") then
            if preview.isEquippable and preview.title and preview.title ~= "" then
                preview.description = "Creates " .. preview.title .. "."
            else
                preview.description = "No cached recipe description available."
            end
        end
    elseif preview.description == "" or preview.description == "No cached recipe description available." or string.find(preview.description, "^Creates%s+") then
        preview.description = "No cached recipe description available."
    end
    if suppressGreenDescription or ShouldHidePreviewGreenText(recipeName, professionName, preview.description, preview.itemLink, nil) then
        preview.description = ""
    end

    -- Icon fallback chain: try itemLink itemID again, then use a stable placeholder.
    if (not preview.icon or preview.icon == "") and preview.itemLink and GetItemInfo then
        local linkItemID = tonumber(MatchCapture(preview.itemLink, "item:(%d+)"))
        if linkItemID and linkItemID > 0 then
            local _, _, _, _, _, _, _, _, _, linkTexture = GetItemInfo(linkItemID)
            if linkTexture and linkTexture ~= "" then
                preview.icon = linkTexture
            end
        end
    end
    if not preview.icon or preview.icon == "" then
        preview.icon = "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    if liveCapture or (table.getn(preview.reagents or {}) > 0) then
        SaveStoredRecipeMeta(professionName, recipeName, preview)
    end

    return preview
end
local function StopPreviewResolveTicker()
    pendingPreviewResolve = nil
    previewResolveTicker:SetScript("OnUpdate", nil)
end
local function SchedulePreviewResolve(recipeName, professionName)
    if not recipeName or recipeName == "" then
        return
    end
    if not professionName or professionName == "Enchanting" then
        return
    end

    if pendingPreviewResolve
        and pendingPreviewResolve.recipe == recipeName
        and pendingPreviewResolve.profession == professionName then
        return
    end

    pendingPreviewResolve = {
        recipe = recipeName,
        profession = professionName,
        attempts = 0,
        nextTime = GetTime() + PREVIEW_RESOLVE_INTERVAL,
    }

    previewResolveTicker:SetScript("OnUpdate", function()
        if not pendingPreviewResolve then
            previewResolveTicker:SetScript("OnUpdate", nil)
            return
        end
        if GetTime() < (pendingPreviewResolve.nextTime or 0) then
            return
        end
        if not uiFrame or not uiFrame:IsShown() or not selectedRecipeData then
            StopPreviewResolveTicker()
            return
        end
        if selectedRecipeData.recipe ~= pendingPreviewResolve.recipe
            or selectedRecipeData.profession ~= pendingPreviewResolve.profession then
            StopPreviewResolveTicker()
            return
        end

        pendingPreviewResolve.attempts = (pendingPreviewResolve.attempts or 0) + 1
        local preview = BuildRecipePreviewData(pendingPreviewResolve.recipe, pendingPreviewResolve.profession)
        local desc = preview.description or ""
        local unresolved = (desc == "")
            or (desc == "No cached recipe description available.")
            or (string.find(desc, "^Creates%s+") ~= nil)

        if not unresolved then
            StopPreviewResolveTicker()
            uiFrame:UpdatePreviewPanel()
            return
        end

        if pendingPreviewResolve.attempts >= PREVIEW_RESOLVE_MAX_ATTEMPTS then
            StopPreviewResolveTicker()
            return
        end

        pendingPreviewResolve.nextTime = GetTime() + PREVIEW_RESOLVE_INTERVAL
    end)
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
            end
        end
    end)
end
local function ToggleCollapseVisibleCategories()
    if not selectedProfession or not uiDisplayRows then
        return
    end
    local collapsed = GetUICollapsedTable()
    local hasHeader = false
    local hasExpanded = false
    local i, data
    for i = 1, table.getn(uiDisplayRows) do
        data = uiDisplayRows[i]
        if data and data.rowType == "groupHeader" and data.profession == selectedProfession and data.collapseKey and data.collapseKey ~= "" then
            hasHeader = true
            if not IsCategoryCollapsed(selectedProfession, data.title) then
                hasExpanded = true
            end
        end
    end
    if not hasHeader then
        return
    end

    local targetCollapsed = true
    if not hasExpanded then
        targetCollapsed = false
    end

    for i = 1, table.getn(uiDisplayRows) do
        data = uiDisplayRows[i]
        if data and data.rowType == "groupHeader" and data.profession == selectedProfession and data.collapseKey and data.collapseKey ~= "" then
            collapsed[data.collapseKey] = targetCollapsed
        end
    end
    RefreshUI()
end
local function CreateUI()
    if uiFrame then
        return
    end
    local f = CreateFrame("Frame", "GuildCraftDB_MainFrame", UIParent)
    f:SetWidth(640)
    f:SetHeight(606)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    f:SetBackdropColor(0, 0, 0, 0.98)
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
    if UISpecialFrames then
        local found = false
        local i
        for i = 1, table.getn(UISpecialFrames) do
            if UISpecialFrames[i] == "GuildCraftDB_MainFrame" then
                found = true
                break
            end
        end
        if not found then
            table.insert(UISpecialFrames, "GuildCraftDB_MainFrame")
        end
    end
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
    searchBox:SetWidth(380)
    searchBox:SetHeight(20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEnterPressed", function()
        RefreshUI()
        searchBox:ClearFocus()
    end)
    f.searchBox = searchBox
    local searchButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    searchButton:SetWidth(60)
    searchButton:SetHeight(22)
    searchButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -124, -34)
    searchButton:SetText("Search")
    searchButton:SetScript("OnClick", function()
        RefreshUI()
    end)
    local clearButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearButton:SetWidth(50)
    clearButton:SetHeight(22)
    clearButton:SetPoint("LEFT", searchButton, "RIGHT", 8, 0)
    clearButton:SetText("Clear")
    clearButton:SetScript("OnClick", function()
        searchBox:SetText("")
        RefreshUI()
    end)
    local refreshButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    refreshButton:SetWidth(65)
    refreshButton:SetHeight(22)
    refreshButton:SetPoint("TOPLEFT", searchButton, "BOTTOMLEFT", 0, -4)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", function()
        RequestGuildRosterRefresh()
    end)
    f.refreshButton = refreshButton
    local collapseButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    collapseButton:SetWidth(70)
    collapseButton:SetHeight(22)
    collapseButton:SetPoint("LEFT", refreshButton, "RIGHT", 8, 0)
    collapseButton:SetText("Collapse")
    collapseButton:SetScript("OnClick", function()
        ToggleCollapseVisibleCategories()
    end)
    f.collapseButton = collapseButton
    local syncStatusText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    syncStatusText:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -86)
    syncStatusText:SetText(syncStatusTextValue)
    syncStatusText:SetWidth(600)
    syncStatusText:SetJustifyH("LEFT")
    f.syncStatusText = syncStatusText

    local professionPanel = CreateFrame("Frame", nil, f)
    professionPanel:SetWidth(155)
    professionPanel:SetHeight(208)
    professionPanel:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -110)
    professionPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    professionPanel:SetBackdropColor(0, 0, 0, 0.98)

    local professionTitle = professionPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    professionTitle:SetPoint("TOPLEFT", professionPanel, "TOPLEFT", 8, -8)
    professionTitle:SetText("Professions")

    local professionContent = CreateFrame("Frame", nil, professionPanel)
    professionContent:SetWidth(147)
    professionContent:SetHeight(178)
    professionContent:SetPoint("TOPLEFT", professionPanel, "TOPLEFT", 4, -24)

    local recipePanel = CreateFrame("Frame", nil, f)
    recipePanel:SetWidth(435)
    recipePanel:SetHeight(260)
    recipePanel:SetPoint("TOPLEFT", professionPanel, "TOPRIGHT", 10, 0)
    recipePanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    recipePanel:SetBackdropColor(0, 0, 0, 0.98)

    local recipeTitle = recipePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    recipeTitle:SetPoint("TOPLEFT", recipePanel, "TOPLEFT", 8, -8)
    recipeTitle:SetText("Recipes")
    f.recipeTitle = recipeTitle

    local scrollFrame = CreateFrame("ScrollFrame", "GuildCraftDB_ScrollFrame", recipePanel, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", recipePanel, "TOPLEFT", 4, -24)
    scrollFrame:SetPoint("BOTTOMRIGHT", recipePanel, "BOTTOMRIGHT", -30, 6)
    scrollFrame:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(RECIPE_ROW_HEIGHT, RefreshUI)
    end)
    f.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, recipePanel)
    content:SetWidth(405)
    content:SetHeight(225)
    content:SetPoint("TOPLEFT", recipePanel, "TOPLEFT", 8, -26)
    f.content = content

    local crafterPanel = CreateFrame("Frame", nil, f)
    crafterPanel:SetWidth(155)
    crafterPanel:SetHeight(257)
    crafterPanel:SetPoint("TOPLEFT", professionPanel, "BOTTOMLEFT", 0, -6)
    crafterPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    crafterPanel:SetBackdropColor(0, 0, 0, 0.98)
    f.crafterPanel = crafterPanel

    local previewPanel = CreateFrame("Frame", nil, f)
    previewPanel:SetWidth(435)
    previewPanel:SetHeight(205)
    previewPanel:SetPoint("TOPLEFT", recipePanel, "BOTTOMLEFT", 0, -6)
    previewPanel:EnableMouse(true)
    previewPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    previewPanel:SetBackdropColor(0, 0, 0, 0.98)
    f.previewPanel = previewPanel

    local crafterTitle = crafterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    crafterTitle:SetPoint("TOPLEFT", crafterPanel, "TOPLEFT", 8, -8)
    crafterTitle:SetWidth(140)
    crafterTitle:SetJustifyH("LEFT")
    crafterTitle:SetText("")
    f.crafterTitle = crafterTitle

    local crafterCacheStatus = crafterPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    crafterCacheStatus:SetPoint("TOPLEFT", crafterPanel, "TOPLEFT", 8, -8)
    crafterCacheStatus:SetWidth(140)
    crafterCacheStatus:SetJustifyH("LEFT")
    crafterCacheStatus:SetText(cacheStatusTextValue)
    f.crafterCacheStatus = crafterCacheStatus

    local crafterOnlineLabel = crafterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    crafterOnlineLabel:SetPoint("TOPLEFT", crafterPanel, "TOPLEFT", 8, -28)
    crafterOnlineLabel:SetText("Online Crafters")

    local crafterOfflineLabel = crafterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    crafterOfflineLabel:SetPoint("TOPLEFT", crafterPanel, "TOPLEFT", 8, -128)
    crafterOfflineLabel:SetText("Offline Crafters")

    local previewIcon = previewPanel:CreateTexture(nil, "ARTWORK")
    previewIcon:SetWidth(32)
    previewIcon:SetHeight(32)
    previewIcon:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", 8, -8)
    f.previewIcon = previewIcon

    local previewName = previewPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    previewName:SetPoint("TOPLEFT", previewIcon, "TOPRIGHT", 8, -2)
    previewName:SetWidth(380)
    previewName:SetJustifyH("LEFT")
    previewName:SetText("Select a recipe")
    f.previewName = previewName

    local previewRequires = previewPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewRequires:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", 8, -44)
    previewRequires:SetWidth(410)
    previewRequires:SetJustifyH("LEFT")
    previewRequires:SetText("")
    f.previewRequires = previewRequires

    local previewDescription = previewPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewDescription:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", 8, -58)
    previewDescription:SetWidth(410)
    previewDescription:SetJustifyH("LEFT")
    previewDescription:SetTextColor(0.25, 1.0, 0.25)
    previewDescription:SetText("")
    f.previewDescription = previewDescription

    local function ShowPreviewItemTooltip(owner)
        if not uiFrame or not selectedRecipeData or not selectedRecipeData.recipe or not selectedRecipeData.profession then
            return
        end

        local recipeName = selectedRecipeData.recipe
        local professionName = selectedRecipeData.profession
        local suppressGreenDescription = ShouldSuppressGreenDescription(recipeName, professionName, uiFrame and uiFrame.previewItemLink or nil, selectedRecipeData and selectedRecipeData.category or nil)

        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")

        if professionName ~= "Enchanting" then
            local safeItemLink = GetSafeLibItemLink(professionName, recipeName)
            if safeItemLink and safeItemLink ~= "" then
                local okSafe = pcall(function()
                    GameTooltip:SetHyperlink(safeItemLink)
                end)
                if okSafe then
                    if professionName ~= "Enchanting" and not suppressGreenDescription and uiFrame and uiFrame.previewDescription then
                        local fromHover = GetPreferredDescriptionFromTooltipFrame(GameTooltip)
                        if fromHover and fromHover ~= "" and not string.find(fromHover, "^Creates%s+") then
                            uiFrame.previewDescription:SetText(fromHover)
                            uiFrame.previewDescription:SetTextColor(0.25, 1.0, 0.25)
                            if selectedRecipeData and selectedRecipeData.recipe and selectedRecipeData.profession then
                                local persistPreview = BuildRecipePreviewData(selectedRecipeData.recipe, selectedRecipeData.profession)
                                persistPreview.description = fromHover
                                SaveStoredRecipeMeta(selectedRecipeData.profession, selectedRecipeData.recipe, persistPreview)
                            end
                        end
                    end
                    return
                end
            end

            local resolvedItemLink = ResolveRecipeItemLink(recipeName, professionName)
            if resolvedItemLink and resolvedItemLink ~= "" then
                local okResolved = pcall(function()
                    GameTooltip:SetHyperlink(resolvedItemLink)
                end)
                if okResolved then
                    if professionName ~= "Enchanting" and not suppressGreenDescription and uiFrame and uiFrame.previewDescription then
                        local fromHover = GetPreferredDescriptionFromTooltipFrame(GameTooltip)
                        if fromHover and fromHover ~= "" and not string.find(fromHover, "^Creates%s+") then
                            uiFrame.previewDescription:SetText(fromHover)
                            uiFrame.previewDescription:SetTextColor(0.25, 1.0, 0.25)
                            if selectedRecipeData and selectedRecipeData.recipe and selectedRecipeData.profession then
                                local persistPreview = BuildRecipePreviewData(selectedRecipeData.recipe, selectedRecipeData.profession)
                                persistPreview.description = fromHover
                                SaveStoredRecipeMeta(selectedRecipeData.profession, selectedRecipeData.recipe, persistPreview)
                            end
                        end
                    end
                    return
                end
            end
        end

        local link = uiFrame.previewItemLink
        if (not link or link == "") then
            link = GetSelectedRecipeLink(recipeName, professionName)
            uiFrame.previewItemLink = link
        end
        if link and link ~= "" then
            local ok = pcall(function()
                GameTooltip:SetHyperlink(link)
            end)
            if ok then
                if professionName ~= "Enchanting" and not suppressGreenDescription and uiFrame and uiFrame.previewDescription then
                    local fromHover = GetPreferredDescriptionFromTooltipFrame(GameTooltip)
                    if fromHover and fromHover ~= "" and not string.find(fromHover, "^Creates%s+") then
                        uiFrame.previewDescription:SetText(fromHover)
                        uiFrame.previewDescription:SetTextColor(0.25, 1.0, 0.25)
                        if selectedRecipeData and selectedRecipeData.recipe and selectedRecipeData.profession then
                            local persistPreview = BuildRecipePreviewData(selectedRecipeData.recipe, selectedRecipeData.profession)
                            persistPreview.description = fromHover
                            SaveStoredRecipeMeta(selectedRecipeData.profession, selectedRecipeData.recipe, persistPreview)
                        end
                    end
                end
                return
            end
        end
        GameTooltip:ClearLines()
        GameTooltip:AddLine(recipeName, 1.0, 0.82, 0.0)
        GameTooltip:AddLine(professionName, 0.6, 0.8, 1.0)
        GameTooltip:Show()
    end
    local function IsCursorOverFrame(frameObj)
        if not frameObj or not frameObj:IsShown() then
            return false
        end
        if MouseIsOver and MouseIsOver(frameObj) then
            return true
        end
        local left = frameObj:GetLeft()
        local right = frameObj:GetRight()
        local top = frameObj:GetTop()
        local bottom = frameObj:GetBottom()
        if not left or not right or not top or not bottom then
            return false
        end
        local x, y = GetCursorPosition()
        local scale = UIParent:GetScale()
        x = x / scale
        y = y / scale
        return x >= left and x <= right and y >= bottom and y <= top
    end

    local previewIconHit = CreateFrame("Button", nil, previewPanel)
    previewIconHit:SetWidth(32)
    previewIconHit:SetHeight(32)
    previewIconHit:SetPoint("TOPLEFT", previewIcon, "TOPLEFT", 0, 0)
    previewIconHit:SetPoint("BOTTOMRIGHT", previewIcon, "BOTTOMRIGHT", 0, 0)
    previewIconHit:EnableMouse(true)
    previewIconHit:SetFrameStrata("TOOLTIP")
    previewIconHit:SetFrameLevel(previewPanel:GetFrameLevel() + 8)
    previewIconHit:SetScript("OnEnter", function()
        ShowPreviewItemTooltip(previewIconHit)
    end)
    previewIconHit:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    previewIconHit:Show()
    f.previewIconHit = previewIconHit

    local previewNameHit = CreateFrame("Button", nil, previewPanel)
    previewNameHit:SetWidth(360)
    previewNameHit:SetHeight(24)
    previewNameHit:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", 44, -8)
    previewNameHit:EnableMouse(true)
    previewNameHit:SetFrameStrata("TOOLTIP")
    previewNameHit:SetFrameLevel(previewPanel:GetFrameLevel() + 8)
    previewNameHit:SetScript("OnEnter", function()
        ShowPreviewItemTooltip(previewNameHit)
    end)
    previewNameHit:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    previewNameHit:Show()
    f.previewNameHit = previewNameHit

    local previewTopHover = CreateFrame("Button", nil, previewPanel)
    previewTopHover:SetWidth(410)
    previewTopHover:SetHeight(34)
    previewTopHover:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", 8, -8)
    previewTopHover:EnableMouse(true)
    previewTopHover:SetFrameStrata("TOOLTIP")
    previewTopHover:SetFrameLevel(previewPanel:GetFrameLevel() + 10)
    previewTopHover:SetScript("OnEnter", function()
        if uiFrame then
            uiFrame.previewHoverTarget = previewTopHover
        end
        ShowPreviewItemTooltip(previewTopHover)
    end)
    previewTopHover:SetScript("OnLeave", function()
        if uiFrame then
            uiFrame.previewHoverTarget = nil
        end
        GameTooltip:Hide()
    end)
    previewTopHover:Show()
    f.previewTopHover = previewTopHover
    f.previewHoverTarget = nil
    previewPanel:SetScript("OnUpdate", nil)

    local previewReagentsLabel = previewPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewReagentsLabel:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", 8, -104)
    previewReagentsLabel:SetText("Reagents:")
    f.previewReagentsLabel = previewReagentsLabel

    local i
    for i = 1, 16 do
        uiProfessionRows[i] = CreateProfessionRow(professionContent, i)
    end

    for i = 1, 11 do
        uiRows[i] = CreateRecipeRow(content, i)
    end

    local emptyText = recipePanel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", recipePanel, "CENTER", 0, 0)
    emptyText:SetText("No matching recipes.")
    f.emptyText = emptyText
    emptyText:Hide()

    f.UpdateCrafterPanel = function()
        local panel = f.crafterPanel
        local maxWidth = 142
        local buttonIndex = 1
        local x, y

        local function placeCrafterList(nameList, startY)
            local c, name
            x = 8
            y = startY

            if not nameList or table.getn(nameList) == 0 then
                local b = AcquireCrafterButton(panel, buttonIndex)
                b.playerName = nil
                b.text:SetText("None")
                b.text:SetTextColor(0.7, 0.7, 0.7)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
                b:SetWidth(b.text:GetStringWidth() + 2)
                b:Show()
                buttonIndex = buttonIndex + 1
                return
            end

            for c = 1, table.getn(nameList) do
                name = nameList[c]
                local shortName = GetShortName(name)
                local display = shortName
                if c < table.getn(nameList) then
                    display = display .. ", "
                end

                local b = AcquireCrafterButton(panel, buttonIndex)
                b.playerName = name
                b.text:SetText(display)

                local classToken = GetPlayerClassToken(name)
                if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
                    local color = RAID_CLASS_COLORS[classToken]
                    b.text:SetTextColor(color.r, color.g, color.b)
                else
                    b.text:SetTextColor(1.0, 1.0, 1.0)
                end

                local width = b.text:GetStringWidth() + 2
                if x + width > maxWidth then
                    x = 8
                    y = y - 14
                end

                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
                b:SetWidth(width)
                b:Show()

                x = x + width
                buttonIndex = buttonIndex + 1
            end
        end

        local k
        for k = 1, table.getn(uiCrafterButtons) do
            uiCrafterButtons[k]:Hide()
        end

        if not selectedRecipeData then
            f.crafterTitle:SetText("")
            placeCrafterList(nil, -44)
            placeCrafterList(nil, -144)
            return
        end

        f.crafterTitle:SetText("")

        local online = {}
        local offline = {}
        local c, crafterName
        if selectedRecipeData.rawCrafters then
            for c = 1, table.getn(selectedRecipeData.rawCrafters) do
                crafterName = selectedRecipeData.rawCrafters[c]
                if IsPlayerOnline(crafterName) then
                    table.insert(online, crafterName)
                else
                    table.insert(offline, crafterName)
                end
            end
        end

        placeCrafterList(online, -44)
        placeCrafterList(offline, -144)
    end

    f.UpdatePreviewPanel = function()
        local panel = f.previewPanel
        local i

        if not selectedRecipeData then
            StopPreviewResolveTicker()
            if f.previewIcon then
                f.previewIcon:SetTexture(nil)
            end
            if f.previewIconHit then
                f.previewIconHit:Hide()
            end
            if f.previewNameHit then
                f.previewNameHit:Hide()
            end
            if f.previewTopHover then
                f.previewTopHover:Hide()
            end
            f.previewHoverTarget = nil
            GameTooltip:Hide()
            f.previewItemLink = nil
            f.previewName:SetText("Select a recipe")
            f.previewRequires:SetText("")
            f.previewDescription:SetText("")
            f.previewDescription:SetTextColor(0.6, 0.6, 0.6)

            if f.previewReagentRows then
                for i = 1, table.getn(f.previewReagentRows) do
                    f.previewReagentRows[i]:Hide()
                end
            end
            return
        end

        local preview = BuildRecipePreviewData(selectedRecipeData.recipe, selectedRecipeData.profession)
        local suppressGreenDescription = ShouldSuppressGreenDescription(selectedRecipeData.recipe, selectedRecipeData.profession, preview.itemLink, selectedRecipeData.category)
        local unresolvedDesc = (selectedRecipeData.profession ~= "Enchanting" and not suppressGreenDescription)
            and ((preview.description or "") == ""
                or (preview.description or "") == "No cached recipe description available."
                or string.find((preview.description or ""), "^Creates%s+") ~= nil)
        if unresolvedDesc then
            SchedulePreviewResolve(selectedRecipeData.recipe, selectedRecipeData.profession)
        else
            StopPreviewResolveTicker()
        end
        f.previewName:SetText(preview.title or selectedRecipeData.recipe)
        f.previewRequires:SetText(preview.requires or "")
        local descText = preview.description or ""
        local didResolveDescription = false
        if selectedRecipeData.profession ~= "Enchanting" and not suppressGreenDescription then
            local hoverDerivedText, hoverDerivedLink = GetPreferredDescriptionForRecipe(selectedRecipeData.recipe, selectedRecipeData.profession, preview.itemLink)
            if hoverDerivedText and hoverDerivedText ~= "" then
                descText = hoverDerivedText
                preview.description = hoverDerivedText
                preview.itemLink = hoverDerivedLink or preview.itemLink
                didResolveDescription = true
            end
        end
        if didResolveDescription then
            SaveStoredRecipeMeta(selectedRecipeData.profession, selectedRecipeData.recipe, preview)
        end
        if ShouldHidePreviewGreenText(selectedRecipeData.recipe, selectedRecipeData.profession, descText, preview.itemLink, selectedRecipeData.category) then
            descText = ""
            preview.description = ""
        end
        f.previewDescription:SetText(descText)
        f.previewItemLink = preview.itemLink
        if descText == "" or descText == "No cached recipe description available." then
            f.previewDescription:SetTextColor(0.6, 0.6, 0.6)
        else
            f.previewDescription:SetTextColor(0.25, 1.0, 0.25)
        end
        if f.previewIcon then
            f.previewIcon:SetTexture(preview.icon)
        end
        if f.previewIconHit then
            if preview.icon and preview.icon ~= "" then
                f.previewIconHit:Show()
            else
                f.previewIconHit:Hide()
            end
        end
        if f.previewNameHit then
            f.previewNameHit:Show()
        end
        if f.previewTopHover then
            f.previewTopHover:Show()
        end

        local descHeight = f.previewDescription:GetHeight() or 0
        if descHeight < 12 then
            descHeight = 12
        end
        local reagentsLabelY = -62 - descHeight
        if reagentsLabelY > -98 then
            reagentsLabelY = -98
        end
        if f.previewReagentsLabel then
            f.previewReagentsLabel:ClearAllPoints()
            f.previewReagentsLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, reagentsLabelY)
        end

        local rowStartY = reagentsLabelY - 16
        if f.previewReagentRows then
            for i = 1, table.getn(f.previewReagentRows) do
                f.previewReagentRows[i]:Hide()
            end
        end

        local total = table.getn(preview.reagents)
        local leftCount = math.ceil(total / 2)
        local col1X = 8
        local col2X = 222

        for i = 1, total do
            local reagent = preview.reagents[i]
            local row = AcquirePreviewReagentRow(panel, i)
            local colX = col1X
            local rowIndex = i
            if i > leftCount then
                colX = col2X
                rowIndex = i - leftCount
            end

            local rowY = rowStartY - ((rowIndex - 1) * 18)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", colX, rowY)
            row.icon:SetTexture(reagent.icon)
            row.text:SetText(reagent.text)
            if reagent.owned and reagent.required and reagent.owned >= reagent.required then
                row.text:SetTextColor(0.2, 1.0, 0.2)
            else
                row.text:SetTextColor(1.0, 0.2, 0.2)
            end
            row:Show()
        end
    end

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
        SetSyncStatus("Sync: idle")
        UpdateWindowTitle()
        CreateMinimapButton()
        if IsInGuild() then
            SendGuildHello()
            ScheduleGuildHello(8)
        end
    elseif event == "TRADE_SKILL_SHOW" then
        ScanTradeSkill(false)
        ScheduleTradeSkillRescan(0.75)
        if IsInGuild() then
            ScheduleGuildHello(2)
        end
        if uiFrame and uiFrame:IsShown() then
            UpdateWindowTitle()
            RefreshUI()
        end
    elseif event == "TRADE_SKILL_UPDATE" then
        ScanTradeSkill(false)
        if uiFrame and uiFrame:IsShown() then
            RefreshUI()
        end
    elseif event == "CRAFT_SHOW" then
        ScanCraft(false)
        ScheduleCraftRescan(0.75)
        if uiFrame and uiFrame:IsShown() then
            RefreshUI()
        end
    elseif event == "CRAFT_UPDATE" then
        ScanCraft(false)
        if uiFrame and uiFrame:IsShown() then
            RefreshUI()
        end
    elseif event == "BAG_UPDATE" then
        if uiFrame and uiFrame:IsShown() and selectedRecipeData then
            uiFrame:UpdatePreviewPanel()
        end
    elseif event == "GUILD_ROSTER_UPDATE" then
        refreshButtonTimer.endTime = nil
        refreshButtonTimer:SetScript("OnUpdate", nil)
        UpdateGuildRosterMetadata()
        RebuildRecipeExport()
        if uiFrame and uiFrame.refreshButton then
            uiFrame.refreshButton:Enable()
        end
        if uiFrame and uiFrame:IsShown() then
            RefreshUI()
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
            SetSyncStatus("Sync in: HELLO from " .. sender)
            DebugMessage("received HELLO from " .. sender)
            ScheduleProfessionSend()
            return
        end
        local _, _, command, playerName, profession, chunkIndex, isLast, recipeString =
            string.find(message, "^([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~?(.*)$")
        if command == "DATA" then
            playerName = GetShortName(playerName)
            if playerName ~= sender then
                DebugMessage("ignored spoofed sync payload from " .. sender .. " claiming to be " .. tostring(playerName))
                return
            end
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
        DEFAULT_CHAT_FRAME:AddMessage("/guildcraft rewrite")
        DEFAULT_CHAT_FRAME:AddMessage("/guildcraft cachemeta")
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
        for playerName in SafePairs(db) do
            count = count + 1
        end
        DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB profile: " .. realmName .. " / " .. guildName)
        DEFAULT_CHAT_FRAME:AddMessage("Stored players: " .. count)
        return
    end
    if msg == "cleanup" then
        local removedExcluded = RemoveExcludedRecipesFromDB()
        local removedBroken = RemoveBrokenRecipesFromDB()
        SanitizeStoredRecipeNames()
        RebuildRecipeExport()
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
    if msg == "rewrite" then
        RewriteSavedVariablesNow()
        return
    end
    if msg == "cachemeta" then
        local profession = GetTradeSkillLine and GetTradeSkillLine() or nil
        if profession and profession ~= "" and profession ~= "UNKNOWN" and CacheTradeSkillRecipeMeta then
            StartBulkMetaCacheJob("trade", profession)
            DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB: started meta cache job for open trade profession")
            return
        end

        profession = GetCraftDisplaySkillLine and GetCraftDisplaySkillLine() or nil
        if profession and profession ~= "" and profession ~= "UNKNOWN" and CacheCraftRecipeMeta then
            StartBulkMetaCacheJob("craft", profession)
            DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB: started meta cache job for open craft profession")
            return
        end

        DEFAULT_CHAT_FRAME:AddMessage("GuildCraftDB: open a profession window first, then run /guildcraft cachemeta")
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
    for player, professions in SafePairs(db) do
        for profession, recipes in SafePairs(professions) do
            if not IsProfessionExcluded(profession) then
                local recipeList = NormalizeRecipeList(recipes)
                for _, recipe in ipairs(recipeList) do
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

