local _, addon = ...

local BookComponent = {};
addon.BookComponent = BookComponent;

local API = addon.API;
local L = addon.L;
local FontUtil = addon.FontUtil;
local ThemeUtil = addon.ThemeUtil;
local GetDBBool = addon.GetDBBool;
local Mixin = API.Mixin;
local Round = API.Round;
local CreateFrame = CreateFrame;

-- User Settings
local PAGE_SELECTED_COLOR = "Ivory";
local PAGE_NORMAL_COLOR = "LightBrown";

local PageButtonMixin = {};
do  --Pagination
    -- Sets the page number displayed by this pagination button.
    function PageButtonMixin:SetPage(page)
        self.PageText:SetText(page);
        self.page = page;
    end

    -- Updates the selected state, text color, and background coordinates.
    function PageButtonMixin:SetSelected(state)
        if state == self.selected then return end;
        self.selected = state;

        if state then
            ThemeUtil:SetFontColor(self.PageText, PAGE_SELECTED_COLOR);
            self.Background:SetTexCoord(780/1024, 820/1024, 1564/2048, 1604/2048);
        else
            ThemeUtil:SetFontColor(self.PageText, PAGE_NORMAL_COLOR);
            self.Background:SetTexCoord(844/1024, 884/1024, 1564/2048, 1604/2048);
        end
    end

    -- Shows the button's highlight when the pointer enters it.
    function PageButtonMixin:OnEnter()
        self.Highlight:Show();
    end

    -- Hides the button's highlight when the pointer leaves it.
    function PageButtonMixin:OnLeave()
        self.Highlight:Hide();
    end

    -- Sets this pagination button to a square size.
    function PageButtonMixin:SetObjectSize(buttonSize)
        self:SetSize(buttonSize, buttonSize);
    end

    -- Applies the supplied texture to the button background and highlight.
    function PageButtonMixin:SetUITexture(file)
        self.Background:SetTexture(file);
        self.Highlight:SetTexture(file);
    end
end

local CloseButton;
do
    -- Creates the book close button once and returns the shared button.
    function BookComponent:GetCloseButton(parent)
        if not CloseButton then
            CloseButton = CreateFrame("Button", nil, parent);
            CloseButton.Texture = CloseButton:CreateTexture(nil, "ARTWORK");
            -- 3.3.5 compatibility: SetAllPoints without the newer boolean argument.
            CloseButton.Texture:SetAllPoints();
            CloseButton.Texture:SetTexCoord(768/1024, 832/1024, 1488/2048, 1552/2048);
            CloseButton.Highlight = CloseButton:CreateTexture(nil, "HIGHLIGHT");
            -- 3.3.5 compatibility: SetAllPoints without the newer boolean argument.
            CloseButton.Highlight:SetAllPoints();
            CloseButton.Highlight:SetTexCoord(832/1024, 896/1024, 1488/2048, 1552/2048);

            -- Hides the book's parent when the close button is clicked.
            function CloseButton:OnClick()
                parent:Hide();
            end
            CloseButton:SetScript("OnClick", CloseButton.OnClick);

            -- Changes the close button's normal and highlight textures.
            function CloseButton:SetUITexture(file)
                CloseButton.Texture:SetTexture(file);
                CloseButton.Highlight:SetTexture(file);
            end
        end
        return CloseButton
    end
end

do  --Header / Book Title
    local TITLE_SPACING = 4;
    local MAX_PAGE_BUTTONS = 9;
    local HeaderFrameMixin = {};

    -- Sets the book title and adjusts its text size to fit.
    function HeaderFrameMixin:SetTitle(title)
        local minLineHeight = 14;
        self:SetAutoScalingText(self.Title, title, minLineHeight);
    end

    -- Fits a title to its font string, using modern text APIs when available.
    function HeaderFrameMixin:SetAutoScalingText(fontString, text, minLineHeight)
        -- 3.3.5 compatibility: Use truncation and text-scaling APIs only when available.
        if fontString.SetMaxLines and fontString.SetTextScale and fontString.IsTruncated then
            fontString:SetMaxLines(1);
            fontString:SetHeight(0);
            fontString:SetText(text);

            local _, baseLineHeight = fontString:GetFont();
            baseLineHeight = Round(baseLineHeight);

            local tryHeight = baseLineHeight;
            local finalScale = 1;

            while tryHeight >= minLineHeight do
                local scale = tryHeight / baseLineHeight;
                fontString:SetTextScale(scale);
                finalScale = scale;
                if fontString:IsTruncated() then
                    tryHeight = tryHeight - 2;
                else
                    break
                end
            end

            if fontString:IsTruncated() then
                local maxLines = 2;
                fontString:SetMaxLines(maxLines);
                self.titleHeight = finalScale * (maxLines * (baseLineHeight + TITLE_SPACING) - TITLE_SPACING);
            else
                self.titleHeight = fontString:GetHeight();
            end
        else
            -- 3.3.5 compatibility: Resize the font with SetFont when newer text APIs are unavailable.
            local fontFile, baseFontSize, flags = fontString.bookBaseFontFile, fontString.bookBaseFontSize, fontString.bookBaseFontFlags;
            if not fontFile then
                fontFile, baseFontSize, flags = fontString:GetFont();
                fontString.bookBaseFontFile = fontFile;
                fontString.bookBaseFontSize = baseFontSize;
                fontString.bookBaseFontFlags = flags;
            end

            fontString:SetText(text);

            if fontFile and baseFontSize and fontString.GetStringWidth then
                local fontSize = baseFontSize;
                local availableWidth = fontString:GetWidth();

                while fontSize > minLineHeight do
                    fontString:SetFont(fontFile, fontSize, flags);
                    if fontString:GetStringWidth() <= availableWidth then
                        break
                    end
                    fontSize = math.max(minLineHeight, fontSize - 2);
                end

                fontString:SetFont(fontFile, fontSize, flags);
                fontString.bookTextScale = fontSize / baseFontSize;
            end

            -- 3.3.5 compatibility: Test the method with dot syntax before calling it with colon syntax.
            self.titleHeight = fontString.GetStringHeight and fontString:GetStringHeight() or fontString:GetHeight();
        end

        self.titleHeight = Round(self.titleHeight or 0);
    end

    -- Returns the total header height, including any spacing below the title.
    function HeaderFrameMixin:GetHeaderHeight()
        return Round(self:GetTitleHeight() + (self.heightBelow or 0));
    end

    -- Sets the spacing between the title and the book body.
    function HeaderFrameMixin:SetHeightBelowTitle(heightBelow)
        self.heightBelow = heightBelow;
    end

    -- Returns the measured title height, or the font string's current height.
    function HeaderFrameMixin:GetTitleHeight()
        return self.titleHeight or self.Title:GetHeight()
    end

    -- Returns the effective title line height after text scaling.
    function HeaderFrameMixin:GetTitleEffectiveLineHeight()
        local _, baseLineHeight = self.Title:GetFont();

        -- 3.3.5 compatibility: GetTextScale may not exist on the legacy FontString.
        local scale = (self.Title.GetTextScale and self.Title:GetTextScale()) or self.Title.bookTextScale or 1;
        return baseLineHeight * scale
    end

    -- Shows or hides the location label according to the game-object setting.
    function HeaderFrameMixin:SetLocation(isGameObject, locationText)
        if isGameObject and GetDBBool("BookShowLocation") then
            self.Location:SetText(locationText);
            self.Location:Show();
        else
            self.Location:SetText(nil);
            self.Location:Hide();
        end
    end

    -- Releases old page buttons and creates the number needed for the book.
    function HeaderFrameMixin:SetMaxPage(maxPage)
        self:ReleaseAllObjects();
        self.maxPage = maxPage;
        self.currentPage = 0;

        if maxPage <= 1 then
            self.dynamicPagination = false;
            self.numPageButtons = 0;
            return 1
        end

        local buttonWidth = self.pageButtonWidth;
        local buttonGap = self.pageButtonGap;
        local numButtons;

        if maxPage > MAX_PAGE_BUTTONS then
            numButtons = MAX_PAGE_BUTTONS;
            self.dynamicPagination = true;
        else
            numButtons = maxPage;
            self.dynamicPagination = false;
        end

        self.numPageButtons = numButtons;

        local fullWidth = (buttonWidth + buttonGap) * numButtons - buttonGap;
        local fromOffsetX = -0.5 * fullWidth;

        for i = 1, numButtons do
            local button = self.pageButtonPool:Acquire();
            button.index = i;
            button:SetPage(i);
            button:SetObjectSize(buttonWidth);
            button:SetPoint("LEFT", self.HeaderDivider, "CENTER", fromOffsetX + (i - 1) * (buttonWidth + buttonGap), 0);
            button:SetSelected(i == 1);
        end

        self:SetCurrentPage(1);
        return numButtons
    end

    -- Updates page labels and selection for fixed or sliding pagination.
    function HeaderFrameMixin:UpdatePageButtons()
        local page = self.currentPage;

        if self.dynamicPagination then
            local leftMostPage = math.max(1, page - 4);
            if leftMostPage == 1 then
                for index, button in self.pageButtonPool:EnumerateActive() do
                    if index == MAX_PAGE_BUTTONS then
                        button:SetPage(self.maxPage);
                    else
                        button:SetPage(index);
                    end
                end
            else
                local rightMostPage = page + 4;
                if rightMostPage >= self.maxPage then
                    for index, button in self.pageButtonPool:EnumerateActive() do
                        if index == 1 then
                            button:SetPage(1);
                        else
                            button:SetPage(self.maxPage + index - MAX_PAGE_BUTTONS);
                        end
                    end
                else
                    for index, button in self.pageButtonPool:EnumerateActive() do
                        if index == 1 then
                            button:SetPage(1);
                        elseif index == MAX_PAGE_BUTTONS then
                            button:SetPage(self.maxPage);
                        else
                            button:SetPage(page + index - 5);
                        end
                    end
                end
            end
        end

        -- Updates one button's selected state against the current page.
        local function SetPageButtonSelected(pageButton)
            pageButton:SetSelected(pageButton.page == page);
        end

        self.pageButtonPool:ProcessActiveObjects(SetPageButtonSelected);
    end

    -- Changes the current page and refreshes the pagination buttons.
    function HeaderFrameMixin:SetCurrentPage(page)
        if page ~= self.currentPage then
            self.currentPage = page;
            self:UpdatePageButtons();
        end
    end

    -- Stores the button width and gap used when pagination buttons are created.
    function HeaderFrameMixin:SetPageButtonSize(buttonWidth, buttonGap)
        self.pageButtonWidth = buttonWidth;
        self.pageButtonGap = buttonGap;
    end

    -- Releases every active page button back to the object pool.
    function HeaderFrameMixin:ReleaseAllObjects()
        self.pageButtonPool:Release();
    end

    -- Sets the texture used by pagination buttons and updates pooled buttons.
    function HeaderFrameMixin:SetUITexture(file)
        self.textureFile = file;
        if self.pageButtonPool then
            -- Applies the texture to one pooled page button.
            local function SetBackGround(pageButton)
                pageButton:SetUITexture(file);
            end
            self.pageButtonPool:ProcessAllObjects(SetBackGround);
        end
    end

    -- Changes selected and normal page-number text colors.
    function HeaderFrameMixin:SetPageTextColor(selectedColor, normalColor)
        PAGE_SELECTED_COLOR = selectedColor;
        PAGE_NORMAL_COLOR = normalColor;

        if self.pageButtonPool then
            -- Applies the selected or normal color to one active button.
            local function SetPageButtonTextColor(pageButton)
                if pageButton.selected then
                    ThemeUtil:SetFontColor(pageButton.PageText, PAGE_SELECTED_COLOR);
                else
                    ThemeUtil:SetFontColor(pageButton.PageText, PAGE_NORMAL_COLOR);
                end
            end
            self.pageButtonPool:ProcessActiveObjects(SetPageButtonTextColor);
        end
    end

    -- Queries the sender location from item tooltip data when the API supports it.
    function HeaderFrameMixin:QueryLetterSender(itemGUID)
        -- 3.3.5 compatibility: GUID tooltip lookup and restricted-value checks may be unavailable.
        local getItemByGUID = addon.TooltipAPI and addon.TooltipAPI.GetItemByGUID;
        local canAccessValue = API.canaccessvalue;

        if getItemByGUID and (not canAccessValue or canAccessValue(itemGUID)) then
            self.itemGUID = itemGUID;
            local tooltipData = itemGUID and getItemByGUID(itemGUID);
            if tooltipData then
                self.dataInstanceID = tooltipData.dataInstanceID;
                if self.dataInstanceID then
                    self:RegisterEvent("TOOLTIP_DATA_UPDATE");
                    self:SetScript("OnEvent", self.OnEvent);
                    self:ProcessTooltipData(tooltipData);
                    return;
                end
            end
        end

        self.itemGUID = nil;
        self.dataInstanceID = nil;
        self:SetScript("OnEvent", nil);
        self:UnregisterEvent("TOOLTIP_DATA_UPDATE");
    end

    -- Displays the sender location when tooltip data contains a suitable second line.
    function HeaderFrameMixin:ProcessTooltipData(tooltipData)
        local line2 = tooltipData and tooltipData.lines and tooltipData.lines[2];
        if line2 and line2.leftText and line2.leftColor
            and line2.leftColor.r == 1 and line2.leftColor.g == 1 and line2.leftColor.b == 1 then
            self.Location:SetText(line2.leftText);
            self.Location:Show();
        end
    end

    -- Handles tooltip-data update events for the queried item.
    function HeaderFrameMixin:OnEvent(event, ...)
        if event == "TOOLTIP_DATA_UPDATE" then
            local dataInstanceID = ...
            if dataInstanceID and dataInstanceID == self.dataInstanceID then
                self:QueryLetterSender(self.itemGUID);
            end
        end
    end

    -- Clears tooltip state and unregisters the update event when the header hides.
    function HeaderFrameMixin:OnHide()
        self.dataInstanceID = nil;
        self.itemGUID = nil;
        self:SetScript("OnEvent", nil);
        self:UnregisterEvent("TOOLTIP_DATA_UPDATE");
    end

    -- Creates the book title, location label, and pooled pagination buttons.
    function BookComponent:InitHeader(headerFrame)
        local Title = headerFrame:CreateFontString(nil, "OVERLAY", "DUIFont_Book_Title");
        headerFrame.Title = Title;
        Title:SetJustifyH("CENTER");
        Title:SetJustifyV("TOP");

        -- 3.3.5 compatibility: SetMaxLines is not available on all legacy FontStrings.
        if Title.SetMaxLines then
            Title:SetMaxLines(2);
        end

        Title:SetSpacing(TITLE_SPACING);
        Title:SetPoint("TOP", headerFrame, "TOP", 0, 0);

        local Location = headerFrame:CreateFontString(nil, "OVERLAY", "DUIFont_Book_10");
        headerFrame.Location = Location;
        Location:SetJustifyH("CENTER");
        Location:SetJustifyV("TOP");
        Location:SetPoint("BOTTOM", Title, "TOP", 0, 9);

        Mixin(headerFrame, HeaderFrameMixin);
        headerFrame:SetScript("OnHide", headerFrame.OnHide);

        -- Navigates the book to the page represented by the clicked button.
        local function PageButton_OnClick(f)
            local MainFrame = headerFrame:GetParent();
            if f.page == 1 then
                MainFrame:ScrollTo(0);
            else
                MainFrame:ScrollToPage(f.page);
            end
            MainFrame.ScrollFrame.paginationTimer = 1;
        end

        -- Creates and configures a page button for the object pool.
        local function CreatePageButton()
            local button = CreateFrame("Button", nil, headerFrame, "DUIBookPageButtonTemplate");
            Mixin(button, PageButtonMixin);
            button:SetScript("OnEnter", button.OnEnter);
            button:SetScript("OnLeave", button.OnLeave);
            button:SetScript("OnClick", PageButton_OnClick);
            button.Background:SetTexCoord(844/1024, 884/1024, 1564/2048, 1604/2048);
            button.Highlight:SetTexCoord(908/1024, 948/1024, 1564/2048, 1604/2048);
            return button
        end

        -- Hides a page button and clears its anchors before pooling it.
        local function RemovePageButton(pageButton)
            pageButton:Hide();
            pageButton:ClearAllPoints();
        end

        -- Applies the current header texture whenever a page button is acquired.
        local function OnAcquirePageButton(pageButton)
            pageButton:SetUITexture(headerFrame.textureFile);
        end

        headerFrame.pageButtonPool = API.CreateObjectPool(CreatePageButton, RemovePageButton, OnAcquirePageButton);
    end
end

do  --Location (Show location for GameObject)
    -- 3.3.5 compatibility: C_Map is unavailable on the original WotLK client.
    local MapAPI = C_Map;
    local GetBestMapForUnit = MapAPI and MapAPI.GetBestMapForUnit;
    local GetMapInfo = MapAPI and MapAPI.GetMapInfo;
    local GetMapPlayerPosition = MapAPI and MapAPI.GetPlayerMapPosition;
    local GetMinimapZoneText = GetMinimapZoneText;
    local GetZoneText = GetZoneText;

    -- 3.3.5 compatibility: Preserve the legacy global before using namespaced map APIs.
    local LegacyGetPlayerMapPosition = _G.GetPlayerMapPosition;

    local FORMAT_MAP_COORD = "%s  %.0f, %.0f";

    -- Returns the player's zone and coordinates, using the map API available on the client.
    function BookComponent:GetPlayerLocation()
        local mapName, x, y;

        if GetBestMapForUnit and GetMapInfo and GetMapPlayerPosition then
            local uiMapID = GetBestMapForUnit("player");
            if uiMapID then
                local mapInfo = GetMapInfo(uiMapID);
                if mapInfo then
                    mapName = mapInfo.name;
                end

                local position = GetMapPlayerPosition(uiMapID, "player");
                if position then
                    x = position.x;
                    y = position.y;
                end
            end
        elseif GetZoneText then
            mapName = GetZoneText();

            -- 3.3.5 compatibility: The legacy function returns x and y as separate numbers.
            if LegacyGetPlayerMapPosition then
                x, y = LegacyGetPlayerMapPosition("player");
            end
        end

        if not mapName and GetMinimapZoneText then
            mapName = GetMinimapZoneText();
        end

        if x and y and mapName then
            x = x * 100;
            y = y * 100;
            return string.format(FORMAT_MAP_COORD, mapName, x, y)
        end

        return mapName
    end
end

do  --ItemButton (Show item's description lore)
    local match = string.match;

    -- 3.3.5 compatibility: Fall back to the legacy GetItemInfo return value for the icon.
    local ItemAPI = C_Item;
    local GetItemIconByID = ItemAPI and ItemAPI.GetItemIconByID;
    local GetItemInfo = GetItemInfo;

    -- Returns an item's icon using the modern API or the legacy item-info API.
    local function GetItemIcon(itemID)
        if GetItemIconByID then
            return GetItemIconByID(itemID);
        elseif GetItemInfo then
            local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID);
            return icon;
        end
    end

    -- 3.3.5 compatibility: The tooltip helper may not be present on every client.
    local GetItemByID = addon.TooltipAPI and addon.TooltipAPI.GetItemByID;
    local SourceItemButtonMixin = {};

    -- Loads an item tooltip and begins searching for its description text.
    function SourceItemButtonMixin:SetItem(itemID)
        self.queryTimes = 0;
        self.itemID = itemID;

        if itemID and GetItemByID then
            local tooltipData = GetItemByID(itemID);
            if tooltipData then
                self:ProcessTooltipData(tooltipData);
            else
                self:ClearAll();
            end
        else
            self:ClearAll();
        end
    end

    -- Finds and displays the quoted lore line in the item's tooltip data.
    function SourceItemButtonMixin:ProcessTooltipData(tooltipData)
        self:SetScript("OnUpdate", nil);
        self.t = nil;

        if not (tooltipData and tooltipData.lines) then
            self:ClearAll();
            return
        end

        local line, description;
        local numLines = #tooltipData.lines;

        for i = numLines, 2, -1 do
            line = tooltipData.lines[i];
            if line.leftText and line.type ~= 20 and match(line.leftText, "^[\"“]") then
                description = line.leftText;
                break
            end
        end

        if description then
            self:DisplayItemDescription(self.itemID, description);
        else
            if self.queryTimes > 2 then
                self:ClearAll();
            else
                self.queryTimes = self.queryTimes + 1;
                self.t = 0;
                self:SetScript("OnUpdate", self.OnUpdate);
            end
        end
    end

    -- Retries tooltip retrieval after a short delay while item data is loading.
    function SourceItemButtonMixin:OnUpdate(elapsed)
        self.t = self.t + elapsed;
        if self.t > 0.2 then
            self.t = 0;
            self:SetScript("OnUpdate", nil);
            local tooltipData = (self.itemID and GetItemByID) and GetItemByID(self.itemID);
            self:ProcessTooltipData(tooltipData);
        end
    end

    -- Displays the item's icon and lore description in the widget.
    function SourceItemButtonMixin:DisplayItemDescription(itemID, description)
        -- 3.3.5 compatibility: Use the legacy item-icon fallback when C_Item is unavailable.
        local icon = GetItemIcon(itemID);
        self.ItemIcon:SetTexture(icon);
        self.ItemText:SetText(description);
        self.ItemBorder:Show();
        self.ItemIcon:Show();
        self.ItemText:Show();
        self.TextBackground:Show();
        self:Layout();
        ThemeUtil:SetFontColor(self.ItemText, "DarkModeGrey70");
        self.ItemText:SetShadowOffset(1, -1);
        self.ItemText:SetShadowColor(0, 0, 0);
    end

    -- Updates the widget dimensions and relayouts it when visible.
    function SourceItemButtonMixin:SetWidgetSize(borderSize, iconSize, borderEffectiveSize, fontSize, maxTextWidth)
        self.ItemBorder:SetSize(borderSize, borderSize);
        self.ItemIcon:SetSize(iconSize, iconSize);
        self.borderEffectiveSize = borderEffectiveSize;
        self.fontSize = fontSize;
        self.ItemText:SetWidth(maxTextWidth);
        if self:IsShown() then
            self:Layout();
        end
    end

    -- Sets the spacing between lines of the item description.
    function SourceItemButtonMixin:SetTextSpacing(spacing)
        self.ItemText:SetSpacing(spacing);
    end

    -- Positions the item icon, lore text, background, and outer widget.
    function SourceItemButtonMixin:Layout()
        local borderSize = self.borderEffectiveSize;
        local gap = self.fontSize;
        self.ItemBorder:ClearAllPoints();
        self.ItemBorder:SetPoint("CENTER", self, "LEFT", 0.5 * borderSize, 0);
        self.ItemText:ClearAllPoints();
        self.ItemText:SetPoint("LEFT", self.ItemBorder, "RIGHT", gap, 0);

        -- 3.3.5 compatibility: Use legacy string measurements if GetWrappedWidth is unavailable.
        local textWidth;
        if self.ItemText.GetWrappedWidth then
            textWidth = self.ItemText:GetWrappedWidth();
        else
            textWidth = math.min(self.ItemText:GetStringWidth(), self.ItemText:GetWidth());
        end

        local textHeight = self.ItemText:GetHeight();
        self.TextBackground:SetSize(textWidth + 2 * gap, textHeight + 2 * gap);
        self.TextBackground:ClearAllPoints();
        self.TextBackground:SetPoint("LEFT", self.ItemText, "LEFT", -gap, 0);
        self:SetSize(API.Round(borderSize + 2 * gap + textWidth), API.Round(math.max(textHeight, borderSize)));
    end

    -- Hides all visual elements of the item-description widget.
    function SourceItemButtonMixin:ClearDisplay()
        self.ItemBorder:Hide();
        self.ItemIcon:Hide();
        self.ItemText:Hide();
        self.TextBackground:Hide();
    end

    -- Stops pending item-data retries and clears the widget display.
    function SourceItemButtonMixin:ClearAll()
        self:SetScript("OnUpdate", nil);
        self.t = nil;
        self:ClearDisplay();
    end

    -- Cancels pending item-data retries when the widget is hidden.
    function SourceItemButtonMixin:OnHide()
        if self.t then
            self:ClearAll();
        end
    end

    -- Sets the texture used for the item's border.
    function SourceItemButtonMixin:SetTexture(file)
        self.ItemBorder:SetTexture(file);
    end

    -- Creates and initializes an item-description widget.
    function BookComponent:CreateSourceItemButton(parent)
        local f = CreateFrame("Frame", nil, parent, "DUIBookItemButtonTemplate");
        f.TextBackground:SetTexture("Interface/AddOns/DialogueUI/Art/Theme_Shared/NameplateDialogShadow.png");
        f.ItemIcon:SetTexCoord(0.0625, 0.9275, 0.0625, 0.9275);
        f.ItemBorder:SetTexCoord(768/1024, 864/1024, 1616/2048, 1712/2048);
        f.fontSize = 14;
        f.borderEffectiveSize = 64;
        API.Mixin(f, SourceItemButtonMixin);
        f:SetScript("OnHide", f.OnHide);
        return f
    end
end
