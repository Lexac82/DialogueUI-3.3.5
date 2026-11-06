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

-- Use the modern gossip API where available; otherwise build quest lists from the
-- legacy quest-greeting APIs used by WoW 3.3.5.
local ModernGossipInfo = C_GossipInfo;

local QuestDataProvider = {};
Skimmer.QuestDataProvider = QuestDataProvider;

local EL = CreateFrame("Frame");

-- Normalize available quests to the {questID, title, ...} shape used by Skimmer.
local function GetAvailableQuests()
    if ModernGossipInfo and ModernGossipInfo.GetAvailableQuests then
        return ModernGossipInfo.GetAvailableQuests() or {};
    end

    -- HINT: Legacy APIs return quest details by index instead of modern quest tables.
    local quests = {};
    if not (GetNumAvailableQuests and GetAvailableTitle) then
        return quests
    end

    local count = GetNumAvailableQuests() or 0;
    for index = 1, count do
        local title = GetAvailableTitle(index);
        local isTrivial, frequency, isRepeatable, isLegendary, questID;

        if API.GetAvailableQuestInfo then
            isTrivial, frequency, isRepeatable, isLegendary, questID =
                API.GetAvailableQuestInfo(index);
        end

        quests[#quests + 1] = {
            questID = questID,
            title = title or "",
            index = index,
            isTrivial = isTrivial,
            frequency = frequency,
            isRepeatable = isRepeatable,
            isLegendary = isLegendary,
        };
    end

    return quests
end

-- Normalize active quests for logic that needs to know whether a quest is complete.
local function GetActiveQuests()
    if ModernGossipInfo and ModernGossipInfo.GetActiveQuests then
        return ModernGossipInfo.GetActiveQuests() or {};
    end

    -- HINT: The Classic greeting APIs expose active quests by index.
    local quests = {};
    if not (GetNumActiveQuests and GetActiveTitle) then
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

-- Select an available quest using the API style supported by the current client.
local function SelectAvailableQuest(questInfo)
    if not questInfo then return end;

    if ModernGossipInfo and ModernGossipInfo.SelectAvailableQuest then
        if questInfo.questID then
            ModernGossipInfo.SelectAvailableQuest(questInfo.questID);
        end
    elseif SelectGossipAvailableQuest and questInfo.index then
        -- HINT: In 3.3.5, SelectGossipAvailableQuest expects the quest's list index.
        SelectGossipAvailableQuest(questInfo.index);
    end
end

do  -- Event handling
    local DialogueEvents = {
        "GOSSIP_SHOW",
        "GOSSIP_CLOSED",
        "QUEST_PROGRESS",
        "QUEST_DETAIL",
        "QUEST_FINISHED",
        "QUEST_GREETING",
        "QUEST_COMPLETE",
    };

    -- Handle gossip and quest events while the Skimmer owns dialogue event processing.
    function EL:OnEvent(event, ...)
        if event == "GOSSIP_SHOW" then
            local handler = GetCustomGossipHandler and GetCustomGossipHandler(...);
            if handler then
                self.customFrame = handler(...);
                return
            end

            self.showGossipFrame = Skimmer:HandleGossip();

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

    -- Register or unregister all dialogue-related events.
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

do  -- Skimmer setup and visibility
    -- Create the option-button pool on first use.
    function Skimmer:Init()
        if not self.optionButtonPool then
            local function CreateOptionButton()
                return CreateFrame("Frame", nil, self, "DUISkimmerOptionTemplate");
            end

            local function RemoveOptionButton(button)
                button:Hide();
                button:ClearAllPoints();

                -- HINT: Clear pooled button state so a reused button cannot retain an old quest.
                button.questID = nil;
                button.dataInstanceID = nil;
            end

            self.optionButtonPool = API.CreateObjectPool(CreateOptionButton, RemoveOptionButton);
        end
    end

    -- Release active buttons and clear tooltip-related references when the Skimmer is hidden.
    function Skimmer:ReleaseAllObjects()
        if self.optionButtonPool then
            self.optionButtonPool:Release();
        end

        if self.ClearTooltipDataWatchList then
            self:ClearTooltipDataWatchList();
        end
    end

    -- Refresh displayed quests when the quest log changes.
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

    -- Close an open legacy gossip frame and release pooled UI elements.
    function Skimmer:OnHide()
        -- HINT: C_GossipInfo.CloseGossip is not a WotLK API.
        if CloseGossip and GossipFrame and GossipFrame:IsShown() then
            CloseGossip();
        end

        self:ReleaseAllObjects();
        self:UnregisterEvent("QUEST_LOG_UPDATE");
    end
    Skimmer:SetScript("OnHide", Skimmer.OnHide);

    -- Track quest-log changes only while the Skimmer is visible.
    function Skimmer:OnShow()
        self:RegisterEvent("QUEST_LOG_UPDATE");
    end
    Skimmer:SetScript("OnShow", Skimmer.OnShow);
end

-- Hide the Skimmer UI.
function Skimmer:HideUI()
    self:Hide();
end

do  -- Gossip and quest display
    -- Handle modern gossip auto-selection when that API is available, then display available quests.
    function Skimmer:HandleGossip()
        if DialogueUI and DialogueUI.IsGossipHandledExternally
            and DialogueUI:IsGossipHandledExternally() then
            return false
        end

        self:Init();

        local availableQuests = GetAvailableQuests();
        local activeQuests = GetActiveQuests();

        -- HINT: Modern auto-selection expects structured gossip-option records.
        -- The legacy WotLK gossip APIs do not expose the same records, so skip this
        -- auto-selection path there rather than passing incompatible return values.
        if ModernGossipInfo and ModernGossipInfo.GetOptions and HandleAutoSelect then
            local options = ModernGossipInfo.GetOptions() or {};
            if HandleAutoSelect(options, activeQuests, availableQuests) then
                return false
            end

            if SortFunc_GossipPrioritizeQuest then
                tsort(options, SortFunc_GossipPrioritizeQuest);
            end
        end

        self:ReleaseAllObjects();

        local lastButton;
        for _, questInfo in ipairs(availableQuests) do
            if questInfo and questInfo.questID then
                local button = self.optionButtonPool:Acquire();
                button:SetQuest(questInfo);

                if lastButton then
                    button:SetPoint("TOPLEFT", lastButton, "BOTTOMLEFT", 0, -16);
                else
                    button:SetPoint("LEFT", UIParent, "CENTER", 96, 0);
                end

                lastButton = button;
            end
        end

        -- Select a quest queued by QuestDataProvider after its greeting data is collected.
        for _, questInfo in ipairs(availableQuests) do
            if questInfo and QuestDataProvider:IsQueuingQuest(questInfo.questID) then
                SelectAvailableQuest(questInfo);
                return
            end
        end

        self:Show();
        return true
    end

    -- Display the currently offered quest's detail view.
    function Skimmer:HandleQuestDetail()
        self:Init();

        local questID = GetQuestID and GetQuestID();
        local title = GetQuestTitle and GetQuestTitle();

        if not questID or questID == 0 then
            return
        end

        local questInfo = {
            questID = questID,
            title = title or "",
        };

        self:ReleaseAllObjects();

        local button = self.optionButtonPool:Acquire();
        button:SetQuest(questInfo);
        button:SetPoint("LEFT", UIParent, "CENTER", 96, 0);

        self:Show();
    end
end

do  -- Classic quest detail cache
    local QuestCache = {};

    -- Cache quest title and objective text when a queued quest's detail frame is opened.
    function QuestDataProvider:OnQuestDetailReceived(questID)
        if not questID then return end;

        self.questQueue = self.questQueue or {};
        QuestCache[questID] = {
            playerLevel = UnitLevel and UnitLevel("player") or 0,
            title = GetQuestTitle and GetQuestTitle() or "",
            objectives = GetObjectiveText and GetObjectiveText() or "",
        };

        self.questQueue[questID] = nil;
    end

    -- Return cached quest text only while it was collected at the current player level.
    function QuestDataProvider:GetQuestObjective(questID)
        local data = QuestCache[questID];
        if data and (not UnitLevel or data.playerLevel == UnitLevel("player")) then
            return data.objectives
        end
    end

    -- Mark a quest to be opened and read when its detail event arrives.
    function QuestDataProvider:RequestQuestDetail(questID)
        if not questID then return end;
        self.questQueue = self.questQueue or {};
        self.questQueue[questID] = true;
    end

    -- Check whether the quest is waiting to be captured from the detail frame.
    function QuestDataProvider:IsQueuingQuest(questID)
        return questID and self.questQueue and self.questQueue[questID] or false
    end
end

do  -- Module control
    -- Enable or disable Skimmer ownership of the dialogue events.
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
end
