local _, addon = ...
local Skimmer = CreateFrame("Frame");
addon.Skimmer = Skimmer;

-- Cache addon helpers and common APIs used throughout this module.
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

-- Legacy quest-detail APIs used when the detail frame is open.
local GetQuestTitle = GetTitleText;
local GetObjectiveText = GetObjectiveText;

-- Share the quest cache with the Skimmer template.
local QuestDataProvider = {};
Skimmer.QuestDataProvider = QuestDataProvider;

-- This frame owns quest and gossip events while the Skimmer is enabled.
local EL = CreateFrame("Frame");

-- Reject nil and zero IDs; zero is used by compatibility fallbacks for unavailable IDs.
local function IsValidQuestID(questID)
    return questID and questID ~= 0
end

-- Return modern gossip options when available.
-- The 3.3.5 path does not expose the same structured gossip-option table.
local function GetOptions()
    if C_GossipInfo and C_GossipInfo.GetOptions then
        return C_GossipInfo.GetOptions() or {}
    end
    return {}
end

-- Return active gossip quests in a common table format.
local function GetActiveQuests()
    if C_GossipInfo and C_GossipInfo.GetActiveQuests then
        return C_GossipInfo.GetActiveQuests() or {}
    end

    -- Build quest records from the legacy quest-greeting APIs.
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

-- Return available quests in a common table format.
local function GetAvailableQuests()
    if C_GossipInfo and C_GossipInfo.GetAvailableQuests then
        return C_GossipInfo.GetAvailableQuests() or {}
    end

    -- In the legacy client, quest titles and quest metadata are retrieved by list index.
    local quests = {};
    if not GetNumAvailableQuests or not GetAvailableTitle then
        return quests
    end

    local count = GetNumAvailableQuests() or 0;
    for index = 1, count do
        local title = GetAvailableTitle(index);
        local questID;

        -- HINT: Capture all returns from the helper; a single-variable assignment
        -- would discard the quest ID returned in the fifth position.
        if API.GetAvailableQuestInfo then
            local isTrivial, frequency, isRepeatable, isLegendary, returnedQuestID =
                API.GetAvailableQuestInfo(index);
            questID = returnedQuestID;
        end

        -- Some legacy helpers cannot determine an ID for every offered quest.
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

-- Select an available quest through the modern API or the legacy gossip API.
local function SelectAvailableQuest(questInfo)
    if not questInfo then return end;

    if C_GossipInfo and C_GossipInfo.SelectAvailableQuest then
        if IsValidQuestID(questInfo.questID) then
            C_GossipInfo.SelectAvailableQuest(questInfo.questID);
            return
        end
    end

    -- The legacy function expects the quest's list index, not its quest ID.
    if SelectGossipAvailableQuest and questInfo.index then
        SelectGossipAvailableQuest(questInfo.index);
    end
end

do  -- Event Handler
    -- Events forwarded to the Skimmer while it owns dialogue handling.
    local DialogueEvents = {
        "GOSSIP_SHOW",
        "GOSSIP_CLOSED",
        "QUEST_PROGRESS",
        "QUEST_DETAIL",
        "QUEST_FINISHED",
        "QUEST_GREETING",
        "QUEST_COMPLETE",
    };

    -- Route gossip and quest events to the appropriate Skimmer handler.
    function EL:OnEvent(event, ...)
        if event == "GOSSIP_SHOW" then
            local handler = GetCustomGossipHandler and GetCustomGossipHandler(...);
            if handler then
                self.customFrame = handler(...);
                return
            end

            self.showGossipFrame = Skimmer:HandleGossip();

        elseif event == "QUEST_GREETING" then
            -- Quest greetings use legacy quest-list APIs and are handled separately.
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
                -- Cache quest details requested by the Skimmer, then close the detail frame.
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

    -- Register or unregister all dialogue events as a group.
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
    -- Initialize the option-button pool once, when the Skimmer is first needed.
    function Skimmer:Init()
        if self.optionButtonPool then
            return
        end

        -- Create a button, apply its behavior mixin, and connect its XML text regions.
        -- Explicit child references are used for compatibility with the 3.3.5 XML system.
        local buttonIndex = 0;

        local function CreateOptionButton()
            buttonIndex = buttonIndex + 1;
            local frameName = "DUISkimmerOptionButton" .. buttonIndex;
            local button = CreateFrame("Frame", frameName, self, "DUISkimmerOptionTemplate");

            -- Add the methods that implement quest display and update behavior.
            API.Mixin(button, DUISkimmerOptionMixin);

            -- Bind the named XML child regions to the fields expected by the mixin.
            button.Title = _G[frameName .. "Title"];
            button.Desc = _G[frameName .. "Desc"];
            button.TestRewardDisplay = _G[frameName .. "TestRewardDisplay"];

            return button
        end

        -- Hide a released button and clear state that should not survive pool reuse.
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
    -- Release active buttons and clear any tooltip-update references.
    function Skimmer:ReleaseAllObjects()
        if self.optionButtonPool then
            self.optionButtonPool:Release();
        end

        if self.ClearTooltipDataWatchList then
            self:ClearTooltipDataWatchList();
        end
    end

    -- Handle quest-log and tooltip events received by the visible Skimmer frame.
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

    -- Close gossip and release pooled objects when the Skimmer is hidden.
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

    -- Observe quest-log changes only while the Skimmer is shown.
    function Skimmer:OnShow()
        self:RegisterEvent("QUEST_LOG_UPDATE");
    end
    Skimmer:SetScript("OnShow", Skimmer.OnShow);
end

-- Hide the Skimmer frame.
do
    function Skimmer:HideUI()
        self:Hide();
    end
end

do
    -- Create and vertically position a button for every valid quest in the supplied list.
    local function AddQuestButtons(questList)
        if not questList then return end;

        -- HINT: Use Skimmer explicitly here; this local function has no implicit self parameter.
        Skimmer:ReleaseAllObjects();

        local lastObject;
        for _, questInfo in ipairs(questList) do
            if questInfo and IsValidQuestID(questInfo.questID) then
                local button = Skimmer.optionButtonPool:Acquire();
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

    -- Handle modern gossip menus and display their available quests.
    function Skimmer:HandleGossip()
        if DialogueUI and DialogueUI.IsGossipHandledExternally
            and DialogueUI:IsGossipHandledExternally() then
            return false
        end

        self:Init();

        local options = GetOptions() or {};
        local activeQuests = GetActiveQuests() or {};
        local availableQuests = GetAvailableQuests() or {};

        -- Auto-selection expects modern structured gossip options.
        if HandleAutoSelect and HandleAutoSelect(options, activeQuests, availableQuests) then
            return false
        end

        -- Sort options for consistent handling where the caller uses this list.
        if SortFunc_GossipPrioritizeQuest and #options > 0 then
            tsort(options, SortFunc_GossipPrioritizeQuest);
        end

        -- Buttons need valid quest IDs because the template requests quest data by ID.
        local validAvailableQuests = {};
        for _, questInfo in ipairs(availableQuests) do
            if questInfo and IsValidQuestID(questInfo.questID) then
                validAvailableQuests[#validAvailableQuests + 1] = questInfo;
            end
        end

        AddQuestButtons(validAvailableQuests);

        -- Select queued quests after their detail data has been captured.
        for _, questInfo in ipairs(validAvailableQuests) do
            if QuestDataProvider:IsQueuingQuest(questInfo.questID) then
                SelectAvailableQuest(questInfo);
                return
            end
        end

        self:Show();
        return true
    end

    -- Handle the legacy quest-greeting frame separately from gossip menus.
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

        -- Continue a queued quest-detail request using the legacy list index.
        for _, questInfo in ipairs(validAvailableQuests) do
            if QuestDataProvider:IsQueuingQuest(questInfo.questID) then
                SelectAvailableQuest(questInfo);
                return
            end
        end

        self:Show();
        return true
    end

    -- Display the currently open quest-detail dialog.
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

    -- Placeholder for future legacy quest-data loading.
    function QuestDataProvider:LoadQuest(questID)
    end

    -- Clear one cached quest or the complete cache.
    function QuestDataProvider:ClearQuestCache(questID)
        if questID then
            QuestCache[questID] = nil;
        else
            QuestCache = {};
        end
    end

    -- Return the cached record for a quest.
    function QuestDataProvider:GetQuestData(questID)
        return QuestCache[questID]
    end

    -- Return the cached quest title, if available.
    function QuestDataProvider:GetQuestTitle(questID)
        local data = QuestCache[questID];
        return data and data.title or nil
    end

    -- Return cached objective text, if available.
    function QuestDataProvider:GetQuestObjective(questID)
        local data = QuestCache[questID];
        return data and data.objectives or nil
    end

    -- Quest reward caching is not implemented for the legacy 3.3.5 path.
    function QuestDataProvider:GetQuestReward(questID)
    end

    -- Check whether cached details were captured at the player's current level.
    function QuestDataProvider:IsQuestDetailCached(questID)
        local playerLevel = UnitLevel and UnitLevel("player") or 0;
        local data = QuestCache[questID];
        return data and data.playerLevel == playerLevel
    end

    -- Store quest details while the quest-detail frame is active.
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

    -- Mark a quest so its details can be captured when its detail frame opens.
    function QuestDataProvider:RequestQuestDetail(questID)
        if not IsValidQuestID(questID) then
            return
        end

        self.questQueue = self.questQueue or {};
        self.questQueue[questID] = true;
    end

    -- Check whether a quest is waiting for its detail data to be captured.
    function QuestDataProvider:IsQueuingQuest(questID)
        return questID and self.questQueue and self.questQueue[questID] or false
    end
end

do  -- Module Control
    -- Enable or disable the Skimmer's ownership of dialogue events.
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

    -- Optional delayed activation used during local development.
    if false and C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            DUI_ToggleSkimmer(true);
        end)
    end
end
