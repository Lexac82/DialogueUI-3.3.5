local _, addon = ...
local API = addon.API;
local L = addon.L;
local BookComponent = addon.BookComponent;
local GetDBBool = addon.GetDBBool;
local CallbackRegistry = addon.CallbackRegistry;
local TTSUtil = addon.TTSUtil;
local BindingUtil = addon.BindingUtil;
local SwipeEmulator = addon.SwipeEmulator;
local FadeHelper = addon.UIParentFadeHelper;
local Round = API.Round;
local FadeFrame = API.UIFrameFade;

-- ----
-- 3.3.5 compatibility: Keep the event listener and cache frame declarations minimal and classic-safe.
-- ----
local MainFrame;
local EL = CreateFrame("Frame");    --EventListener
local Formatter = {};               --Format content, convert html to fontstring
local Cache = CreateFrame("Frame"); --Cache the whole book when opened

-- ----
-- 3.3.5 compatibility: Several WoW APIs exist only on some clients; guard them before use.
-- ----
local InCombatLockdown = InCombatLockdown;
local UnitGUID = UnitGUID;
local IsShiftKeyDown = IsShiftKeyDown;
local GetBindingAction = GetBindingAction;
local match = string.match;
local find = string.find;
local gsub = string.gsub;

-- 3.3.5 compatibility: C_Item.GetItemIDByGUID is not available on the classic/WotLK client.
local GetItemIDByGUID = (C_Item and C_Item.GetItemIDByGUID) or nil;

-- Legacy ItemText globals are still valid for this book UI.
local CloseItemText = CloseItemText;
local ItemTextGetCreator = ItemTextGetCreator;
local ItemTextGetItem = ItemTextGetItem;
local ItemTextGetMaterial = ItemTextGetMaterial;
local ItemTextGetText = ItemTextGetText;
local ItemTextGetPage = ItemTextGetPage;
local ItemTextHasNextPage = ItemTextHasNextPage;
local ItemTextPrevPage = ItemTextPrevPage;
local ItemTextNextPage = ItemTextNextPage;
local ItemTextIsFullPage = ItemTextIsFullPage;

-- User Settings
local PIXEL_SCALE = 0.53333;
local FRAME_SIZE_MULTIPLIER = 1.0;  --(See DialogueUI.lua) 1.1 / 1.25
local WOW_PAGE_WIDTH = 412; --ParchmentLarge
local OTHER_CONTENT_ALPHA = 0.4;

local TagFonts = {
    ["p"] = "DUIFont_Book_Paragraph",
    ["h1"] = "DUIFont_Book_H1",
    ["h2"] = "DUIFont_Book_H2",
    ["h3"] = "DUIFont_Book_H3",
    ["title"] = "DUIFont_Book_Title",
    ["smallprint"] = "DUIFont_Book_10",
};

local RawSize = {   --Unit: Pixel
    FRAME_WIDTH = 768,
    FRAME_HEIGHT_MAX = 896,
    FRAME_HEIGHT_MIN = 192,
    FRAME_TOP_HEIGHT = 64,
    FRAME_BOTTOM_HEIGHT = 88,

    PIECE_WIDTH = 1024,
    PIECE_HEIGHT_FULL = 1152,
    PIECE_TOP_HEIGHT = 192,
    PIECE_TOP_OFFSET = 128,
    PIECE_BOTTOM_HEIGHT = 256,
    PIECE_BOTTOM_OFFSET = -128,
    PIECE_BOTTOM_OVERLAP = -40,

    PADDING_H = 60,     --To the left/right
    PADDING_V = 90,     --To the top/bottom

    CLOSE_BUTTON_OFFSET = 26,
    CLOSE_BUTTON_SIZE = 64,

    HEADER_DIVIDER_HEIGHT = 32,
    FOOTER_DIVIDER_HEIGHT = 32,

    HEADER_OVERLAP_HEIGHT = 80,
    HEADER_DIVIDER_BELOW_TITLE = -46,

    PAGE_BUTTON_SIZE = 40,
    PAGE_BUTTON_GAP = 2,

    ITEM_BORDER_SIZE = 96,
    ITEM_BORDER_EFFECTIVE_SIZE = 80,
    ITEM_ICON_SIZE = 64,
};

local ConvertedSize = {};

-- Calculates the scaled frame and content dimensions used by the book UI.
local function CalculateSizeData()
    local a = PIXEL_SCALE * FRAME_SIZE_MULTIPLIER;
    for k, v in pairs(RawSize) do
        ConvertedSize[k] = a * v;
    end

    ConvertedSize.FRAME_SHRINK_RANGE = a * (RawSize.FRAME_HEIGHT_MAX - RawSize.FRAME_TOP_HEIGHT - RawSize.FRAME_BOTTOM_HEIGHT);
    ConvertedSize.CONTENT_WIDTH = a * (RawSize.FRAME_WIDTH - 2*RawSize.PADDING_H);

    -- 3.3.5 compatibility: Make sure the formatter utility font exists before using it.
    if Formatter.UtilityFontString then
        Formatter.UtilityFontString:SetWidth(ConvertedSize.CONTENT_WIDTH);
    end
end

-- Extracts the object type and ID from a GUID when the client supports it.
local function GetObjectTypeAndID(guid)
    -- 3.3.5 compatibility: Apply restricted-value checks only when the helper exists.
    if not guid or (API.canaccessvalue and not API.canaccessvalue(guid)) then
        return
    end

    local objectType = match(guid, "^(%a+)%-");
    if objectType == "GameObject" then
        local id = match(guid, "GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)");
        if id then
            return objectType, tonumber(id)
        end
    elseif objectType == "Item" then
        if GetItemIDByGUID then
            local itemID = GetItemIDByGUID(guid);
            return objectType, itemID, itemID
        end

        -- 3.3.5 compatibility: Fall back to the GUID when the Retail helper is unavailable.
        return objectType, guid
    end
end

-- Checks whether the current book has multiple pages.
local function IsMultiPageBook()
    -- 3.3.5 compatibility: Guard the legacy ItemText functions and page result.
    if not ItemTextGetPage or not ItemTextHasNextPage then
        return false
    end

    local page = ItemTextGetPage();
    if not page then
        return false
    end

    local hasNext = ItemTextHasNextPage();
    return (page == 1 and hasNext) or (page > 1)
end


do  --Cache
    Cache.data = {};

    -- Clears the cached book and stops any pending page or layout updates.
    function Cache:ClearObjectCache()
        self.activeData = nil;
        self.fullyCached = false;
        self.needTurnBack = false;
        self.spacingPending = nil;
        self.nextContentIsPageStart = nil;
        self:SetScript("OnUpdate", nil);
    end

    -- Starts a fresh cache record for the currently opened book or readable item.
    function Cache:SetActiveObject(objectType, objectID, itemID)
        self:SetScript("OnUpdate", nil);

        -- 3.3.5 compatibility: Clear transient state before beginning to cache another book.
        self.spacingPending = nil;
        self.nextContentIsPageStart = nil;
        self.pageStartOffset = nil;

        local isObjectChanged;
        local identifier;
        local objectLocation;

        if objectType and objectID then
            identifier = objectType .. ":" .. tostring(objectID);
            isObjectChanged = identifier ~= self.identifier;
            self.identifier = identifier;

            if objectType == "GameObject" and BookComponent.GetPlayerLocation then
                objectLocation = BookComponent:GetPlayerLocation();
            end
        else
            isObjectChanged = true;
            self.identifier = nil;
        end

        local title = ItemTextGetItem and ItemTextGetItem();

        local data = {
            pageTexts = {},         -- [page] = rawText
            fullyCached = false,
            maxPage = 1,
            pageStartOffset = {},   -- [page] = offsetY
            maxContentIndex = 0,
            location = objectLocation,
            title = title,
            itemID = itemID,
            formattedContent = {},
        };

        self.activeData = data;
        self.fullyCached = false;
        self.needTurnBack = false;

        return isObjectChanged
    end

    -- Returns the saved scroll position for the currently identified book.
    function Cache:GetLastPagePosition()
        if not (self.identifier and self.pagePositions) then
            return
        end

        return self.pagePositions[self.identifier]
    end

    -- Saves the current scroll position for the active book.
    function Cache:SavePagePosition()
        if not self.identifier or not MainFrame or not MainFrame.ScrollFrame then
            return
        end

        if not self.pagePositions then
            self.pagePositions = {};
        end

        local offset = MainFrame.ScrollFrame:GetVerticalScroll();
        -- Scroll positions may need resetting if frame scale or font size changes.
        self.pagePositions[self.identifier] = offset;
    end

    -- Reports whether all pages of the active book have been cached.
    function Cache:IsCurrentObjectFullyCached()
        return self.fullyCached
    end

    -- Reports whether the active cache contains multiple pages.
    function Cache:IsMultiPageBook()
        if self.activeData then
            return self.activeData.maxPage > 1
        end

        -- 3.3.5 compatibility: Return the legacy ItemText API result rather than discarding it.
        return IsMultiPageBook()
    end

    -- Returns the cached page count, or one when no book is active.
    function Cache:GetMaxPage()
        return self.activeData and self.activeData.maxPage or 1
    end

    -- Returns the active book's location, if available.
    function Cache:GetBookLocation()
        return self.activeData and self.activeData.location
    end

    -- Returns the active readable item's ID, if available.
    function Cache:GetCurrentItemID()
        return self.activeData and self.activeData.itemID
    end

    -- Advances the in-game readable to its next page after a short delay.
    function Cache:OnUpdate_TurnNextPage(elapsed)
        self.t = self.t + elapsed;
        if self.t > 0.016 then
            self.t = 0;
            self:SetScript("OnUpdate", nil);

            -- 3.3.5 compatibility: ItemTextNextPage is a legacy global; guard it before calling.
            if ItemTextNextPage then
                ItemTextNextPage();
            end

            self.needTurnBack = false;
        end
    end

    -- Schedules an in-game turn to the next page.
    function Cache:RequestTurnNextPage()
        self.t = 0;
        self:SetScript("OnUpdate", self.OnUpdate_TurnNextPage);
    end

    -- Returns the in-game readable to its first page, then lays out the cached book.
    function Cache:OnUpdate_TurnPrevPage(elapsed)
        self.t = self.t + elapsed;
        if self.t > 0.016 then
            self.t = 0;

            -- 3.3.5 compatibility: Guard legacy ItemText functions in case the client lacks them.
            if not ItemTextPrevPage or not ItemTextGetPage then
                self:SetScript("OnUpdate", nil);
                self.needTurnBack = false;
                return
            end

            ItemTextPrevPage();
            local page = ItemTextGetPage();

            if not page or page <= 1 then
                self:SetScript("OnUpdate", nil);
                self.needTurnBack = false;
                self:BeginCalculateTextHeight();
            end
        end
    end

    -- Schedules an in-game turn to the previous page.
    function Cache:RequestTurnPrevPage()
        self.t = 0;
        self:SetScript("OnUpdate", self.OnUpdate_TurnPrevPage);
    end

    -- Caches the current in-game page and advances or starts layout when complete.
    function Cache:CacheCurrentPage()
        if not self.activeData or not ItemTextGetPage or not ItemTextGetText then
            return
        end

        local page = ItemTextGetPage();
        if not page then
            return
        end

        local rawText = ItemTextGetText(page);
        if rawText == nil then
            return
        end

        self.activeData.pageTexts[page] = rawText;

        -- 3.3.5 compatibility: ItemTextHasNextPage is a legacy global and may be absent.
        local hasNextPage = ItemTextHasNextPage and ItemTextHasNextPage();

        if hasNextPage then
            self:RequestTurnNextPage();
        else
            self.activeData.maxPage = page;
            self.activeData.fullyCached = true;
            self.fullyCached = true;
            self.needTurnBack = page > 1;

            self:BeginCalculateTextHeight();
        end
    end

    -- Returns an iterator over the cached raw page texts.
    function Cache:EnumeratePageTexts()
        if self.activeData then
            return ipairs(self.activeData.pageTexts);
        end

        return ipairs({});
    end

    -- Returns an iterator over the formatted content records.
    function Cache:EnumerateFormattedContent()
        if self.activeData then
            return ipairs(self.activeData.formattedContent);
        end

        return ipairs({});
    end

    -- Calculates content positions and records the start offset of each page.
    function Cache:CalculateFullContentHeight(fromOffsetY, removePagePadding)
        local offsetY = fromOffsetY;
        local page = 0;

        if not self.activeData then
            return offsetY
        end

        -- 3.3.5 compatibility: Discard stale offsets when recalculating the layout.
        self.activeData.pageStartOffset = {};

        for _, data in self:EnumerateFormattedContent() do
            if data.text then
                offsetY = offsetY + (data.spacingAbove or 0);

                if data.isPageStart then
                    page = page + 1;
                    self:SetPageStartOffset(page, offsetY);
                end

                data.offsetY = offsetY;
                offsetY = Round(offsetY + (data.textHeight or 0) + (data.spacingBelow or 0));
                data.endingOffsetY = offsetY;
            elseif data.image then
                offsetY = offsetY + (data.spacingAbove or 0);

                if data.isPageStart then
                    page = page + 1;
                    self:SetPageStartOffset(page, offsetY);
                end

                data.offsetY = offsetY;
                offsetY = Round(offsetY + (data.height or 0));
                data.endingOffsetY = offsetY;
            end
        end

        return offsetY
    end

    -- Returns the number of formatted content records in the active book.
    function Cache:GetMaxContentIndex()
        if self.activeData then
            return self.activeData.maxContentIndex
        end

        return 0
    end

    -- Measures a batch of formatted text records on successive update frames.
    function Cache:OnUpdate_CalculateTextHeight(elapsed)
        self.t = self.t + elapsed;
        if self.t > 0 then
            self.t = 0;
            self:SetScript("OnUpdate", nil);

            if not self.activeData then
                return
            end

            for _ = 1, 10 do
                self.fromContentIndex = self.fromContentIndex + 1;

                if self.fromContentIndex <= self.toContentIndex then
                    local data = self.activeData.formattedContent[self.fromContentIndex];
                    if data and data.text then
                        data.textHeight = Formatter:GetTextHeight(data.fontTag, data.text);
                    end
                else
                    if MainFrame then
                        MainFrame:ShowUI();
                    end
                    return
                end
            end

            self:SetScript("OnUpdate", self.OnUpdate_CalculateTextHeight);
        end
    end

    -- Formats all cached pages and starts measuring the formatted text.
    function Cache:BeginCalculateTextHeight()
        if not self.activeData or not MainFrame or not MainFrame.Header then
            return
        end

        local title = self.activeData.title;
        MainFrame.Header:SetTitle(title);
        Formatter.titleText = title;

        -- 3.3.5 compatibility: Rebuild formatting from scratch to avoid duplicated content.
        self.activeData.formattedContent = {};
        self.activeData.maxContentIndex = 0;
        self.spacingPending = nil;
        self.nextContentIsPageStart = nil;

        local addPagePadding = IsMultiPageBook();
        local maxPage = self:GetMaxPage();

        for page, rawText in self:EnumeratePageTexts() do
            self:FlagNextContentIsPageStart();
            Formatter:FormatText(rawText);

            if addPagePadding and page ~= maxPage then
                self:AddSpacerToLastContent(Formatter.PAGE_SPACING);
            end
        end

        self:CalculateTextHeight();
    end

    -- Resets the text-measurement state and begins the asynchronous measurement pass.
    function Cache:CalculateTextHeight()
        if not self.activeData then
            return
        end

        MainFrame:ReleaseAllObjects();
        self.t = 0;
        self.fromContentIndex = 0;
        self.toContentIndex = self:GetMaxContentIndex();
        self:SetScript("OnUpdate", self.OnUpdate_CalculateTextHeight);
    end

    -- Stores a formatted text record in the active book cache.
    function Cache:StoreText(fontTag, text, justifyH, spacingBelow)
        if not self.activeData then
            return
        end

        local index = self.activeData.maxContentIndex + 1;
        self.activeData.maxContentIndex = index;

        justifyH = justifyH or "LEFT";
        if justifyH == "right" then
            -- Treat right alignment as centered for the supported book layouts.
            justifyH = "CENTER";
        end

        local spacingAbove = 0;
        if self.spacingPending then
            spacingAbove = self.spacingPending;
            self.spacingPending = nil;
        end

        local isPageStart;
        if self.nextContentIsPageStart then
            self.nextContentIsPageStart = nil;
            isPageStart = true;
        end

        self.activeData.formattedContent[index] = {
            text = text,
            align = justifyH,
            fontTag = fontTag,
            spacingBelow = spacingBelow or 0,
            spacingAbove = spacingAbove,
            isPageStart = isPageStart,
        };
    end

    -- Removes the trailing spacing from the last formatted text record.
    function Cache:RemoveLastTextSpacingBelow()
        local index = self.activeData and self.activeData.maxContentIndex;
        local data = index and self.activeData.formattedContent[index];

        if data then
            data.spacingBelow = 0;
        end
    end

    -- Stores a formatted image record in the active book cache.
    function Cache:StoreImage(file, align, width, height, left, right, top, bottom)
        if not self.activeData then
            return
        end

        local index = self.activeData.maxContentIndex + 1;
        self.activeData.maxContentIndex = index;

        align = align or "CENTER";

        local spacingAbove = 0;
        if self.spacingPending then
            spacingAbove = self.spacingPending;
            self.spacingPending = nil;
        end

        local isPageStart;
        if self.nextContentIsPageStart then
            self.nextContentIsPageStart = nil;
            isPageStart = true;
        end

        self.activeData.formattedContent[index] = {
            image = file,
            align = align,
            width = width,
            height = height,
            left = left,
            right = right,
            top = top,
            bottom = bottom,
            spacingBelow = 0,
            spacingAbove = spacingAbove,
            isPageStart = isPageStart,
        };
    end

    -- Adds spacing below the last cached content record.
    function Cache:AddSpacerToLastContent(height)
        if not self.activeData then
            return
        end

        local index = self.activeData.maxContentIndex;
        local data = self:GetContentDataByIndex(index);

        if data then
            data.spacingBelow = (data.spacingBelow or 0) + height;
        end
    end

    -- Adds spacing above the next cached content record.
    function Cache:AddSpacerToNextContent(height)
        if self.spacingPending then
            self.spacingPending = self.spacingPending + height;
        else
            self.spacingPending = height;
        end
    end

    -- Marks the next stored content record as the start of a page.
    function Cache:FlagNextContentIsPageStart()
        self.nextContentIsPageStart = true;
    end

    -- Stores the vertical offset at which a page begins.
    function Cache:SetPageStartOffset(page, offsetY)
        if self.activeData then
            self.activeData.pageStartOffset[page] = offsetY;
        end
    end

    -- Returns the vertical offset for a page, or zero when it has none.
    function Cache:GetPageStartOffset(page)
        if self.activeData then
            return self.activeData.pageStartOffset[page] or 0
        end
    end

    -- Returns a formatted content record by its index.
    function Cache:GetContentDataByIndex(contentIndex)
        if self.activeData then
            return self.activeData.formattedContent[contentIndex]
        end
    end

    -- Returns the active book's formatted content list.
    function Cache:GetFormattedContent()
        if self.activeData then
            return self.activeData.formattedContent
        end

        return {};
    end

    -- Returns the active book's raw pages, optionally concatenated for copying.
    function Cache:GetRawContent(concatnate)
        if not self.activeData then
            return
        end

        if not concatnate then
            return self.activeData.pageTexts
        end

        local text = self.activeData.title or "";
        local itemID = self:GetCurrentItemID();

        if itemID then
            text = text .. "\n[itemID:" .. itemID .. "]";
        else
            local location = self:GetBookLocation();
            if location then
                text = text .. "\n" .. location;
            end
        end

        local addPager = #self.activeData.pageTexts > 1;
        for page, rawText in ipairs(self.activeData.pageTexts) do
            if addPager then
                text = text .. "\n\n" .. page .. "\n" .. rawText;
            else
                text = text .. "\n\n" .. rawText;
            end
        end

        return text
    end
end


DUIBookUIMixin = {};

-- Initialize the named XML children and attach the book-frame behavior for WotLK.
function DUIBookFrame_OnLoad(frame)
    API.Mixin(frame, DUIBookUIMixin);

    frame.ScreenVignette = _G["DUIBookFrameScreenVignette"];
    frame.ScrollFrame = _G["DUIBookFrameScrollFrame"];
    frame.ScrollFrame.ScrollChild = _G["DUIBookFrameScrollFrameScrollChild"];
    frame.Header = _G["DUIBookFrameHeader"];
    frame.Header.HeaderDivider = _G["DUIBookFrameHeaderHeaderDivider"];
    -- 3.3.5 compatibility: Bind the pagination divider element declared in BookUI.xml.
    frame.Header.HeaderDividerExclusion = _G["DUIBookFrameHeaderHeaderDividerExclusion"];
    frame.Header.HeaderScrollOverlap = _G["DUIBookFrameHeaderHeaderScrollOverlap"];
    frame.Footer = _G["DUIBookFrameFooter"];
    frame.Footer.FooterDivider = _G["DUIBookFrameFooterFooterDivider"];
    frame.ContentFrame = _G["DUIBookFrameContentFrame"];

    -- Register the frame scripts after its mixin methods are available.
    frame:SetScript("OnShow", frame.OnShow);
    frame:SetScript("OnHide", frame.OnHide);
    frame:SetScript("OnMouseUp", frame.OnMouseUp);

    frame:OnLoad();
end


do  --Background Calculation \ Theme
    local TextureKit = {
        [1] = {
            file = "Parchment.png",
            textColor = {0.19, 0.17, 0.13},
            pageSelectedColor = "Ivory",
            pageNormalColor = "LightBrown",
            shadow = false,
            widgetTheme = 3,
        },
        [2] = {
            file = "Metal.png",
            textColor = {0.8, 0.8, 0.8},
            pageSelectedColor = "DarkModeGrey90",
            pageNormalColor = "DarkModeGrey70",
            shadow = true,
            widgetTheme = 4,
        },
    };

    -- Applies the selected background texture, font colors, shadows, and widget theme.
    function DUIBookUIMixin:SetTextureKit(textureKitID)
        local info = textureKitID and TextureKit[textureKitID];
        if not info or textureKitID == self.textureKitID then
            return
        end

        local file = "Interface/AddOns/DialogueUI/Art/Book/TextureKit-" .. info.file;

        self.textureKitID = textureKitID;
        self.textureFile = file;
        self.widgetTheme = info.widgetTheme;

        if self.BackgroundPieces then
            for _, obj in pairs(self.BackgroundPieces) do
                obj:SetTexture(file);
            end
        end

        if self.CloseButton then
            self.CloseButton:SetUITexture(file);
        end

        self.Header:SetUITexture(file);
        self.Header.HeaderScrollOverlap:SetTexture(file);
        self.Header.HeaderScrollOverlap:SetTexCoord(128/1024, 896/1024, 1408/2048, 1488/2048);

        self.Footer.FooterDivider:SetTexture(file);
        self.Footer.FooterDivider:SetTexCoord(0, 768/1024, 1488/2048, 1520/2048);

        self.Header.HeaderDivider:SetTexture(file);
        self.Header.HeaderDivider:SetTexCoord(0, 768/1024, 1520/2048, 1552/2048);

        local r, g, b = unpack(info.textColor);
        local useShadow = info.shadow;

        for tag, fontObjectName in pairs(TagFonts) do
            local fontObject = _G[fontObjectName];

            -- 3.3.5 compatibility: Ignore font objects that are not defined by the loaded UI files.
            if fontObject then
                if tag == "smallprint" then
                    addon.ThemeUtil:SetFontColor(fontObject, info.pageNormalColor);
                else
                    fontObject:SetTextColor(r, g, b);
                end

                if useShadow then
                    fontObject:SetShadowOffset(0, 2);
                    fontObject:SetShadowColor(0, 0, 0);
                else
                    fontObject:SetShadowOffset(0, 0);
                end
            end
        end

        self.Header:SetPageTextColor(info.pageSelectedColor, info.pageNormalColor);

        if self.TTSButton then
            self.TTSButton:SetTheme(info.widgetTheme);
        end

        if self.CopyTextButton then
            self.CopyTextButton:SetTheme(info.widgetTheme);
        end

        if self.SourceItemButton then
            self.SourceItemButton:SetTexture(file);
        end
    end

    -- Sets the book frame height and positions its one- or two-piece background.
    function DUIBookUIMixin:SetFrameHeight(height, scrollable)
        local pieces = self.BackgroundPieces;

        if not pieces then
            pieces = {};
            self.BackgroundPieces = pieces;
            pieces[1] = self:CreateTexture(nil, "BACKGROUND", nil, -1);
            pieces[2] = self.Footer:CreateTexture(nil, "OVERLAY", nil, -1);
        end

        local size = ConvertedSize;

        if height < size.FRAME_HEIGHT_MIN then
            height = size.FRAME_HEIGHT_MIN;
        end

        local isDynamicHeight = (not scrollable) and (height + 8) < size.FRAME_HEIGHT_MAX;
        local useTwoPieceBG = scrollable or isDynamicHeight;

        if not isDynamicHeight then
            height = size.FRAME_HEIGHT_MAX;
        end

        if useTwoPieceBG or (useTwoPieceBG ~= self.useTwoPieceBG) then
            pieces[1]:ClearAllPoints();
            pieces[2]:ClearAllPoints();

            if useTwoPieceBG then
                local centralRatio = (height - size.FRAME_TOP_HEIGHT - size.FRAME_BOTTOM_HEIGHT) / size.FRAME_SHRINK_RANGE;
                if centralRatio > 1 then
                    centralRatio = 1;
                elseif centralRatio < 0 then
                    centralRatio = 0;
                end

                pieces[1]:SetTexCoord(0, 1, 0, (192 + 744 * centralRatio)/2048);
                pieces[1]:SetSize(size.PIECE_WIDTH, size.PIECE_TOP_HEIGHT);
                pieces[1]:SetPoint("TOP", self, "TOP", 0, size.PIECE_TOP_OFFSET);
                pieces[1]:SetPoint("BOTTOM", pieces[2], "TOP", 0, size.PIECE_BOTTOM_OVERLAP);

                pieces[2]:SetTexCoord(0, 1, 1152/2048, 1408/2048);
                pieces[2]:SetSize(size.PIECE_WIDTH, size.PIECE_BOTTOM_HEIGHT);
                pieces[2]:SetPoint("BOTTOM", self, "BOTTOM", 0, size.PIECE_BOTTOM_OFFSET);
                pieces[2]:Show();
            else
                height = size.FRAME_HEIGHT_MAX;

                pieces[1]:SetTexCoord(0, 1, 0, 1152/2048);
                pieces[1]:SetSize(size.PIECE_WIDTH, size.PIECE_HEIGHT_FULL);
                pieces[1]:SetPoint("CENTER", self, "CENTER", 0, 0);
                pieces[2]:Hide();
            end

            self.useTwoPieceBG = useTwoPieceBG;
            self:SetSize(size.FRAME_WIDTH, height);
        end

        return height
    end

    -- Positions the book frame and screen vignette within the current viewport.
    function DUIBookUIMixin:Reposition()
        local viewportWidth = API.GetBestViewportSize();
        local distanceToEdge = 48;
        local defaultOffsetX, anchor;
        local vignetteOffset = viewportWidth * 128/896;

        self.ScreenVignette:ClearAllPoints();

        local isLeft = true;

        if isLeft then
            defaultOffsetX = -0.5 * viewportWidth + distanceToEdge;
            anchor = "LEFT";
            self.ScreenVignette:SetTexCoord(0, 1, 0, 1);
            self.ScreenVignette:SetPoint("TOPLEFT", nil, "TOP", -0.5 * viewportWidth - vignetteOffset, 1);
            self.ScreenVignette:SetPoint("BOTTOMRIGHT", nil, "BOTTOM", 0.5 * viewportWidth, -1);
        else
            defaultOffsetX = 0.5 * viewportWidth - distanceToEdge;
            anchor = "RIGHT";
            self.ScreenVignette:SetTexCoord(1, 0, 0, 1);
            self.ScreenVignette:SetPoint("TOPLEFT", nil, "TOP", -0.5 * viewportWidth, 1);
            self.ScreenVignette:SetPoint("BOTTOMRIGHT", nil, "BOTTOM", 0.5 * viewportWidth + vignetteOffset, -1);
        end

        self.defaultOffsetX = defaultOffsetX;
        self.defaultAnchor = anchor;

        self:ClearAllPoints();
        self:SetPoint(anchor, nil, "CENTER", defaultOffsetX, 0);
    end

    -- Updates the optional source-item widget's spacing and dimensions.
    function DUIBookUIMixin:UpdateSourceItemButton()
        if self.SourceItemButton then
            local size = ConvertedSize;
            self.SourceItemButton:SetTextSpacing(Formatter.TEXT_SPACING);

            local maxTextWidth = size.CONTENT_WIDTH - size.ITEM_BORDER_EFFECTIVE_SIZE;
            self.SourceItemButton:SetWidgetSize(
                size.ITEM_BORDER_SIZE,
                size.ITEM_ICON_SIZE,
                size.ITEM_BORDER_EFFECTIVE_SIZE,
                Formatter.FONT_SIZE,
                maxTextWidth
            );
        end
    end

    -- Reapplies scaled dimensions to the book frame and its child controls.
    function DUIBookUIMixin:Resize()
        local size = ConvertedSize;

        self.ContentFrame:SetSize(size.FRAME_WIDTH, 64);

        if self.CloseButton then
            self.CloseButton:SetPoint(
                "TOPRIGHT",
                self,
                "TOPRIGHT",
                -size.CLOSE_BUTTON_OFFSET,
                -size.CLOSE_BUTTON_OFFSET
            );
            self.CloseButton:SetSize(size.CLOSE_BUTTON_SIZE, size.CLOSE_BUTTON_SIZE);
        end

        self.Header.Title:SetWidth(size.CONTENT_WIDTH);
        self.Header.Title:SetPoint("TOP", self, "TOP", 0, -size.PADDING_V);

        self.Header.HeaderScrollOverlap:SetSize(size.FRAME_WIDTH, size.HEADER_OVERLAP_HEIGHT);
        self.Footer.FooterDivider:SetSize(size.FRAME_WIDTH, size.FOOTER_DIVIDER_HEIGHT);
        self.Header.HeaderDivider:SetSize(size.FRAME_WIDTH, size.HEADER_DIVIDER_HEIGHT);
        self.Header:SetPageButtonSize(size.PAGE_BUTTON_SIZE, size.PAGE_BUTTON_GAP);

        self.Header:SetWidth(size.CONTENT_WIDTH);
        self:LayoutWidgets();
        self:UpdateSourceItemButton();
    end

    -- Calculates pagination, frame height, and scroll-frame placement for formatted content.
    function DUIBookUIMixin:SetScrollContentHeight(contentHeight, maxPage)
        local size = ConvertedSize;

        local usePagination = maxPage > 1;
        local titleHeight = self.Header:GetTitleHeight();
        local titleLineHeight = self.Header:GetTitleEffectiveLineHeight();
        local titleSpacing = 0.35 * titleLineHeight;
        local heightBelowTitle;
        local heightBelowTitleNoPagination = titleSpacing + 2;

        if usePagination then
            heightBelowTitle = Formatter.PARAGRAPH_SPACING + size.PAGE_BUTTON_SIZE;
        else
            heightBelowTitle = heightBelowTitleNoPagination;
        end

        local maxContentHeight = size.FRAME_HEIGHT_MAX
            - 2 * size.PADDING_V
            - titleHeight
            - heightBelowTitle;
        local scrollable = contentHeight > maxContentHeight;

        if not scrollable then
            usePagination = false;
        end

        if maxPage > 1 and not usePagination then
            local offsetY = self:GetContentFromOffsetY(false);
            Cache:CalculateFullContentHeight(offsetY);
        end

        if not usePagination then
            heightBelowTitle = heightBelowTitleNoPagination;
            maxPage = 1;
        end

        self.Header:SetHeightBelowTitle(heightBelowTitle);

        local numPageButtons = self.Header:SetMaxPage(maxPage);
        local headerOffsetY;

        -- 3.3.5 compatibility: HeaderDividerExclusion is absent from the supplied BookUI.xml.
        -- If the XML later defines it, this block toggles it to leave space behind the page buttons.
        local dividerExclusion = self.Header.HeaderDividerExclusion;

        if usePagination then
            if dividerExclusion then
                dividerExclusion:Show();
                local buttonSpan = numPageButtons * (size.PAGE_BUTTON_SIZE + size.PAGE_BUTTON_GAP)
                    + 3 * size.PAGE_BUTTON_GAP;
                dividerExclusion:SetWidth(buttonSpan);
                dividerExclusion:SetHeight(size.PAGE_BUTTON_SIZE + 4);
            end

            headerOffsetY = size.HEADER_DIVIDER_BELOW_TITLE;
            self.Header.HeaderDivider:ClearAllPoints();
            self.Header.HeaderDivider:SetPoint("CENTER", self.Header.Title, "BOTTOM", 0, headerOffsetY);
        else
            if dividerExclusion then
                dividerExclusion:Hide();
            end

            headerOffsetY = -Formatter.PARAGRAPH_SPACING;
            self.Header.HeaderDivider:ClearAllPoints();
            self.Header.HeaderDivider:SetPoint(
                "CENTER",
                self,
                "TOP",
                0,
                -Round(size.PADDING_V + titleHeight + titleSpacing)
            );
        end

        local headerHeight = self.Header:GetHeaderHeight();
        local totalFrameHeight = headerHeight + contentHeight + 2 * size.PADDING_V;
        self:SetFrameHeight(totalFrameHeight, scrollable);

        self.ScrollFrame:ClearAllPoints();
        self.ScrollFrame:SetPoint(
            "TOPLEFT",
            self,
            "TOPLEFT",
            0,
            -size.PADDING_V - headerHeight
        );
        self.ScrollFrame:SetPoint(
            "BOTTOMRIGHT",
            self,
            "BOTTOMRIGHT",
            0,
            size.PADDING_V
        );

        local scrollRange;

        if scrollable then
            self.ContentFrame:SetParent(self.ScrollFrame.ScrollChild);
            self.ContentFrame:SetPoint("TOPLEFT", self.ScrollFrame.ScrollChild, "TOPLEFT", 0, 0);
            self.ContentFrame:SetFrameLevel(self.ScrollFrame.ScrollChild:GetFrameLevel());

            local scrollFrameHeight = self.ScrollFrame:GetHeight();
            scrollRange = Round(contentHeight + Formatter.PAGE_SPACING - scrollFrameHeight);
            self:SetScript("OnMouseWheel", self.OnMouseWheel);
        else
            scrollRange = 0;
            self.ContentFrame:SetParent(self);
            self.ContentFrame:SetPoint("TOP", self, "TOP", 0, -size.PADDING_V - headerHeight);
            self.ContentFrame:SetFrameLevel(self.Footer:GetFrameLevel() + 10);
            self:SetScript("OnMouseWheel", nil);
        end

        self.scrollable = scrollable;
        self.ScrollFrame:SetScrollRange(scrollRange);
        self.ScrollFrame:SetUseOverlapBorder(scrollable, scrollable);

        self.Header:SetHeight(Round(headerHeight));
        SwipeEmulator:SetScrollable(scrollable, self.ScrollFrame);
    end
end



do  --Scroll Anim
    -- A very small easing helper for the intro animation.
    local EasingFunc = addon.EasingFunctions.outQuart;
    local ANIM_DURATION_SCROLL_EXPAND = 0.5;

    -- Animates the book frame into view when it is shown.
    local function AnimIntro_FlyIn_OnUpdate(self, elapsed)
        self.t = self.t + elapsed;
        local offsetY = EasingFunc(self.t, -48, 0, ANIM_DURATION_SCROLL_EXPAND);
        local alpha = 4 * self.t;

        if alpha > 1 then
            alpha = 1;
        end

        if self.t >= ANIM_DURATION_SCROLL_EXPAND then
            offsetY = 0;
            self.t = 0;
            self:SetScript("OnUpdate", nil);

            -- 3.3.5 compatibility: Do not force any object visibility on older clients.
            local function ShowOutOfBoundObjects(obj)
                -- obj:Show();
            end

            self.fontStringPool:ProcessActiveObjects(ShowOutOfBoundObjects);
            self.texturePool:ProcessActiveObjects(ShowOutOfBoundObjects);
        end

        self:SetPoint(self.defaultAnchor, nil, "CENTER", self.defaultOffsetX, offsetY);
        self:SetAlpha(alpha);
    end

    -- Resets the scroll position to the top of the content.
    function DUIBookUIMixin:ResetScroll()
        self.ScrollFrame:ResetScroll();
    end

    -- Returns true when the book is at the top of the scrollable content.
    function DUIBookUIMixin:IsAtPageTop()
        if self.scrollable then
            return self.ScrollFrame:IsAtPageTop();
        else
            return true
        end
    end

    -- Returns true when the book is at the bottom of the scrollable content.
    function DUIBookUIMixin:IsAtPageBottom()
        if self.scrollable then
            return self.ScrollFrame:IsAtPageBottom();
        else
            return true
        end
    end

    -- Handles mouse wheel scrolling for the book content.
    function DUIBookUIMixin:OnMouseWheel(delta)
        if not Cache:IsCurrentObjectFullyCached() then
            return
        end

        if delta > 0 then
            if IsShiftKeyDown() then
                self:ScrollToNearPrevPage();
            else
                self:ScrollBy(-Formatter.OFFSET_PER_SCROLL);
            end
        else
            if IsShiftKeyDown() then
                self:ScrollToNearNextPage();
            else
                self:ScrollBy(Formatter.OFFSET_PER_SCROLL);
            end
        end
    end

    -- Scrolls by a relative value.
    function DUIBookUIMixin:ScrollBy(deltaValue)
        self.ScrollFrame:ScrollBy(deltaValue);
    end

    -- Scrolls to an absolute vertical position.
    function DUIBookUIMixin:ScrollTo(value)
        self.ScrollFrame:ScrollTo(value);
    end

    -- Scrolls the content so the given content index is moved toward the top.
    function DUIBookUIMixin:ScrollToContent(contentIndex)
        local data = Cache:GetContentDataByIndex(contentIndex);
        if data then
            local offsetY = data.offsetY;
            offsetY = offsetY - self.scrollFromOffetY;
            self:ScrollTo(offsetY);
        end
    end

    -- Scrolls to the start of a given page.
    function DUIBookUIMixin:ScrollToPage(page)
        local maxPage = Cache:GetMaxPage();
        if page > maxPage then
            page = maxPage;
        end

        if page == 1 then
            self:ScrollTo(0);
            return
        end

        local offsetY = Cache:GetPageStartOffset(page);
        if offsetY then
            offsetY = offsetY - self.scrollFromOffetY;
            self:ScrollTo(offsetY);
        end
    end

    -- Determines the current page based on the scroll position.
    function DUIBookUIMixin:GetCurrentPage()
        local offset = self.ScrollFrame:GetScrollTarget() + self.scrollFromOffetY + 0.4 * self.ScrollFrame:GetViewSize();
        local maxPage = Cache:GetMaxPage();

        if self.ScrollFrame:IsAtPageTop() then
            return 1
        end

        if self.ScrollFrame:IsAtPageBottom() then
            return maxPage
        end

        for page = maxPage, 1, -1 do
            local pageOffset = Cache:GetPageStartOffset(page);
            if offset > pageOffset then
                return page
            end
        end

        return 1
    end

    -- Scrolls just beyond the next page break.
    function DUIBookUIMixin:ScrollToNearNextPage()
        local offset = self.ScrollFrame:GetScrollTarget() + self.scrollFromOffetY + 0.1;
        local maxPage = Cache:GetMaxPage();

        for page = 1, maxPage do
            local pageOffset = Cache:GetPageStartOffset(page);
            if offset < pageOffset then
                if page == 1 and page < maxPage then
                    page = 2;
                    pageOffset = Cache:GetPageStartOffset(page);
                end
                local offsetY = pageOffset - self.scrollFromOffetY;
                self:ScrollTo(offsetY)
                break
            end
        end
    end

    -- Scrolls just before the previous page break.
    function DUIBookUIMixin:ScrollToNearPrevPage()
        local offset = self.ScrollFrame:GetScrollTarget() + self.scrollFromOffetY - 0.1;
        local maxPage = Cache:GetMaxPage();

        for page = maxPage, 1, -1 do
            local pageOffset = Cache:GetPageStartOffset(page);
            if offset > pageOffset then
                local offsetY;
                if page == 1 then
                    offsetY = 0;
                else
                    offsetY = pageOffset - self.scrollFromOffetY;
                end
                self:ScrollTo(offsetY)
                break
            end
        end
    end
end



do  --Formatter
    local IgnoredTags = {
        ["<br/>"] = true,
        ["</p>"] = true,
        ["<HTML><BODY>"] = true,
        ["</BODY></HTML>"] = true,
    };

    local ValidAlignments = {
        ["left"] = "LEFT",
        ["center"] = "CENTER",
        ["right"] = "RIGHT",
    };

    -- Sets the base font size and derived spacing values used throughout the formatter.
    function Formatter:SetBaseFontSize(baseFontSize)
        self.FONT_SIZE = baseFontSize;
        self.TEXT_SPACING = 0.35 * baseFontSize;
        self.PARAGRAPH_SPACING = 4 * self.TEXT_SPACING;
        self.PAGE_SPACING = 4 * self.PARAGRAPH_SPACING;
        self.OFFSET_PER_SCROLL = Round(4 * (self.FONT_SIZE + self.TEXT_SPACING));

        -- 3.3.5 compatibility: Utility font string may not be initialized yet.
        if self.UtilityFontString then
            self.UtilityFontString:SetSpacing(self.TEXT_SPACING);
        end
    end

    -- Acquires a reusable texture object from the pool.
    function Formatter:AcquireTexture()
        if MainFrame and MainFrame.texturePool then
            local tex = MainFrame.texturePool:Acquire();
            return tex
        end

        return nil
    end

    -- Applies the appropriate font object to a FontString by tag name.
    function Formatter:SetFontObjectByTag(fontString, fontTag)
        if not fontString then
            return
        end

        if not (fontTag and TagFonts[fontTag]) then
            fontTag = "p";
        end

        fontString:SetFontObject(TagFonts[fontTag]);
    end

    -- Acquires a reusable FontString object by tag and applies the matching font.
    function Formatter:AcquireFontStringByTag(fontTag)
        if MainFrame and MainFrame.fontStringPool then
            local fs = MainFrame.fontStringPool:Acquire();
            self:SetFontObjectByTag(fs, fontTag);
            return fs
        end

        return nil
    end

    -- Inserts a plain text block at the given offset and returns the updated offset.
    function Formatter:InsertText(offsetY, text, tag, justifyH)
        -- Unused in the current layout flow, but kept as a legacy helper.
        local fs = self:AcquireFontStringByTag(tag);
        if not fs then
            return offsetY, 0
        end

        local textRef = MainFrame.ContentFrame;
        fs:SetPoint("TOP", textRef, "TOP", 0, -offsetY);
        fs:SetJustifyH(justifyH or "LEFT");
        fs:SetText(text);
        local height = fs:GetHeight();
        offsetY = Round(offsetY + height);
        return offsetY, height
    end

    -- Inserts a header block and adds padding below it.
    function Formatter:InsertHeader(offsetY, text, tag, justifyH)
        -- Unused in the current layout flow, but kept as a legacy helper.
        local textHeight;
        offsetY, textHeight = self:InsertText(offsetY, text, tag, justifyH);
        offsetY = offsetY + ConvertedSize.PADDING_H;
        return offsetY, textHeight
    end

    -- Inserts a paragraph block and adds paragraph spacing above it.
    function Formatter:InsertParagraph(offsetY, text, tag, justifyH)
        -- Unused in the current layout flow, but kept as a legacy helper.
        local textHeight;
        offsetY, textHeight = self:InsertText(offsetY + self.PARAGRAPH_SPACING, text, tag, justifyH);
        return offsetY, textHeight
    end

    -- Sets the width used by the utility font string for measuring text height.
    function Formatter:SetUtilityTextWidth(width)
        if self.UtilityFontString then
            self.UtilityFontString:SetWidth(width);
        end
    end

    -- Returns the measured height of text rendered with a specific font tag.
    function Formatter:GetTextHeight(fontTag, text)
        if not self.UtilityFontString then
            return 0
        end

        self.UtilityFontString:SetSpacing(self.TEXT_SPACING or 0);
        self.UtilityFontString:SetSize(ConvertedSize.CONTENT_WIDTH or 0, 0);

        if fontTag ~= self.utilityFontTag then
            self.utilityFontTag = fontTag;
            local fontObject = TagFonts[fontTag] or TagFonts["p"];
            self.UtilityFontString:SetFontObject(fontObject);
        end

        self.UtilityFontString:SetText(text);
        local height = self.UtilityFontString:GetHeight();
        self.UtilityFontString:SetText(nil);

        return height
    end

    -- Decides whether input text should be parsed as plain paragraphs or HTML.
    function Formatter:FormatText(text)
        if find(text, "<HTML>") then
            return self:FormatHTML(text)
        else
            return self:FormatParagraph(text)
        end
    end

    -- Converts plain text into cached book content without HTML parsing.
    function Formatter:FormatParagraph(text)
        local paragraphs = API.SplitParagraph(text);
        local fontTag = "p";
        local align = "LEFT";
        local paragraphSpacing = self.PARAGRAPH_SPACING;
        local numParagraphs = paragraphs and #paragraphs or 0;
        local anyAdded = false;

        if numParagraphs > 0 then
            for _, paragraphText in ipairs(paragraphs) do
                if paragraphText ~= "" then
                    anyAdded = true;
                    Cache:StoreText(fontTag, paragraphText, align, paragraphSpacing);
                end
            end
        end

        if anyAdded then
            Cache:RemoveLastTextSpacingBelow();
        end
    end

    -- Removes a small set of legacy HTML wrapper tags from the formatted text.
    local function CleanUpTags(text)
        text = gsub(text, "^<[^<>]+>", "", 1);
        text = gsub(text, "^<[^<>]+>", "", 1);
        text = gsub(text, "<[^<>]+>$", "", 1);
        text = gsub(text, "<[^<>]+>$", "", 1);
        text = gsub(text, "<[^<>]+>$", "", 1);
        text = gsub(text, "<BR/>", "\n");
        return text
    end

    -- Parses HTML-like book content and converts images/tags into cache entries.
    function Formatter:FormatHTML(text)
        local paragraphs = API.SplitParagraph(text);
        local match = match;
        local lower = string.lower;

        local numTexts = 0;
        local numImages = 0;
        local paragraphSpacing = self.PARAGRAPH_SPACING or 0;
        local numParagraphs = paragraphs and #paragraphs or 0;
        local anyAdded = false;

        if numParagraphs > 0 then
            for _, paragraphText in ipairs(paragraphs) do
                if not IgnoredTags[paragraphText] then
                    local tag, align;
                    tag = match(paragraphText, "^</*([%w]+)/*>");
                    if not tag then
                        tag = match(paragraphText, "^<([%w]+)%s");
                    end

                    if tag and not IgnoredTags[tag] then
                        tag = lower(tag);

                        if tag == "img" then
                            local file = match(paragraphText, "src=\"([%S]+)\"");
                            if file then
                                numImages = numImages + 1;

                                local width = match(paragraphText, "width=\"(%d+)");
                                width = width and tonumber(width);
                                local height = match(paragraphText, "height=\"(%d+)");
                                height = height and tonumber(height);

                                align = match(paragraphText, "align=\"(%a+)") or "center";
                                local imageWidth, imageHeight;
                                local left, right, top, bottom = 0, 1, 0, 1;
                                file = lower(file);

                                if not (width and height) then
                                    width, height = BookComponent:GetTextureSize(file);
                                end

                                if not (width and height) then
                                    local ratio, _l, _r, _t, _b = BookComponent:GetTextureCoordForFile(file);
                                    if ratio then
                                        imageWidth = ConvertedSize.CONTENT_WIDTH;
                                        imageHeight = ratio * imageWidth;
                                        width = imageWidth;
                                        height = imageHeight;
                                        left, right, top, bottom = _l, _r, _t, _b;
                                    end

                                    if not (width and height) then
                                        if width then
                                            width = math.min(width, ConvertedSize.CONTENT_WIDTH);
                                            height = width;
                                        elseif height then
                                            height = math.min(height, ConvertedSize.CONTENT_WIDTH);
                                            width = height;
                                        end
                                    end
                                end

                                if not (width and height) then
                                    width = ConvertedSize.CONTENT_WIDTH;
                                    height = width;
                                    imageWidth = Round(width * 0.618);
                                    imageHeight = imageWidth;
                                end

                                if width and height then
                                    if file == "interface\\common\\spacer" then
                                        Cache:AddSpacerToNextContent(self.PARAGRAPH_SPACING);
                                    else
                                        if not imageWidth then
                                            local scale = width / WOW_PAGE_WIDTH;
                                            imageWidth = Round(ConvertedSize.CONTENT_WIDTH * scale);
                                            imageHeight = Round(imageWidth * height / width);
                                        end
                                        Cache:StoreImage(file, align, imageWidth, imageHeight, left, right, top, bottom);
                                    end
                                end
                            end
                        else
                            local _;
                            _, align = match(paragraphText, "^<([%w]+)%s+align=\"(%a+)\"");

                            if align then
                                align = lower(align);
                            end

                            if (not align) or (not ValidAlignments[align]) then
                                align = "LEFT";
                            end

                            paragraphText = CleanUpTags(paragraphText);

                            if paragraphText and paragraphText ~= "" then
                                numTexts = numTexts + 1;
                                if numTexts > 1 or (paragraphText ~= self.titleText) then
                                    if not (tag and TagFonts[tag]) then
                                        tag = "p";
                                    end
                                    anyAdded = true;
                                    Cache:StoreText(tag, paragraphText, align, paragraphSpacing);
                                end
                            end
                        end
                    else
                        paragraphText = CleanUpTags(paragraphText);
                        if paragraphText and paragraphText ~= "" then
                            numTexts = numTexts + 1;
                            align = "LEFT";
                            tag = "p";
                            anyAdded = true;
                            Cache:StoreText(tag, paragraphText, align, paragraphSpacing);
                        end
                    end
                end
            end
        end

        if anyAdded then
            Cache:RemoveLastTextSpacingBelow();
        end
    end

    -- Returns the vertical offset used to position content within the scrollable area.
    function DUIBookUIMixin:GetContentFromOffsetY(scrollable)
        local fromOffsetY;
        if scrollable then
            fromOffsetY = Round(ConvertedSize.PADDING_H - Formatter.PARAGRAPH_SPACING);
        else
            fromOffsetY = Round(Formatter.PARAGRAPH_SPACING);
        end

        -- 3.3.5 compatibility: Scroll offsets are not always initialized until the frame is built.
        MainFrame.scrollFromOffetY = fromOffsetY;
        return fromOffsetY
    end

    -- Rebuilds the content from the cache and sets the scroll state.
    function DUIBookUIMixin:RebuildContentFromCache()
        if not Cache:IsCurrentObjectFullyCached() then
            return
        end

        self:ReleaseAllObjects();

        local maxPage = Cache:GetMaxPage();
        local offsetY = self:GetContentFromOffsetY(maxPage > 1);
        offsetY = Cache:CalculateFullContentHeight(offsetY);
        self:SetScrollContentHeight(offsetY, maxPage);

        self.ScrollFrame:SetContent(Cache:GetFormattedContent());

        local lastOffset = Cache:GetLastPagePosition();
        if lastOffset then
            self.ScrollFrame:SnapTo(lastOffset);
        else
            self:ResetScroll();
        end

        if self.SourceItemButton and GetDBBool("BookUIItemDescription") then
            self:UpdateSourceItemButton();
            self.SourceItemButton:SetItem(Cache:GetCurrentItemID());
        end
    end

    -- Empty placeholder; no logic required in the current implementation.
    function DUIBookUIMixin:SetMaxPage(maxPage)
    end
end


do  --Main UI
    -- Initializes the book frame and creates its utility font string.
    function DUIBookUIMixin:OnLoad()
        MainFrame = self;
        addon.BookUI = self;
        self.OnLoad = nil;
        self:SetScript("OnLoad", nil);

        if addon.SharedVignette then
            addon.SharedVignette:AddOwner(self);
        end

        local utilityFontString = self.ContentFrame:CreateFontString(
            nil,
            "ARTWORK",
            "DUIFont_Book_Paragraph"
        );
        utilityFontString:SetJustifyV("TOP");
        utilityFontString:SetPoint("TOP", self.ContentFrame, "TOP", 0, 0);
        Formatter.UtilityFontString = utilityFontString;

        CalculateSizeData();
        Formatter:SetBaseFontSize(12);
        self:SetFrameHeight(480);

        -- 3.3.5 compatibility: Register the cutscene callback only if this addon API provides it.
        if API.SetPlayCutsceneCallback then
            API.SetPlayCutsceneCallback(function()
                self:Hide();
            end);
        end
    end

    -- Initializes the header, scroll frame, object pools, and close button.
    function DUIBookUIMixin:Init()
        self.Init = nil;
        self:Reposition();

        BookComponent:InitHeader(self.Header);

        local scrollFrame = self.ScrollFrame;
        addon.InitEasyScrollFrame(
            scrollFrame,
            self.Header.HeaderScrollOverlap,
            self.Footer.FooterDivider
        );
        addon.InitRecyclableScrollFrame(scrollFrame);

        -- Sets up or updates a pooled visual object for one content record.
        function scrollFrame:SetObjectData(obj, data, contentIndex)
            if not obj then
                if data.text then
                    obj = Formatter:AcquireFontStringByTag(data.fontTag);
                elseif data.image then
                    obj = Formatter:AcquireTexture();
                end
            end

            if not obj then
                return nil
            end

            local offsetX = 0;

            if data.text then
                Formatter:SetFontObjectByTag(obj, data.fontTag);
                obj:SetJustifyH(data.align);
                obj:SetText(data.text);
            elseif data.image then
                obj:SetSize(data.width, data.height);
                obj:SetTexture(data.image);
                obj:SetTexCoord(data.left, data.right, data.top, data.bottom);
            end

            obj.contentIndex = contentIndex;
            obj:SetPoint("TOP", MainFrame.ContentFrame, "TOP", offsetX, -data.offsetY);
            obj:Show();

            if MainFrame.isReadingContent and data.text then
                if obj.contentIndex == MainFrame.focusedContentIndex then
                    FadeFrame(obj, 0, 1);
                else
                    FadeFrame(obj, 0, OTHER_CONTENT_ALPHA);
                end
            end

            return obj
        end

        -- Returns the visual object type required by a formatted content record.
        function scrollFrame:GetDataRequiredObjectType(data)
            if data.text then
                return "FontString"
            elseif data.image then
                return "Texture"
            end
        end

        -- Synchronizes the header's selected page with the scroll position.
        function scrollFrame:UpdatePagination()
            local page = MainFrame:GetCurrentPage();
            MainFrame.Header:SetCurrentPage(page);
        end

        scrollFrame:SetUsePagination(true);

        -- Creates a font string for the reusable font-string pool.
        local function CreateFontString()
            local fontString = self.ContentFrame:CreateFontString(
                nil,
                "ARTWORK",
                "DUIFont_Quest_Paragraph"
            );
            fontString:SetSpacing(Formatter.TEXT_SPACING);
            return fontString
        end

        -- Clears and hides a font string before returning it to the pool.
        local function RemoveFontString(fontString)
            fontString:SetText(nil);
            fontString:Hide();
            fontString:ClearAllPoints();
        end

        -- Resets a font string's size and line spacing when acquired from the pool.
        local function OnAcquireFontString(fontString)
            fontString:SetSpacing(Formatter.TEXT_SPACING);
            fontString:SetSize(ConvertedSize.CONTENT_WIDTH, 0);
        end

        self.fontStringPool = API.CreateObjectPool(
            CreateFontString,
            RemoveFontString,
            OnAcquireFontString
        );

        -- Creates a texture for the reusable texture pool.
        local function CreateTexture()
            return self.ContentFrame:CreateTexture(nil, "ARTWORK")
        end

        -- Clears and hides a texture before returning it to the pool.
        local function RemoveTexture(texture)
            texture:SetTexture(nil);
            texture:Hide();
            texture:ClearAllPoints();
        end

        self.texturePool = API.CreateObjectPool(CreateTexture, RemoveTexture);

        self.CloseButton = BookComponent:GetCloseButton(self);

        self:Resize();
        self:SetTextureKit(1);
        self:OnShow();
    end

    -- Releases pooled content objects and clears the focused content index.
    function DUIBookUIMixin:ReleaseAllObjects()
        if self.Init then
            return
        end

        self.focusedContentIndex = nil;

        if self.fontStringPool then
            self.fontStringPool:Release();
        end
        if self.texturePool then
            self.texturePool:Release();
        end
    end

    -- Registers combat events and performs show-time setup.
    function DUIBookUIMixin:OnShow()
        EL:RegisterEvent("PLAYER_REGEN_ENABLED");
        EL:RegisterEvent("PLAYER_REGEN_DISABLED");
        EL.inCombat = InCombatLockdown();

        self:EnableControls(true);

        if addon.SharedVignette then
            addon.SharedVignette:TryShow();
        end

        CallbackRegistry:Trigger("BookUI.Show");
    end

    -- Unregisters frame events, clears cached display objects, and restores UI fading.
    function DUIBookUIMixin:OnHide()
        EL:UnregisterEvent("PLAYER_REGEN_ENABLED");
        EL:UnregisterEvent("PLAYER_REGEN_DISABLED");

        self:EnableControls(false);

        if CloseItemText then
            CloseItemText();
        end

        self:ReleaseAllObjects();
        Cache:ClearObjectCache();

        if self.ScrollFrame then
            self.ScrollFrame:ClearContent();
        end

        if addon.SharedVignette then
            addon.SharedVignette:TryHide();
        end

        self:StopReadingBook();
        CallbackRegistry:Trigger("BookUI.Hide");

        -- 3.3.5 compatibility: Check the method with dot syntax before invoking it with colon syntax.
        if FadeHelper and FadeHelper.FadeInUI then
            FadeHelper:FadeInUI(self);
        end
    end

    -- Handles mouse clicks on the book frame, including click-to-read and right-click close.
    function DUIBookUIMixin:OnMouseUp(button)
        if button == "LeftButton" then
            if GetDBBool("TTSEnabled")
                and GetDBBool("BookTTSClickToRead")
                and not SwipeEmulator:ShouldConsumeClick() then
                self:SpeakCursorFocusContent();
            end
        elseif button == "RightButton"
            and GetDBBool("RightClickToCloseUI")
            and self:IsMouseMotionFocus() then
            self:Hide();
        end
    end

    local EasingFunc = addon.EasingFunctions.outQuart;
    local ANIM_DURATION_SCROLL_EXPAND = 0.5;

    -- Animates the book frame into place after it is shown.
    local function AnimIntro_FlyIn_OnUpdate(self, elapsed)
        self.t = self.t + elapsed;

        local offsetY = EasingFunc(self.t, -48, 0, ANIM_DURATION_SCROLL_EXPAND);
        local alpha = math.min(4 * self.t, 1);

        if self.t >= ANIM_DURATION_SCROLL_EXPAND then
            offsetY = 0;
            self.t = 0;
            self:SetScript("OnUpdate", nil);
        end

        self:SetPoint(self.defaultAnchor, nil, "CENTER", self.defaultOffsetX, offsetY);
        self:SetAlpha(alpha);
    end

    -- Rebuilds and displays the cached book content, then plays its entrance animation.
    function DUIBookUIMixin:ShowUI()
        -- 3.3.5 compatibility: The cutscene helper may not be provided by the target client.
        if API.IsPlayingCutscene and API.IsPlayingCutscene() then
            return
        end

        SwipeEmulator:SetOwner(self.ScrollFrame);
        self:RebuildContentFromCache();

        if not self:IsShown() then
            self.t = 0;
            self:SetAlpha(0);
            self:Show();
            self:SetScript("OnUpdate", AnimIntro_FlyIn_OnUpdate);

            if FadeHelper then
                FadeHelper:FadeOutUI(self);
            end
        end

        CallbackRegistry:Trigger("BookUI.BookCached");
    end

    -- Clears the cached book and hides the book frame.
    function DUIBookUIMixin:HideUI()
        Cache:ClearObjectCache();
        self:Hide();
    end

    -- Hides the book UI when the dialogue UI handles an interaction event.
    CallbackRegistry:Register("DialogueUI.HandleEvent", function()
        if MainFrame then
            MainFrame:HideUI();
        end
    end);
end



do  --TTS
    -- Finds the index of the visible text object currently under the mouse cursor.
    function DUIBookUIMixin:GetCursorFocusContent()
        -- 3.3.5 compatibility: Fall back to IsMouseOver if IsMouseMotionFocus is unavailable.
        local hasMouseFocus;
        if self.IsMouseMotionFocus then
            hasMouseFocus = self:IsMouseMotionFocus();
        elseif self.IsMouseOver then
            hasMouseFocus = self:IsMouseOver();
        end

        if not hasMouseFocus or not self.fontStringPool then
            return
        end

        for _, obj in self.fontStringPool:EnumerateActive() do
            -- 3.3.5 compatibility: Check that the pooled object supports the mouse query.
            if obj.IsMouseOver and obj:IsMouseOver() then
                return obj.contentIndex
            end
        end
    end

    -- Fades text objects to emphasize the currently spoken paragraph.
    function DUIBookUIMixin:FadeOtherContent()
        if not self.fontStringPool or not self.ScrollFrame then
            return
        end

        if self.focusedContentIndex and self.isReadingContent then
            -- Applies reading and dimmed alpha values to one pooled text object.
            local function FadeObject(obj)
                if obj.contentIndex == self.focusedContentIndex then
                    FadeFrame(obj, 1, 1);
                else
                    FadeFrame(obj, 1, OTHER_CONTENT_ALPHA);
                end
            end

            self.fontStringPool:ProcessAllObjects(FadeObject);

            -- Reapplies text emphasis after scrolling finishes.
            self.ScrollFrame.onScrollFinishedCallback = function()
                self:FadeOtherContent();
            end
        else
            -- Restores full opacity on one pooled text object.
            local function FadeObject(obj)
                local duration = self:IsVisible() and 0.5 or 0;
                FadeFrame(obj, duration, 1);
            end

            self.fontStringPool:ProcessAllObjects(FadeObject);
            self.ScrollFrame.onScrollFinishedCallback = nil;
        end
    end

    -- Stops book narration and restores the normal text appearance.
    function DUIBookUIMixin:StopReadingBook()
        TTSUtil:StopReadingBook();

        if self.isReadingContent then
            self.isReadingContent = false;
            self.focusedContentIndex = nil;
            self:FadeOtherContent();
        end
    end

    -- Speaks the next text record and scrolls it into view when necessary.
    function DUIBookUIMixin:ReadAndMoveToNextLine()
        if not self.isReadingContent then
            return
        end

        if not Cache:IsCurrentObjectFullyCached() then
            self.isReadingContent = false;
            return
        end

        local contentIndex = (self.focusedContentIndex or 0) + 1;
        local data = Cache:GetContentDataByIndex(contentIndex);

        -- Skip images and other non-text records.
        while data and not data.text do
            contentIndex = contentIndex + 1;
            data = Cache:GetContentDataByIndex(contentIndex);
        end

        local found;
        if data and data.text then
            found = true;
            self.focusedContentIndex = contentIndex;
            TTSUtil:ReadBookLine(data.text);

            local viewSize = self.ScrollFrame:GetViewSize();
            local fromOffset = self.ScrollFrame:GetVerticalScroll();
            local toOffset = fromOffset + viewSize;

            if data.endingOffsetY <= fromOffset
                or data.offsetY >= toOffset
                or (data.offsetY <= toOffset and data.endingOffsetY >= toOffset) then
                local offsetY = data.offsetY - self.scrollFromOffetY;
                SwipeEmulator:StopWatching(self.ScrollFrame);
                self:ScrollTo(offsetY);
            end
        end

        self.isReadingContent = found and true or false;
        self:FadeOtherContent();

        return found
    end

    -- Starts or stops narration for the text record currently under the cursor.
    function DUIBookUIMixin:SpeakCursorFocusContent()
        local contentIndex = self:GetCursorFocusContent();
        if not contentIndex then
            return
        end

        if self.focusedContentIndex == contentIndex then
            self:StopReadingBook();
            return
        end

        local data = Cache:GetContentDataByIndex(contentIndex);
        if data and data.text then
            self.focusedContentIndex = contentIndex;
            self.isReadingContent = true;

            local userInput = true;
            TTSUtil:ReadBookLine(data.text, userInput);
            self:FadeOtherContent();
        end
    end

    -- Starts or stops narration for the first visible text paragraph.
    function DUIBookUIMixin:SpeakTopContent()
        if not self:IsVisible() then
            return
        end

        local contentIndex = 1;
        local data = Cache:GetContentDataByIndex(contentIndex);

        if data then
            local fromOffset = self.ScrollFrame:GetVerticalScroll();
            local foundIndex;

            while data do
                if data.text
                    and ((data.offsetY <= fromOffset and data.endingOffsetY >= fromOffset)
                    or data.offsetY >= fromOffset) then
                    local offsetY = data.offsetY - self.scrollFromOffetY;
                    SwipeEmulator:StopWatching(self.ScrollFrame);
                    self:ScrollTo(offsetY);
                    foundIndex = contentIndex;
                    break
                end

                contentIndex = contentIndex + 1;
                data = Cache:GetContentDataByIndex(contentIndex);
            end

            if foundIndex then
                if self.focusedContentIndex == foundIndex then
                    self:StopReadingBook();
                    return
                end

                data = Cache:GetContentDataByIndex(foundIndex);
                if data and data.text then
                    self.focusedContentIndex = foundIndex;
                    self.isReadingContent = true;

                    local userInput = true;
                    TTSUtil:ReadBookLine(data.text, userInput);
                    self:FadeOtherContent();
                end
            end
        end
    end

    -- Scrolls the currently focused or hovered text record toward the top of the view.
    function DUIBookUIMixin:GetAndScrollToNextText()
        local contentIndex = self.focusedContentIndex or self:GetCursorFocusContent();
        if not contentIndex then
            return
        end

        local data = Cache:GetContentDataByIndex(contentIndex);
        if data then
            local offsetY = data.offsetY - self.scrollFromOffetY;
            self:ScrollTo(offsetY);
        end
    end
end


do  --Keyboard Control
    local IsModifierKeyDown = IsModifierKeyDown;

    -- Safely changes whether unhandled keyboard input is passed through to the game.
    local function SetKeyboardInputPropagation(frame, shouldPropagate)
        -- 3.3.5 compatibility: This method is not available on the WotLK client.
        if frame.SetPropagateKeyboardInput then
            frame:SetPropagateKeyboardInput(shouldPropagate);
        end
    end

    -- Enables keyboard shortcuts only when the client supports safe input propagation.
    function DUIBookUIMixin:EnableControls(state)
        local inCombat = InCombatLockdown and InCombatLockdown();

        -- 3.3.5 compatibility: Without propagation control, capturing keys could block normal game input.
        local canCaptureKeyboard = self.EnableKeyboard and self.SetPropagateKeyboardInput;

        if state and not inCombat and canCaptureKeyboard then
            self:EnableKeyboard(true);
            self:SetScript("OnKeyDown", self.OnKeyDown);
        else
            self:SetScript("OnKeyDown", nil);

            if self.EnableKeyboard then
                self:EnableKeyboard(false);
            end
        end
    end

    -- Handles book keyboard shortcuts and passes unhandled keys through to the game.
    function DUIBookUIMixin:OnKeyDown(key)
        local handled = false;

        if key == "ESCAPE" then
            handled = true;
            if not addon.Clipboard:CloseIfShown() then
                self:Hide();
            end
        elseif key == "F1" then
            handled = true;
            addon.SettingsUI:ToggleUI();
        elseif BindingUtil:GetActiveKeyAction(key) == "TTS"
            and not (IsModifierKeyDown and IsModifierKeyDown())
            and GetDBBool("TTSEnabled")
            and GetDBBool("TTSUseHotkey") then
            handled = true;
            addon.TTSUtil:ToggleSpeaking("book");
        else
            local action = GetBindingAction and GetBindingAction(key);
            if action == "OPENALLBAGS" or action == "TOGGLEBACKPACK" then
                handled = true;
                self:Hide();
            end
        end

        -- 3.3.5 compatibility: Guard the lockdown check and propagation API.
        if InCombatLockdown and InCombatLockdown() then
            self:Hide();
        else
            SetKeyboardInputPropagation(self, not handled);
        end
    end
end


do  --EventListener
    -- 3.3.5 compatibility: This listener only needs the core readable-item events.
    -- ITEM_TEXT_TRANSLATION had no handling here and is omitted to avoid registering
    -- an event that may not exist on the target client.
    local BOOK_EVENTS = {
        "ITEM_TEXT_BEGIN",
        "ITEM_TEXT_READY",
        "ITEM_TEXT_CLOSED",
    };

    local MaterialTextureKitID = {
        ["Default"] = 1,
        ["Stone"] = 2,
        ["Parchment"] = 1,
        ["Marble"] = 2,
        ["Silver"] = 2,
        ["Bronze"] = 2,
        ["ParchmentLarge"] = 1,
        ["Progenitor"] = 2,
    };

    -- Hides the book after the readable interface closes, unless the setting keeps it open.
    function EL:OnUpdate(elapsed)
        self.t = self.t + elapsed;
        if self.t > 0.03 then
            self:SetScript("OnUpdate", nil);

            if not self.showItemText
                and MainFrame
                and MainFrame:IsShown()
                and not GetDBBool("BookKeepUIOpen") then
                MainFrame:Hide();
            end
        end
    end

    -- Schedules a delayed check after readable-item events have settled.
    function EL:ProcessEventNextUpdate(customDelay)
        customDelay = customDelay or 0;
        self.t = -customDelay;
        self.processEvent = true;
        self:SetScript("OnUpdate", self.OnUpdate);
    end

    -- Handles readable-item lifecycle and player combat events.
    function EL:OnEvent(event, ...)
        if event == "ITEM_TEXT_BEGIN" then
            if not MainFrame then
                return
            end

            if MainFrame.Init then
                MainFrame:Init();
            end

            -- 3.3.5 compatibility: Use the legacy ItemText globals when available.
            local material = (ItemTextGetMaterial and ItemTextGetMaterial()) or "Parchment";
            local textureKitID = MaterialTextureKitID[material] or 1;
            MainFrame:SetTextureKit(textureKitID);

            local guid = UnitGUID and UnitGUID("npc");
            local objectType, objectID, itemID;

            if guid then
                objectType, objectID, itemID = GetObjectTypeAndID(guid);
            end

            Cache:SetActiveObject(objectType, objectID, itemID);

            MainFrame.Header:QueryLetterSender(nil);
            if objectType == "GameObject" then
                MainFrame.Header:SetLocation(true, Cache:GetBookLocation());
            else
                MainFrame.Header:SetLocation(false);

                -- Plain Letter
                if itemID == 8383 then
                    MainFrame.Header:QueryLetterSender(guid);
                end
            end

            self.itemTextBegun = true;

            if MainFrame.SourceItemButton then
                MainFrame.SourceItemButton:SetItem(nil);
            end

        elseif event == "ITEM_TEXT_READY" then
            self.showItemText = true;

            if not Cache.needTurnBack and Cache:IsCurrentObjectFullyCached() then
                -- The cached UI is already ready.
            elseif Cache.needTurnBack and IsMultiPageBook() then
                -- The current page will be turned back by the normal close flow.
            elseif not Cache:IsCurrentObjectFullyCached() then
                Cache:CacheCurrentPage();
            end

        elseif event == "ITEM_TEXT_CLOSED" then
            if self.itemTextBegun then
                self.itemTextBegun = false;
                Cache:SavePagePosition();

                -- 3.3.5 compatibility: Guard the legacy close function before calling it.
                if CloseItemText then
                    CloseItemText();
                end
            end

            self.showItemText = false;
            -- Readable interaction may emit multiple close/begin/ready events in quick succession.
            self:ProcessEventNextUpdate();

        elseif event == "PLAYER_REGEN_DISABLED" then
            self.inCombat = true;

            -- 3.3.5 compatibility: Keyboard propagation controls are not present on every client.
            if MainFrame and MainFrame.SetPropagateKeyboardInput then
                MainFrame:SetPropagateKeyboardInput(true);
            end

            if MainFrame then
                MainFrame:EnableControls(false);
            end

            if self:IsShown() and addon.CameraUtil
                and addon.CameraUtil.OnEnterCombatDuringInteraction then
                addon.CameraUtil:OnEnterCombatDuringInteraction();
            end

        elseif event == "PLAYER_REGEN_ENABLED" then
            self.inCombat = false;

            if MainFrame and MainFrame:IsVisible() then
                MainFrame:EnableControls(true);
            end
        end
    end

    -- Transfers readable-item event handling between this listener and Blizzard's frame.
    function EL:EnableModule(state)
        local itemTextFrame = ItemTextFrame;

        if state then
            if self.enabled then
                return
            end

            self.enabled = true;
            self:SetScript("OnEvent", self.OnEvent);

            for _, eventName in ipairs(BOOK_EVENTS) do
                self:RegisterEvent(eventName);
            end

            if itemTextFrame then
                itemTextFrame:UnregisterAllEvents();
            end
        elseif self.enabled then
            self.enabled = false;
            self:SetScript("OnEvent", nil);
            self:UnregisterAllEvents();

            for _, eventName in ipairs(BOOK_EVENTS) do
                if itemTextFrame then
                    itemTextFrame:RegisterEvent(eventName);
                end
            end
        end
    end

    -- Enables or disables the custom book UI according to the caller and saved setting.
    local function EnableBookUI(state)
        state = state and GetDBBool("BookUIEnabled");

        if state then
            if not EL.enabled then
                EL:EnableModule(true);
            end
        elseif EL.enabled then
            EL:EnableModule(false);

            if MainFrame then
                MainFrame:Hide();
            end
        end
    end

    addon.EnableBookUI = EnableBookUI;
end



do  --Settings
    local FrameSizeIndexScale = {
        [0] = 0.9,
        [1] = 1.0,
        [2] = 1.1,
        [3] = 1.25,
        [4] = 1.4,
    };

    -- Applies the changed layout after a delay to avoid repeated recalculation.
    function DUIBookUIMixin:OnSettingsChanged()
        if not self:IsShown() or self.settingsDirty then
            return
        end

        self.settingsDirty = true;

        -- 3.3.5 compatibility: Recalculate immediately when C_Timer is unavailable.
        local function Recalculate()
            self.settingsDirty = nil;
            CalculateSizeData();
            Cache:CalculateTextHeight();
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(0, Recalculate);
        else
            Recalculate();
        end
    end

    -- Reacts to the selected book size scale.
    local function Settings_FrameSize(dbValue)
        if GetDBBool("MobileDeviceMode") then
            dbValue = 4;
        end

        local newScale = dbValue and FrameSizeIndexScale[dbValue];
        if newScale then
            if newScale ~= FRAME_SIZE_MULTIPLIER then
                if MainFrame and MainFrame.OnSettingsChanged then
                    MainFrame:OnSettingsChanged();
                end
            end

            FRAME_SIZE_MULTIPLIER = newScale;
            CalculateSizeData();

            if MainFrame and not MainFrame.Init then
                MainFrame:Resize();
            end
        end
    end
    CallbackRegistry:Register("SettingChanged.BookUISize", Settings_FrameSize);

    -- Recalculates the size and formatting after a font change.
    local function OnFontSizeChanged(baseFontSize, fontSizeID)
        Formatter:SetBaseFontSize(baseFontSize);
        if MainFrame and MainFrame.OnSettingsChanged then
            MainFrame:OnSettingsChanged();
        end
    end
    CallbackRegistry:Register("FontSizeChanged", OnFontSizeChanged);

    -- Enables or disables the event listener for the book display.
    local function Settings_BookUIEnabled(state)
        EL:EnableModule(state);
    end
    CallbackRegistry:Register("SettingChanged.BookUIEnabled", Settings_BookUIEnabled);

    -- Toggles the vignette background for the book.
    local function Settings_BookDarkenScreen(state)
        if MainFrame and MainFrame.ScreenVignette then
            MainFrame.ScreenVignette:SetShown(state);
        end
    end
    CallbackRegistry:Register("SettingChanged.BookDarkenScreen", Settings_BookDarkenScreen);

    -- Shows or hides the book location text in the title bar.
    local function Settings_BookShowLocation(state)
        if MainFrame and MainFrame:IsShown() then
            if state then
                MainFrame.Header:SetLocation(true, Cache:GetBookLocation());
            else
                MainFrame.Header:SetLocation(false);
            end
        end
    end
    CallbackRegistry:Register("SettingChanged.BookShowLocation", Settings_BookShowLocation);

    --TTS and Copy Buttons
    local TTSButton;

    -- Enables or disables the TTS button on the book frame.
    local function Settings_TTSEnabled(dbValue)
        if dbValue == true then
            if not TTSButton then
                local themeID = 3;
                if addon.CreateTTSButton then
                    TTSButton = addon.CreateTTSButton(MainFrame, themeID);
                    TTSButton:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 8, -8);
                    TTSButton.system = "book";
                    MainFrame.TTSButton = TTSButton;
                end
            end

            if TTSButton then
                TTSButton:Show();

                if MainFrame and MainFrame.widgetTheme then
                    TTSButton:SetTheme(MainFrame.widgetTheme);
                end
            end
        else
            if TTSButton then
                TTSButton:Hide();
            end
        end

        if MainFrame then
            MainFrame:LayoutWidgets();
        end
    end
    CallbackRegistry:Register("SettingChanged.TTSEnabled", Settings_TTSEnabled);

    -- Clipboard
    local CopyTextButton;

    -- Opens the clipboard if the book content should be copied.
    local function CopyTextButton_OnClick(self)
        if addon.Clipboard and addon.Clipboard:CloseIfFromSameSender(self) then
            return
        end

        local str = Cache:GetRawContent(true);
        if addon.Clipboard then
            addon.Clipboard:ShowContent(str, self);
        end
    end

    -- Enables or disables the copy-text button on the book frame.
    local function Settings_ShowCopyTextButton(dbValue)
        if dbValue == true then
            if not CopyTextButton then
                local themeID = 1;
                if addon.CreateCopyTextButton then
                    CopyTextButton = addon.CreateCopyTextButton(MainFrame, CopyTextButton_OnClick, themeID);
                    CopyTextButton:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -8, -8);
                    MainFrame.CopyTextButton = CopyTextButton;
                    CopyTextButton:SetWidth(16);
                end
            end

            if CopyTextButton then
                CopyTextButton:Show();

                if MainFrame and MainFrame.widgetTheme then
                    CopyTextButton:SetTheme(MainFrame.widgetTheme);
                end
            end
        else
            if CopyTextButton then
                CopyTextButton:Hide();
            end
        end

        if MainFrame then
            MainFrame:LayoutWidgets();
        end
    end
    CallbackRegistry:Register("SettingChanged.ShowCopyTextButton", Settings_ShowCopyTextButton);

    -- Positions the optional TTS and copy buttons relative to the main frame.
    function DUIBookUIMixin:LayoutWidgets()
        local object1, object2;

        if GetDBBool("TTSEnabled") and TTSButton then
            object1 = TTSButton;
        end

        if GetDBBool("ShowCopyTextButton") and CopyTextButton then
            if object1 then
                object2 = CopyTextButton;
            else
                object1 = CopyTextButton;
            end
        end

        if object1 then
            local offset = ConvertedSize.CLOSE_BUTTON_OFFSET;
            object1:ClearAllPoints();
            object1:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", offset, -offset);

            if object2 then
                object2:ClearAllPoints();
                object2:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", offset + 32, -offset);
            end
        end
    end

    --Source Item Button
    local SourceItemButton;

    -- Enables or disables the source-item metadata area beneath the book title.
    local function Settings_BookUIItemDescription(state, userInput)
        if state then
            if not SourceItemButton then
                if BookComponent and BookComponent.CreateSourceItemButton then
                    SourceItemButton = BookComponent:CreateSourceItemButton(MainFrame);
                    SourceItemButton:SetPoint("BOTTOM", MainFrame, "TOP", 0, 16);
                    MainFrame.SourceItemButton = SourceItemButton;
                end
            end

            if SourceItemButton then
                SourceItemButton:Show();
                SourceItemButton:SetTexture(MainFrame.textureFile);

                if MainFrame and MainFrame:IsShown() then
                    MainFrame:Resize();
                    SourceItemButton:SetItem(Cache:GetCurrentItemID());
                end
            end
        else
            if SourceItemButton then
                SourceItemButton:Hide();
            end
        end
    end
    CallbackRegistry:Register("SettingChanged.BookUIItemDescription", Settings_BookUIItemDescription);
end
