local _, addon = ...
local Skimmer = addon.Skimmer;
local QuestDataProvider = Skimmer.QuestDataProvider;
local CallbackRegistry = addon.CallbackRegistry;
local TooltipAPI = addon.TooltipAPI;

local GetQuestLogIndexByID = GetQuestLogIndexByID;
local GetQuestLogRewardXP = GetQuestLogRewardXP;
local GetQuestLogRewardMoney = GetQuestLogRewardMoney;
local GetNumQuestLogRewards = GetNumQuestLogRewards;
local GetQuestLogRewardInfo = GetQuestLogRewardInfo;
local GetQuestItemLink = GetQuestItemLink;
local strtrim = strtrim or function(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""));
end;

DUISkimmerOptionMixin = {};

-- Set the quest represented by this button and refresh its title, objective, and reward summary.
function DUISkimmerOptionMixin:SetQuest(questInfo, getObjectiveFromTooltip)
    if not questInfo then return end;

    self.questID = questInfo.questID;
    self.Title:SetText(questInfo.title or "");

    -- HINT: Always try the tooltip compatibility layer first; it falls back to the
    -- cached QuestDataProvider objective when tooltip data is unavailable.
    self:UpdateQuestObjectives();
    self:UpdateQuestData();

    -- Refresh quest details after the addon's asynchronous quest-data callback completes.
    if self.questID and CallbackRegistry and CallbackRegistry.LoadQuest then
        local questID = self.questID;
        CallbackRegistry:LoadQuest(questID, function(id)
            if self.questID == id and self:IsShown() then
                self:UpdateQuestObjectives();
                self:UpdateQuestData();
            end
        end);
    end
end

-- Join two optional text fragments with a subtle separator.
local function JoinText(a, b)
    if a and a ~= "" then
        if b and b ~= "" then
            return a .. " |cff808080·|r " .. b
        end
        return a
    end
    return b
end

-- Add a reward item icon to a space-separated icon string.
local function AppendIcon(iconString, texture, iconSize)
    if not texture then
        return iconString
    end

    local icon = string.format("|T%s:%d:%d|t", texture, iconSize, iconSize);
    if iconString then
        return iconString .. " " .. icon
    end
    return icon
end

-- Build a concise summary of XP, money, and item rewards available through the legacy quest log.
function DUISkimmerOptionMixin:UpdateQuestData()
    local questID = self.questID;
    local output;
    local iconSize = 16;

    if not questID then
        if self.TestRewardDisplay then
            self.TestRewardDisplay:SetText("");
        end
        return
    end

    -- HINT: Legacy quest-log reward APIs use a quest-log index, not a quest ID.
    -- Quests not yet in the log have no index, so their reward summary may be incomplete.
    local questIndex = GetQuestLogIndexByID and GetQuestLogIndexByID(questID);
    if questIndex and questIndex <= 0 then
        questIndex = nil;
    end

    if questIndex then
        if GetQuestLogRewardXP then
            local xp = GetQuestLogRewardXP(questIndex);
            if xp and xp > 0 then
                output = JoinText(output, "XP " .. xp);
            end
        end

        if GetQuestLogRewardMoney then
            local money = GetQuestLogRewardMoney(questIndex);
            if money and money > 0 then
                -- HINT: C_CurrencyInfo.GetCoinTextureString is Retail-only.
                -- Use the addon's existing money formatter for 3.3.5 compatibility.
                local coinText = addon.API.GenerateMoneyText
                    and addon.API.GenerateMoneyText(money, true)
                    or tostring(money);
                output = JoinText(output, coinText);
            end
        end

        if GetNumQuestLogRewards and GetQuestLogRewardInfo then
            local numRewards = GetNumQuestLogRewards(questIndex);
            local icons;

            for index = 1, (numRewards or 0) do
                local name, texture = GetQuestLogRewardInfo(index, questIndex);
                icons = AppendIcon(icons, texture, iconSize);
            end

            output = JoinText(output, icons);
        end
    end

    -- HINT: Major-faction, modern currency, and reward-spell APIs are omitted:
    -- C_MajorFactions and C_QuestInfoSystem are not available in WotLK 3.3.5a.

    if self.TestRewardDisplay then
        self.TestRewardDisplay:SetText(output and strtrim(output) or "");
    end
end

-- Layout is intentionally left to the parent Skimmer UI.
function DUISkimmerOptionMixin:Layout()
end

-- Read the first useful quest-description line from the compatibility tooltip.
function DUISkimmerOptionMixin:UpdateQuestObjectives()
    local questID = self.questID;
    if not questID then return end;

    local tooltipData;
    if TooltipAPI and TooltipAPI.GetHyperlink then
        tooltipData = TooltipAPI.GetHyperlink("quest:" .. questID);
    end

    local tooltipText;
    if tooltipData and tooltipData.lines then
        for index, line in ipairs(tooltipData.lines) do
            -- Skip the title line and blank lines; use the first descriptive line.
            if index > 1 and line.leftText then
                local text = strtrim(line.leftText);
                if text ~= "" and text ~= (self.Title:GetText() or "") then
                    tooltipText = text;
                    break
                end
            end
        end
    end

    -- Fall back to the quest details captured by QuestDataProvider on QUEST_DETAIL.
    if not tooltipText and QuestDataProvider and QuestDataProvider.GetQuestObjective then
        tooltipText = QuestDataProvider:GetQuestObjective(questID);
    end

    self.Desc:SetText(tooltipText or "...");
end

do
    -- Tooltip data may be refreshed asynchronously by the shared compatibility tooltip.
    -- Refresh active Skimmer buttons when that callback is emitted.
    local function OnSharedTooltipDataUpdate()
        if Skimmer.optionButtonPool then
            Skimmer.optionButtonPool:ProcessActiveObjects(function(optionButton)
                if optionButton.questID then
                    optionButton:UpdateQuestObjectives();
                end
            end);
        end
    end

    -- HINT: The tooltip compatibility layer emits this CallbackRegistry event;
    -- it is not a WoW frame event that should be registered with RegisterEvent.
    if CallbackRegistry then
        CallbackRegistry:Register("SharedTooltip.TOOLTIP_DATA_UPDATE", OnSharedTooltipDataUpdate);
    end

    -- Refresh displayed reward summaries when the quest log changes.
    function Skimmer:UpdateDisplayedQuests()
        if not self.optionButtonPool then return end;

        self.optionButtonPool:ProcessActiveObjects(function(optionButton)
            if optionButton.questID then
                optionButton:UpdateQuestData();
            end
        end);
    end
end
