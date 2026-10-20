-- Lints the addon (luacheck GorlocCraftScan). Tests define their own mock globals and are not linted.
std = "lua51"
max_line_length = false
ignore = {
    "432/self", -- WoW script handlers receive their own self
}

-- Globals the addon defines.
globals = {
    "GorlocCraftScanDB",
    "SlashCmdList",
    "SLASH_GORLOCCRAFTSCAN1",
    "SLASH_GORLOCCRAFTSCAN2",
}

-- WoW API and Auctionator globals the addon reads. Add new ones here when the code starts using them.
read_globals = {
    "Auctionator",
    "C_AddOns",
    "C_Item",
    "C_Timer",
    "C_TradeSkillUI",
    "ChatFontNormal",
    "CreateFrame",
    "date",
    "Enum",
    "GetBuildInfo",
    "GetNormalizedRealmName",
    "GetProfessionInfo",
    "GetProfessions",
    "GetRealmName",
    "GetTime",
    "GetTimePreciseSec",
    "InCombatLockdown",
    "LE_EXPANSION_LEVEL_CURRENT",
    "PanelTemplates_SetNumTabs",
    "PanelTemplates_SetTab",
    "ProfessionsFrame",
    "time",
    "tinsert",
    "UIParent",
    "UISpecialFrames",
    "UnitGUID",
    "UnitName",
    "WOW_PROJECT_ID",
    "WOW_PROJECT_MAINLINE",
}
