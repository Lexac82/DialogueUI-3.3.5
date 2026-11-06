local _, addon = ...
local Skimmer = addon.Skimmer;
local QuestDataProvider = Skimmer and Skimmer.QuestDataProvider;
local CallbackRegistry = addon.CallbackRegistry;
local TooltipAPI = addon.TooltipAPI;
local API = addon.API;

-- Cache legacy quest-log APIs that may be absent on modified clients.
local GetQuestLogIndexByID = GetQuestLogIndexByID;
local GetLogIndexForQuestID = API and API.GetLogIndexForQuestID;
local GetQuestLogRewardXP = GetQuestLogRewardXP;
local GetQuestLogRewardMoney = GetQuestLogRewardMoney;
local GetNumQuestLogRewards = GetNumQuestLogRewards;
local GetQuestLogRewardInfo = GetQuestLogRewardInfo;
local GetQuestLogSelection = GetQuestLogSelection;
local SelectQuestLogEntry = SelectQuestLogEntry;

-- Use the client trim function when available, with a Lua 5.1-compatible fallback.
local strtrim = strtrim or function(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""));
end;

DUISkimmerOptionMixin = {};

-- Return a valid quest-log index for a quest ID, or nil when the quest is not in the log.
local function GetQuestLogIndex(questID)
    if not questID or questID == 0 then
        return nil
    end

    local index;
    if GetLogIndexForQuestID then
        index = GetLogIndexForQuestID(questID);
    elseif GetQuestLogIndexByID then
        index = GetQuestLogIndexByID(questID);
    end

    if index and index > 0 then
        return index
    end
end

-- Read legacy reward data for one quest while preserving the player's current quest-log selection.
local function GetLegacyQuestRewards(questID)
    local questIndex = GetQuestLogIndex(questID);
    if not questIndex or not SelectQuestLogEntry then
        return nil, nil, nil
    end

    local previousSelection = GetQuestLogSelection and GetQuestLogSelection();

    SelectQuestLogEntry(questIndex);

    -- In WotLK these reward functions read the currently selected quest-log entry.
    local xp = GetQuestLogRewardXP and GetQuestLogRewardXP();
    local money = GetQuestLogRewardMoney and GetQuestLogRewardMoney();

    local icons;
    if GetNumQuestLogRewards and GetQuestLogRewardInfo then
        local numRewards = GetNumQuestLogRewards() or 0;
        for rewardIndex = 1, numRewards do
            local name, texture = GetQuestLogRewardInfo(rewardIndex);
            if texture then
                local icon = string.format("|T%s:16:16|t", texture);
                if icons then
                    icons = icons .. " " .. icon;
                else
                    icons = icon;
                end
            end
        end
    end

    -- Restore the prior selection so displaying the Skimmer does not change the quest log.
    if previousSelection and previousSelection > 0 then
        SelectQuestLogEntry(previousSelection);
    end

    return xp, money, icons
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

-- Format a copper amount using the addon's formatter when it is available.
local function FormatMoney(money)
    if not money or money <= 0 then
        return nil
    end

    -- C_CurrencyInfo is not available in the WotLK client.
    if API and API.GenerateMoneyText then
        return API.GenerateMoneyText(money, true)
    end

    -- Keep a readable fallback rather than calling a Retail-only currency API.
    return tostring(money) .. " copper"
end

-- Set this option button to a quest and refresh its text and reward summary.
function DUISkimmerOptionMixin:SetQuest(questInfo, getObjectiveFromTooltip)
    if not questInfo then return end;

    self.questID = questInfo.questID;
    self.Title:SetText(questInfo.title or "");

    self:UpdateQuestObjectives();
    self:UpdateQuestData();

    -- Request quest data where supported; the 3.3.5 callback registry may use a timed fallback.
    if self.questID and CallbackRegistry and CallbackRegistry.LoadQuest then
        local questID = self.questID;
        CallbackRegistry:LoadQuest(questID, function(loadedQuestID)
            if self.questID == loadedQuestID and self:IsShown() then
                self:UpdateQuestObjectives();
                self:UpdateQuestData();
            end
        end);
    end
end

-- Build a concise XP, money, and item-reward summary using legacy quest-log APIs.
function DUISkimmerOptionMixin:UpdateQuestData()
    local questID = self.questID;
    local output;

    if not questID or questID == 0 then
        if self.TestRewardDisplay then
            self.TestRewardDisplay:SetText("");
        end
        return
    end

    -- Legacy reward APIs use the selected quest-log entry, not a quest ID argument.
    local xp, money, icons = GetLegacyQuestRewards(questID);

    if xp and xp > 0 then
        output = JoinText(output, "XP " .. tostring(xp));
    end

    output = JoinText(output, FormatMoney(money));
    output = JoinText(output, icons);

    -- Modern major-faction, currency, and reward-spell APIs are intentionally omitted:
    -- they are not available in WoW 3.3.5a.

    if self.TestRewardDisplay then
        self.TestRewardDisplay:SetText(output and strtrim(output) or "");
    end
end

-- Layout is controlled by the parent Skimmer frame.
function DUISkimmerOptionMixin:Layout()
end

-- Obtain the first useful quest-description line from the addon's tooltip compatibility layer.
function DUISkimmerOptionMixin:UpdateQuestObjectives()
    local questID = self.questID;
    if not questID or questID == 0 then
        if self.Desc then
            self.Desc:SetText("");
        end
        return
    end

    local tooltipData;
    if TooltipAPI and TooltipAPI.GetHyperlink then
        tooltipData = TooltipAPI.GetHyperlink("quest:" .. questID);
    end

    local tooltipText;
    if tooltipData and tooltipData.lines then
        for lineIndex, line in ipairs(tooltipData.lines) do
            -- Skip the title line and blank lines; display the first useful text line.
            if lineIndex > 1 and line.leftText then
                local text = strtrim(line.leftText);
                if text ~= "" and text ~= (self.Title:GetText() or "") then
                    tooltipText = text;
                    break
                end
            end
        end
    end

    -- Fall back to quest details cached when the legacy quest-detail frame was opened.
    if not tooltipText and QuestDataProvider and QuestDataProvider.GetQuestObjective then
        tooltipText = QuestDataProvider:GetQuestObjective(questID);
    end

    if self.Desc then
        self.Desc:SetText(tooltipText or "...");
    end
end

do
    -- Refresh objective text after the compatibility tooltip reports an update.
    local function OnSharedTooltipDataUpdate()
        if Skimmer and Skimmer.optionButtonPool then
            Skimmer.optionButtonPool:ProcessActiveObjects(function(optionButton)
                if optionButton.questID and optionButton.UpdateQuestObjectives then
                    optionButton:UpdateQuestObjectives();
                end
            end);
        end
    end

    -- The tooltip compatibility layer uses CallbackRegistry rather than a WoW frame event.
    if CallbackRegistry then
        CallbackRegistry:Register("SharedTooltip.TOOLTIP_DATA_UPDATE", OnSharedTooltipDataUpdate);
    end

    -- Refresh the visible reward summaries when the quest log changes.
    function Skimmer:UpdateDisplayedQuests()
        if not self.optionButtonPool then return end;

        self.optionButtonPool:ProcessActiveObjects(function(optionButton)
            if optionButton.questID and optionButton.UpdateQuestData then
                optionButton:UpdateQuestData();
            end
        end);
    end
end
