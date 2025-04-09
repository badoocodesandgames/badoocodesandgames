local ADDON_NAME = "SimpleBags"
local ADDON_VERSION = "1.0.0"

local tooltip = CreateFrame("GameTooltip", "SimpleBagsScanningTooltip", nil, "GameTooltipTemplate")
tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local unusableItemsCache = {}
local soulboundItemsCache = {}

local ITEM_SIZE = 35
local ITEM_PADDING = 4
local ITEMS_PER_ROW = 6
local BAG_IDS = {0, 1, 2, 3, 4}
local HIGHLIGHT_SIZE_OFFSET = -2
local HIGHLIGHT_ALPHA = 0.3
local HEADER_HEIGHT = 14
local CATEGORY_SPACING = 2
local BAG_ICON_SIZE = 35
local BAG_ICON_PADDING = 4
local CATEGORY_ICON_SIZE = 16
local NUM_CONTAINER_FRAMES = 13

local ADDON_NAME = "SimpleBags"
local ADDON_VERSION = "1.0.0"

-- Ensure LibStub is available
local LibStub = _G.LibStub
if not LibStub then
    error("SimpleBags requires LibStub to function. Please ensure it is correctly embedded in the Libs folder.")
end

-- Initialize the addon with Ace3 libraries
if not _G[ADDON_NAME] then
    local success, addon = pcall(function()
        return LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
    end)
    if not success then
        error("Failed to initialize SimpleBags with Ace3 libraries: " .. addon)
    end
    _G[ADDON_NAME] = addon
end
local SimpleBags = _G[ADDON_NAME]

local defaults = {
    profile = {
        window = {
            scale = 1.0,
            position = { point = "BOTTOMRIGHT", x = -20, y = 20 },
            showGold = true,
            highlightQuestItems = true,
            highlightSoulbound = true,
            highlightUnequippable = true,
            showEmptySlots = false,
            showCategories = { ["Quest"] = true, ["BoE"] = true, ["Soulbound"] = true, ["Food/Drink"] = true, ["Other Items"] = true },
            isLocked = false,
            excludedItems = { ["Bobbotheclown"] = true },
            includedCategories = {},
            customCategories = {},
            categoryOrder = {"Quest", "BoE", "Soulbound", "Food/Drink", "Other Items"}
        }
    }
}

local function GetSafeItemInfo(link)
    if not link then return nil end
    local success, itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, 
          itemSubType, itemStackCount, itemEquipLoc, itemTexture = pcall(GetItemInfo, link)
    if success then
        return itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, 
               itemSubType, itemStackCount, itemEquipLoc, itemTexture
    end
    return nil
end

function SimpleBags:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("SimpleBagsDB", defaults, true)
    self:RegisterEvent("PLAYER_LOGIN", "OnPlayerLogin")
    self:RegisterEvent("BAG_UPDATE", "OnBagUpdate")
	self:RegisterEvent("MERCHANT_SHOW", "OnMerchantShow")
    self:RegisterEvent("MERCHANT_CLOSED", "OnMerchantClosed")
    self:RegisterEvent("PLAYER_MONEY", "UpdateGold")
    self:RegisterEvent("ITEM_LOCKED", function() wipe(unusableItemsCache) wipe(soulboundItemsCache) end)
    self:RegisterEvent("ITEM_UNLOCKED", function() wipe(unusableItemsCache) wipe(soulboundItemsCache) end)
    self:RegisterEvent("TRADE_CLOSED", function() 
        wipe(unusableItemsCache) 
        wipe(soulboundItemsCache) 
        self:UpdateBagContents() 
    end)
	-- Add mail events here
    self:RegisterEvent("MAIL_SHOW", "OnMailShow")
    self:RegisterEvent("MAIL_CLOSED", "OnMailClosed")
    self:RegisterChatCommand("sbags", "ToggleBags")
    self:RegisterChatCommand("sbags", "ToggleBags")
end

-- Handler for when the mailbox is opened
function SimpleBags:OnMailShow()
    -- Hide default Blizzard bag frames if they are shown
    if _G["ContainerFrame1"] and _G["ContainerFrame1"]:IsShown() then
        for i = 1, NUM_CONTAINER_FRAMES do
            local frame = _G["ContainerFrame" .. i]
            if frame then frame:Hide() end
        end
    end
    
    -- Show the SimpleBags frame
    self:ToggleBags()
end

-- Handler for when the mailbox is closed
function SimpleBags:OnMailClosed()
    -- Optionally hide the SimpleBags frame when the mailbox closes
    -- Uncomment the line below if you want the bags to close automatically
    -- self:ToggleBags()
end

function SimpleBags:OnMerchantShow()
    if BankFrame:IsShown() then CloseBankFrame() end
    if _G["ContainerFrame1"] and _G["ContainerFrame1"]:IsShown() then
        for i=1, NUM_CONTAINER_FRAMES do
            local frame = _G["ContainerFrame"..i]
            if frame then frame:Hide() end
        end
    end
    
    self:ToggleBags()
end

function SimpleBags:OnMerchantClosed()
    -- Optionally close our bags when merchant closes
    -- self:ToggleBags()
end

local function IsSoulbound(bagID, slot)
    local key = bagID .. "," .. slot
    if soulboundItemsCache[key] ~= nil then return soulboundItemsCache[key] end
    tooltip:ClearLines()
    tooltip:SetBagItem(bagID, slot)
    for i = 1, tooltip:NumLines() do
        local line = _G["SimpleBagsScanningTooltipTextLeft" .. i]
        if line and line:GetText() and line:GetText() == ITEM_SOULBOUND then
            soulboundItemsCache[key] = true
            return true
        end
    end
    soulboundItemsCache[key] = false
    return false
end

local function IsUnusableItem(bagID, slot)
    local key = bagID .. "," .. slot
    if unusableItemsCache[key] ~= nil then return unusableItemsCache[key] end
    tooltip:ClearLines()
    tooltip:SetBagItem(bagID, slot)
    for i = 1, tooltip:NumLines() do
        local leftText = _G["SimpleBagsScanningTooltipTextLeft" .. i]
        if leftText and leftText:GetText() then
            local r, g, b = leftText:GetTextColor()
            if r > 0.98 and g < 0.15 and b < 0.15 then
                unusableItemsCache[key] = true
                return true
            end
        end
    end
    unusableItemsCache[key] = false
    return false
end

local function IsBindOnEquip(bagID, slot)
    tooltip:ClearLines()
    tooltip:SetBagItem(bagID, slot)
    for i = 1, tooltip:NumLines() do
        local line = _G["SimpleBagsScanningTooltipTextLeft" .. i]
        if line and line:GetText() and line:GetText() == ITEM_BIND_ON_EQUIP then
            return true
        end
    end
    return false
end

function SimpleBags:OnPlayerLogin()
    self:InitializeFrame()
    local frame = _G["SimpleBagsFrame"]
    frame:SetClampedToScreen(true)
    frame:SetScale(self.db.profile.window.scale or 1.0)
    frame:SetFrameLevel(50)
    frame.isLocked = self.db.profile.window.isLocked or false

    if not frame.titleRegion then
        frame.titleRegion = CreateFrame("Frame", nil, frame)
        frame.titleRegion:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.titleRegion:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.titleRegion:SetHeight(30)
        frame.titleRegion:EnableMouse(true)
    end

    frame:SetScript("OnShow", function(self) SimpleBags:UpdateBagContents() SimpleBags:UpdateGold() end)
    frame:SetScript("OnHide", function(self) SimpleBags:SavePosition() end)
    
    frame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not self.isLocked then
            local mouseFocus = GetMouseFocus()
            if mouseFocus == self or mouseFocus == self.titleRegion then
                self.isDragging = true
                self:StartMoving()
            end
        end
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if self.isDragging then
            self:StopMovingOrSizing()
            self.isDragging = false
            SimpleBags:SavePosition()
        end
    end)

    frame.titleRegion:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            if not _G["SimpleBagsSettingsMenu"] then
                local settingsMenu = CreateFrame("Frame", "SimpleBagsSettingsMenu", UIParent, "UIDropDownMenuTemplate")
                settingsMenu.displayMode = "MENU"
                settingsMenu.initialize = function(dropdown, level) SimpleBags:InitializeSettingsMenu(level) end
			    settingsMenu:SetFrameStrata("TOOLTIP")  
				settingsMenu:SetFrameLevel(150)
            end
            ToggleDropDownMenu(1, nil, _G["SimpleBagsSettingsMenu"], self, 0, 0)
        end
    end)

    local toggleButton = _G["SimpleBagsToggleButton"] or CreateFrame("Button", "SimpleBagsToggleButton", nil, "SecureActionButtonTemplate")
    toggleButton:SetScript("OnClick", function() SimpleBags:ToggleBags() end)
    SetOverrideBindingClick(toggleButton, false, "B", "SimpleBagsToggleButton")

    frame:Hide()
    self:LoadPosition()
    self:UpdateGold()
    self:UpdateBagContents()
end

function SimpleBags:OnBagUpdate(bagID)
    self:UpdateBagContents()
    local bagsFrame = _G["SimpleBagsBagsFrame"]
    if bagsFrame and bagsFrame:IsShown() then bagsFrame:Hide() end
end

function SimpleBags:InitializeSettingsMenu(level)
    if not level then return end
    if level == 1 then
        local window = self.db.profile.window

        local info = UIDropDownMenu_CreateInfo()
        info.text = window.isLocked and "Unlock Frame" or "Lock Frame"
        info.func = function()
            window.isLocked = not window.isLocked
            _G["SimpleBagsFrame"].isLocked = window.isLocked
            print("|cFF33FF99[SimpleBags]|r Frame " .. (window.isLocked and "locked" or "unlocked") .. ".")
            CloseDropDownMenus()
        end
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Reset Position"
        info.func = function()
            window.position = CopyTable(defaults.profile.window.position)
            SimpleBags:LoadPosition()
            print("|cFF33FF99[SimpleBags]|r Position reset to default.")
            CloseDropDownMenus()
        end
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Highlight Quest Items"
        info.func = function()
            window.highlightQuestItems = not window.highlightQuestItems
            SimpleBags:UpdateBagContents()
            print("|cFF33FF99[SimpleBags]|r Quest item highlighting " .. (window.highlightQuestItems and "enabled" or "disabled") .. ".")
        end
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Highlight Soulbound Items"
        info.func = function()
            window.highlightSoulbound = not window.highlightSoulbound
            SimpleBags:UpdateBagContents()
            print("|cFF33FF99[SimpleBags]|r Soulbound item highlighting " .. (window.highlightSoulbound and "enabled" or "disabled") .. ".")
        end
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Highlight Unusable Items"
        info.func = function()
            window.highlightUnequippable = not window.highlightUnequippable
            SimpleBags:UpdateBagContents()
            print("|cFF33FF99[SimpleBags]|r Unusable item highlighting " .. (window.highlightUnequippable and "enabled" or "disabled") .. ".")
        end
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Create Category"
        info.func = function()
            StaticPopup_Show("SIMPLEBAGS_CREATE_CATEGORY")
        end
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

info = UIDropDownMenu_CreateInfo()
        info.text = "Manage Categories"
        info.func = function()
            self:ShowManageCategoriesFrame()
            CloseDropDownMenus()
        end
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
    end
end

function SimpleBags:InitializeFrame()
    local frame = _G["SimpleBagsFrame"]
    
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:SetBackdropBorderColor(0.2, 0.8, 0.2, 1)

    local container = _G["SimpleBagsContainer"]
    local title = _G["SimpleBagsFrameTitle"]
    title:SetPoint("TOPRIGHT", -20,-10)

    local bagsButton = _G["SimpleBagsFrameBagsButton"]
    bagsButton:SetText("B")
    bagsButton:SetScript("OnClick", function() SimpleBags:ToggleBagsList() end)

    local emptyButton = _G["SimpleBagsFrameEmptyButton"]
    emptyButton:SetText("E")
    emptyButton:SetScript("OnClick", function()
        SimpleBags.db.profile.window.showEmptySlots = not SimpleBags.db.profile.window.showEmptySlots
        SimpleBags:UpdateBagContents()
    end)

    local moneyFrame = _G["SimpleBagsMoneyFrame"] or CreateFrame("Frame", "SimpleBagsMoneyFrame", frame)
    moneyFrame:SetSize(140, 20)
    moneyFrame:SetPoint("BOTTOM", frame, "BOTTOM", 0, 6)
    moneyFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    moneyFrame:SetBackdropColor(0, 0, 0, 1)
    moneyFrame:SetBackdropBorderColor(0.7, 0.5, 0.2, 1)

    local goldIcon = _G["SimpleBagsGoldIcon"] or moneyFrame:CreateTexture("SimpleBagsGoldIcon", "OVERLAY")
    goldIcon:SetSize(16, 16)
    goldIcon:SetPoint("LEFT", moneyFrame, "LEFT", 20, 0)
    goldIcon:SetTexture("Interface\\MoneyFrame\\UI-MoneyIcons")
    goldIcon:SetTexCoord(0, 0.25, 0, 1)

    local goldText = _G["SimpleBagsGoldText"] or moneyFrame:CreateFontString("SimpleBagsGoldText", "OVERLAY", "GameFontHighlightSmall")
    goldText:SetPoint("RIGHT", goldIcon, "RIGHT", 14, 0)
    goldText:SetJustifyH("RIGHT")

    local silverIcon = _G["SimpleBagsSilverIcon"] or moneyFrame:CreateTexture("SimpleBagsSilverIcon", "OVERLAY")
    silverIcon:SetSize(16, 16)
    silverIcon:SetPoint("RIGHT", goldText, "RIGHT", 20, 0)
    silverIcon:SetTexture("Interface\\MoneyFrame\\UI-MoneyIcons")
    silverIcon:SetTexCoord(0.25, 0.5, 0, 1)

    local silverText = _G["SimpleBagsSilverText"] or moneyFrame:CreateFontString("SimpleBagsSilverText", "OVERLAY", "GameFontHighlightSmall")
    silverText:SetPoint("RIGHT", silverIcon, "RIGHT", 14, 0)
    silverText:SetJustifyH("RIGHT")

    local copperIcon = _G["SimpleBagsCopperIcon"] or moneyFrame:CreateTexture("SimpleBagsCopperIcon", "OVERLAY")
    copperIcon:SetSize(16, 16)
    copperIcon:SetPoint("RIGHT", silverText, "RIGHT", 20, 0)
    copperIcon:SetTexture("Interface\\MoneyFrame\\UI-MoneyIcons")
    copperIcon:SetTexCoord(0.5, 0.75, 0, 1)

    local copperText = _G["SimpleBagsCopperText"] or moneyFrame:CreateFontString("SimpleBagsCopperText", "OVERLAY", "GameFontHighlightSmall")
    copperText:SetPoint("RIGHT", copperIcon, "RIGHT", 14, 0)
    copperText:SetJustifyH("RIGHT")

    container:SetFrameLevel(frame:GetFrameLevel() + 1)
end

StaticPopupDialogs["SIMPLEBAGS_CREATE_CATEGORY"] = {
    text = "Enter a name for the new category (max 8 characters):",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = true,
    OnShow = function(self)
        self.editBox:SetMaxLetters(8)
    end,
    OnAccept = function(self)
        local categoryName = self.editBox:GetText():trim()
        if categoryName ~= "" and #categoryName <= 8 then
            SimpleBags:AddCategory(categoryName)
        elseif #categoryName > 8 then
            print("|cFF33FF99[SimpleBags]|r Category name must be 8 characters or less.")
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local categoryName = self:GetText():trim()
        if categoryName ~= "" and #categoryName <= 8 then
            SimpleBags:AddCategory(categoryName)
            self:GetParent():Hide()
        elseif #categoryName > 8 then
            print("|cFF33FF99[SimpleBags]|r Category name must be 8 characters or less.")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true
}

function SimpleBags:ShowManageCategoriesFrame()
    local frame = _G["SimpleBagsManageCategoriesFrame"]
    if not frame then
        frame = CreateFrame("Frame", "SimpleBagsManageCategoriesFrame", UIParent)
        frame:SetFrameStrata("TOOLTIP")
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        frame:SetBackdropColor(0, 0, 0, 1)
        frame:SetBackdropBorderColor(0.2, 0.8, 0.2, 1)
        frame:SetPoint("CENTER", UIParent, "CENTER")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:SetScript("OnMouseDown", function(self) self:StartMoving() end)
        frame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)
        frame:Hide()

        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", frame, "TOP", 0, -10)
        title:SetText("Manage Categories")

        local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
		closeButton:SetSize(22, 22)
        closeButton:SetScript("OnClick", function() frame:Hide() end)

        frame.categoryFrames = {}
    end

    for _, catFrame in pairs(frame.categoryFrames) do
        catFrame:Hide()
    end

    local frameWidth = 320
    local buttonWidth = 60
    local spacing = 5
    local rowHeight = 25
    local offsetY = -40
    local numCategories = #self.db.profile.window.categoryOrder

    for i, category in ipairs(self.db.profile.window.categoryOrder) do
        local catFrame = frame.categoryFrames[i] or CreateFrame("Frame", nil, frame)
        catFrame:SetPoint("TOP", frame, "TOP", 0, offsetY)
        catFrame:SetSize(frameWidth - 40, 20)
        frame.categoryFrames[i] = catFrame

        local moveButton = catFrame.moveButton or CreateFrame("Button", nil, catFrame, "UIPanelButtonTemplate")
        moveButton:SetSize(16, 16)
        moveButton:SetPoint("LEFT", catFrame, "LEFT", 0, 0)
        moveButton:SetText("v")
        moveButton:SetScript("OnClick", function()
            self:MoveCategory(category)
            frame:Hide()
            self:ShowManageCategoriesFrame()
        end)
        catFrame.moveButton = moveButton

        local text = catFrame.text or catFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", moveButton, "RIGHT", 5, 0)
        text:SetText(category)
        catFrame.text = text

        local toggleButton = catFrame.toggleButton or CreateFrame("Button", nil, catFrame, "UIPanelButtonTemplate")
        toggleButton:SetSize(buttonWidth, 20)
        toggleButton:SetPoint("CENTER", catFrame, "CENTER", 20, 0)
        toggleButton:SetText(self.db.profile.window.showCategories[category] and "Hide" or "Show")
        toggleButton:SetScript("OnClick", function()
            self.db.profile.window.showCategories[category] = not self.db.profile.window.showCategories[category]
            toggleButton:SetText(self.db.profile.window.showCategories[category] and "Hide" or "Show")
            self:UpdateBagContents()
            print("|cFF33FF99[SimpleBags]|r " .. category .. " " .. (self.db.profile.window.showCategories[category] and "shown" or "hidden") .. ".")
        end)
        catFrame.toggleButton = toggleButton

        if not tContains(defaults.profile.window.categoryOrder, category) then
            local removeButton = catFrame.removeButton or CreateFrame("Button", nil, catFrame, "UIPanelButtonTemplate")
            removeButton:SetSize(buttonWidth, 20)
            removeButton:SetPoint("LEFT", toggleButton, "RIGHT", spacing, 0)
            removeButton:SetText("Remove")
            removeButton:SetScript("OnClick", function()
                self:RemoveCategory(category)
                frame:Hide()
                self:ShowManageCategoriesFrame()
            end)
            catFrame.removeButton = removeButton
        elseif catFrame.removeButton then
            catFrame.removeButton:Hide()
        end

        catFrame:Show()
        offsetY = offsetY - rowHeight
    end

    local baseHeight = 70
    local totalHeight = baseHeight + (numCategories * rowHeight)
    frame:SetSize(frameWidth, math.max(totalHeight, 150))

    frame:Show()
end

function SimpleBags:MoveCategory(category)
    local order = self.db.profile.window.categoryOrder
    for i, cat in ipairs(order) do
        if cat == category then
            if i > 1 and IsShiftKeyDown() then
                order[i], order[i - 1] = order[i - 1], order[i]
                self:UpdateBagContents()
                print("|cFF33FF99[SimpleBags]|r " .. category .. " moved up.")
            elseif i < #order and not IsShiftKeyDown() then
                order[i], order[i + 1] = order[i + 1], order[i]
                self:UpdateBagContents()
                print("|cFF33FF99[SimpleBags]|r " .. category .. " moved down.")
            end
            break
        end
    end
end

function SimpleBags:LoadPosition()
    local pos = self.db.profile.window.position or defaults.profile.window.position
    local frame = _G["SimpleBagsFrame"]
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
end

function SimpleBags:SavePosition()
    local frame = _G["SimpleBagsFrame"]
    local point, _, _, x, y = frame:GetPoint()
    self.db.profile.window.position = { point = point, x = x, y = y }
end

function SimpleBags:UpdateGold()
    if not self.db.profile.window.showGold then 
        _G["SimpleBagsGoldText"]:SetText("")
        _G["SimpleBagsSilverText"]:SetText("")
        _G["SimpleBagsCopperText"]:SetText("")
        _G["SimpleBagsMoneyFrame"]:Hide()
        return 
    end
    
    _G["SimpleBagsMoneyFrame"]:Show()
    local money = GetMoney()
    local gold = floor(money / (100 * 100))
    local silver = floor((money / 100) % 100)
    local copper = money % 100
    
    _G["SimpleBagsGoldText"]:SetText(gold > 0 and gold or "")
    _G["SimpleBagsSilverText"]:SetText(silver > 0 and silver or "")
    _G["SimpleBagsCopperText"]:SetText(copper > 0 and copper or "")
end

function SimpleBags:ToggleBagsList()
    local bagsFrame = _G["SimpleBagsBagsFrame"]
    local wasShown = bagsFrame and bagsFrame:IsShown()
    
    if not bagsFrame then
        bagsFrame = CreateFrame("Frame", "SimpleBagsBagsFrame", _G["SimpleBagsFrame"])
        bagsFrame:SetFrameStrata("DIALOG")
        bagsFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        bagsFrame:SetBackdropColor(0, 0, 0, 1)
        bagsFrame:SetBackdropBorderColor(0.2, 0.8, 0.2, 1)
    end
    
    for i = 1, 4 do
        local bagIcon = _G["SimpleBagsBagIcon"..i]
        if bagIcon then bagIcon:Hide() end
    end
    
    local numEquipped = 0
    for i = 1, 4 do
        local bagID = i
        local bagIcon = _G["SimpleBagsBagIcon"..bagID] or CreateFrame("Button", "SimpleBagsBagIcon"..bagID, bagsFrame)
        bagIcon.bagID = bagID
        bagIcon:SetSize(BAG_ICON_SIZE, BAG_ICON_SIZE)
        bagIcon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        bagIcon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local link = GetInventoryItemLink("player", ContainerIDToInventoryID(self.bagID))
            if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetText("Empty Bag Slot") end
            GameTooltip:Show()
        end)
        bagIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bagIcon:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                local inventoryID = ContainerIDToInventoryID(self.bagID)
                PickupInventoryItem(inventoryID)
                if CursorHasItem() then PutItemInBackpack() end
                SimpleBags:UpdateBagContents()
                SimpleBags:ToggleBagsList()
            end
        end)
        
        local link = GetInventoryItemLink("player", ContainerIDToInventoryID(bagID))
        if link then
            local _, _, _, _, _, _, _, _, _, texture = GetSafeItemInfo(link)
            bagIcon:SetNormalTexture(texture or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
            bagIcon:SetPoint("TOPLEFT", 10 + numEquipped * (BAG_ICON_SIZE + BAG_ICON_PADDING), -10)
            bagIcon:Show()
            numEquipped = numEquipped + 1
        else
            bagIcon:Hide()
        end
    end
    
    local frameWidth = 20 + numEquipped * (BAG_ICON_SIZE + BAG_ICON_PADDING)
    if numEquipped == 0 then frameWidth = 20 + BAG_ICON_SIZE end
    bagsFrame:SetSize(frameWidth, BAG_ICON_SIZE + 20)
    bagsFrame:SetPoint("BOTTOMLEFT", _G["SimpleBagsFrame"], "TOPLEFT", 0, 5)
    
    if wasShown then bagsFrame:Hide() else bagsFrame:Show() bagsFrame:Raise() end
end

function SimpleBags:AddCategory(categoryName)
    if not categoryName or categoryName == "" then return end
    if tContains(self.db.profile.window.categoryOrder, categoryName) then
        print("|cFF33FF99[SimpleBags]|r Category '" .. categoryName .. "' already exists.")
        return
    end
    table.insert(self.db.profile.window.categoryOrder, categoryName)
    self.db.profile.window.customCategories[categoryName] = true
    self.db.profile.window.showCategories[categoryName] = true
    self:UpdateBagContents()
    print("|cFF33FF99[SimpleBags]|r Category added: " .. categoryName)
    
    local manageFrame = _G["SimpleBagsManageCategoriesFrame"]
    if manageFrame and manageFrame:IsShown() then
        manageFrame:Hide()
        self:ShowManageCategoriesFrame()
    end
end

function SimpleBags:RemoveCategory(categoryName)
    if tContains(defaults.profile.window.categoryOrder, categoryName) then
        print("|cFF33FF99[SimpleBags]|r Cannot remove default category '" .. categoryName .. "'.")
        return
    end
    if not tContains(self.db.profile.window.categoryOrder, categoryName) then
        print("|cFF33FF99[SimpleBags]|r Category '" .. categoryName .. "' does not exist.")
        return
    end
    for i, cat in ipairs(self.db.profile.window.categoryOrder) do
        if cat == categoryName then
            table.remove(self.db.profile.window.categoryOrder, i)
            self.db.profile.window.customCategories[categoryName] = nil
            self.db.profile.window.showCategories[categoryName] = nil
            for itemName, assignedCat in pairs(self.db.profile.window.includedCategories) do
                if assignedCat == categoryName then
                    self.db.profile.window.includedCategories[itemName] = nil
                end
            end
            self:UpdateBagContents()
            print("|cFF33FF99[SimpleBags]|r Category removed: " .. categoryName)
            break
        end
    end
end

function SimpleBags:AssignItemToCategory(itemName, category)
    if not tContains(self.db.profile.window.categoryOrder, category) then return end
    self.db.profile.window.includedCategories[itemName] = category
    self.db.profile.window.excludedItems[itemName] = nil
    self:UpdateBagContents()
    print("|cFF33FF99[SimpleBags]|r " .. itemName .. " assigned to " .. category .. ".")
end

function SimpleBags:UpdateBagContents()
    local frame = _G["SimpleBagsFrame"]
    if not frame or not frame:IsShown() then return end
    
    local container = _G["SimpleBagsContainer"]
    
    for i = 1, container:GetNumChildren() do
        local child = select(i, container:GetChildren())
        if child then 
            child:Hide() 
            if child.highlight then child.highlight:Hide() end 
        end
    end
    
    for _, category in ipairs(self.db.profile.window.categoryOrder) do
        local header = _G["SimpleBagsHeader" .. category]
        if header then header:Hide() end
        local catIcon = _G["SimpleBagsCategoryIcon" .. category]
        if catIcon then catIcon:Hide() end
    end
    
    for i = 1, container:GetNumRegions() do
        local region = select(i, container:GetRegions())
        if region and region:GetObjectType() == "FontString" and strfind(region:GetName() or "", "SimpleBagsHeader") then
            local currentCategory = strmatch(region:GetName(), "SimpleBagsHeader(.+)")
            if not tContains(self.db.profile.window.categoryOrder, currentCategory) then
                region:Hide()
            end
        end
    end
    
    local items = {}
    for _, category in ipairs(self.db.profile.window.categoryOrder) do
        items[category] = {}
    end
    
    local showEmptySlots = self.db.profile.window.showEmptySlots or false
    local showCategories = self.db.profile.window.showCategories or {}
    
    for _, bagID in ipairs(BAG_IDS) do
        local numSlots = GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local texture, itemCount, locked, quality, readable, lootable, itemLink = GetContainerItemInfo(bagID, slot)
            local isQuestItem, questId = GetContainerItemQuestInfo(bagID, slot)
            local category = "Other Items"
            
            itemLink = GetContainerItemLink(bagID, slot) or itemLink
            if itemLink then
                local itemName = GetItemInfo(itemLink) or "Unknown Item"
                if questId or isQuestItem then
                    category = "Quest"
                elseif self.db.profile.window.includedCategories[itemName] then
                    category = self.db.profile.window.includedCategories[itemName]
                elseif not self.db.profile.window.excludedItems[itemName] then
                    if IsBindOnEquip(bagID, slot) then
                        category = "BoE"
                    elseif IsSoulbound(bagID, slot) then
                        category = "Soulbound"
                    else
                        local _, _, _, _, _, itemType = GetSafeItemInfo(itemLink)
                        if itemType == "Consumable" then
                            category = "Food/Drink"
                        end
                    end
                end
            end
            
            if texture or showEmptySlots then
                table.insert(items[category], {
                    bagID = bagID, slot = slot, texture = texture or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag",
                    count = itemCount, link = itemLink, quality = quality,
                    isSoulbound = itemLink and IsSoulbound(bagID, slot),
                    isUnusable = itemLink and IsUnusableItem(bagID, slot)
                })
            end
        end
    end
    
    local verticalOffset = 0
    local maxItemsInRow = 0
    
    for _, category in ipairs(self.db.profile.window.categoryOrder) do
        if showCategories[category] then
            local headerName = "SimpleBagsHeader" .. category
            local header = _G[headerName] or container:CreateFontString(headerName, "OVERLAY", "GameFontHighlightSmall")
            header:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -verticalOffset)
            header:SetText(category .. " (" .. #items[category] .. ")")
            
            local catIconName = "SimpleBagsCategoryIcon" .. category
            local catIcon = _G[catIconName] or CreateFrame("Button", catIconName, container)
            catIcon:SetSize(CATEGORY_ICON_SIZE, CATEGORY_ICON_SIZE)
            catIcon:SetPoint("LEFT", header, "RIGHT", 5, 0)
            catIcon:SetNormalTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
            catIcon:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
            catIcon:EnableMouse(true)
            catIcon.category = category
            catIcon:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Drop item here to add to " .. self.category)
                GameTooltip:Show()
            end)
            catIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
            catIcon:SetScript("OnReceiveDrag", function(self)
                local infoType, itemID, itemLink = GetCursorInfo()
                if infoType == "item" and itemLink then
                    local itemName = GetItemInfo(itemLink)
                    if itemName then
                        SimpleBags:AssignItemToCategory(itemName, self.category)
                        ClearCursor()
                    end
                end
            end)
            
            header:Show()
            catIcon:Show()
            verticalOffset = verticalOffset + HEADER_HEIGHT
            
            if #items[category] > 0 then
                local index = 0
                for _, item in ipairs(items[category]) do
                    local buttonName = "SimpleBagsItem"..item.bagID.."_"..item.slot
                    local button = _G[buttonName] or CreateFrame("Button", buttonName, container, "ContainerFrameItemButtonTemplate")
                    
                    button:SetParent(container)
                    button:ClearAllPoints()
                    button:SetID(item.slot)
                    button.bagID = item.bagID
                    button.slot = item.slot
                    button:Enable()
                    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    
                    button:SetScript("OnEnter", function(self) 
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT") 
                        GameTooltip:SetBagItem(self.bagID, self.slot) 
                        GameTooltip:Show() 
                    end)
                    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    
                    button:SetScript("OnMouseDown", function(self, button)
                        if button == "LeftButton" then 
                            self:GetParent():GetParent().isDragging = false 
                        end
                    end)
                    
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        PickupContainerItem(self.bagID, self.slot)
    elseif button == "RightButton" then
        UseContainerItem(self.bagID, self.slot)
    end
end)
                    
                    local row = floor(index / ITEMS_PER_ROW)
                    local col = index % ITEMS_PER_ROW
                    button:SetPoint("TOPLEFT", container, "TOPLEFT", 
                        col * (ITEM_SIZE + ITEM_PADDING), 
                        -(verticalOffset + row * (ITEM_SIZE + ITEM_PADDING)))
                    
                    local icon = _G[buttonName.."IconTexture"]
                    icon:SetTexture(item.texture or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
                    
                    local count = _G[buttonName.."Count"]
                    if item.count and item.count > 1 then
                        count:SetText(item.count)
                        count:Show()
                    else
                        count:Hide()
                    end
                    
                    local normal = _G[buttonName.."NormalTexture"]
                    if item.quality and item.quality > 1 then
                        normal:SetVertexColor(GetItemQualityColor(item.quality))
                    else
                        normal:SetVertexColor(1, 1, 1, 1)
                    end
                    
                    if not button.highlight then
                        button.highlight = button:CreateTexture(nil, "OVERLAY")
                        button.highlight:SetPoint("CENTER", button, "CENTER")
                        button.highlight:SetSize(ITEM_SIZE + HIGHLIGHT_SIZE_OFFSET, ITEM_SIZE + HIGHLIGHT_SIZE_OFFSET)
                        button.highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
                    end
                    
                    if category == "Quest" and self.db.profile.window.highlightQuestItems then
                        button.highlight:SetVertexColor(0, 1, 0, HIGHLIGHT_ALPHA)
                        button.highlight:Show()
                    elseif item.isSoulbound and self.db.profile.window.highlightSoulbound then
                        button.highlight:SetVertexColor(0.5, 0, 1, HIGHLIGHT_ALPHA)
                        button.highlight:Show()
                    elseif item.isUnusable and self.db.profile.window.highlightUnequippable then
                        button.highlight:SetVertexColor(1, 0, 0, HIGHLIGHT_ALPHA)
                        button.highlight:Show()
                    else
                        button.highlight:Hide()
                    end
                    
                    button:Show()
                    index = index + 1
                end
                
                local numItemsInCategory = #items[category]
                local numRows = ceil(numItemsInCategory / ITEMS_PER_ROW)
                maxItemsInRow = math.max(maxItemsInRow, math.min(numItemsInCategory, ITEMS_PER_ROW))
                verticalOffset = verticalOffset + numRows * (ITEM_SIZE + ITEM_PADDING) + CATEGORY_SPACING
            else
                verticalOffset = verticalOffset + CATEGORY_SPACING
            end
        end
    end
    
    local containerWidth = maxItemsInRow * (ITEM_SIZE + ITEM_PADDING) - ITEM_PADDING
    if maxItemsInRow == 0 then containerWidth = ITEM_SIZE end
    local containerHeight = verticalOffset - CATEGORY_SPACING
    
    local minFrameWidth = 160
    local frameWidth = math.max(containerWidth + 40, minFrameWidth)
    local frameHeight = containerHeight + 80
    
    frame:SetSize(frameWidth, frameHeight)
    container:SetSize(containerWidth, containerHeight)
    
    local freeSlots, totalSlots = 0, 0
    for _, bagID in ipairs(BAG_IDS) do
        freeSlots = freeSlots + GetContainerNumFreeSlots(bagID)
        totalSlots = totalSlots + GetContainerNumSlots(bagID)
    end
    _G["SimpleBagsFrameTitle"]:SetText(format("%d/%d", totalSlots - freeSlots, totalSlots))
end

function SimpleBags:ToggleBags(input)
    local frame = _G["SimpleBagsFrame"]
    if frame:IsShown() then 
        frame:Hide() 
    else 

        if _G["ContainerFrame1"] and _G["ContainerFrame1"]:IsShown() then
            for i=1, NUM_CONTAINER_FRAMES do
                local frame = _G["ContainerFrame"..i]
                if frame then frame:Hide() end
            end
        end
        frame:Show() 
    end
end