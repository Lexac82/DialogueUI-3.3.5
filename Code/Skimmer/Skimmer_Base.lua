local _, addon = ...
local Skimmer = CreateFrame("Frame");
addon.Skimmer = Skimmer;

local API = addon.API;
local GetCustomGossipHandler = addon.GetCustomGossipHandler;
local DialogueUI = addon.DialogueUI;
local HandleAutoSelect = addon.DialogueHandleAutoSelect;
local SortFunc_GossipPrioritizeQuest = addon.SortFunc_GossipPrioritizeQuest;

local tsort = table.sort;
local CreateFrame = CreateFrame;
local InCombatLockdown = InCombatLockdown;
local DeclineQuest = DeclineQuest;
local GetQuestID = GetQuestID;
local UnitLevel = UnitLevel;

local GetQuestTitle = GetTitleText;
local GetObjectiveText = GetObjectiveText;

local QuestDataProvider = {};
Skimmer.QuestDataProvider = QuestDataProvider;

local EL = CreateFrame("Frame");

local function IsValidQuestID(questID)
    return questID and questID ~= 0
end

local function GetOptions()
    if C_GossipInfo and C_GossipInfo.GetOptions then
        return C_GossipInfo.GetOptions() or {}
    end
    return {}
end

local function GetActiveQuests()
    if C_GossipInfo and C_GossipInfo.GetActiveQuests then
        return C_GossipInfo.GetActiveQuests() or {}
    end

    local quests = {};
    if not GetNumActiveQuests or not GetActiveTitle then
        return quests
    end

    local count = GetNumActiveQuests() or 0;
    for index = 1, count do
        local title, isComplete = GetActiveTitle(index);
        local questID = API.GetActiveQuestID and API.GetActiveQuestID(index);

        quests[#quests + 1] = {
            questID = questID,
            title = title or "",
            index = index,
            isComplete = isComplete,
        };
    end

    return quests
end

local function GetAvailableQuests()
    if C_GossipInfo and C_GossipInfo.GetAvailableQuests then
        return C_GossipInfo.GetAvailableQuests() or {}
    end

    local quests = {};
    if not GetNumAvailableQuests or not GetAvailableTitle then
        return quests
    end

    local count = GetNumAvailableQuests() or 0;
    for index = 1, count do
        local title = GetAvailableTitle(index);
        local availableInfo = API.GetAvailableQuestInfo and API.GetAvailableQuestInfo(index);

        local questID;
        if availableInfo and type(availableInfo) == "table" then
            questID = availableInfo.questID or availableInfo[5];
        elseif availableInfo then
            questID = select(5, availableInfo);
        end

        -- Legacy 3.3.5 returns 0 or nil for some entries and that is not a valid quest ID.
        if not IsValidQuestID(questID) then
            questID = nil;
        end

        quests[#quests + 1] = {
            questID = questID,
            title = title or "",
            index = index,
        };
    end

    return quests
end

local function SelectAvailableQuest(questInfo)
    if not questInfo then return end;

    if C_GossipInfo and C_GossipInfo.SelectAvailableQuest then
        if IsValidQuestID(questInfo.questID) then
            C_GossipInfo.SelectAvailableQuest(questInfo.questID);
            return
        end
    end

    if SelectGossipAvailableQuest and questInfo.index then
        SelectGossipAvailableQuest(questInfo.index);
    end
end

do  -- Event Handler
    local DialogueEvents = {
        "GOSSIP_SHOW",
        "GOSSIP_CLOSED",
        "QUEST_PROGRESS",
        "QUEST_DETAIL",
        "QUEST_FINISHED",
        "QUEST_GREETING",
        "QUEST_COMPLETE",
    };

    function EL:OnEvent(event, ...)
        if event == "GOSSIP_SHOW" then
            local handler = GetCustomGossipHandler and GetCustomGossipHandler(...);
            if handler then
                self.customFrame = handler(...);
                return
            end

            self.showGossipFrame = Skimmer:HandleGossip();

        elseif event == "QUEST_GREETING" then
            self.showGossipFrame = Skimmer:HandleQuestGreeting();

        elseif event == "GOSSIP_CLOSED" then
            local interactionIsContinuing = ...;
            if self.showGossipFrame then
                if interactionIsContinuing then
                    self.interactionIsContinuing = true;
                end
                if not self.interactionIsContinuing then
                    Skimmer:HideUI();
                end
                self.interactionIsContinuing = nil;
            elseif self.customFrame then
                if not InCombatLockdown or not InCombatLockdown() then
                    if HideUIPanel then
                        HideUIPanel(self.customFrame);
                    else
                        self.customFrame:Hide();
                    end
                end
                self.customFrame = nil;
            end

        elseif event == "QUEST_DETAIL" then
            local questID = GetQuestID and GetQuestID();
            if QuestDataProvider:IsQueuingQuest(questID) then
                QuestDataProvider:OnQuestDetailReceived(questID);
                if DeclineQuest then
                    DeclineQuest();
                end
            else
                Skimmer:HandleQuestDetail();
            end

        elseif event == "QUEST_FINISHED" then
            Skimmer:HideUI();
        end
    end

    function EL:ListenEvents(state)
        local method = state and "RegisterEvent" or "UnregisterEvent";

        if state then
            self:SetScript("OnEvent", self.OnEvent);
        else
            self:SetScript("OnEvent", nil);
        end

        for _, event in ipairs(DialogueEvents) do
            self[method](self, event);
        end
    end
end

do
    function Skimmer:Init()
        if self.optionButtonPool then
            return
        end

        -- Create a skimmer option button, attach the mixin, and bind the XML child text fields.
        -- This keeps the button compatible with older 3.3.5 XML behavior where parentKey is not exposed
        -- consistently the same way as in newer clients.
        local buttonIndex = 0;

        local function CreateOptionButton()
            buttonIndex = buttonIndex + 1;
            local frameName = "DUISkimmerOptionButton" .. buttonIndex;
            local button = CreateFrame("Frame", frameName, self, "DUISkimmerOptionTemplate");

            -- Attach the mixin so the frame has methods such as SetQuest, UpdateQuestObjectives, and UpdateQuestData.
            API.Mixin(button, DUISkimmerOptionMixin);

            -- Bind the named XML child fields to the field names expected by the mixin.
            button.Title = _G[frameName .. "Title"];
            button.Desc = _G[frameName .. "Desc"];
            button.TestRewardDisplay = _G[frameName .. "TestRewardDisplay"];

            return button
        end

        -- Remove pooled buttons and clear stale state before reusing them.
        local function RemoveOptionButton(button)
            button:Hide();
            button:ClearAllPoints();
            button.questID = nil;
            button.dataInstanceID = nil;
        end

        self.optionButtonPool = API.CreateObjectPool(CreateOptionButton, RemoveOptionButton);
    end
end

do
    function Skimmer:ReleaseAllObjects()
        if self.optionButtonPool then
            self.optionButtonPool:Release();
        end

        if self.ClearTooltipDataWatchList then
            self:ClearTooltipDataWatchList();
        end
    end

    function Skimmer:OnEvent(event, ...)
        if event == "QUEST_LOG_UPDATE" then
            if self.UpdateDisplayedQuests then
                self:UpdateDisplayedQuests();
            end
        elseif event == "TOOLTIP_DATA_UPDATE" then
            if self.HandleTooltipDataUpdate then
                self:HandleTooltipDataUpdate(...);
            end
        end
    end
    Skimmer:SetScript("OnEvent", Skimmer.OnEvent);

    function Skimmer:OnHide()
        if C_GossipInfo and C_GossipInfo.CloseGossip then
            C_GossipInfo.CloseGossip();
        elseif CloseGossip then
            CloseGossip();
        end

        self:ReleaseAllObjects();
        self:UnregisterEvent("QUEST_LOG_UPDATE");
    end
    Skimmer:SetScript("OnHide", Skimmer.OnHide);

    function Skimmer:OnShow()
        self:RegisterEvent("QUEST_LOG_UPDATE");
    end
    Skimmer:SetScript("OnShow", Skimmer.OnShow);
end

do
    function Skimmer:HideUI()
        self:Hide();
    end
end

do
    local function AddQuestButtons(questList)
        if not questList then return end;

        self:ReleaseAllObjects();

        local lastObject;
        for _, questInfo in ipairs(questList) do
            if questInfo and IsValidQuestID(questInfo.questID) then
                local button = self.optionButtonPool:Acquire();
                button:SetQuest(questInfo);

                if lastObject then
                    button:SetPoint("TOPLEFT", lastObject, "BOTTOMLEFT", 0, -16);
                else
                    button:SetPoint("LEFT", UIParent, "CENTER", 96, 0);
                end

                lastObject = button;
            end
        end
    end

    function Skimmer:HandleGossip()
        if DialogueUI and DialogueUI.IsGossipHandledExternally and DialogueUI:IsGossipHandledExternally() then
            return false
        end

        self:Init();

        local options = GetOptions() or {};
        local activeQuests = GetActiveQuests() or {};
        local availableQuests = GetAvailableQuests() or {};

        if HandleAutoSelect and HandleAutoSelect(options, activeQuests, availableQuests) then
            return false
        end

        if SortFunc_GossipPrioritizeQuest and #options > 0 then
            tsort(options, SortFunc_GossipPrioritizeQuest);
        end

        local validAvailableQuests = {};
        for _, questInfo in ipairs(availableQuests) do
            if questInfo and IsValidQuestID(questInfo.questID) then
                validAvailableQuests[#validAvailableQuests + 1] = questInfo;
            end
        end

        AddQuestButtons(validAvailableQuests);

        for _, questInfo in ipairs(validAvailableQuests) do
            if QuestDataProvider:IsQueuingQuest(questInfo.questID) then
                SelectAvailableQuest(questInfo);
                return
            end
        end

        self:Show();
        return true
    end

    function Skimmer:HandleQuestGreeting()
        self:Init();

        local availableQuests = GetAvailableQuests() or {};
        local validAvailableQuests = {};
        for _, questInfo in ipairs(availableQuests) do
            if questInfo and IsValidQuestID(questInfo.questID) then
                validAvailableQuests[#validAvailableQuests + 1] = questInfo;
            end
        end

        if #validAvailableQuests == 0 then
            self:HideUI();
            return false
        end

        AddQuestButtons(validAvailableQuests);

        for _, questInfo in ipairs(validAvailableQuests) do
            if QuestDataProvider:IsQueuingQuest(questInfo.questID) then
                SelectAvailableQuest(questInfo);
                return
            end
        end

        self:Show();
        return true
    end

    function Skimmer:HandleQuestDetail()
        self:Init();

        local questID = GetQuestID and GetQuestID();
        if not IsValidQuestID(questID) then
            return
        end

        local questInfo = {
            questID = questID,
            title = GetQuestTitle and GetQuestTitle() or "",
        };

        self:ReleaseAllObjects();

        local button = self.optionButtonPool:Acquire();
        button:SetQuest(questInfo);
        button:SetPoint("LEFT", UIParent, "CENTER", 96, 0);

        self:Show();
    end
end

do  -- QuestDataProvider
    local QuestCache = {};

    function QuestDataProvider:LoadQuest(questID)
        -- Legacy compatibility stub for future quest prefetching.
    end

    function QuestDataProvider:ClearQuestCache(questID)
        -- Legacy compatibility stub for future cache resets.
    end

    function QuestDataProvider:GetQuestData(questID)
        return QuestCache[questID]
    end

    function QuestDataProvider:GetQuestTitle(questID)
        local data = QuestCache[questID];
        return data and data.title or nil
    end

    function QuestDataProvider:GetQuestObjective(questID)
        local data = QuestCache[questID];
        return data and data.objectives or nil
    end

    function QuestDataProvider:GetQuestReward(questID)
        -- Not implemented in the legacy 3.3.5 path yet.
    end

    function QuestDataProvider:IsQuestDetailCached(questID)
        local playerLevel = UnitLevel and UnitLevel("player") or 0;
        local data = QuestCache[questID];
        return data and data.playerLevel == playerLevel
    end

    function QuestDataProvider:OnQuestDetailReceived(questID)
        if not IsValidQuestID(questID) then
            return
        end

        QuestCache[questID] = {
            playerLevel = UnitLevel and UnitLevel("player") or 0,
            title = GetQuestTitle and GetQuestTitle() or "",
            objectives = GetObjectiveText and GetObjectiveText() or "",
        };

        if self.questQueue then
            self.questQueue[questID] = nil;
        end
    end

    function QuestDataProvider:RequestQuestDetail(questID)
        if not IsValidQuestID(questID) then
            return
        end

        self.questQueue = self.questQueue or {};
        self.questQueue[questID] = true;
    end

    function QuestDataProvider:IsQueuingQuest(questID)
        return questID and self.questQueue and self.questQueue[questID] or false
    end
end

do  -- Module Control
    function DUI_ToggleSkimmer(state)
        if state then
            EL:ListenEvents(true);
            if addon.SetHandleEventExternally then
                addon.SetHandleEventExternally(true);
            end
        else
            EL:ListenEvents(false);
            if addon.SetHandleEventExternally then
                addon.SetHandleEventExternally(false);
            end
        end
    end

    if false then
        C_Timer.After(2, function()
            DUI_ToggleSkimmer(true);
        end)
    end
end
