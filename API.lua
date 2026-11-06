local _, addon = ...
local API = addon.API;
local L = addon.L;
local CallbackRegistry = addon.CallbackRegistry;

-- Cache frequently used standard functions in local variables.
local floor = math.floor;
local sqrt = math.sqrt;
local tostring = tostring;
local find = string.find;

-- Use the client locale to select locale-specific formatting behavior.
local LOCALE = GetLocale and GetLocale() or "enUS";


-- No-operation helper that returns nil.
local function AlwaysNil(arg)
end
API.Nop = AlwaysNil;

-- Compatibility fallback for APIs that are unavailable on some clients.
local function AlwaysFalse(arg)
    return false
end
API.AlwaysFalse = AlwaysFalse;

-- Compatibility fallback for APIs whose safe default is true.
local function AlwaysTrue(arg)
    return true
end
API.AlwaysTrue = AlwaysTrue;

-- Compatibility fallback for APIs that should return a numeric zero.
local function AlwaysZero(arg)
    return 0
end


-- Provide cross-version wrappers for APIs that check restricted or secret values.
local issecurevalue = issecurevalue or AlwaysFalse;
local canaccessvalue = canaccessvalue or AlwaysTrue;
API.issecurevalue = issecurevalue;
API.canaccessvalue = canaccessvalue;
API.ShouldUnitIdentityBeSecret = C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret or AlwaysFalse;

-- Check whether a value is safe to access and is not nil or false.
function API.DoesValueExist(v)
    if canaccessvalue(v) then
        if v then
            return true
        end
    end
    return false
end

-- Copy the entries of a named Enum table when that enum exists on this client.
local function CopyEnum(name)
    local tbl = {};
    if Enum and Enum[name] then
        for k, v in pairs(Enum[name]) do
            tbl[k] = v;
        end
    end
    return tbl
end


-- General-purpose numeric helpers used by UI layout and animation code.
do  -- Math
    -- Return the straight-line distance between two points in 2D space.
    local function GetPointsDistance2D(x1, y1, x2, y2)
        return sqrt( (x1 - x2)*(x1 - x2) + (y1 - y2)*(y1 - y2))
    end
    API.GetPointsDistance2D = GetPointsDistance2D;

    -- Round a number to the nearest integer.
    local function Round(n)
        return floor(n + 0.5);
    end
    API.Round = Round;

    -- Restrict a value to the inclusive range between min and max.
    local function Clamp(value, min, max)
        if value > max then
            return max
        elseif value < min then
            return min
        end
        return value
    end
    API.Clamp = Clamp;

    -- Interpolate between two values using amount as the blend factor.
    local function Lerp(startValue, endValue, amount)
        return (1 - amount) * startValue + amount * endValue;
    end
    API.Lerp = Lerp;

    -- Interpolate while first constraining the blend factor to the range 0–1.
    local function ClampLerp(startValue, endValue, amount)
        amount = Clamp(amount, 0, 1);
        return Lerp(startValue, endValue, amount);
    end
    API.ClampLerp = ClampLerp;

    -- Clamp a value to the normalized range 0–1.
    local function Saturate(value)
        return Clamp(value, 0.0, 1.0);
    end

    -- Normalize time-based interpolation to behave consistently across frame rates.
    local TARGET_FRAME_PER_SEC = 60.0;

    -- Interpolate by an amount scaled to elapsed time, capped to the normalized range.
    local function DeltaLerp(startValue, endValue, amount, timeSec)
        return Lerp(startValue, endValue, Saturate(amount * timeSec * TARGET_FRAME_PER_SEC));
    end
    API.DeltaLerp = DeltaLerp;


    -- Format large currency-related numbers using locale-appropriate abbreviations.
    do  -- Currency number abbreviation
        local ABBREVIATION_K = L["Abbrev Breakpoint 1000"];

        -- East Asian locales use a 10,000-based abbreviation suffix.
        if LOCALE == "zhCN" or LOCALE == "zhTW" or LOCALE == "koKR" then
            local ABBREVIATION_W = L["Abbrev Breakpoint 10000"];
            API.AbbreviateNumbers = function(value)
                if value > 100000 then
                    return floor(value / 10000) .. ABBREVIATION_W
                elseif value >= 10000 then
                    return floor(value / 1000)/10 .. ABBREVIATION_W
                else
                    return tostring(value)
                end
            end
        else
            -- Other locales use a 1,000-based abbreviation suffix.
            API.AbbreviateNumbers = function(value)
                if value > 10000 then
                    return floor(value / 1000) .. ABBREVIATION_K
                elseif value > 1000 then
                    return floor(value / 100)/10 .. ABBREVIATION_K
                else
                    return tostring(value)
                end
            end
        end
    end
end

-- Table helpers for copying methods from mixins onto objects.
do  -- Table
    -- Copy all key-value pairs from the supplied mixins onto an existing object.
    local function Mixin(object, ...)
        for i = 1, select("#", ...) do
            local mixin = select(i, ...)
            for k, v in pairs(mixin) do
                object[k] = v;
            end
        end
        return object
    end
    API.Mixin = Mixin;

    -- Create a new table and populate it with the methods from the supplied mixins.
    local function CreateFromMixins(...)
        return Mixin({}, ...)
    end
    API.CreateFromMixins = CreateFromMixins;
end


-- Pixel utilities convert screen pixels and UI coordinates and update registered
-- objects when the display resolution or UI scale changes.
do  -- Pixel
    local GetPhysicalScreenSize = GetPhysicalScreenSize;
    local SCREEN_WIDTH, SCREEN_HEIGHT = GetPhysicalScreenSize();
    local UI_SCALE_RATIO = 1 / UIParent:GetEffectiveScale();

    -- Return the UI scale factor needed to represent one physical screen pixel.
    local function GetPixelPertectScale()
        return (768/SCREEN_HEIGHT)
    end
    API.GetPixelPertectScale = GetPixelPertectScale;

    -- Apply the current pixel-perfect scale to a texture slice.
    local function UpdateTextureSliceScale(textureSlice)
        --Temp Fix for 10.1.7 change
        textureSlice:SetScale(GetPixelPertectScale());
    end
    API.UpdateTextureSliceScale = UpdateTextureSliceScale;

    --if addon.IS_CATA then
        --Era 1.15.3 has this issue too
        --API.UpdateTextureSliceScale = AlwaysNil;  --4.4.1 has this issue too
    --end

    -- Convert a physical pixel size to UI coordinates for a given effective scale.
    -- If pixelSize is omitted, return the UI-coordinate size of one physical pixel.
    local function GetPixelForScale(scale, pixelSize)
        if pixelSize then
            return pixelSize * (768/SCREEN_HEIGHT)/scale
        else
            return (768/SCREEN_HEIGHT)/scale
        end
    end
    API.GetPixelForScale = GetPixelForScale;

    -- Convert a pixel size using the widget's current effective scale.
    local function GetPixelForWidget(widget, pixelSize)
        local scale = widget:GetEffectiveScale();
        return GetPixelForScale(scale, pixelSize);
    end
    API.GetPixelForWidget = GetPixelForWidget;

    -- Convert a UI size to the corresponding physical-pixel size at the supplied scale.
    local function GetSizeInPixel(scale, size)
        return size * scale / (768/SCREEN_HEIGHT)
    end
    API.GetSizeInPixel = GetSizeInPixel;

    -- Disable texture snapping options that can make rendered edges appear sharpened.
    local function DisableSharpening(texture)
        texture:SetTexelSnappingBias(0);
        texture:SetSnapToPixelGrid(false);
    end
    API.DisableSharpening = DisableSharpening;

    -- Return the viewport dimensions, limiting the width to a 16:9 aspect ratio.
    local function GetBestViewportSize()
        --WorldFrame's size is unaffected by screen resolution
        --Issue caused by occasionally bugged resolution since 11.0? https://github.com/Peterodox/YUI-Dialogue/issues/104
        local viewportWidth, viewportHeight = WorldFrame:GetSize();
        viewportWidth = math.min(viewportWidth, viewportHeight * 16/9);
        return viewportWidth, viewportHeight
    end
    API.GetBestViewportSize = GetBestViewportSize;

    -- Track UI objects that need their pixel-dependent layout refreshed.
    local PixelUtil = CreateFrame("Frame");
    addon.PixelUtil = PixelUtil;

    PixelUtil.objects = {};

    -- Add an object whose UpdatePixel method should be called when scale changes.
    function PixelUtil:AddPixelPerfectObject(object)
        table.insert(self.objects, object);
    end

    -- Mark registered objects as needing a scale refresh and schedule an update.
    function PixelUtil:MarkScaleDirty()
        self.scaleDirty = true;
        self.t = 0;
        self:SetScript("OnUpdate", self.OnUpdate);
    end
    PixelUtil:MarkScaleDirty();

    -- Recalculate pixel-dependent layout for every registered object when needed.
    function PixelUtil:RequireUpdate()
        if self.scaleDirty then
            self.scaleDirty = nil;
            local scale;

            for _, object in ipairs(self.objects) do
                scale = object:GetEffectiveScale();
                object:UpdatePixel(scale);
            end
        end
    end

    -- Debounce scale refreshes so multiple display events trigger one update.
    function PixelUtil:OnUpdate(elpased)
        self.t = self.t + elpased;
        if self.t > 0.1 then
            self.t = 0;
            self:SetScript("OnUpdate", nil);
            self:RequireUpdate();
        end
    end

    -- Recompute pixel scaling after a UI-scale or physical-display-size change.
    PixelUtil:RegisterEvent("UI_SCALE_CHANGED");
    PixelUtil:RegisterEvent("DISPLAY_SIZE_CHANGED");

    PixelUtil:SetScript("OnEvent", function(self, event, ...)
        SCREEN_WIDTH, SCREEN_HEIGHT = GetPhysicalScreenSize();
        UI_SCALE_RATIO = 1 / UIParent:GetEffectiveScale();
        self:MarkScaleDirty();
    end);


    local GetCursorPosition = GetCursorPosition;

    -- Return cursor coordinates adjusted to the current UI scale.
    local function GetScaledCursorPosition()
        local x, y = GetCursorPosition();
        return x*UI_SCALE_RATIO, y*UI_SCALE_RATIO
    end
    API.GetScaledCursorPosition = GetScaledCursorPosition;
end


-- Object pools reuse UI objects to reduce repeated creation and destruction.
-- The regular pool releases all active objects together; the dynamic pool lets
-- individual objects be recycled independently.
do  -- Object Pool
    local ObjectPoolMixin = {};
    local ipairs = ipairs;
    local tinsert = table.insert;
    local tremove = table.remove;

    -- Release every active object using the pool's configured removal handler.
    function ObjectPoolMixin:Release()
        for i, object in ipairs(self.objects) do
            if i <= self.numActive then
                self.Remove(object);
            else
                break
            end
        end
        self.numActive = 0;
    end

    -- Acquire the next sequential object, creating it if the pool has none available.
    function ObjectPoolMixin:Acquire()
        local n = self.numActive + 1;
        self.numActive = n;

        if not self.objects[n] then
            self.objects[n] = self.Create();
        end

        if self.OnAcquired then
            self.OnAcquired(self.objects[n]);
        end

        self.objects[n]:Show();

        return self.objects[n]
    end

    -- Initialize an empty pool with no active objects.
    function ObjectPoolMixin:OnLoad()
        self.numActive = 0;
        self.objects = {};
    end

    -- Call a method on each currently active object.
    function ObjectPoolMixin:CallActive(method)
        for i = 1, self.numActive do
            self.objects[i][method](self.objects[i]);
        end
    end

    -- Call a method on every object ever created by this pool.
    function ObjectPoolMixin:CallAllObjects(method, ...)
        for i, obj in ipairs(self.objects) do
            obj[method](obj, ...);
        end
    end

    -- Apply a function to each currently active object.
    function ObjectPoolMixin:ProcessActiveObjects(func)
        for i = 1, self.numActive do
            func(self.objects[i]);
        end
    end

    -- Apply a function to every object created by this pool.
    function ObjectPoolMixin:ProcessAllObjects(func)
        for i, obj in ipairs(self.objects) do
            func(obj);
        end
    end

    -- Return all pooled objects that satisfy the supplied predicate.
    function ObjectPoolMixin:GetObjectsByPredicate(pred)
        local tbl = {};
        for i, obj in ipairs(self.objects) do
            if pred(obj) then
                tinsert(tbl, obj);
            end
        end
        return tbl
    end

    -- Return a new table containing only the currently active objects.
    function ObjectPoolMixin:GetActiveObjects()
        local tbl = {};
        for i = 1, self.numActive do
            tinsert(tbl, self.objects[i]);
        end
        return tbl
    end

    -- Return an ipairs iterator over the currently active objects.
    function ObjectPoolMixin:EnumerateActive()
        local activeObjects = self:GetActiveObjects();
        return ipairs(activeObjects)
    end

    -- Default removal behavior hides an object and clears its anchor points.
    local function RemoveObject(object)
        object:Hide();
        object:ClearAllPoints();
    end

    -- Create a sequential object pool with optional removal and acquisition handlers.
    local function CreateObjectPool(createFunc, removeFunc, onAcquiredFunc)
        local pool = API.CreateFromMixins(ObjectPoolMixin);
        pool:OnLoad();
        pool.Create = createFunc;
        pool.Remove = removeFunc or RemoveObject;
        pool.OnAcquired = onAcquiredFunc;
        return pool
    end
    API.CreateObjectPool = CreateObjectPool;


    -- Dynamic pools maintain separate collections for all, active, and reusable objects.
    local DynamicPoolMixin = {};

    -- Release all active objects and rebuild the reusable-object bins.
    function DynamicPoolMixin:ReleaseAll()
        local removeFunc = self.Remove or RemoveObject;
        for obj, active in pairs(self.activeObjects) do
            if active then
                removeFunc(obj);
            end
        end
        self.activeObjects = {};
        self.bins = {};
        for i, obj in ipairs(self.allObjects) do
            self.bins[i] = obj;
        end
    end

    -- Recycle one active object by removing it from the active set and returning it to the bins.
    function DynamicPoolMixin:RecycleObject(obj)
        if self.activeObjects[obj] then
            self.activeObjects[obj] = nil;
            if self.Remove then
                self.Remove(obj);
            else
                RemoveObject(obj);
            end
        end
        tinsert(self.bins, obj);
    end

    -- Acquire a reusable object, creating one only when the bins are empty.
    function DynamicPoolMixin:Acquire()
        local obj = tremove(self.bins);
        if not obj then
            obj = self.Create();
            obj.Release = self.ReleaseObject;
            tinsert(self.allObjects, obj);
        end
        if self.OnAcquired then
            self.OnAcquired(obj);
        end
        self.activeObjects[obj] = true;
        return obj
    end

    -- Call a method on each currently active object, passing up to four arguments.
    function DynamicPoolMixin:CallActive(method, arg1, arg2, arg3, arg4)
        for obj, active in pairs(self.activeObjects) do
            obj[method](obj, arg1, arg2, arg3, arg4);
        end
    end

    -- Return a pairs iterator over the active-object set.
    function DynamicPoolMixin:EnumerateActive()
        return pairs(self.activeObjects);
    end

    -- Print total, active, and inactive object counts for debugging.
    function DynamicPoolMixin:DebugGetCount()
        local numTotal = #self.allObjects;
        local numInactive = #self.bins;
        local numActive = 0;
        for obj, active in pairs(self.activeObjects) do
            numActive = numActive + 1;
        end
        print(numTotal, numActive, numInactive);
    end

    -- Create a dynamic pool with optional removal and acquisition handlers.
    local function CreateDynamicObjectPool(createFunc, removeFunc, onAcquiredFunc)
        local pool = API.CreateFromMixins(DynamicPoolMixin);

        pool.allObjects = {};
        pool.bins = {};
        pool.activeObjects = {};

        pool.Create = createFunc;
        pool.Remove = removeFunc or RemoveObject;
        pool.OnAcquired = onAcquiredFunc;

        -- Let each acquired object release itself back into this pool.
        pool.ReleaseObject = function(obj)
            pool:RecycleObject(obj);
        end

        return pool
    end
    API.CreateDynamicObjectPool = CreateDynamicObjectPool;
end



-- String helpers for parsing text, adapting localized format strings, and resolving
-- IDs or objects from string representations.
do  -- String
    local match = string.match;
    local gmatch = string.gmatch;
    local gsub = string.gsub;

    -- Split text into non-control-character runs, omitting entries that are only a space.
    local function SplitParagraph(text)
        local tbl = {};

        if text then
            local n = 0;
            for v in gmatch(text, "[%C]+") do
                if v ~= " " then
                    n = n + 1;
                    tbl[n] = v;
                end
            end
        end

        return tbl
    end
    API.SplitParagraph = SplitParagraph;


    -- Approximate reading speed in characters per second; the result is clamped
    -- to avoid extremely short or long automatic display timings.
    local READING_CPS = 15; --Vary depends on Language
    local strlenutf8 = strlenutf8;

    -- Estimate how long the supplied text takes to read.
    local function GetTextReadingTime(text)
        local numWords = strlenutf8(text);
        return API.Clamp(numWords / READING_CPS, 2.75, 8);
    end
    API.GetTextReadingTime = GetTextReadingTime;


    -- Convert integer format placeholders to string placeholders for localized values.
    local function ReplaceRegularExpression(formatString)
        return gsub(formatString, "%%d", "%%s")
    end
    API.ReplaceRegularExpression = ReplaceRegularExpression;

    -- Update selected localized format strings to accept values formatted as text.
    do
        -- Replace numeric placeholders when a localized format requires string input.
        local function UpdateFormat(k)
            if L[k] then
                L[k] = ReplaceRegularExpression(L[k]);
            else
                print("DialogueUI Missing String:", k);
            end
        end

        UpdateFormat("Format Player XP");
        UpdateFormat("Format Gold Amount")
        UpdateFormat("Format Silver Amount")
        UpdateFormat("Format Copper Amount")
    end

    -- Extract an item ID from an item hyperlink, if the link contains one.
    local function GetItemIDFromHyperlink(link)
        local id = match(link, "[Ii]tem:(%d*)");
        if id then
            return tonumber(id)
        end
    end
    API.GetItemIDFromHyperlink = GetItemIDFromHyperlink;

    -- Resolve a dotted global object path such as "FrameName.Key1.Key2".
    local function GetGlobalObject(objNameKey)
        local obj = _G;

        for k in string.gmatch(objNameKey, "[%w_]+") do
            obj = obj[k];
            if not obj then
                return
            end
        end

        return obj
    end
    API.GetGlobalObject = GetGlobalObject;

    -- Check whether the global object path resolves to an existing value.
    local function DoesGlobalObjectExist(objNameKey)
        return GetGlobalObject(objNameKey) ~= nil
    end
    API.DoesGlobalObjectExist = DoesGlobalObjectExist;
end


-- Helpers for identifying the current NPC interaction, handling gossip closure,
-- detecting cutscenes, and querying NPC or unit identity.
do  -- NPC Interaction
    local SetUnitCursorTexture = SetUnitCursorTexture;
    local UnitExists = UnitExists;
    local UnitName = UnitName;
    local UnitGUID = UnitGUID;

    -- Temporary texture used to ask the client which interaction cursor applies to a unit.
    local f = CreateFrame("Frame");
    f.texture = f:CreateTexture();
    f.texture:SetSize(1, 1);

    -- Map recognized cursor texture values to internal interaction categories.
    local CursorTextureTypes = {
        ["Cursor Talk"] = "gossip",     --Most interactable NPC that doesn't provide quests
        [4675624] = "direction",        --Guard, asking for direction
    };

    -- Base directory for custom NPC interaction icons.
    local TexturePrefix = "Interface/AddOns/DialogueUI/Art/Icons/NPCType-";

    -- Map internal interaction categories to custom icon filename suffixes.
    local CustomTypeTexture = {
        direction = "Direction",
    };

    -- Return the cursor texture and, when recognized, its interaction category.
    local function GetInteractType(unit)
        if UnitExists(unit) then
            --Returns cursor texture (RepairNPC, Transmog, Taxi...)
            --Quest NPC (with question mark) returns nil (there is no type icon on the nameplate)
            SetUnitCursorTexture(f.texture, unit);
            local file = f.texture:GetTexture();
            return file, file and CursorTextureTypes[file]
        end
    end
    API.GetInteractType = GetInteractType;

    -- Return the addon's custom icon path for interaction types that have one.
    local function GetInteractTexture(unit)
        local _, type = GetInteractType(unit);
        if type and CustomTypeTexture[type] then
            return TexturePrefix..CustomTypeTexture[type]
        end
    end
    API.GetInteractTexture = GetInteractTexture;


    -- Determine whether the current "npc" unit token refers to a unit other than the player.
    function API.IsQuestNPCPlayer()
        if UnitExists("npc") then
            local bool = UnitIsUnit("npc", "player");
            if canaccessvalue(bool) then
                return not bool
            else
                return false
            end
        end
    end

    -- WotLK fallback: infer gossip interaction from the visibility of the standard frame.
    local function IsInteractingWithGossip()
        return GossipFrame and GossipFrame:IsShown()
    end
    API.IsInteractingWithGossip = IsInteractingWithGossip;

    -- WotLK fallback: infer quest-giver interaction from the visibility of the quest frame.
    local function IsInteractingWithQuestGiver()
        return QuestFrame and QuestFrame:IsShown()
    end
    API.IsInteractingWithQuestGiver = IsInteractingWithQuestGiver;

    -- Report an active dialog interaction when an NPC exists and a gossip or quest frame is visible.
    local function IsInteractingWithDialogNPC()
        return UnitExists("npc") and (IsInteractingWithGossip() or IsInteractingWithQuestGiver() or (GossipFrame and GossipFrame:IsShown()) or (QuestFrame and QuestFrame:IsShown()))
    end
    API.IsInteractingWithDialogNPCC = IsInteractingWithDialogNPC;

    -- In WotLK, gossip closure is requested through the global CloseGossip function.
    local CloseGossip = CloseGossip;

    -- Finish a deferred gossip-close operation on the next update.
    local function ResetCloseStatus(self, elapsed)
        self.isClosing = false;
        self:SetScript("OnUpdate", nil);
        if f.closeInteraction then
            CloseGossip();
        end
    end

    -- Schedule gossip closure for the next update, allowing other code to cancel it first.
    local function CloseGossipInteraction()
        f.closeInteraction = true;
        if not f.isClosing then
            f.isClosing = true;
            f:SetScript("OnUpdate", ResetCloseStatus);
        end
    end
    API.CloseGossipInteraction = CloseGossipInteraction;

    -- Cancel a previously scheduled gossip closure if it has not executed yet.
    local function CancelClosingGossipInteraction()
        if f.isClosing then
            f.closeInteraction = false;
        end
    end
    API.CancelClosingGossipInteraction = CancelClosingGossipInteraction;


    -- Listen for cinematic and movie events and expose cutscene state to addon callbacks.
    local CGListener = CreateFrame("Frame");
    do
        -- Check whether either of the standard cinematic or movie frames is currently visible.
        local function IsPlayingCutscene()
            if (not CGListener.CinematicFrame) and CinematicFrame then
                CGListener.CinematicFrame = CinematicFrame;
            end

            if (not CGListener.MovieFrame) and MovieFrame then
                CGListener.MovieFrame = MovieFrame;
            end

            if (CGListener.CinematicFrame and CGListener.CinematicFrame:IsShown()) or (CGListener.MovieFrame and CGListener.MovieFrame:IsShown()) then
                --Cinematic played upon loading screen finished doesn't trigger events due to loading order? 11.1.0 Undermine
                return true
            else
                return false
            end
        end
        API.IsPlayingCutscene = IsPlayingCutscene;


        -- Register cinematic and movie lifecycle events.
        CGListener:RegisterEvent("CINEMATIC_START");
        CGListener:RegisterEvent("CINEMATIC_STOP");
        CGListener:RegisterEvent("PLAY_MOVIE");
        CGListener:RegisterEvent("STOP_MOVIE");
        --CGListener:RegisterEvent("LOADING_SCREEN_DISABLED");

        -- Schedule a one-frame-delayed check of the cinematic and movie frame visibility.
        function CGListener:CheckStatus()
            self:SetScript("OnUpdate", self.OnUpdate_CheckStatus);
        end

        -- Check the cutscene state on the next update and notify listeners if playback is active.
        function CGListener:OnUpdate_CheckStatus(elapsed)
            self:SetScript("OnUpdate", nil);
            self.isPlayingCutscene = IsPlayingCutscene();
            if self.isPlayingCutscene then
                CallbackRegistry:Trigger("PlayCutscene");
            end
        end

        -- Suppress duplicate cutscene notifications until the pause flag is cleared next frame.
        function CGListener:PauseUpdate()
            self.paused = true;
            self:SetScript("OnUpdate", self.OnUpdate_PauseUpdate);
        end

        -- Clear the temporary cutscene-notification pause on the next update.
        function CGListener:OnUpdate_PauseUpdate(elapsed)
            self:SetScript("OnUpdate", nil);
            self.paused = nil;
        end

        -- Notify registered listeners once when a cinematic or movie starts.
        CGListener:SetScript("OnEvent", function(self, event, ...)
            --self:CheckStatus();
            if event == "CINEMATIC_START" or event == "PLAY_MOVIE" then
                if not self.paused then
                    self:PauseUpdate();
                    CallbackRegistry:Trigger("PlayCutscene");
                end
            end
        end);
    end


    -- Register a callback to be invoked when cinematic or movie playback starts.
    local function SetPlayCutsceneCallback(callback)
        CallbackRegistry:Register("PlayCutscene", callback);
    end
    API.SetPlayCutsceneCallback = SetPlayCutsceneCallback;


    -- Model-size evaluation helpers and actors used by clients that support ModelScene.
    local ModelScene, NPCActor, MountActor, CameraController;
    --local IsUnitModelReadyForUI = IsUnitModelReadyForUI;


    -- Expose model actor callbacks used by the utility ModelScene template.
    DUIUtilityActorMixin = {};

    -- These methods are stubs for WotLK clients, where ModelScene evaluation is unavailable.
    function DUIUtilityActorMixin:EvaluateNPCHeight()
        -- Stub for 3.3.5a
    end

    -- Return the mount scale after model loading on clients that implement this method.
    function DUIUtilityActorMixin:GetMountScale()
        -- Stub for 3.3.5a
    end

    -- Forward model-load completion to the callback registered on this actor.
    function DUIUtilityActorMixin:OnModelLoaded()
        if self.onModelLoadedCallback then
            self.onModelLoadedCallback(self);
        end
    end

    -- Provide a safe WotLK fallback for NPC-size evaluation.
    local function EvaluateNPCSize()
        -- ModelScene not available in 3.3.5a
        return false;
    end
    API.EvaluateNPCSize = EvaluateNPCSize;

    -- Provide a safe WotLK fallback for mount-scale evaluation.
    local function EvaluateMountScale(mountID)
        -- Not supported in 3.3.5a
    end
    API.EvaluateMountScale = EvaluateMountScale;

    -- Reference scale measurements used by model-size evaluation on supported clients.
    --0.8, 1.0, 1.6: Goblin
    --0.9, 1.1, 2.1: Human
    --1.1, 1.3, 1.7: Dwarf
    --0.9, 1.2, 2.5: NElf M
    --0.8, 0.8, 2.1: VElf F
    --0.5, 0.8, 1.1: Gnome
    --3.2, 2.0, 2.9: Malicia
    --3.8, 3.5, 5.2: Draknoid
    --2.9, 5.1, 7.7: Watcher Koranos
    --30, 20, 14:    Dragon Aspect

    -- Create a small, reusable ModelScene frame when model inspection is supported.
    local function CreateModelScene()
        if not ModelScene then
            ModelScene = CreateFrame("ModelScene");
            ModelScene:SetSize(1, 1);
        end
    end

    -- Load the specified unit into a ModelScene actor for size evaluation.
    local function EvaluateUnitSize(unit)
        CreateModelScene();

        if API.ShouldUnitIdentityBeSecret(unit) then
            return false
        end

        if not NPCActor then
            NPCActor = ModelScene:CreateActor(nil, "DUIUtilityActorTemplate");
            NPCActor.onModelLoadedCallback = NPCActor.EvaluateNPCHeight;
        end

        NPCActor:SetModelByUnit(unit);
        return true
    end

    -- Evaluate the current NPC unit's model size.
    local function EvaluateNPCSize()
        return EvaluateUnitSize("npc");
    end
    API.EvaluateNPCSize = EvaluateNPCSize;


    -- Load the player's model and mount model to evaluate their relative scale.
    local function EvaluateMountScale(mountID)
        CreateModelScene();

        if not MountActor then
            MountActor = ModelScene:CreateActor(nil, "DUIUtilityActorTemplate");
            MountActor.onModelLoadedCallback = MountActor.GetMountScale;
        end

        if not PlayerActor then
            PlayerActor = ModelScene:CreateActor(nil, "DUIUtilityActorTemplate");
            PlayerActor.onModelLoadedCallback = function() print("LOADED") end;
        end

        local hasAlternateForm, inAlternateForm = C_PlayerInfo.GetAlternateFormInfo();
        local sheatheWeapon = true;
        local autodress = false;
        local hideWeapon = true;
        local useNativeForm = not inAlternateForm;
        PlayerActor:SetScale(1);

        local result = PlayerActor:SetModelByUnit("player", sheatheWeapon, autodress, hideWeapon, useNativeForm);
        if result then
            local creatureDisplayID, _, _, isSelfMount, _, modelSceneID, animID, spellVisualKitID, disablePlayerMountPreview = C_MountJournal.GetMountInfoExtraByID(mountID);
            MountActor.mountName = C_MountJournal.GetMountInfoByID(mountID);
            local showCustomization = true;
            MountActor:ClearModel();
            MountActor:SetModelByCreatureDisplayID(creatureDisplayID, showCustomization);
        end
    end
    API.EvaluateMountScale = EvaluateMountScale;

    -- Store the camera controller used by other addon components.
    local function SetCameraController(controller)
        CameraController = controller;
    end
    addon.SetCameraController = SetCameraController;


    local match = string.match;

    -- Parse a creature, vehicle, or game-object ID from a GUID string.
    local function GetCreatureIDFromGUID(guid)
        --Including Creature, Vehicle, GameObject
        if not canaccessvalue(guid) then return end;

        local id = guid and match(guid, "^%a+%-0%-%d*%-%d*%-%d*%-(%d*)");
        if id then
            return tonumber(id)
        end
    end
    API.GetCreatureIDFromGUID = GetCreatureIDFromGUID;

    -- Return the current NPC's accessible name and its creature ID, when available.
    local function GetCurrentNPCInfo()
        local name = UnitName("npc");
        local creatureID = GetCreatureIDFromGUID(UnitGUID("npc"));
        if creatureID then
            name = canaccessvalue(name) and name or "";
            return name, creatureID
        end
    end
    API.GetCurrentNPCInfo = GetCurrentNPCInfo;

    -- Parse and return the unit type and ID from a unit GUID.
    local function GetUnitTypeAndID(unit)
        unit = unit or "npc";
        local guid = UnitGUID("npc");
        if not canaccessvalue(guid) then return end;
        if guid then
            local unitType, id = match(guid, "^(%a+)%-0%-%d*%-%d*%-%d*%-(%d*)");
            if unitType and id then
                return unitType, tonumber(id)
            end
        end
    end
    API.GetUnitTypeAndID = GetUnitTypeAndID;

    -- NPC IDs treated as interaction objects rather than ordinary dialog characters.
    local SkippedNPC = {
        [94398] = true,     --Fleet Command Table
        [94399] = true,     --Fleet Command Table
        [138704] = true,    --Mission Command Table
        [138706] = true,    --Mission Command Table
        [147244] = true,    --Mission Command Table
        [215758] = true,    --Mission Command Table
    };

    -- Identify whether the current interaction is with a game object, vehicle, or listed special NPC.
    local function IsInteractingWithGameObject()
        local unitType, id = GetUnitTypeAndID("npc");
        if id then
            if unitType == "GameObject" or unitType == "Vehicle" then
                return true
            elseif unitType == "Creature" and id then
                id = tonumber(id) or 0;
                return SkippedNPC[id]
            end
        end
    end
    API.IsInteractingWithGameObject = IsInteractingWithGameObject;

    -- Localized default label used to recognize the scouting-map NPC.
    local SCOUTING_MAP = ADVENTURE_MAP_TITLE or "Scouting Map";
    local UnitClass = UnitClass;

    -- Check whether the current NPC's class/name label identifies it as the scouting map.
    local function IsTargetAdventureMap()
        local className = UnitClass("npc");
        return className == SCOUTING_MAP
    end
    API.IsTargetAdventureMap = IsTargetAdventureMap;
end


-- Easing functions map elapsed animation time to an interpolated value.
-- Parameters are t (elapsed time), b (start value), e (end value), and d (duration).
do  -- Easing
    local EasingFunctions = {};
    addon.EasingFunctions = EasingFunctions;


    local sin = math.sin;
    local cos = math.cos;
    local pow = math.pow;
    local pi = math.pi;

    --t: total time elapsed
    --b: beginning position
    --e: ending position
    --d: animation duration

	-- Interpolate at a constant rate from the start value to the end value.
    function EasingFunctions.linear(t, b, e, d)
        return (e - b) * t / d + b
    end

	-- Interpolate toward the end value with a sine-based ease-out curve.
    function EasingFunctions.outSine(t, b, e, d)
        return (e - b) * sin(t / d * (pi / 2)) + b
    end

	-- Interpolate with a sine curve that eases both into and out of the transition.
    function EasingFunctions.inOutSine(t, b, e, d)
        return -(e - b) / 2 * (cos(pi * t / d) - 1) + b
    end

	-- Interpolate toward the end value with a quartic ease-out curve.
    function EasingFunctions.outQuart(t, b, e, d)
        t = t / d - 1;
        return (b - e) * (pow(t, 4) - 1) + b
    end

	-- Interpolate toward the end value with a quintic ease-out curve.
    function EasingFunctions.outQuint(t, b, e, d)
        t = t / d
        return (b - e)* (pow(1 - t, 5) - 1) + b
    end

	-- Interpolate from the start value with a quadratic ease-in curve.
    function EasingFunctions.inQuad(t, b, e, d)
        t = t / d
        return (e - b) * pow(t, 2) + b
    end

	-- Return the end value immediately, without interpolation.
    function EasingFunctions.none(t, b, e, d)
        return e
    end

	-- Keep the start value unchanged for the full duration.
    function EasingFunctions.noChange(t, b, e, d)
        return b
    end
end

--------------------------------------------------------------------------------
-- Compatibility shim for C_QuestLog in WotLK 3.3.5a
--------------------------------------------------------------------------------
-- Provide a limited C_QuestLog-compatible interface using the legacy WotLK quest-log APIs.
-- These wrappers can only return information available from the player's current quest log.
if not C_QuestLog then
    C_QuestLog = {};

    -- Check whether a quest ID currently has an entry in the player's quest log.
    C_QuestLog.IsOnQuest = function(questID)
        if not questID then return false; end
        if GetQuestLogIndexByID then
            local index = GetQuestLogIndexByID(questID);
            return index and index > 0;
        end
        return false;
    end;

    -- Return a conservative false value because WotLK has no equivalent trivial-quest query here.
    C_QuestLog.IsQuestTrivial = function(questID)
        return false;
    end;

   	-- Return the title for a quest currently present in the quest log, or an empty string if unavailable.
    C_QuestLog.GetTitleForQuestID = function(questID)
        if not questID then return ""; end
        if GetQuestLogIndexByID then
            local index = GetQuestLogIndexByID(questID);
            if index and index > 0 then
                local title = GetQuestLogTitle(index);
                return title;
            end
        end
        return "";
    end;

   	-- Forward the legacy quest-log entry counts, or return zero counts if the function is unavailable.
	C_QuestLog.GetNumQuestLogEntries = function()
        if GetNumQuestLogEntries then
            return GetNumQuestLogEntries();
        end
        return 0, 0;
    end;

    -- Extract the quest ID from the legacy quest-log title API's return values.
    C_QuestLog.GetQuestIDForLogIndex = function(index)
        if GetQuestLogTitle then
            local _, _, _, _, _, _, _, questID = GetQuestLogTitle(index);
            return questID or 0;
        end
        return 0;
    end;

    -- Adapt legacy quest-log title values into a table shaped like modern C_QuestLog.GetInfo results.
	C_QuestLog.GetInfo = function(index)
        if GetQuestLogTitle then
            local title, level, questTag, suggestedGroup, isHeader, isComplete, frequency, questID = GetQuestLogTitle(index);
            if not title then return nil; end
            return {
                title = title,
                level = level,
                isHeader = isHeader,
                isComplete = isComplete,
                frequency = frequency,
                questID = questID,
                isHidden = false,
            };
        end
        return nil;
    end;

	
	
    -- Stub modern quest features that cannot be determined by the WotLK 3.3.5a quest-log API.
	C_QuestLog.IsAccountQuest = AlwaysFalse;
    C_QuestLog.GetQuestTagInfo = AlwaysFalse;
    C_QuestLog.GetQuestDetailsTheme = AlwaysFalse;
    C_QuestLog.IsWorldQuest = AlwaysFalse;
    C_QuestLog.IsQuestTask = AlwaysFalse;

	-- HINT: Add these wrappers to the C_QuestLog compatibility setup.
	-- The legacy watch functions use quest-log indices, while callers pass quest IDs.
	local LegacyIsQuestWatched = IsQuestWatched;
	local LegacyAddQuestWatch = AddQuestWatch;
	local LegacyRemoveQuestWatch = RemoveQuestWatch;

	if not C_QuestLog.GetQuestWatchType then
    	C_QuestLog.GetQuestWatchType = function(questID)
        	local index = GetQuestLogIndexByID and GetQuestLogIndexByID(questID);
        	if index and index > 0 and LegacyIsQuestWatched
            	and LegacyIsQuestWatched(index) then
            	return 1; -- Any non-nil value indicates that the quest is watched.
        	end
    	end;
	end

	if not C_QuestLog.AddQuestWatch then
    	C_QuestLog.AddQuestWatch = function(questID)
        	local index = GetQuestLogIndexByID and GetQuestLogIndexByID(questID);
        	if index and index > 0 and LegacyAddQuestWatch then
            	return LegacyAddQuestWatch(index);
        	end
    	end;
	end

	if not C_QuestLog.RemoveQuestWatch then
    	C_QuestLog.RemoveQuestWatch = function(questID)
        	local index = GetQuestLogIndexByID and GetQuestLogIndexByID(questID);
        	if index and index > 0 and LegacyRemoveQuestWatch then
            	return LegacyRemoveQuestWatch(index);
        	end
    	end;
	end
end

-- Collect quest-related APIs and provide shared helpers for quest state, rewards,
-- display metadata, localization, and quest-log navigation.
do  -- Quest
    local ICON_PATH = "Interface/AddOns/DialogueUI/Art/Icons/";
    local Enum_QuestClassification = CopyEnum("QuestClassification");

	-- Cache native functions when present and substitute safe fallbacks for APIs
	-- that are unavailable on the current client.
    local QuestGetAutoAccept = QuestGetAutoAccept or AlwaysFalse;
    local C_QuestLog = C_QuestLog;
    local IsOnQuest = C_QuestLog.IsOnQuest;
    local GetQuestReward = GetQuestReward;
    local ReadyForTurnIn = C_QuestLog.ReadyForTurnIn or IsQuestComplete or AlwaysFalse;
    local QuestIsFromAreaTrigger = QuestIsFromAreaTrigger or AlwaysFalse;
    local GetSuggestedGroupSize = GetSuggestedGroupSize or AlwaysZero;
    local IsQuestTrivial = C_QuestLog.IsQuestTrivial or AlwaysFalse;
    local IsCampaignQuest = (C_CampaignInfo and C_CampaignInfo.IsCampaignQuest) or AlwaysFalse;
    local IsQuestTask = C_QuestLog.IsQuestTask or AlwaysFalse;
    local IsWorldQuest = C_QuestLog.IsWorldQuest or AlwaysFalse;
    local GetRewardSkillPoints = GetRewardSkillPoints or AlwaysFalse;
    local GetRewardArtifactXP = GetRewardArtifactXP or AlwaysZero;
    local QuestCanHaveWarModeBonus = C_QuestLog.QuestCanHaveWarModeBonus or AlwaysFalse;
    local QuestHasQuestSessionBonus = C_QuestLog.QuestHasQuestSessionBonus or AlwaysFalse;
    local GetQuestItemInfoLootType = GetQuestItemInfoLootType or AlwaysZero;
    local GetTitleForQuestID = C_QuestLog.GetTitleForQuestID or C_QuestLog.GetQuestInfo or AlwaysFalse;
    local GetQuestTimeLeftSeconds = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftSeconds or AlwaysNil;
    local IsQuestFlaggedCompletedOnAccount = C_QuestLog.IsQuestFlaggedCompletedOnAccount or AlwaysFalse;
    local GetLogIndexForQuestID = C_QuestLog.GetLogIndexForQuestID or GetQuestLogIndexByID or AlwaysNil;
    local GetNumQuestLeaderBoards = GetNumQuestLeaderBoards;
    local GetQuestLogLeaderBoard = GetQuestLogLeaderBoard;
    local GetQuestClassification = C_QuestInfoSystem.GetQuestClassification or AlwaysNil;
    local IsAccountQuest = C_QuestLog.IsAccountQuest or AlwaysFalse;

    API.IsQuestFlaggedCompletedOnAccount = IsQuestFlaggedCompletedOnAccount;
    API.ReadyForTurnIn = ReadyForTurnIn;

    -- Return whether the player has the specified quest ID in the quest log.
	local function IsPlayerOnQuest(questID)
        if questID then
            return IsOnQuest(questID)
        end
    end
    API.IsPlayerOnQuest = IsPlayerOnQuest;

    if AcknowledgeAutoAcceptQuest then
        API.AcknowledgeAutoAcceptQuest = AcknowledgeAutoAcceptQuest;
    else    --Classic
        API.AcknowledgeAutoAcceptQuest = AcceptQuest;
    end

   	local GetQuestCurrency;

    if C_QuestOffer and C_QuestOffer.GetQuestRewardCurrencyInfo then
        local GetQuestRequiredCurrencyInfo = C_QuestOffer.GetQuestRequiredCurrencyInfo;
        local GetQuestRewardCurrencyInfo = C_QuestOffer.GetQuestRewardCurrencyInfo;

		-- Select the quest-currency API available on this client and normalize its fields
		-- so downstream UI code can use a consistent displayed-amount value.
        function GetQuestCurrency(questInfoType, index)
            --Unifiy two APIs and their payload structures:
            --"duiDisplayedAmount" for displaying the ItemCount

            local tbl;

            if questInfoType == "reward" or questInfoType == "choice" then
                tbl = GetQuestRewardCurrencyInfo(questInfoType, index);
                tbl.duiDisplayedAmount = tbl.totalRewardAmount;
            elseif questInfoType == "required" then
                tbl = GetQuestRequiredCurrencyInfo(index);
                tbl.duiDisplayedAmount = tbl.requiredAmount;
            end

            return tbl
        end
    else
        local GetQuestCurrencyInfo = GetQuestCurrencyInfo;
        local GetQuestCurrencyID = GetQuestCurrencyID;
		
		-- Normalize modern and legacy quest-currency APIs into one result-table format.
        function GetQuestCurrency(questInfoType, index)
            local name, texture, amount, quality = GetQuestCurrencyInfo(questInfoType, index)
            local currencyID = GetQuestCurrencyID(questInfoType, index);

            local tbl = {
                texture = texture,
                name = name,
                currencyID = currencyID,
                quality = quality or 0,
                baseRewardAmount = amount,
                bonusRewardAmount = 0,
                totalRewardAmount = amount,
                questRewardContextFlags = nil,
                requiredAmount = 0,
                duiDisplayedAmount = amount;
            };

            return tbl
        end
    end
    API.GetQuestCurrency = GetQuestCurrency;

	-- Build a readable list of objective progress strings for a quest in the quest log.
    local function GetQuestLogProgress(questID)
        local questLogIndex = GetLogIndexForQuestID(questID);
        if questLogIndex then
            local numObjectives = GetNumQuestLeaderBoards(questLogIndex);
            if numObjectives > 0 then
                local str;
                local text, objectiveType, finished;
                local n = 0;
                for i = 1, numObjectives do
                    text, objectiveType, finished = GetQuestLogLeaderBoard(i, questLogIndex);
                    if text then
                        if str then
                            str = str.."\n".."- "..text;
                        else
                            str = "- "..text;
                        end
                    end
                end
                return str
            end
        end
    end
    API.GetQuestLogProgress = GetQuestLogProgress;

    --Classic
    API.QuestGetAutoAccept = QuestGetAutoAccept;
    API.QuestIsFromAreaTrigger = QuestIsFromAreaTrigger;
    API.GetSuggestedGroupSize = GetSuggestedGroupSize;
    API.GetRewardSkillPoints = GetRewardSkillPoints;
    API.GetRewardArtifactXP = GetRewardArtifactXP;
    API.QuestCanHaveWarModeBonus = QuestCanHaveWarModeBonus;
    API.QuestHasQuestSessionBonus = QuestHasQuestSessionBonus;
    API.GetQuestItemInfoLootType = GetQuestItemInfoLootType;
    API.GetTitleForQuestID = GetTitleForQuestID;
    API.IsAccountQuest = IsAccountQuest;
    API.GetLogIndexForQuestID = GetLogIndexForQuestID;

    if GetAvailableQuestInfo then
        API.GetAvailableQuestInfo = GetAvailableQuestInfo;
    else
        API.GetAvailableQuestInfo = function()
            return false, 1, false, false, 0
        end
    end

    if GetActiveQuestID then
        API.GetActiveQuestID = GetActiveQuestID;
    else
        API.GetActiveQuestID = function()
            return 0
        end
    end

	-- Claim the selected quest reward and notify listeners that quest completion was triggered.
    local function CompleteCurrentQuest(rewardChoiceID, isAutoComplete)
        rewardChoiceID = rewardChoiceID or 0;
        GetQuestReward(rewardChoiceID);
        CallbackRegistry:Trigger("TriggerQuestFinished", isAutoComplete);   --In some cases game doesn't fire QUEST_FINISHED after completing a quest?
    end
    API.CompleteCurrentQuest = CompleteCurrentQuest;

    local QuestMixin = {};
    do
        -- Refresh classification and trivial-quest state on an existing quest-info object.
		function QuestMixin:Refresh()
            self.classification = GetQuestClassification(self.questID) or -1;
            self.isTrivial = IsQuestTrivial(self.questID);
        end
    end

	-- Fill missing quest metadata and derive display flags from the available quest information.
    local function BuildQuestInfo(questInfo)
        questInfo.Refresh = QuestMixin.Refresh;

        local class = GetQuestClassification(questInfo.questID) or -1;
        questInfo.classification = class;

        if questInfo.isOnQuest == nil then
            questInfo.isOnQuest = IsOnQuest(questInfo.questID);
        end

        if not questInfo.isComplete then     --Classic Shenanigans
            questInfo.isComplete = ReadyForTurnIn(questInfo.questID);
        end

        if questInfo.isCampaign == nil then
            questInfo.isCampaign = IsCampaignQuest(questInfo.questID);  --QuestMixin uses C_CampaignInfo.GetCampaignID() ~= 0. Wonder what's the difference here;
        end

        if questInfo.isLegendary == nil then
            questInfo.isLegendary = class == Enum_QuestClassification.Legendary;
        end

        if questInfo.isImportant == nil then
            questInfo.isImportant = class == Enum_QuestClassification.Important;
        end

        if questInfo.isTrivial == nil then
            questInfo.isTrivial  = IsQuestTrivial(questInfo.questID);   --May not get the correct value during the first call
        end

        if questInfo.frequency == nil then
            --frequency may be inaccurate?
            questInfo.frequency = 0;
        end

        if not questInfo.isMeta then
            questInfo.isMeta = class == Enum_QuestClassification.Meta;
        end

        if questInfo.frequency == 2 then
            questInfo.isWeekly = true;
        end

        if questInfo.frequency == 1 then
            questInfo.isDaily = true;
        end

        if questInfo.isAccountQuest == nil then
            questInfo.isAccountQuest = IsAccountQuest(questInfo.questID);
        end

        return questInfo
    end
    API.BuildQuestInfo = BuildQuestInfo;

	-- Select the addon icon representing a quest's availability, completion, type, and frequency.
    local function GetQuestIcon(questInfo)
        --QuestMapLogTitleButton_OnEnter

        if not questInfo then
            return ICON_PATH.."IncompleteQuest.png";
        end

        local file;

        if questInfo.isOnQuest then
            if questInfo.isComplete then
                if questInfo.isCampaign then
                    file = "CompleteCampaignQuest.png";
                elseif questInfo.isLegendary then
                    file = "CompleteLegendaryQuest.png";
                elseif questInfo.isImportant then
                    file = "CompleteImportantQuest.png";
                else
                    file = "CompleteQuest.png";
                end
            else
                if questInfo.isCampaign then
                    file = "IncompleteCampaignQuest.png";
                elseif questInfo.isLegendary then
                    file = "IncompleteLegendaryQuest.png";
                elseif questInfo.isImportant then
                    file = "IncompleteImportantQuest.png";
                elseif questInfo.isMeta then
                    file = "IncompleteMetaQuest.png";
                else
                    file = "IncompleteQuest.png";
                end
            end

        else
            if questInfo.frequency == 1 then    --Enum.QuestFrequency.Daily
                file = "DailyQuest.png";
            elseif questInfo.frequency == 2 then    --Enum.QuestFrequency.Weekly
                file = "WeeklyQuest.png";
            elseif questInfo.frequency == 3 and not questInfo.isMeta then   ----Enum.QuestFrequency.ResetByScheduler
                file = "RepeatableScheduler.png";    --TWW
            elseif  questInfo.repeatable then
                file = "RepeatableQuest.png";
            else
                if questInfo.isCampaign then
                    file = "AvailableCampaignQuest.png";
                elseif questInfo.isLegendary then
                    file = "AvailableLegendaryQuest.png";
                elseif questInfo.isImportant then
                    file = "AvailableImportantQuest.png";
                elseif questInfo.isMeta then
                    file = "AvailableMetaQuest.png";
                else
                    file = "AvailableQuest.png";
                end
            end
        end

        return ICON_PATH..file
    end
    API.GetQuestIcon = GetQuestIcon;

	-- Return whether the current quest is configured for automatic acceptance.
    local function IsQuestAutoAccepted()
        return QuestGetAutoAccept()
    end
    API.IsQuestAutoAccepted = IsQuestAutoAccepted;

	-- Suppress the accepted-quest alert for quests classified as both world quests and tasks.
    local function ShouldShowQuestAcceptedAlert(questID)
        return not (IsWorldQuest(questID) and IsQuestTask(questID));
    end
    API.ShouldShowQuestAcceptedAlert = ShouldShowQuestAcceptedAlert;

    local GetDetailText = GetQuestText;
    local GetProgressText = GetProgressText;
    local GetRewardText = GetRewardText;
    local GetGreetingText = GetGreetingText;
    local GetGossipText = C_GossipInfo.GetText;

    local QuestTextMethod = {
        Detail = GetDetailText,
        Progress = GetProgressText,
        Complete = GetRewardText,
        Greeting = GetGreetingText,
    };

    API.GetGossipText = GetGossipText;

	-- Return the text associated with a quest-dialog stage when non-empty.
    local function GetQuestText(method)
        local text = QuestTextMethod[method]();
        if text and text ~= "" then
            return text
        end
    end
    API.GetQuestText = GetQuestText;

    if C_QuestInfoSystem.GetQuestRewardCurrencies then
        local GetQuestRewardCurrencies = C_QuestInfoSystem.GetQuestRewardCurrencies;

		-- Count reward currencies using the modern quest-offer API.
        local function GetNumRewardCurrencies_TWW(questID)
            local currencyRewards = GetQuestRewardCurrencies(questID) or {};
            return #currencyRewards
        end
        API.GetNumRewardCurrencies = GetNumRewardCurrencies_TWW;
    else
        local GetNumRewardCurrencies_Deprecated = GetNumRewardCurrencies;
        API.GetNumRewardCurrencies = GetNumRewardCurrencies_Deprecated;
    end


    --QuestTheme
    local GetQuestDetailsTheme = C_QuestLog.GetQuestDetailsTheme or AlwaysFalse;
    local DECOR_PATH = "Interface/AddOns/DialogueUI/Art/ParchmentDecor/";
    local BackgroundDecors = {
        ["QuestBG-Dragonflight"] = "Dragonflight.png",
        ["QuestBG-Azurespan"] = "Dragonflight.png",
        ["QuestBG-EmeraldDream"] = "Dragonflight-Green.png",
        ["QuestBG-Ohnplains"] = "Dragonflight-Green.png",
        ["QuestBG-Thaldraszus"] = "Dragonflight-Bronze.png",
        ["QuestBG-Walkingshore"] = "Dragonflight-Red.png",
        ["QuestBG-ZaralekCavern"] = "Dragonflight.png",
        ["QuestBG-ExilesReach"] = "Dragonflight.png",

        ["QuestBG-Alliance"] = "Alliance.png",
        ["QuestBG-Horde"] = "Horde.png",

        ["QuestBG-Flame"] = "TWW-Flame.png",
        ["QuestBG-Candle"] = "TWW-Candle.png",
        ["QuestBG-Storm"] = "TWW-Storm.png",
        ["QuestBG-Web"] = "TWW-Web.png",
        ["QuestBG-1027"] = "TWW-Azeroth.png",
        ["QuestBG-Rocket"] = "TWW-Rocket.png",
        ["QuestBG-Fist"] = "TWW-Fist.png",

        ["QuestBG-Sky"] = "MID-DarkHeart.png",
    };

	-- Return a localized background-decor asset for a quest theme, when one is mapped.
    local function GetQuestBackgroundDecor(questID)
        local theme = GetQuestDetailsTheme(questID);
        if theme then
            --print(theme.background);
        end
        --theme = {background = "QuestBG-Test"};    --debug
        if theme and theme.background and BackgroundDecors[theme.background] then
            return DECOR_PATH..BackgroundDecors[theme.background]
        end
    end
    API.GetQuestBackgroundDecor = GetQuestBackgroundDecor;


    local MAX_QUESTS;
    local GetNumQuestLogEntries = C_QuestLog.GetNumQuestLogEntries;
    local GetQuestIDForLogIndex = C_QuestLog.GetQuestIDForLogIndex;
    local GetQuestInfo = C_QuestLog.GetInfo;

	-- Estimate remaining quest-log capacity by counting visible, non-header quests
	-- that are not account-wide quests. The result is approximate.
    local function GetNumQuestCanAccept()
        --*Unreliable
        --numQuests include all types of quests.
        --(Account/Daily) quests don't count towards MaxQuest(35)
        if not MAX_QUESTS then
            MAX_QUESTS = C_QuestLog.GetMaxNumQuestsCanAccept();
        end

        local numShownEntries, numAllQuests = GetNumQuestLogEntries();
        local numQuests = 0;
        local questID;
        local n = 0;
        print("numShownEntries", numShownEntries);

        for i = 1, numShownEntries do
            questID = GetQuestIDForLogIndex(i);
            if questID ~= 0 then
                local info = GetQuestInfo(i);

                if info and not (info.isHidden or info.isHeader) then
                    if not (IsAccountQuest(questID)) then
                        numQuests = numQuests + 1;

                        print(numQuests, questID, info.title)
                    end
                end
            end
        end

        print("Num Quests:", numQuests);
        return MAX_QUESTS - numQuests, MAX_QUESTS
    end

    local GetItemInfoInstant = C_Item.GetItemInfoInstant;
    local select = select;

	-- Classify an item as a quest item or a possible quest item using its item class.
    local function IsQuestLoreItem(item)
        --Display lore text (QuestItemDisplay)
        if not item then return end;
        local classID, subclassID = select(6, GetItemInfoInstant(item));
        --print(item, classID, subclassID)
        local isQuestItem = classID == 12;
        local isPotentialQuestItem = (classID == 0 and subclassID == 8) or (classID == 15 and subclassID == 4);
        return isQuestItem, isPotentialQuestItem;
    end
    API.IsQuestLoreItem = IsQuestLoreItem;

    -- Check whether an item belongs to the quest-item class.
	local function IsQuestRequiredItem(item)
        --Don't show item count in bag if ItemType == 12
        if not item then return end;
        local classID, subclassID = select(6, GetItemInfoInstant(item));
        return classID == 12
    end
    API.IsQuestRequiredItem = IsQuestRequiredItem;

	-- Resolve a quest name from whichever task, quest-log, or compatibility API is available.
    local function GetQuestName(questID)
        local questName = C_TaskQuest.GetQuestInfoByQuestID(questID);
        if not questName then
            --Retail
            if C_QuestLog.GetTitleForQuestID then
                questName = C_QuestLog.GetTitleForQuestID(questID);
                if questName and questName ~= "" then
                    return questName
                else
                    C_QuestLog.RequestLoadQuestByID(questID);
                end
            end

            --Classic
            if GetQuestLogIndexByID then
                local questIndex = GetQuestLogIndexByID(questID);
                if questIndex and questIndex > 0 then
                    questName = GetQuestLogTitle(questIndex);
                else
                    questName = C_QuestLog.GetQuestInfo(questID);
                end
            end
        end
        return questName
    end
    API.GetQuestName = GetQuestName;

    local HoldableItems = {
        INVTYPE_WEAPON = true,
        INVTYPE_2HWEAPON = true,
        INVTYPE_SHIELD = true,
        INVTYPE_HOLDABLE = true,
        INVTYPE_RANGED = true,
        INVTYPE_RANGEDRIGHT = true,
        INVTYPE_WEAPONMAINHAND = true,
        INVTYPE_WEAPONOFFHAND = true,
    };

    local NoUseTransmogSkin = {
        INVTYPE_HEAD = true,
        INVTYPE_HAND = true,
        --INVTYPE_FEET = true,
    };

    local TransmogSetupGear = {
        INVTYPE_HEAD = {78420},
        INVTYPE_HAND = {78420, 78425},
    };

	-- Check whether an item uses a weapon or off-hand-style equipment slot.
    local function IsHoldableItem(item)
        if item then
            local _, _, _, itemEquipLoc = GetItemInfoInstant(item);
            return HoldableItems[itemEquipLoc];
        end
    end
    API.IsHoldableItem = IsHoldableItem;

	-- Return transmog-preview options for the item's equipment slot.
    local function GetTransmogSetup(item)
        local _, _, _, itemEquipLoc = GetItemInfoInstant(item);
        local useTransmogSkin = not (NoUseTransmogSkin[itemEquipLoc] or false);
        local setupGear = TransmogSetupGear[itemEquipLoc];
        return useTransmogSkin, setupGear
    end
    API.GetTransmogSetup = GetTransmogSetup;


    --QuestTag
    local GetQuestTagInfo = C_QuestLog.GetQuestTagInfo or AlwaysFalse;
    local QUEST_TAG_NAME = {
        --Also: Enum.QuestTagType
        [Enum.QuestTag.Dungeon] = {L["Quest Type Dungeon"], "QuestTag-Dungeon.png"},
        [Enum.QuestTag.Raid] = {L["Quest Type Raid"], "QuestTag-Raid.png"},
        [Enum.QuestTag.Raid10] = {L["Quest Type Raid"], "QuestTag-Raid.png"},
        [Enum.QuestTag.Raid25] = {L["Quest Type Raid"], "QuestTag-Raid.png"},

        [271] = {L["Quest Type Covenant Calling"]},
    };

    local function GetQuestTag(questID)
        local info = GetQuestTagInfo(questID);
        if info and info.tagID then
            return info.tagID
        end
    end
    API.GetQuestTag = GetQuestTag;

    local function GetQuestTagNameIcon(tagID)
        if QUEST_TAG_NAME[tagID] then
            local icon = QUEST_TAG_NAME[tagID][2];
            if icon then
                icon = ICON_PATH..icon;
            end
            return QUEST_TAG_NAME[tagID][1], icon
        end
    end
    API.GetQuestTagNameIcon = GetQuestTagNameIcon;


    local PLAYER_HONOR_ICON;

	-- Lazily select the honor icon appropriate for the player's faction.
    local function GetHonorIcon()
        if PLAYER_HONOR_ICON == nil then
            if UnitFactionGroup and UnitFactionGroup("player") == "Horde" then
                PLAYER_HONOR_ICON = "Interface/Icons/PVPCurrency-Honor-Horde";
            else
                PLAYER_HONOR_ICON = "Interface/Icons/PVPCurrency-Honor-Alliance";
            end
        end

        return PLAYER_HONOR_ICON
    end
    API.GetHonorIcon = GetHonorIcon;

	-- Return a quest's remaining time as seconds or formatted text.
    local function GetQuestTimeLeft(questID, formatedToText)
        local seconds = GetQuestTimeLeftSeconds(questID);
        if seconds then
            if formatedToText then
                return API.SecondsToTime(seconds, true, true)
            else
                return seconds
            end
        end
    end
    API.GetQuestTimeLeft = GetQuestTimeLeft;

	-- Report whether a quest has recurring-time information and return that time if available.
    local function GetRecurringQuestTimeLeft(questID, formatedToText)
        if GetQuestClassification(questID) then
            local seconds = GetQuestTimeLeft(questID, formatedToText);
            return true, seconds
        else
            return false
        end
    end
    API.GetRecurringQuestTimeLeft = GetRecurringQuestTimeLeft;

	
	-- Allow integrations to transform quest and gossip text, for example to apply roleplay names.
	-- Without a registered modifier, text is returned unchanged.
    do
        -- Default text modifier that leaves the input unchanged.
		local function TextModifier_None(text)
            return text
        end

        local TextModifier = TextModifier_None;

		-- Return quest text after applying the currently configured text modifier.
        local function GetModifiedQuestText(method)
            local text = GetQuestText(method);
            if text then
                return TextModifier(text)
            end
        end
        API.GetModifiedQuestText = GetModifiedQuestText;

		-- Return gossip text after applying the currently configured text modifier.
        local function GetModifiedGossipText()
            local text = GetGossipText();
            if text then
                return TextModifier(text)
            end
        end
        API.GetModifiedGossipText = GetModifiedGossipText;

		-- Set or reset the modifier used for quest and gossip text.
        local function SetDialogueTextModifier(modifierFunc)
            TextModifier = modifierFunc or TextModifier_None;
        end
        addon.SetDialogueTextModifier = SetDialogueTextModifier;

        -- Notify listeners when an external chat-text modifier is registered.
		addon.SetChatTextModifier = function(modifierFunc)
            modifierFunc("test");
            CallbackRegistry:Trigger("SetChatTextModifier", modifierFunc or TextModifier_None);
        end
    end


    --QuestLine
	-- Retrieve questline details for the player's current map when the required APIs exist.
	-- Otherwise expose a no-result fallback for compatibility.
    if C_QuestLog.GetZoneStoryInfo and C_QuestLine and C_QuestLine.GetQuestLineInfo then
        local GetBestMapForUnit = C_Map.GetBestMapForUnit;
        -- Return whether the map has a questline and, if available, its name, ID, map ID, and achievement ID.
		function API.GetQuestLineInfo(questID)
            local uiMapID = GetBestMapForUnit("player");
            local hasQuestLineOnMap, questLineName, questLineID, achievementID;
            if uiMapID then
                achievementID = C_QuestLog.GetZoneStoryInfo(uiMapID);
                if achievementID then
                    hasQuestLineOnMap = true;
                    local questLineInfo = C_QuestLine.GetQuestLineInfo(questID, uiMapID);
                    if questLineInfo then
                        questLineName = questLineInfo.questLineName;
                        questLineID = questLineInfo.questLineID;
                    end
                end
            end
            return hasQuestLineOnMap, questLineName, questLineID, uiMapID, achievementID
        end
    else
        function API.GetQuestLineInfo(questID)

        end
    end


    -- Open Quest Log
    -- Open the world map and show the specified quest in the quest log when the required
	-- UI functions are available and the player is not in combat.
	function API.ViewQuestInQuestLog(questID)
        if not (InCombatLockdown() and GetLogIndexForQuestID(questID) and QuestMapFrame_ShowQuestDetails) then return end;
        if C_Map.OpenWorldMap then
            C_Map.OpenWorldMap();
        end
        QuestMapFrame_ShowQuestDetails(questID);
        return true
    end
end



-- Define shared colors for item quality and addon text, and provide helpers
-- to apply those colors consistently to UI text.
do  -- Color
    -- Use brighter custom colors for Rare and Epic items.
    local CreateColor = CreateColor;
    local ITEM_QUALITY_COLORS = ITEM_QUALITY_COLORS;
    local QualityColors = {};

    -- Define custom colors for Poor, Common, Rare, and Epic item qualities.
    QualityColors[0] = CreateColor(0.9, 0.9, 0.9, 1);
    QualityColors[1] = QualityColors[0];
    QualityColors[3] = CreateColor(105/255, 158/255, 255/255, 1);
    QualityColors[4] = CreateColor(185/255, 83/255, 255/255, 1);

    -- Return a custom color for overridden qualities or the client default otherwise.
    local function GetItemQualityColor(quality)
        if QualityColors[quality] then
            return QualityColors[quality]
        else
            return ITEM_QUALITY_COLORS[quality].color
        end
    end
    API.GetItemQualityColor = GetItemQualityColor;


    -- Semantic text colors used for standard, emphasized, completed, and error messages.
    local TextPalette = {
        [0] = CreateColor(1, 1, 1, 1),              --Fallback
        [1] = CreateColor(0.87, 0.86, 0.75, 1),     --Ivory: Used by big buttons and low-priority alerts like criteria complete
        [2] = CreateColor(0.19, 0.17, 0.13, 1),     --Dark Brown: Used as paragraph text color
        [3] = CreateColor(0.42, 0.75, 0.48, 1),     --Green: Quest Complete
        [4] = CreateColor(1.000, 0.125, 0.125, 1),  --ERROR_COLOR
    };

    -- Return the requested palette color, falling back to white for an unknown index.
    local function GetTextColorByIndex(colorIndex)
        if not (colorIndex and TextPalette[colorIndex]) then
            colorIndex = 0;
        end
        return TextPalette[colorIndex]
    end
    API.GetTextColorByIndex = GetTextColorByIndex;

    -- Apply a palette color to a font string.
    local function SetTextColorByIndex(fontString, colorIndex)
        local color = GetTextColorByIndex(colorIndex);
        if color then
            local r, g, b = color:GetRGB();
            fontString:SetTextColor(r, g, b);
        end
    end
    API.SetTextColorByIndex = SetTextColorByIndex;

    -- Apply a color mixin to a font string, using white when no color is supplied.
    local function SetTextColorByGlobal(fontString, colorMixin)
        local r, g, b;
        if colorMixin then
            r, g, b = colorMixin:GetRGB();
        else
            r, g, b = 1, 1, 1;
        end
        fontString:SetTextColor(r, g, b);
    end
    API.SetTextColorByGlobal = SetTextColorByGlobal;
end

-- Currency and player-progression helpers, with fallbacks for clients that lack
-- the modern currency API.
do  -- Currency (3.3.5 compatibility)
    local format = string.format;
    local FormatLargeNumber = FormatLargeNumber or function(n) return tostring(n); end;

    -- Provide a safe placeholder when the client does not expose currency information.
    local GetCurrencyInfo = GetCurrencyInfo or function(currencyID)
        -- In WotLK 3.3.5a, currencies are often handled differently or via item IDs.
        -- Returning dummy values to prevent errors.
        return { name = "Unknown", quantity = 0, maxQuantity = 0, iconFileID = 0 };
    end;

    -- Use the modern currency-container lookup when available; otherwise return no entry.
    local GetCurrencyContainerInfoDefault = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyContainerInfo or function(currencyID, numItems)
        return nil;
    end;

    -- Return container metadata from the modern API, or use the supplied fallback values.
    local function GetCurrencyContainerInfo(currencyID, numItems, name, texture, quality)
        local entry = GetCurrencyContainerInfoDefault(currencyID, numItems);
        if entry then
            return entry.name, entry.icon, entry.displayAmount, entry.quality
        end
        return name, texture, numItems, quality
    end
    API.GetCurrencyContainerInfo = GetCurrencyContainerInfo;

    -- Convert an amount in copper into a localized gold, silver, and copper string.
    -- Optional colorization applies the corresponding in-game currency colors.
    local function GenerateMoneyText(rawCopper, colorized, noAbbreviation) --coins
        local text;
        local gold = floor(rawCopper / 10000);
        local silver = floor((rawCopper - gold * 10000) / 100);
        local copper = floor(rawCopper - gold * 10000 - silver * 100);

        local goldText, silverText, copperText;

        -- Format copper only when the amount contains copper.
        if copper > 0 then
            if noAbbreviation then
                copperText = format(L["Format Copper Amount"], copper);
            else
                copperText = copper..L["Symbol Copper"];
            end

            if colorized then
                copperText = "|cffe3b277"..copperText.."|r";
            end
        end

        -- Format silver and gold when either denomination is present.
        if gold ~= 0 or silver ~= 0 then
            if noAbbreviation then
                silverText = format(L["Format Silver Amount"], silver);
            else
                silverText = silver..L["Symbol Silver"];
            end

            if colorized then
                silverText = "|cffc5d2e8"..silverText.."|r";
            end

            if gold > 0 then
                if noAbbreviation then
                    goldText = format(L["Format Gold Amount"], FormatLargeNumber(gold));
                else
                    goldText = gold..L["Symbol Gold"];
                end

                if colorized then
                    goldText = "|cffffbb18"..goldText.."|r";
                end

                -- Assemble the denominations that have a value.
                if copperText then
                    text = goldText.." "..silverText.." "..copperText;
                elseif silver == 0 then
                    text = goldText;
                else
                    text = goldText.." "..silverText;
                end
            else
                if copperText then
                    text = silverText.." "..copperText;
                else
                    text = silverText;
                end
            end
        else
            text = copperText;
        end

        return text
    end
    API.GenerateMoneyText = GenerateMoneyText;


    -- Currency IDs whose rewards should not be reported as overflowing.
    local IGNORED_OVERFLOW_ID = {
        [3068] = true,      --Delver's Journey
        [3143] = true,      --Delver's Journey
    };

    -- Check whether adding a reward would exceed the currency's configured capacity.
    local function WillCurrencyRewardOverflow(currencyID, rewardQuantity)
        if IGNORED_OVERFLOW_ID[currencyID] then return false end;

        local currencyInfo = GetCurrencyInfo(currencyID);
        local quantity = currencyInfo and (currencyInfo.useTotalEarnedForMaxQty and currencyInfo.totalEarned or currencyInfo.quantity);
        return quantity and currencyInfo.maxQuantity > 0 and rewardQuantity + quantity > currencyInfo.maxQuantity;
    end
    API.WillCurrencyRewardOverflow = WillCurrencyRewardOverflow;

    -- Return the reward amount unchanged unless it would overflow, in which case
    -- add an overflow icon or red text depending on the caller's display style.
    local function GetColorizedAmountForCurrency(currencyID, rewardQuantity, useIcon)
        if WillCurrencyRewardOverflow(currencyID, rewardQuantity) then
            if useIcon then --For Small Button
                return "|TInterface/AddOns/DialogueUI/Art/Icons/CurrencyOverflow.png:0:0|t"..rewardQuantity.."|r"
            else
                return "|cffff2020"..rewardQuantity.."|r"
            end
        else
            return rewardQuantity
        end
    end
    API.GetColorizedAmountForCurrency = GetColorizedAmountForCurrency;

    -- Return the player's current quantity for a currency, defaulting to zero when unavailable.
    local function GetOwnedCurrencyQuantity(currencyID)
        local currencyInfo = GetCurrencyInfo(currencyID);
        return currencyInfo and currencyInfo.quantity or 0
    end
    API.GetOwnedCurrencyQuantity = GetOwnedCurrencyQuantity;

    -- Cache player XP and level APIs used by the progression helpers below.
    local UnitXP = UnitXP;
    local UnitXPMax = UnitXPMax;
    local UnitLevel = UnitLevel;

    -- Return the player's current XP as a rounded percentage of the current level's XP requirement.
    local function GetXPPercentage(xp)
        local current = UnitXP("player");
        local max = UnitXPMax("player");
        if current and max and max ~= 0 and xp > 0 then
            local ratio = xp/max;
            if ratio > 1 then
                
            end
            return API.Round(ratio*100);
        else
            return 0
        end
    end
    API.GetXPPercentage = GetXPPercentage;

    -- Return the player's level, current XP, and XP required for the next level.
    local function GetPlayerLevelXP()
        local level = UnitLevel("player");
        local currentXP = UnitXP("player");
        local maxXP = UnitXPMax("player");
        return level, currentXP, maxXP
    end
    API.GetPlayerLevelXP = GetPlayerLevelXP;

    -- Determine whether the player's level has reached the maximum known for this client.
    local function IsPlayerAtMaxLevel()
        local maxLevel;

        if GetMaxLevelForPlayerExpansion then
            maxLevel = GetMaxLevelForPlayerExpansion();
        elseif GetMaxPlayerLevel then
            maxLevel = GetMaxPlayerLevel();
        else
            maxLevel = 999
        end

        return UnitLevel("player") >= maxLevel
    end
    API.IsPlayerAtMaxLevel = IsPlayerAtMaxLevel;
end


-- Grid layout mixin for placing objects in cells, including objects that span
-- multiple rows or columns.
do  -- Grid Layout
    local ipairs = ipairs;
    local tinsert = table.insert;

    local GridMixin = {};

    -- Initialize a one-cell grid with no spacing between cells.
    function GridMixin:OnLoad()
        self:SetGrid(1, 1);
        self:SetSpacing(0);
    end

    -- Set the grid dimensions in cells and clear its current occupancy data.
    function GridMixin:SetGrid(x, y)
        self.x = x;
        self.y = y;
        self:ResetGrid();
    end

    -- Set the pixel spacing between adjacent grid cells.
    function GridMixin:SetSpacing(spacing)
        self.spacing = spacing;
    end

    -- Clear cell occupancy and reset the search and size-tracking state.
    function GridMixin:ResetGrid()
        self.grid = {};
        self.fromRow = 1;
        self.maxOccupiedX = 0;
        self.maxOccupiedY = 0;
    end

    -- Set the pixel dimensions of an individual grid cell.
    function GridMixin:SetGridSize(gridWidth, gridHeight)
        self.gridWidth = gridWidth;
        self.gridHeight = gridHeight;
    end

    -- Append rows initialized with unoccupied cells.
    function GridMixin:CreateNewRows(n)
        n = n or 1;

        for i = 1, n do
            local tbl = {};
            for col = 1, self.x do
                tinsert(tbl, false);
            end
            tinsert(self.grid, tbl);
        end
    end

    -- Find the first available rectangular region large enough for an object,
    -- mark its cells as occupied, and add rows if the current grid has no fit.
    function GridMixin:FindGridForSize(objectSizeX, objectSizeY)
        local found = false;
        local maxRow = #self.grid;
        local topleftGridX, topleftGridY;

        for row = self.fromRow, maxRow do
            local rowStatus = self.grid[row];
            local maxCol = #rowStatus;
            local rowFull = true;

            for col, occupied in ipairs(rowStatus) do
                if not occupied then
                    rowFull = false;
                    if (col + objectSizeX - 1 <= maxCol) and (row + objectSizeY - 1 <= maxRow) then
                        found = true;
                        topleftGridX = col;
                        topleftGridY = row;

                        -- Reserve every cell covered by the object's rectangular footprint.
                        for _row = row, row + objectSizeY - 1 do
                            for _col = col, col + objectSizeX - 1 do
                                self.grid[_row][_col] = true;
                            end
                        end

                        -- Track the furthest occupied grid coordinates for size calculation.
                        if topleftGridX > self.maxOccupiedX then
                            self.maxOccupiedX = topleftGridX;
                        end

                        if topleftGridY > self.maxOccupiedY then
                            self.maxOccupiedY = topleftGridY;
                            if objectSizeY > 1 then
                                self.maxOccupiedY = self.maxOccupiedY + objectSizeY - 1;
                            end
                        end

                        break
                    end
                end
            end

            if found then
                break
            end

            -- Skip rows already known to be full on subsequent searches.
            if rowFull then
                self.fromRow = self.fromRow + 1;
            end
        end

        if found then
            return topleftGridX, topleftGridY
        else
            -- Extend the grid vertically and retry until a suitable region exists.
            self:CreateNewRows(self.y);
            return self:FindGridForSize(objectSizeX, objectSizeY)
        end
    end

    -- Mark cells after content in each row as occupied, preventing later objects
    -- from being placed into gaps that should remain visually empty.
    function GridMixin:FlagPreviousRowFull()
        local maxRow = #self.grid;

        for row = self.fromRow, maxRow do
            local rowStatus = self.grid[row];
            local anyContentThisRow;
            for col, occupied in ipairs(rowStatus) do
                if col == 1 then
                    if occupied then
                        anyContentThisRow = true;
                    end
                else
                    if anyContentThisRow then
                        self.grid[row][col] = true;
                    end
                end
            end
        end
    end

    -- Convert a cell's top-left grid coordinates into pixel offsets from the layout origin.
    function GridMixin:GetOffsetForGridPosition(topleftGridX, topleftGridY)
        local offsetX = (topleftGridX - 1) * (self.gridWidth + self.spacing);
        local offsetY = (topleftGridY - 1) * (self.gridHeight + self.spacing);
        return offsetX, -offsetY
    end

    -- Find a free region for an object and anchor it at the corresponding grid position.
    function GridMixin:PlaceObject(object, objectSizeX, objectSizeY, anchorTo, fromOffsetX, fromOffsetY)
        local topleftGridX, topleftGridY = self:FindGridForSize(objectSizeX, objectSizeY);
        local offsetX, offsetY = self:GetOffsetForGridPosition(topleftGridX, topleftGridY);
        object:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", fromOffsetX + offsetX, fromOffsetY + offsetY);
    end

    -- Return the pixel dimensions required by the currently occupied grid cells.
    function GridMixin:GetWrappedSize()
        local width = (self.maxOccupiedX > 0 and self.maxOccupiedX * (self.gridWidth + self.spacing) - self.spacing) or 0;
        local height = (self.maxOccupiedY > 0 and self.maxOccupiedY * (self.gridHeight + self.spacing) - self.spacing) or 0;

        return width, height
    end

    -- Create and initialize a reusable grid-layout object.
    local function CreateGridLayout()
        local grid = API.CreateFromMixins(GridMixin);
        grid:OnLoad();
        return grid
    end
    API.CreateGridLayout = CreateGridLayout;
end


-- Manage concurrent alpha transitions for UI frames through one shared update frame.
do  -- Fade Frame
    local abs = math.abs;
    local tinsert = table.insert;
    local wipe = wipe;

    -- Store each frame's active transition separately from the list of frames being updated.
    local fadeInfo = {};
    local fadingFrames = {};

    local f = CreateFrame("Frame");

	-- Advance each active fade and stop the update loop once all transitions have completed.
    local function OnUpdate(self, elapsed)
        local i = 1;
        local frame, info, timer, alpha;
        local isComplete = true;
        while fadingFrames[i] do
            frame = fadingFrames[i];
            info = fadeInfo[frame];
            if info then
                timer = info.timer + elapsed;
                if timer >= info.duration then
                    alpha = info.toAlpha;
                    fadeInfo[frame] = nil;
                    if info.alterShownState and alpha <= 0 then
                        frame:Hide();
                    end
                else
                    alpha = info.fromAlpha + (info.toAlpha - info.fromAlpha) * timer/info.duration;
                    info.timer = timer;
                end
                frame:SetAlpha(alpha);
                isComplete = false;
            end
            i = i + 1;
        end

        if isComplete then
            self:Clear();
        end
    end

    -- Stop all active transitions and clear the tracking tables.
    function f:Clear()
        self:SetScript("OnUpdate", nil);
        wipe(fadingFrames);
        wipe(fadeInfo);
    end

    -- Add or replace a frame's alpha transition.
    -- The duration is adjusted according to the remaining alpha distance unless
    -- useConstantDuration requests the full duration regardless of that distance.
    function f:Add(frame, fullDuration, fromAlpha, toAlpha, alterShownState, useConstantDuration)
        local alpha = frame:GetAlpha();

        -- Optionally show before fading in and hide when the final alpha reaches zero.
        if alterShownState then
            if toAlpha > 0 then
                frame:Show();
            end
            if toAlpha == 0 then
                if not frame:IsShown() then
                    frame:SetAlpha(0);
                    alpha = 0;
                end
                if alpha == 0 then
                    frame:Hide();
                end
            end
        end

        -- Ignore transitions that would not change the frame's final alpha.
        if fromAlpha == toAlpha or alpha == toAlpha then
            if fadeInfo[frame] then
                fadeInfo[frame] = nil;
            end
            return;
        end

        local duration;
        if useConstantDuration then
            duration = fullDuration;
        else
            if fromAlpha then
                duration = fullDuration * (alpha - toAlpha)/(fromAlpha - toAlpha);
            else
                duration = fullDuration * abs(alpha - toAlpha);
            end
        end

        -- Apply the final state immediately when the computed transition has no duration.
        if duration <= 0 then
            fadeInfo[frame] = nil;
			frame:SetAlpha(toAlpha);
           	if alterShownState and toAlpha <= 0 then
                 frame:Hide();
        	end
            return;
        end
				
        -- Store the transition state used by the shared OnUpdate handler.
        fadeInfo[frame] = {
            fromAlpha = alpha,
            toAlpha = toAlpha,
            duration = duration,
            timer = 0,
            alterShownState = alterShownState,
        };

        -- Avoid adding the same frame to the update list more than once.
        for i = 1, #fadingFrames do
            if fadingFrames[i] == frame then
                return;
            end
        end

        tinsert(fadingFrames, frame);
        self:SetScript("OnUpdate", OnUpdate);
    end

    -- Fade a frame at a consistent speed, with optional automatic show/hide behavior.
    function f:SimpleFade(frame, toAlpha, alterShownState, speedMultiplier)
        --Use a constant fading speed: 1.0 in 0.25s
        --alterShownState: if true, run Frame:Hide() when alpha reaches zero / run Frame:Show() at the beginning
        speedMultiplier = speedMultiplier or 1;
        local alpha = frame:GetAlpha();
        local duration = abs(alpha - toAlpha) * 0.25 * speedMultiplier;
        if duration <= 0 then
            return;
        end

        self:Add(frame, duration, alpha, toAlpha, alterShownState, true);
    end

    -- Immediately set all transitioning frames to their target alpha and stop the update loop.
    function f:Snap()
        local i = 1;
        local frame, info;
        while fadingFrames[i] do
            frame = fadingFrames[i];
            info = fadeInfo[frame];
            if info then
                frame:SetAlpha(info.toAlpha);
				if info.alterShownState and info.toAlpha <= 0 then
					frame:Hide();
				end
            end
            i = i + 1;
        end
        self:Clear();
    end

    -- Fade from the current alpha, or from an explicitly supplied initial alpha, to a target.
    local function UIFrameFade(frame, duration, toAlpha, initialAlpha)
        if initialAlpha then
            frame:SetAlpha(initialAlpha);
            f:Add(frame, duration, initialAlpha, toAlpha, true, false);
        else
            f:Add(frame, duration, nil, toAlpha, true, false);
        end
    end

    -- Set alpha to zero, then fade the frame in to fully opaque.
    local function UIFrameFadeIn(frame, duration)
        frame:SetAlpha(0);
        f:Add(frame, duration, 0, 1, true, false);
    end


    API.UIFrameFade = UIFrameFade;       --from current alpha
    API.UIFrameFadeIn = UIFrameFadeIn;   --from 0 to 1
end



-- Model helpers with fallbacks for APIs that are unavailable in WotLK 3.3.5a.
do  -- Model (3.3.5 Compatibility)
    local UnitRace = UnitRace;

    -- Altered-form detection is a modern API and is absent in WotLK.
    local WantsAlteredForm = C_UnitAuras and C_UnitAuras.WantsAlteredForm or AlwaysFalse;

    -- Assign a unit to a model and request altered-form blending only when supported.
    local function SetModelByUnit(model, unit)
        if not model or not UnitExists(unit) then return; end

        local _, raceFileName = UnitRace(unit);

        -- Altered-form blending applies to modern Dracthyr and Worgen models only.
        if (raceFileName == "Dracthyr" or raceFileName == "Worgen") and C_UnitAuras then
            local arg = WantsAlteredForm(unit);
            model:SetUnit(unit, false, arg);    -- blend = false

            -- HINT: Verify that the model widget used by callers supports SetUnit(unit, showMount, useNativeForm).
            -- WotLK does not use this modern altered-form branch, so it calls SetUnit with two arguments.
        else
            model:SetUnit(unit, false);
        end

        model.unit = unit;
    end
    API.SetModelByUnit = SetModelByUnit;

    -- Configure a model's lighting, using the positional arguments supported by older clients.
    local function SetModelLight(model, enabled, omni, dirX, dirY, dirZ, ambIntensity, ambR, ambG, ambB, dirIntensity, dirR, dirG, dirB)
        if not model or not model.SetLight then return; end

        -- HINT: Retail accepts a light-information table, but WotLK's Model:SetLight
        -- uses positional light parameters. Keep this positional call for 3.3.5a.
        model:SetLight(
            enabled,
            omni or false,
            dirX or 0,
            dirY or 0,
            dirZ or 0,
            ambIntensity or 1,
            ambR or 1,
            ambG or 1,
            ambB or 1,
            dirIntensity or 1,
            dirR or 1,
            dirG or 1,
            dirB or 1
        );
    end
    API.SetModelLight = SetModelLight;

    -- Queue portrait updates when the client reports that a unit model is not yet ready.
    do  -- UnitPortraitSetter
        local UnitPortraitSetter = CreateFrame("Frame");
        UnitPortraitSetter.queue = {};

        -- Set a portrait immediately when ready, or defer it until the next queue update.
        function UnitPortraitSetter:SetPortraitTexture(textureObject, unit)
            -- HINT: The original expression ended with "or true", which made a false
            -- readiness result behave as true. This form preserves false when the API exists.
            local isReady = not IsUnitModelReadyForUI or IsUnitModelReadyForUI(unit);

            if isReady then
                self.queue[textureObject] = nil;
                SetPortraitTexture(textureObject, unit);
            else
                self.queue[textureObject] = unit;
                self.t = 0;
                self:SetScript("OnUpdate", self.OnUpdate);
            end
        end

        -- Wait briefly, then update queued portraits that are still visible.
        function UnitPortraitSetter:OnUpdate(elapsed)
            self.t = self.t + elapsed;
            if self.t >= 1.0 then
                self.t = 0;
                self:SetScript("OnUpdate", nil);
                for textureObject, unit in pairs(self.queue) do
                    if textureObject:IsVisible() then
                        SetPortraitTexture(textureObject, unit);
                    end
                end
                self.queue = {};
            end
        end

        -- Expose portrait setting through the addon's compatibility API.
        API.SetPortraitTexture = function(textureObject, unit)
            UnitPortraitSetter:SetPortraitTexture(textureObject, unit);
        end
    end
end


-- Retrieve faction status through modern APIs when available, with safe fallbacks
-- for clients such as WotLK 3.3.5a that do not provide these faction APIs.
do  -- Faction -- Reputation
    local C_GossipInfo = C_GossipInfo;
    local C_MajorFactions = C_MajorFactions;
    local C_Reputation = C_Reputation;

    -- Prefer the available faction-by-ID API, including its modern replacement.
    local GetFactionInfoByID = GetFactionInfoByID or (C_Reputation and C_Reputation.GetFactionDataByID);

    -- HINT: C_CurrencyInfo is absent on WotLK. Use a false-returning fallback
    -- instead of indexing it directly.
    local GetFactionGrantedByCurrency = C_CurrencyInfo and C_CurrencyInfo.GetFactionGrantedByCurrency or AlwaysFalse;

    -- Account-wide reputation is not supported on clients without this API.
    local IsAccountWideReputation = C_Reputation and C_Reputation.IsAccountWideReputation or AlwaysFalse;

    -- Build localized faction standing and progress text when faction data is available.
    local function GetFactionStatusText(factionID)
        --Derived from Blizzard ReputationFrame_InitReputationRow in ReputationFrame.lua
        if not factionID then return end;

        -- HINT: WotLK does not provide a general faction-by-ID lookup here.
        -- Return safely rather than trying to call an unavailable modern API.
        if not GetFactionInfoByID then return end;

        local factionName;
        local p1, description, standingID, barMin, barMax, barValue = GetFactionInfoByID(factionID);

        -- Modern clients return a data table; older supported API variants may return multiple values.
        if type(p1) == "table" then
            standingID = p1.reaction;
            barMin = p1.currentReactionThreshold;
            barMax = p1.nextReactionThreshold;
            barValue = p1.currentStanding;
            factionName = p1.name;
        else
            factionName = p1;
        end

        -- Check for Paragon status only when the corresponding reputation API exists.
        local isParagon;
        if C_Reputation and C_Reputation.IsFactionParagonForCurrentPlayer then
            isParagon = C_Reputation.IsFactionParagonForCurrentPlayer(factionID);
        elseif C_Reputation and C_Reputation.IsFactionParagon then
            isParagon = C_Reputation.IsFactionParagon(factionID);
        end

        -- Major factions and friendship reputation are modern features; treat them as unavailable otherwise.
        local isMajorFaction = C_Reputation and C_Reputation.IsMajorFaction
            and C_Reputation.IsMajorFaction(factionID);
        local repInfo = C_GossipInfo and C_GossipInfo.GetFriendshipReputation
            and C_GossipInfo.GetFriendshipReputation(factionID);

        local isCapped;
        local factionStandingtext;  --Revered/Junior/Renown 1

        -- Friendship factions use their own reaction and rank progress values.
        if repInfo and repInfo.friendshipFactionID and repInfo.friendshipFactionID > 0 then
            factionStandingtext = repInfo.reaction;

            if repInfo.nextThreshold then
                barMin, barMax, barValue = repInfo.reactionThreshold, repInfo.nextThreshold, repInfo.standing;
                barValue = barValue - barMin;
                barMax = barMax - barMin;
            else
                barMin, barMax, barValue = 0, 1, 1;
                isCapped = true;
            end

            local rankInfo = C_GossipInfo.GetFriendshipReputationRanks
                and C_GossipInfo.GetFriendshipReputationRanks(repInfo.friendshipFactionID);
            if rankInfo then
                factionStandingtext = factionStandingtext
                    .. string.format(" (Lv. %s/%s)", rankInfo.currentLevel, rankInfo.maxLevel);
            end

        -- Major factions display Renown progress and may also have Paragon progress.
        elseif isMajorFaction and C_MajorFactions and C_MajorFactions.GetMajorFactionData then
            local majorFactionData = C_MajorFactions.GetMajorFactionData(factionID);
            if majorFactionData then
                barMin, barMax = 0, majorFactionData.renownLevelThreshold;
                isCapped = C_MajorFactions.HasMaximumRenown
                    and C_MajorFactions.HasMaximumRenown(factionID) or false;
                barValue = isCapped and majorFactionData.renownLevelThreshold
                    or majorFactionData.renownReputationEarned or 0;
                factionStandingtext = L["Renown Level Label"] .. majorFactionData.renownLevel;

                if isParagon and C_Reputation.GetFactionParagonInfo then
                    local totalEarned, threshold = C_Reputation.GetFactionParagonInfo(factionID);
                    if totalEarned and threshold and threshold ~= 0 then
                        local paragonLevel = floor(totalEarned / threshold);
                        local currentValue = totalEarned - paragonLevel * threshold;
                        factionStandingtext = ("|cff00ccff" .. L["Paragon Reputation"]
                            .. "|r %d/%d"):format(currentValue, threshold);
                    end
                elseif isCapped then
                    factionStandingtext = factionStandingtext .. " " .. L["Level Maxed"];
                end
            end

        -- Standard reputation standings, including the WotLK-style reaction levels.
        elseif standingID and standingID > 0 then
            isCapped = standingID == 8;  --MAX_REPUTATION_REACTION
            local gender = UnitSex and UnitSex("player");
            local standingLabelKey = "FACTION_STANDING_LABEL" .. standingID;

            -- HINT: Use GetText when available, with the localized global string as a fallback.
            -- This allows the standard standing labels to work on clients without newer helpers.
            if GetText then
                factionStandingtext = GetText(standingLabelKey, gender);
            else
                factionStandingtext = _G[standingLabelKey];
            end
        end

        -- Show numeric progress for uncapped reputations when values are available.
        local rolloverText; --(0/24000)
        if barValue and barMax and (not isCapped) then
            rolloverText = string.format("(%s/%s)", barValue, barMax);
        end

        -- Assemble the status label and progress into one display string.
        local text;

        if factionStandingtext then
            if not text then text = L["Current Colon"] end;
            factionStandingtext = " |cffffffff" .. factionStandingtext .. "|r";
            text = text .. factionStandingtext;
        end

        if rolloverText then
            if not text then text = L["Current Colon"] end;
            rolloverText = "  |cffffffff" .. rolloverText .. "|r";
            text = text .. rolloverText;
        end

        return text, factionName
    end
    API.GetFactionStatusText = GetFactionStatusText;

    -- Resolve the faction associated with a currency and return its status, if supported.
    local function GetFactionStatusTextByCurrencyID(currencyID)
        local factionID = GetFactionGrantedByCurrency(currencyID);
        if factionID then
            return GetFactionStatusText(factionID);
        end
    end
    API.GetFactionStatusTextByCurrencyID = GetFactionStatusTextByCurrencyID;

    -- Return whether the specified faction uses account-wide reputation, if that API exists.
    local function IsReputationAccountWide(factionID)
        return factionID and IsAccountWideReputation(factionID);
    end

    -- HINT: Export the wrapper so callers get the safe false fallback on older clients.
    API.IsAccountWideReputation = IsReputationAccountWide;
end


-- Chat output helpers and custom clickable links used by the addon.
do  -- Chat Message
    -- Use the modern hyperlink stripper when available, then a legacy global,
    -- and finally a simple fallback that keeps only the link's displayed text.
    local StripHyperlinks = (C_StringUtil and C_StringUtil.StripHyperlinks)
        or StripHyperlinks
        or function(text)
            return (text:gsub("|H.-|h(.-)|h", "%1"));
        end;
    API.StripHyperlinks = StripHyperlinks;

    -- Addon icon prepended to messages printed to the chat frame.
    local ADDON_ICON = "|TInterface\\AddOns\\DialogueUI\\Art\\Icons\\Logo:0:0|t";

    -- Print a labeled addon message after removing clickable hyperlinks from its body.
    local function PrintMessage(header, msg)
        if not msg then
            msg = "";
        end
        if StripHyperlinks then
            msg = StripHyperlinks(msg);
        end
        print(ADDON_ICON.."|cffffd100"..header.."  |cffffffff"..msg.."|r");
    end
    API.PrintMessage = PrintMessage;

    -- Print quest-completion text without hyperlinks, skipping empty messages.
    function API.PrintQuestCompletionText(msg)
        if msg == "" then return end;
        if StripHyperlinks then
            msg = StripHyperlinks(msg);
        end
        print(ADDON_ICON.." |cffffd100"..msg.."|r");
    end

    -- Build a standard clickable quest link when the quest ID and title are available.
    function API.GenerateQuestLink(questID)
        if questID and questID ~= 0 then
            local questName = questID and API.GetQuestName(questID);
            if questName then
                return string.format("|cffffff00|Hquest:%s:0|h[%s]|h|r", questID, questName);
            end
        end
    end


    -- Store handlers and display colors for custom DialogueUI hyperlink types.
    local CustomLinkUtil = {};

    -- Register a custom link type and the callback that handles its payload.
    function API.AddCustomLinkType(typeName, callback, colorCode)
        CustomLinkUtil[typeName] = {
            callback = callback,
            colorCode = colorCode,
        };
    end

    -- Generate a clickable custom hyperlink and register its click handler once.
    function API.GenerateCustomLink(typeName, displayedText, ...)
        if CustomLinkUtil[typeName] then
            if not CustomLinkUtil.registered then
                -- HINT: EventRegistry is a modern API and is not available in WotLK 3.3.5a.
                -- hooksecurefunc on the global SetItemRef function is the legacy-compatible
                -- way to observe chat-link clicks without replacing Blizzard's handler.
                if hooksecurefunc then
                    hooksecurefunc("SetItemRef", function(link, text, button, chatFrame)
                        if link then
                            local _typeName, subText = string.match(link, "dialogueui:([^:]+):([^|]+)");
                            if _typeName and CustomLinkUtil[_typeName] then
                                local args = {};
                                for arg in string.gmatch(subText, "[^:]+") do
                                    table.insert(args, arg);
                                end
                                CustomLinkUtil[_typeName].callback(unpack(args));
                            end
                        end
                    end);
                    CustomLinkUtil.registered = true;
                else
                    -- HINT: If this fallback is reached, the client cannot install the
                    -- SetItemRef hook, so generated custom links will not invoke callbacks.
                    return;
                end
            end

            -- Build the hyperlink payload; WoW chat links require at least one payload value.
            --|cffxxxxxx|Htype:payload|h[text]|h|r
            local args = {...};
            local link = "|Haddon:dialogueui:"..typeName;

            if #args == 0 then
                args = {0};
            end

            for i, v in ipairs(args) do
                link = link..":"..v;
            end

            link = string.format("|cff%s%s|h[%s]|h|r", CustomLinkUtil[typeName].colorCode or "ffd100", link, displayedText);

            return link
        end
    end

    -- Print a blocked quest alert with links to the quest and the unblock action.
    function API.ShowBlockedQuestMessage(questID)
        local questLink = API.GenerateQuestLink(questID);
        if questLink then
            local addonActionLink = API.GenerateCustomLink("UnblockQuest", L["Click To Unblock Quest"], questID);
            local msg = string.format(L["Block Auto Pushed Quest Alert Format"], questLink).." "..addonActionLink;
            print(ADDON_ICON.."|cffffffff"..msg.."|r");
        end
    end
end



-- Tooltip and equipment helpers with fallbacks for the legacy WotLK API.
do  -- Tooltip (3.3.5 Compatibility)
    local GetInventoryItemLink = GetInventoryItemLink;
    local GetInventoryItemID = GetInventoryItemID;
    local GetQuestItemLink = GetQuestItemLink;

    -- Normalize item information to the fields consumed by this block.
    local GetItemInfoInstant = GetItemInfoInstant or function(item)
        -- HINT: WotLK's GetItemInfo returns localized type names rather than modern numeric
        -- class/subclass IDs. Preserve the equipment location at return position 4; callers
        -- that require numeric class IDs must handle unavailable values safely.
        if not GetItemInfo then return end;

        local name, link, rarity, level, minLevel, itemType, itemSubType,
            stackCount, equipLoc = GetItemInfo(item);

        if not name then return end;
        return nil, itemType, itemSubType, equipLoc, nil, nil, nil;
    end;

    local EQUIPLOC_SLOTID = {
        INVTYPE_HEAD = 1,
        INVTYPE_NECK = 2,
        INVTYPE_SHOULDER = 3,
        INVTYPE_BODY = 4,
        INVTYPE_CHEST = 5,
        INVTYPE_ROBE = 5,
        INVTYPE_WAIST = 6,
        INVTYPE_LEGS = 7,
        INVTYPE_FEET = 8,
        INVTYPE_WRIST = 9,
        INVTYPE_HAND = 10,
        INVTYPE_FINGER = 11,
        INVTYPE_TRINKET = 13,
        INVTYPE_WEAPON = 16,
        INVTYPE_SHIELD = 17,
        INVTYPE_CLOAK = 15,
        INVTYPE_2HWEAPON = 16,
        INVTYPE_WEAPONMAINHAND = 16,
        INVTYPE_WEAPONOFFHAND = 17,
        INVTYPE_HOLDABLE = 17,
        INVTYPE_RANGED = 18,
        INVTYPE_RANGEDRIGHT = 18,
    };

    -- Format positive and non-positive item-stat differences with distinct colors.
    local FORMAT_POSITIVE_VALUE = "|cff19ff19+%s|r %s";
    local FORMAT_NEGATIVE_VALUE = "|cffff2020%s|r %s";

    local function FormatValueDiff(value, name)
        if value > 0 then
            return FORMAT_POSITIVE_VALUE:format(value, name);
        else
            return FORMAT_NEGATIVE_VALUE:format(value, name);
        end
    end

    -- Map an item's equipment location to its inventory slot.
    local function GetEquippedSlotID(item)
        local _, _, _, itemEquipLoc = GetItemInfoInstant(item);
        return itemEquipLoc and EQUIPLOC_SLOTID[itemEquipLoc]
    end

    -- Return the equipped item link or links that can be compared with the given item.
    local function GetEquippedItemLink(comparisonItem)
        local slotID = GetEquippedSlotID(comparisonItem);

        if slotID then
            local link1 = GetInventoryItemLink("player", slotID);
            local link2;
            if slotID == 11 then
                link2 = GetInventoryItemLink("player", 12);
            elseif slotID == 13 then
                link2 = GetInventoryItemLink("player", 14);
            elseif slotID == 16 then
                link2 = GetInventoryItemLink("player", 17);
                if link2 then
                    local slotID2 = GetEquippedSlotID(link2);
                    if not (slotID2 and slotID2 == slotID) then
                        link2 = nil;
                    end
                end
            end

            if link2 and not link1 then
                link1 = link2;
                link2 = nil;
            end

            return link1, link2
        end
    end
    API.GetEquippedItemLink = GetEquippedItemLink;


    -- Return the item-level difference, optionally formatted as localized text.
    local function GetItemLevelDelta(newItem, oldItem, formatedToText)
        local newItemLevel = API.GetItemLevel(newItem) or 0;
        local oldItemLevel = API.GetItemLevel(oldItem) or 0;
        local diff = newItemLevel - oldItemLevel;

        if formatedToText then
            if diff ~= 0 then
                return FormatValueDiff(diff, L["Item Level"]);
            end
            return
        end

        return diff
    end
    API.GetItemLevelDelta = GetItemLevelDelta;


    -- Compare an item's level with the currently equipped item in each applicable slot.
    local function GetEquippedItemLevelDelta(newLink)
        if not (newLink and API.IsEquippableItem(newLink)) then return end;

        local newItemLevel = API.GetItemLevel(newLink) or 0;
        local slotID = GetEquippedSlotID(newLink);
        local unit = "player";

        if slotID then
            local link1, link2, secondarySlotID;
            local itemID1 = GetInventoryItemID(unit, slotID);
            local itemID2;

            if itemID1 then
                link1 = GetInventoryItemLink(unit, slotID);
            end
            if slotID == 11 then
                secondarySlotID = 12;
            elseif slotID == 13 then
                secondarySlotID = 14;
            elseif slotID == 16 then
                secondarySlotID = 17;
                itemID2 = GetInventoryItemID(unit, secondarySlotID);
                if itemID2 then
                    local equippedSlotID = GetEquippedSlotID(itemID2);
                    if not (equippedSlotID and equippedSlotID == slotID) then
                        itemID2 = nil;
                        secondarySlotID = nil;
                    end
                else
                    secondarySlotID = nil;
                end
            end

            local n = 0;
            local tbl = {};
            local itemLevel;

            if itemID1 then
                n = n + 1;
                itemLevel = link1 and API.GetItemLevel(link1) or 0;
                tbl[n] = {
                    isReady = itemLevel > 0 and newItemLevel > 0,
                    delta = newItemLevel - itemLevel,
                };
            else
                n = n + 1;
                tbl[n] = {
                    isReady = newItemLevel > 0,
                    delta = newItemLevel,
                };
            end

            if secondarySlotID then
                itemID2 = GetInventoryItemID(unit, secondarySlotID);
                link2 = GetInventoryItemLink(unit, secondarySlotID);
                n = n + 1;
                if itemID2 then
                    itemLevel = link2 and API.GetItemLevel(link2) or 0;
                    tbl[n] = {
                        isReady = itemLevel > 0 and newItemLevel > 0,
                        delta = newItemLevel - itemLevel,
                    };
                else
                    tbl[n] = {
                        isReady = newItemLevel > 0,
                        delta = newItemLevel,
                    };
                end
            end

            return tbl
        end
    end

    -- Select the largest available item-level improvement and report whether all comparisons are ready.
    local function GetMaxEquippedItemLevelDelta(newLink)
        local itemLevelDeltaInfo = GetEquippedItemLevelDelta(newLink);
        if itemLevelDeltaInfo then
            local isReady = true;
            local maxDelta;
            for _, info in ipairs(itemLevelDeltaInfo) do
                if info.isReady then
                    if not maxDelta then
                        maxDelta = info.delta;
                    elseif info.delta > maxDelta then
                        maxDelta = info.delta;
                    end
                else
                    isReady = false;
                end
            end
            return maxDelta, isReady
        else
            return nil, true
        end
    end
    API.GetMaxEquippedItemLevelDelta = GetMaxEquippedItemLevelDelta;


    -- Compare a quest reward item with the currently equipped item.
    local function GetRewardItemLevelDelta(questInfoType, index)
        local newLink = GetQuestItemLink(questInfoType, index);
        return GetMaxEquippedItemLevelDelta(newLink);
    end
    API.GetRewardItemLevelDelta = GetRewardItemLevelDelta;

    -- Return whether an item is an upgrade and whether the comparison data is ready.
    local function IsItemAnUpgrade(newLink)
        local delta, isReady = GetMaxEquippedItemLevelDelta(newLink)
        return (delta and delta > 0), isReady
    end
    API.IsItemAnUpgrade = IsItemAnUpgrade;
    API.IsItemAnUpgrade_External = IsItemAnUpgrade;

    -- Compare a quest reward item with equipped gear to determine whether it is an upgrade.
    local function IsRewardItemUpgrade(questInfoType, index)
        local newLink = GetQuestItemLink(questInfoType, index);
        return API.IsItemAnUpgrade_External(newLink)
    end
    API.IsRewardItemUpgrade = IsRewardItemUpgrade;


    -- Tooltip-based compatibility layer for clients without C_TooltipInfo.
    local TooltipAPI = {};

    -- Create a minimal color object when the client does not provide CreateColor.
    local CreateColor = CreateColor or function(r, g, b, a)
        return {
            r = r, g = g, b = b, a = a,
            GetRGB = function(self)
                return self.r, self.g, self.b;
            end,
        };
    end;

    local TOOLTIP_NAME = "DialogueUIVirtualTooltip";
    local TP = CreateFrame("GameTooltip", TOOLTIP_NAME, nil, "GameTooltipTemplate");
    local UIParent = UIParent;

    TP:SetOwner(UIParent, "ANCHOR_NONE");

    -- HINT: Guard SetClampedToScreen in case a modified 3.3.5 client lacks this frame method.
    if TP.SetClampedToScreen then
        TP:SetClampedToScreen(false);
    end

    TP:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, -128);
    TP:Show();
    TP:SetScript("OnUpdate", nil);
    TP.shouldManuallyAddItemLevel = true;

    -- Delay tooltip-data notifications to avoid firing repeatedly during rapid tooltip updates.
    local UpdateFrame = CreateFrame("Frame");

    local function UpdateTooltipInfo_OnUpdate(self, elapsed)
        self.t = self.t + elapsed;
        if self.t > 0.2 then
            self.t = 0;
            self:SetScript("OnUpdate", nil);
            CallbackRegistry:Trigger("SharedTooltip.TOOLTIP_DATA_UPDATE", 0);
        end
    end

    -- Reset the update timer when the tooltip's item or spell changes.
    function UpdateFrame:OnItemChanged(numLines)
        self.t = 0;
        self.numLines = numLines;
        self:SetScript("OnUpdate", UpdateTooltipInfo_OnUpdate);
    end

    -- Retrieve the current item or spell hyperlink when the GameTooltip supports those getters.
    local function GetTooltipHyperlink()
        -- HINT: Older GameTooltip implementations may not expose GetItem/GetSpell.
        -- Getter wrappers below set TP.hyperlink explicitly as a fallback.
        if TP.GetItem then
            local name, link = TP:GetItem();
            if link then
                return link
            end
        end

        if TP.GetSpell then
            local name, link = TP:GetSpell();
            if link then
                return "spell:" .. link
            end
        end

        return TP.hyperlink
    end

    -- Convert the current GameTooltip lines into a common data table for addon consumers.
    local function GetTooltipTexts()
        local numLines = TP:NumLines();
        if numLines == 0 then return end;

        local tooltipData = {};
        tooltipData.dataInstanceID = 0;

        local shouldAddItemLevel = TP.shouldManuallyAddItemLevel;
        local itemLevel;
        local itemLink = GetTooltipHyperlink();

        if itemLink then
            if itemLink ~= TP.previousHyperlink then
                UpdateFrame:OnItemChanged(numLines);
            end

            if shouldAddItemLevel and API.IsEquippableItem(itemLink) then
                itemLevel = API.GetItemLevel(itemLink);
            end
        end

        TP.previousHyperlink = itemLink;
        tooltipData.hyperlink = itemLink;

        local lines = {};
        local n = 0;

        local fs, text;
        for i = 1, numLines do
            -- Insert the manually computed item level near the top of the tooltip.
            if i == 2 and shouldAddItemLevel and itemLevel then
                n = n + 1;
                lines[n] = {
                    leftText = L["Format Item Level"] and L["Format Item Level"]:format(itemLevel) or ("Item Level: " .. itemLevel),
                    leftColor = CreateColor(1, 0.82, 0),
                };
            end

            fs = _G[TOOLTIP_NAME .. "TextLeft" .. i];
            if fs then
                n = n + 1;

                local r, g, b = fs:GetTextColor();
                text = fs:GetText();
                local lineData = {
                    leftText = text,
                    leftColor = CreateColor(r, g, b),
                    rightText = nil,
                    wrapText = true,
                    leftOffset = 0,
                };

                fs = _G[TOOLTIP_NAME .. "TextRight" .. i];
                if fs then
                    text = fs:GetText();
                    if text and text ~= "" then
                        r, g, b = fs:GetTextColor();
                        lineData.rightText = text;
                        lineData.rightColor = CreateColor(r, g, b);
                    end
                end

                lines[n] = lineData;
            end
        end

        -- Append the vendor sell price when the item API returns one.
        local sellPrice = itemLink and API.GetItemSellPrice and API.GetItemSellPrice(itemLink);
        if sellPrice then
            n = n + 1;
            lines[n] = {
                leftText = "",
                price = sellPrice,
            };
        end

        tooltipData.lines = lines;
        return tooltipData
    end

    -- Expose only tooltip operations supported by the current client.
    do
        local accessors = {
            SetItemByID = "GetItemByID",
            SetCurrencyByID = "GetCurrencyByID",
            SetQuestItem = "GetQuestItem",
            SetQuestCurrency = "GetQuestCurrency",
            SetSpellByID = "GetSpellByID",
            SetItemByGUID = "GetItemByGUID",
            SetHyperlink = "GetHyperlink",
        };

        for accessor, getterName in pairs(accessors) do
            local setter = TP[accessor];

            -- HINT: WotLK commonly lacks SetItemByID and SetSpellByID.
            -- Emulate those two operations using the legacy SetHyperlink method.
            if not setter and TP.SetHyperlink and accessor == "SetItemByID" then
                setter = function(tooltip, itemID)
                    tooltip.hyperlink = "item:" .. itemID;
                    tooltip:SetHyperlink(tooltip.hyperlink);
                end
            elseif not setter and TP.SetHyperlink and accessor == "SetSpellByID" then
                setter = function(tooltip, spellID)
                    tooltip.hyperlink = "spell:" .. spellID;
                    tooltip:SetHyperlink(tooltip.hyperlink);
                end
            end

            if setter then
                TooltipAPI[getterName] = function(...)
                    TP:ClearLines();
                    TP:SetOwner(UIParent, "ANCHOR_PRESERVE");
                    setter(TP, ...);
                    return GetTooltipTexts();
                end
            end
        end

        -- HINT: SetQuestItem is retained only if the GameTooltip actually implements it.
        -- If the target 3.3.5 client lacks it, quest reward tooltip retrieval needs a
        -- client-specific fallback rather than a modern C_TooltipInfo call.
    end

    addon.TooltipAPI = TooltipAPI;

    -- Compare item class/subclass values returned by the available item-info API.
    local function AreItemsSameType(item1, item2)
        local classID1, subclassID1 = select(6, GetItemInfoInstant(item1));
        local classID2, subclassID2 = select(6, GetItemInfoInstant(item2));

        -- HINT: The WotLK fallback above cannot provide modern numeric class IDs.
        -- Avoid treating two unavailable IDs as a confirmed matching item type.
        if classID1 == nil or classID2 == nil or subclassID1 == nil or subclassID2 == nil then
            return false
        end

        return classID1 == classID2 and subclassID1 == subclassID2;
    end

    -- Load an equippable item tooltip for comparison and report that a comparison was started.
    local function GetItemComparisonInfo(item)
        local _, _, _, itemEquipLoc = GetItemInfoInstant(item);
        local slotID = itemEquipLoc and EQUIPLOC_SLOTID[itemEquipLoc];

        if slotID then
            TP:ClearLines();
            TP:SetOwner(UIParent, "ANCHOR_PRESERVE");
            if type(item) == "number" then
                -- HINT: Use the legacy hyperlink setter when SetItemByID is unavailable.
                if TP.SetItemByID then
                    TP:SetItemByID(item);
                elseif TP.SetHyperlink then
                    TP.hyperlink = "item:" .. item;
                    TP:SetHyperlink(TP.hyperlink);
                else
                    return
                end
            else
                TP.hyperlink = item;
                TP:SetHyperlink(item);
            end
            return nil, true
        end
    end
    API.GetItemComparisonInfo = GetItemComparisonInfo;

    -- Use localized trigger labels where available, with WotLK English fallbacks.
    local ON_USE = ITEM_SPELL_TRIGGER_ONUSE or "Use:";
    local ON_EQUIP = ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:";

    -- Cache whether each item link has already been inspected for use/equip effects.
    local ITEMLINK_CACHED = {};

    -- Extract "Use" and "Equip" effect lines from an item tooltip.
    local function GetItemEffect(itemLink)
        local cached = true;
        local classID, subClassID = select(6, GetItemInfoInstant(itemLink));

        -- HINT: The fallback GetItemInfoInstant cannot supply numeric class IDs in WotLK.
        -- This class-ID test therefore requires a client-specific mapping if it must work there.
        if classID == 4 and subClassID == 0 then
            local tooltipData = addon.TooltipAPI.GetHyperlink and addon.TooltipAPI.GetHyperlink(itemLink);
            if tooltipData and tooltipData.lines then
                if not ITEMLINK_CACHED[itemLink] then
                    ITEMLINK_CACHED[itemLink] = true;
                    cached = false;
                end

                local effectText, processed;
                for _, lineData in ipairs(tooltipData.lines) do
                    processed = false;
                    if lineData.leftText then
                        if find(lineData.leftText, ON_USE) then
                            processed = true;
                            if effectText then
                                effectText = effectText .. "\n" .. lineData.leftText;
                            else
                                effectText = lineData.leftText;
                            end
                        end

                        if (not processed) and find(lineData.leftText, ON_EQUIP) then
                            if effectText then
                                effectText = effectText .. "\n" .. lineData.leftText;
                            else
                                effectText = lineData.leftText;
                            end
                        end
                    end
                end
                return effectText, cached
            end
        end
        return nil, true
    end
    API.GetItemEffect = GetItemEffect;
end


-- Item helpers with legacy API fallbacks for WotLK 3.3.5a.
do  -- Items (3.3.5 Compatibility)
    local GetItemInfo = GetItemInfo;

    -- HINT: WotLK may not provide IsEquippableItem. Determine equipability from
    -- the legacy GetItemInfo equipment-location return value instead.
    local IsEquippableItem = IsEquippableItem or function(item)
        if not item or not GetItemInfo then return false end;

        local name, link, quality, itemLevel, minLevel, itemType, itemSubType,
            stackCount, equipLoc = GetItemInfo(item);

        return equipLoc ~= nil and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP";
    end;

    -- These modern item categories are not exposed by the WotLK item APIs.
    local IsCosmeticItem = AlwaysFalse;
    local IsDecorItem = AlwaysFalse;
    local GetTransmogItemInfo = AlwaysFalse;

    -- Return the item level from the modern detailed API or the legacy item-info API.
    local function GetItemLevelFallback(item)
        if not item or not GetItemInfo then return 0 end;

        local name, link, quality, itemLevel = GetItemInfo(item);
        return itemLevel or 0;
    end
    local GetItemLevel = GetDetailedItemLevelInfo or GetItemLevelFallback;

    -- HINT: Match the modern GetItemInfoInstant return positions used by this addon.
    -- WotLK's GetItemInfo provides localized type/subtype and equipment location,
    -- but not reliable numeric classID/subclassID values. Those fields remain nil.
    local GetItemInfoInstant = GetItemInfoInstant or function(item)
        if not item or not GetItemInfo then return end;

        local itemID;
        if type(item) == "number" then
            itemID = item;
        elseif type(item) == "string" then
            itemID = tonumber(string.match(item, "[Ii]tem:(%d+)"));
        end

        local name, link, rarity, itemLevel, minLevel, itemType, itemSubType,
            stackCount, equipLoc, texture = GetItemInfo(item);

        if not name then return end;

        -- Return order: itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID.
        return itemID, itemType, itemSubType, equipLoc, texture, nil, nil;
    end;

    -- Dressing-room item previews and toys are unsupported or unavailable in WotLK.
    local IsDressableItem = IsDressableItemByID or AlwaysFalse;
    local GetQuestItemLink = GetQuestItemLink;
    local GetToyInfo = AlwaysNil;

    -- Expose item APIs and compatibility fallbacks to other addon modules.
    API.IsEquippableItem = IsEquippableItem;
    API.IsCosmeticItem = IsCosmeticItem;
    API.GetTransmogItemInfo = GetTransmogItemInfo;
    API.GetItemInfo = GetItemInfo;
    API.IsDressableItem = IsDressableItem;
    API.IsDecorItem = IsDecorItem;

    -- Return an item's level, defaulting to zero when it is unavailable.
    local function _GetItemLevel(item)
        if item then
            return GetItemLevel(item) or 0
        end
    end
    API.GetItemLevel = _GetItemLevel;

    -- Check whether an item can be compared as equippable gear and is not cosmetic.
    local function IsItemValidForComparison(itemID)
        return itemID and (not IsCosmeticItem(itemID)) and IsEquippableItem(itemID)
    end
    API.IsItemValidForComparison = IsItemValidForComparison;

    -- Return the item's vendor sell price when it is known and greater than zero.
    local function GetItemSellPrice(item)
        if item and GetItemInfo then
            local sellPrice = select(11, GetItemInfo(item));
            if sellPrice and sellPrice > 0 then
                return sellPrice
            end
        end
    end
    API.GetItemSellPrice = GetItemSellPrice;

    -- Return the sell price of a quest-choice item, or zero when no item link is available.
    local function GetQuestChoiceSellPrice(index)
        if not GetQuestItemLink then return 0 end;

        local hyperlink = GetQuestItemLink("choice", index);
        if hyperlink and find(hyperlink, "[Ii]tem:") then
            return GetItemSellPrice(hyperlink) or 0
        else
            return 0
        end
    end
    API.GetQuestChoiceSellPrice = GetQuestChoiceSellPrice;

    -- Classify an item using modern numeric class IDs when they are available.
    local function GetItemClassification(item)
        if IsCosmeticItem(item) then
            return "cosmetic"
        end

        local itemID, _, _, _, _, classID, subClassID = GetItemInfoInstant(item);

        if API.IsContainerItem and API.IsContainerItem(itemID) then
            return "container"
        end

        if classID == 2 or classID == 4 then
            return "equipment"
        elseif classID == 17 then
            return "pet"
        elseif classID == 15 then
            if subClassID == 2 then
                return "pet"
            elseif subClassID == 5 then
                return "mount"
            end
        end

        local toyItemID = GetToyInfo(itemID);
        if toyItemID then
            return "toy"
        end

        if IsDecorItem(itemID) then
            return "decor"
        end

        -- HINT: The WotLK fallback cannot provide numeric classID/subClassID,
        -- and modern toy/decor APIs are unavailable. This may return nil for
        -- otherwise classifiable legacy items unless a localized type mapping
        -- is added for the target client.
    end
    API.GetItemClassification = GetItemClassification;
end


-- Helpers for resolving the preferred interact binding and checking controller mode.
do  -- Keybindings
    -- HINT: Guard the API so the helper remains safe on clients where it is unavailable.
    local GetBindingKey = GetBindingKey or function()
        return nil, nil;
    end;

    -- Find the first interact-target binding that is a single key rather than a key combination.
    local function GetBestInteractKey()
        local key1, key2 = GetBindingKey("INTERACTTARGET");
        local key, errorText;

        -- Normalize empty strings to nil so unbound keys follow the same path.
        if key1 == "" then key1 = nil; end;
        if key2 == "" then key2 = nil; end;

        if key1 or key2 then
            if key1 then
                if not find(key1, "-") then
                    key = key1;
                end
            end

            if (not key) and key2 then
                if not find(key2, "-") then
                    key = key2;
                end
            end

            if not key then
                errorText = L["Cannot Use Key Combination"];
            end
        else
            errorText = L["Interact Key Not Set"];
        end

        -- HINT: Verify that "INTERACTTARGET" is an actual binding command in the target
        -- 3.3.5 client. If it is not, this correctly reports no binding, but a client-specific
        -- legacy binding action or addon setting will be needed to provide an interact key.
        return key, errorText
    end
    API.GetBestInteractKey = GetBestInteractKey;

    -- Treat every configured input device other than keyboard and mouse as controller mode.
    API.IsControllerMode = function()
        return addon.GetDBValue("InputDevice") ~= 1
    end
end

-- Texture helpers for standard icon presentation.
do  -- TextureUtil
    -- Crop the outer edge of an icon texture to hide its built-in border.
    local function RemoveIconBorder(texture)
        -- SetTexCoord is available on WotLK texture regions.
        texture:SetTexCoord(0.0625, 0.9375, 0.0625, 0.9375);
    end
    API.RemoveIconBorder = RemoveIconBorder;
end



-- Bag helpers for locating items and retrieving quest-related item metadata.
do  -- Inventory Bags Container (3.3.5 Compatibility)
    -- WotLK bag IDs are 0 for the backpack and 1–4 for equipped bags.
    local NUM_BAG_SLOTS = 4;
    local GetItemCount = GetItemCount;
    local GetContainerNumSlots = GetContainerNumSlots;
    local GetContainerItemID = GetContainerItemID;
    local GetContainerItemQuestInfo = GetContainerItemQuestInfo;
    local GetContainerItemInfo = GetContainerItemInfo;
    local GetInventoryItemID = GetInventoryItemID;

    -- Find the first bag and slot containing the specified item ID.
    local function GetItemBagPosition(itemID)
        -- HINT: Guard the APIs so this helper fails safely if a client build or UI
        -- modification does not expose one of the expected container functions.
        if not itemID or not GetItemCount or not GetContainerNumSlots or not GetContainerItemID then
            return
        end

        local count = GetItemCount(itemID); -- The default does not include bank contents.
        if count and count > 0 then
            for bagID = 0, NUM_BAG_SLOTS do
                for slotID = 1, GetContainerNumSlots(bagID) do
                    if GetContainerItemID(bagID, slotID) == itemID then
                        return bagID, slotID
                    end
                end
            end
        end
    end
    API.GetItemBagPosition = GetItemBagPosition;

    -- Return readable/lootable state and quest association for an item in the bags.
    local function GetBagQuestItemInfo(itemID)
        -- Used by Widget_QuestItemDisplay.
        local bagID, slotID = GetItemBagPosition(itemID);
        if bagID and slotID and GetContainerItemInfo then
            -- In WotLK, GetContainerItemInfo returns multiple values rather than a table:
            -- texture, itemCount, locked, quality, readable, lootable, itemLink.
            local texture, itemCount, locked, quality, readable, lootable =
                GetContainerItemInfo(bagID, slotID);

            if texture then
                local itemInfo = {};
                itemInfo.isReadable = readable;
                itemInfo.hasLoot = lootable;

                -- HINT: GetContainerItemQuestInfo is not guaranteed to exist in 3.3.5.
                -- Keep quest metadata optional when the client does not provide it.
                if GetContainerItemQuestInfo then
                    local _, questID, isActive = GetContainerItemQuestInfo(bagID, slotID);
                    if questID then
                        itemInfo.questID = questID;
                        itemInfo.isOnQuest = isActive;
                    end
                end

                return itemInfo
            end
        end
    end
    API.GetBagQuestItemInfo = GetBagQuestItemInfo;

    -- Return an item hyperlink from the bags or equipped slots when one is available.
    local function GetItemLinkInBag(itemID)
        if not itemID or not GetItemCount or not GetContainerNumSlots
            or not GetContainerItemID or not GetContainerItemInfo then
            return
        end

        local count = GetItemCount(itemID);
        if count and count > 0 then
            for bagID = 0, NUM_BAG_SLOTS do
                for slotID = 1, GetContainerNumSlots(bagID) do
                    if GetContainerItemID(bagID, slotID) == itemID then
                        local _, _, _, _, _, _, hyperlink =
                            GetContainerItemInfo(bagID, slotID);
                        if hyperlink then
                            return hyperlink
                        end
                    end
                end
            end

            -- HINT: Localize both inventory functions here. The original code localized
            -- GetInventoryItemID but called GetInventoryItemLink as a global.
            local GetInventoryItemLink = GetInventoryItemLink;
            if GetInventoryItemID and GetInventoryItemLink then
                for slotID = 1, 19 do
                    if GetInventoryItemID("player", slotID) == itemID then
                        return GetInventoryItemLink("player", slotID)
                    end
                end
            end

            -- Fall back to an item hyperlink when no bag or equipment link was returned.
            return string.format("|Hitem:%d|h", itemID)
        end
    end
    API.GetItemLinkInBag = GetItemLinkInBag;
end


-- Spell helpers with safe fallbacks for APIs that may be unavailable in WotLK 3.3.5a.
do  -- Spell (3.3.5 Compatibility)
    local GetSpellInfo = GetSpellInfo;

    -- HINT: Do not treat every non-nil ID as a valid spell. In WotLK, GetSpellInfo
    -- is the appropriate fallback for checking whether the client recognizes a spell.
    local DoesSpellExist = DoesSpellExist or function(spellID)
        return spellID ~= nil and GetSpellInfo and GetSpellInfo(spellID) ~= nil;
    end;

    -- WotLK has no modern shapeshift-form ID API; zero represents no known form.
    local GetShapeshiftFormID = GetShapeshiftFormID or AlwaysZero;

    -- Glyph lookup by spell is unavailable on clients without this API.
    local GetCurrentGlyphNameForSpell = GetCurrentGlyphNameForSpell or AlwaysNil;

    API.GetShapeshiftFormID = GetShapeshiftFormID;

    -- Return the glyph ID associated with a spell when the client provides that lookup.
    local function GetGlyphIDForSpell(spellID)
        local _, glyphID = GetCurrentGlyphNameForSpell(spellID);
        return glyphID
    end
    API.GetGlyphIDForSpell = GetGlyphIDForSpell;


    -- Return a localized spell name, or a readable fallback for missing spell data.
    local function GetSpellName(spellID)
        if spellID and DoesSpellExist(spellID) then
            local name = GetSpellInfo and GetSpellInfo(spellID);
            return name
        else
            if spellID then
                return "Unknown Spell: " .. tostring(spellID)
            else
                return "Unknown Spell"
            end
        end
    end
    API.GetSpellName = GetSpellName;
end



-- Helpers for formatting durations and measuring elapsed time since first use.
do  -- Time -- Date
    local time = time;
    local abs = math.abs; -- HINT: Use the absolute duration when formatting negative values.

    -- Use client-provided localized duration formats when available.
    local D_DAYS = D_DAYS or "%d |4Day:Days;";
    local D_HOURS = D_HOURS or "%d |4Hour:Hours;";
    local D_MINUTES = D_MINUTES or "%d |4Minute:Minutes;";
    local D_SECONDS = D_SECONDS or "%d |4Second:Seconds;";

    -- Abbreviated unit formats; these defaults match the full labels.
    local DAYS_ABBR = DAYS_ABBR or "%d |4Day:Days;"
    local HOURS_ABBR = HOURS_ABBR or "%d |4Hr:Hr;";
    local MINUTES_ABBR = MINUTES_ABBR or "%d |4Min:Min;";
    local SECONDS_ABBR = SECONDS_ABBR or "%d |4Sec:Sec;";

    local format = string.format;

    -- Apply a duration format string to one numeric unit value.
    local function FormatTime(t, pattern)
        return format(pattern, t)
    end

    -- Format seconds as days, hours, minutes, and seconds.
    -- If oneUnit is true, show only the largest non-zero unit.
    local function SecondsToTime(seconds, abbreviated, oneUnit)
        -- HINT: Reject invalid input instead of performing arithmetic on nil or non-numeric values.
        if type(seconds) ~= "number" then
            return "";
        end

        local initialSeconds = seconds; -- HINT: Correct spelling; retain the original sign for display.
        seconds = abs(seconds);          -- HINT: Format the duration magnitude, then add the sign afterward.

        local timeString = "";
        local isComplete = false;
        local days = 0;
        local hours = 0;
        local minutes = 0;

        -- Extract whole days and retain the remaining seconds.
        if seconds >= 86400 then
            days = floor(seconds / 86400);
            seconds = seconds - days * 86400;

            local dayText = FormatTime(days, (abbreviated and DAYS_ABBR) or D_DAYS);
            timeString = dayText;

            if oneUnit then
                isComplete = true;
            end
        end

        -- Extract hours unless one-unit formatting has already selected days.
        if not isComplete then
            hours = floor(seconds / 3600);
            seconds = seconds - hours * 3600;

            if hours > 0 then
                local hourText = FormatTime(hours, (abbreviated and HOURS_ABBR) or D_HOURS);
                if timeString == "" then
                    timeString = hourText;
                else
                    timeString = timeString.." "..hourText;
                end

                if oneUnit then
                    isComplete = true;
                end
            end
        end

        -- Extract minutes unless a larger unit was selected.
        if not isComplete then
            minutes = floor(seconds / 60);
            seconds = seconds - minutes * 60;

            if minutes > 0 then
                local minuteText = FormatTime(minutes, (abbreviated and MINUTES_ABBR) or D_MINUTES);
                if timeString == "" then
                    timeString = minuteText;
                else
                    timeString = timeString.." "..minuteText;
                end

                if oneUnit then
                    isComplete = true;
                end
            end
        end

        -- Append remaining whole seconds when not limited to one unit.
        if (not isComplete) and seconds > 0 then
            seconds = floor(seconds);
            local secondText = FormatTime(seconds, (abbreviated and SECONDS_ABBR) or D_SECONDS);
            if timeString == "" then
                timeString = secondText;
            else
                timeString = timeString.." "..secondText;
            end
        end

        -- HINT: The previous implementation colored negative values but formatted
        -- their duration as an empty string. Display the sign as well as the color.
        if initialSeconds < 0 then
            timeString = "|cffff4800-"..timeString.."|r";
        end

        return timeString
    end
    API.SecondsToTime = SecondsToTime;

    -- Format seconds as a clock string in minutes:seconds form.
    local function SecondsToClock(seconds)
        --Clock: 00:00
        -- HINT: Use the absolute duration for the fields and preserve a negative sign explicitly.
        if type(seconds) ~= "number" then
            return "0:00";
        end

        local sign = seconds < 0 and "-" or "";
        seconds = abs(seconds);
        return format("%s%s:%02d", sign, floor(seconds / 60), floor(seconds % 60))
    end
    API.SecondsToClock = SecondsToClock;


    -- Return elapsed whole seconds since the first call to this function.
    local REF_TIME;
    local function GetRelativeTime()
        if not REF_TIME then
            REF_TIME = time();
            return 0
        end

        return time() - REF_TIME
    end
    API.GetRelativeTime = GetRelativeTime;
end


-- System helpers with fallbacks for APIs that differ between client versions.
do  -- System
    -- Prefer the modern multi-focus API and return its first result.
    if GetMouseFoci then
        local GetMouseFoci = GetMouseFoci;
        local function GetMouseFocus()
            local objects = GetMouseFoci();
            return objects and objects[1]
        end
        API.GetMouseFocus = GetMouseFocus;
    elseif GetMouseFocus then
        -- WotLK provides the legacy single-focus API.
        API.GetMouseFocus = GetMouseFocus;
    else
        API.GetMouseFocus = AlwaysNil;
    end

    -- Objective-tracker refresh is not available in WotLK 3.3.5a.
    local function TriggerQuestObjectiveTrackerDirty()
        -- HINT: Deliberate no-op: the modern objective tracker does not exist in WotLK.
        return;
    end
    API.TriggerQuestObjectiveTrackerDirty = TriggerQuestObjectiveTrackerDirty;

    -- Resolve a quest ID to its legacy quest-log index.
    local function GetLegacyQuestLogIndex(questID)
        if questID and GetQuestLogIndexByID then
            local index = GetQuestLogIndexByID(questID);
            if index and index > 0 then
                return index
            end
        end
    end

    -- Refresh a quest's watch status to dismiss its objective-tracker popup when possible.
    local function RemoveQuestObjectiveTrackerQuestPopUp(questID)
        -- Prefer modern quest-ID-based watch APIs when available.
        if C_QuestLog and C_QuestLog.GetQuestWatchType
            and C_QuestLog.RemoveQuestWatch and C_QuestLog.AddQuestWatch then

            local watchType = C_QuestLog.GetQuestWatchType(questID);
            local isWatched = watchType ~= nil;

            if isWatched then
                C_QuestLog.RemoveQuestWatch(questID);
                C_QuestLog.AddQuestWatch(questID);
            else
                C_QuestLog.AddQuestWatch(questID);
                C_QuestLog.RemoveQuestWatch(questID);
            end
            return
        end

        -- HINT: WotLK watch APIs use the quest-log index rather than the quest ID.
        -- Only toggle the watch when the legacy API can determine its current state.
        local index = GetLegacyQuestLogIndex(questID);
        if index and IsQuestWatched and AddQuestWatch and RemoveQuestWatch then
            local isWatched = IsQuestWatched(index);
            if isWatched then
                RemoveQuestWatch(index);
                AddQuestWatch(index);
            else
                AddQuestWatch(index);
                RemoveQuestWatch(index);
            end
        end
    end
    API.RemoveQuestObjectiveTrackerQuestPopUp = RemoveQuestObjectiveTrackerQuestPopUp;


    -- Clear keyboard focus safely, using the secure-call helper available on this client.
    local GetCurrentKeyBoardFocus = GetCurrentKeyBoardFocus or AlwaysNil;

    function API.ClearEditBoxFocus()
        local keyBoardFocus = GetCurrentKeyBoardFocus();
        if keyBoardFocus and keyBoardFocus.ClearFocus then
            -- HINT: securecallfunction is not guaranteed in WotLK.
            -- Fall back to the legacy securecall API, then invoke the method directly.
            if securecallfunction then
                securecallfunction(keyBoardFocus.ClearFocus, keyBoardFocus);
            elseif securecall then
                securecall(keyBoardFocus.ClearFocus, keyBoardFocus);
            else
                keyBoardFocus:ClearFocus();
            end
        end
    end
    CallbackRegistry:Register("DialogueUI.Show", API.ClearEditBoxFocus);
    CallbackRegistry:Register("BookUI.Show", API.ClearEditBoxFocus);


    -- Close known gossip confirmation popups when the client exposes the legacy popup API.
    if StaticPopup_FindVisible then
        function API.CloseGossipStaticPopups()
            local whiches = {"GOSSIP_CONFIRM", "GOSSIP_ENTER_CODE"};
            local soundUnmuted = true;
            for _, which in ipairs(whiches) do
                local dialog = StaticPopup_FindVisible(which);
                if dialog then
                    if soundUnmuted then
                        soundUnmuted = false;
                        API.BrieflyMuteUIOpenHideSound();
                    end
                    dialog:Show();
                    dialog:Hide();
                end
            end
        end
    else
        API.CloseGossipStaticPopups = AlwaysNil;
    end
end


-- Zone and location helpers.
do  -- Zone -- Location -- Area (3.3.5 Compatibility)
    -- Return the localized name of the player's current zone.
    local function GetZoneName(areaID)
        -- HINT: GetRealZoneText is available on WotLK; areaID is unused because
        -- this legacy API reports the player's current zone rather than an arbitrary area.
        return (GetRealZoneText and GetRealZoneText()) or "";
    end
    API.GetZoneName = GetZoneName;
end


-- Optional developer-only diagnostics.
do  -- Dev Tool
    local DEV_MODE = false;

    -- Keep this block disabled in production; its diagnostic queries include modern-only APIs.
    if not DEV_MODE then return end;

    local GetQuestIDForLogIndex = C_QuestLog and C_QuestLog.GetQuestIDForLogIndex;
    local GetQuestInfo = C_QuestLog and C_QuestLog.GetInfo;

    -- Count quest capacity for debugging; this calculation depends on client quest-log semantics.
    local function GetNumQuestCanAccept()
        --numQuests include all types of quests.
        --(Account/Daily) quests don't count towards MaxQuest(35)
        if not MAX_QUESTS then
            -- HINT: Guard this modern API before enabling the developer block on WotLK.
            if not C_QuestLog or not C_QuestLog.GetMaxNumQuestsCanAccept then
                return 0, 0
            end
            MAX_QUESTS = C_QuestLog.GetMaxNumQuestsCanAccept();
        end

        if not GetNumQuestLogEntries or not GetQuestIDForLogIndex or not GetQuestInfo then
            return 0, MAX_QUESTS
        end

        local numShownEntries, numAllQuests = GetNumQuestLogEntries();
        local numQuests = 0;
        local questID;

        for i = 1, numShownEntries do
            questID = GetQuestIDForLogIndex(i);
            if questID ~= 0 then
                print(i, questID)
            end
            if questID ~= 0 and not API.IsAccountQuest(questID) then
                local info = GetQuestInfo(i);
                if info and (not (info.isHidden or info.isHeader)) and info.frequency == 1 then
                    numAllQuests = numAllQuests - 1;
                end
            end
        end

        return MAX_QUESTS - numAllQuests, MAX_QUESTS
    end

    -- Add a key/value diagnostic row to a tooltip.
    local function TooltipAddInfo(tooltip, info, key)
        if info then
            tooltip:AddDoubleLine(key, tostring(info[key]));
        end
    end

    -- Quest-info fields included in the developer tooltip when present.
    local QuestInfoFields = {
        "questID", "campaignID", "frequency", "isHeader", "isTask", "isBounty", "isStory", "isAutoComplete",
    };

    -- Display quest metadata for the quest-log row currently under the cursor.
    local function QuestMapLogTitleButton_OnEnter_Callback(_, button, questID)
        local tooltip = GameTooltip;
        if not tooltip or not tooltip:IsShown() then return end;

        -- HINT: The modern quest map and several fields below are not available in WotLK.
        if not C_QuestLog or not C_QuestLog.GetInfo or not button or not button.questLogIndex then
            return
        end

        local info = C_QuestLog.GetInfo(button.questLogIndex);
        if not info then return end;

        for _, key in ipairs(QuestInfoFields) do
            TooltipAddInfo(tooltip, info, key)
        end

        tooltip:AddDoubleLine("Account", tostring(API.IsAccountQuest(questID)));

        -- HINT: Guard modern quest metadata calls; they are not part of the WotLK quest API.
        if C_QuestLog.IsQuestCalling then
            tooltip:AddDoubleLine("isCalling", tostring(C_QuestLog.IsQuestCalling(questID)));
        end
        if C_QuestLog.GetQuestType then
            tooltip:AddDoubleLine("QuestType", tostring(C_QuestLog.GetQuestType(questID)));
        end
        if C_QuestLog.IsRepeatableQuest then
            tooltip:AddDoubleLine("isRepeatable", tostring(C_QuestLog.IsRepeatableQuest(questID)));
        end

        tooltip:Show();
    end

    -- HINT: EventRegistry is Retail-only. This developer callback is registered only
    -- when that registry exists; use a WotLK-specific tooltip hook if you need it there.
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback(
            "QuestMapLogTitleButton.OnEnter",
            QuestMapLogTitleButton_OnEnter_Callback,
            nil
        );
    end
end
