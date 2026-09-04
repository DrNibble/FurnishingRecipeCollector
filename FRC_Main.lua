FurnishingRecipeCollector = FurnishingRecipeCollector or {}
local FRC = FurnishingRecipeCollector
FRC.Name = "FurnishingRecipeCollector"
FRC.DisplayName = "Furnishing Recipe Collector"
FRC.Author = "tomstock"
FRC.Version = "1.4.9"

FRC.logger = nil

FRC.defaultSetting = {
  debug = false,
  -- MM data-confidence filter (require both conditions before showing a price)
  priceMMMinSales   = 5,             -- minimum numSales for MM price to be shown
  priceMMMaxDays    = 8,             -- maximum numDays for MM price to be shown
  furnishing_on = true,
  furnishing_showrecipe_on = true,
  furnishing_showrecipe_mm_on = true,
  furnishing_showrecipe_lck_on = true,
  furnishingrecipe_on = true,
  furnishingrecipe_mm_on = true,
  grabbag_on= true,
  grabbag_lck_on= true,
  folio_on= true,
  folio_lck_on= true,
  colorCharUnknown=0x777766,
  colorCharKnown=0x3399FF,
  colorAllUnknown=0x777766,
  colorAllKnown=0x55ff1c,
  colorAllPartial=0x3399FF,
  colorQualityNormal=0XEDEAED,
  colorQualityMagic=0X34A221,
  colorQualitySuperior=0X458ADF,
  colorQualityEpic=0X9D43EC,
  colorQualityLegendary=0XE2C437,
}

--------------------------------------------------------------------
-- Locals
--------------------------------------------------------------------
--ZOs local speed-up/reference variables
local tos = tostring
local LCK = LibCharacterKnowledge

--[[
  ==============================================
  Setup LibDebugLogger as an optional dependency
  ==============================================
--]]
if LibDebugLogger then
  FRC.logger = LibDebugLogger.Create(FRC.Name)
  FRC.logger:SetEnabled(false)
end

--[[
  ==============================================
  Plugin Initialization - cache titles where possible, recreate when necessary
  ==============================================
--]]
local function OnLoad(eventCode, name)

  if name ~= FRC.Name then return end
  EVENT_MANAGER:UnregisterForEvent(FRC.Name, EVENT_ADD_ON_LOADED)

  FRC.savedVariables = ZO_SavedVars:NewAccountWide("FurnishingRecipeCollectorSavedVariables", 1, nil, FRC.defaultSetting) --Instead of nil you can also use GetWorldName() to save the SV server dependent

  if FRC.logger ~= nil then FRC.logger:Info("Loaded logger") end
  if FRC.logger ~= nil then FRC.logger:SetEnabled(FRC.savedVariables.debug) end

  local menuOptions = {
    type         = "panel",
    name         = FRC.DisplayName,
    displayName   = FRC.DisplayName,
    author       = FRC.Author,
    version       = FRC.Version,
    registerForRefresh  = true,
    registerForDefaults = true,
  }

  local dataTable = {
    {
      type = "description",
      text = "Displays additional information in tooltips for furnshing recipes obtained through Writ vendors. ",
    },
    {
      type = "description",
      text = "Character Knowledge requires the LibCharacterKnowledge library to be installed or Character Knowledge addon installed.",
    },
    {
      type = "description",
      text = "Debug requires the LibDebugLogger library to be installed",
    },
    {
      type = "description",
      text = "Prices require the Master Merchant addon to be installed",
    },
    {
      type = "divider",
    },
   -- Master Merchant data-confidence filter
{
  type    = "slider",
  name    = "MM Minimum Sales",
  tooltip = "Master Merchant price is only shown when the item has more than this many sales. Filters out low-sample (unreliable) prices.",
  min     = 0,
  max     = 50,
  step    = 1,
  default = 5,
  getFunc = function() return FRC.savedVariables.priceMMMinSales end,
  setFunc = function(newValue) FRC.savedVariables.priceMMMinSales = newValue end,
  disabled = function() return not FRC.MasterMerchantAvailable() end,
  requiresReload = false,
},
{
  type    = "slider",
  name    = "MM Maximum Age (days)",
  tooltip = "Master Merchant price is only shown when the sales data is more recent than this many days. Filters out stale prices.",
  min     = 1,
  max     = 30,
  step    = 1,
  default = 8,
  getFunc = function() return FRC.savedVariables.priceMMMaxDays end,
  setFunc = function(newValue) FRC.savedVariables.priceMMMaxDays = newValue end,
  disabled = function() return not FRC.MasterMerchantAvailable() end,
  requiresReload = false,
},
{
  type = "divider",
},
    { type = "checkbox", name = "Debug Logging Enabled", getFunc = function() return FRC.savedVariables.debug end, setFunc = function( newValue ) FRC.savedVariables.debug = newValue; if FRC.logger ~= nil then FRC.logger:SetEnabled(FRC.savedVariables.debug) end end, --[[warning = "",]] requiresReload = false},
    {
      type = "divider",
    },
    {type = "checkbox",name = "Show on Furnishings",getFunc = function() return FRC.savedVariables.furnishing_on end,setFunc = function( newValue ) FRC.savedVariables.furnishing_on = newValue; end,--[[warning = "",]]  requiresReload = false},
    {type = "checkbox",name = "Show Recipe on Furnishings",getFunc = function() return FRC.savedVariables.furnishing_showrecipe_on end,setFunc = function( newValue ) FRC.savedVariables.furnishing_showrecipe_on = newValue; end,--[[warning = "",]]  requiresReload = false},
    {type = "checkbox",name = "Show Recipe MM Price on Furnishings",getFunc = function() return FRC.savedVariables.furnishing_showrecipe_mm_on end,setFunc = function( newValue ) FRC.savedVariables.furnishing_showrecipe_mm_on = newValue; end,--[[warning = "",]]  requiresReload = false},
    {type = "checkbox",name = "Show Recipe Character Knowledge on Furnishings",getFunc = function() return FRC.savedVariables.furnishing_showrecipe_lck_on end,setFunc = function( newValue ) FRC.savedVariables.furnishing_showrecipe_lck_on = newValue; end,--[[warning = "",]]  requiresReload = false},
    {
      type = "divider",
    },
    {type = "checkbox",name = "Show on Furnishing Recipes",getFunc = function() return FRC.savedVariables.furnishingrecipe_on end,setFunc = function( newValue ) FRC.savedVariables.furnishingrecipe_on = newValue; end,--[[warning = "",]]  requiresReload = false},
    {type = "checkbox",name = "Show Recipe MM Price on Furnishing Recipes",getFunc = function() return FRC.savedVariables.furnishingrecipe_mm_on end,setFunc = function( newValue ) FRC.savedVariables.furnishingrecipe_mm_on = newValue; end,--[[warning = "",]]  requiresReload = false},

    {
      type = "divider",
    },
    {type = "checkbox",name = "Show on Writ Vendor Grab Bags",getFunc = function() return FRC.savedVariables.grabbag_on end,setFunc = function( newValue ) FRC.savedVariables.grabbag_on = newValue; end,--[[warning = "",]]  requiresReload = false},
    {type = "checkbox",name = "Show Character Knowledge",getFunc = function() return FRC.savedVariables.grabbag_lck_on end,setFunc = function( newValue ) FRC.savedVariables.grabbag_lck_on = newValue; end,--[[warning = "",]]  requiresReload = false},
    {
      type = "divider",
    },
    {type = "checkbox",name = "Show on Writ Vendor Folios",getFunc = function() return FRC.savedVariables.folio_on end,setFunc = function( newValue ) FRC.savedVariables.folio_on = newValue; end,--[[warning = "",]]  requiresReload = false},
    {type = "checkbox",name = "Show Character Knowledge",getFunc = function() return FRC.savedVariables.folio_lck_on end,setFunc = function( newValue ) FRC.savedVariables.folio_lck_on = newValue; end,--[[warning = "",]]  requiresReload = false},
  }
  local LAM = LibAddonMenu2
  LAM:RegisterAddonPanel(FRC.Name .. "Options", menuOptions )
  LAM:RegisterOptionControls(FRC.Name .. "Options", dataTable )

  FRC.HookTooltips()

  -- Debug slash command for price lookup diagnostics
  SLASH_COMMANDS["/frc_debug"] = function(itemLink)
    if itemLink == nil or itemLink == "" then
      d("FRC Debug: /frc_debug <itemLink> - paste an item link")
      return
    end

    d("=== FRC Debug ===")
    d("Input link: " .. tostring(itemLink))

    local vItemId = GetItemLinkItemId(itemLink)
    d("ItemId: " .. tostring(vItemId))

    local vItemType, vSpecialType = GetItemLinkItemType(itemLink)
    d("ItemType: " .. tostring(vItemType) .. " SpecialType: " .. tostring(vSpecialType))

    -- Try GetItemLinkRecipeResultItemLink with the ORIGINAL tooltip link
    local resultLink = GetItemLinkRecipeResultItemLink(itemLink)
    d("GetItemLinkRecipeResultItemLink(itemLink): " .. tostring(resultLink))

    -- Try with Linkify
    local linkified = "|H1:item:" .. vItemId .. ":1:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h"
    local resultLink2 = GetItemLinkRecipeResultItemLink(linkified)
    d("GetItemLinkRecipeResultItemLink(Linkify): " .. tostring(resultLink2))

    -- Try alternative API: GetRecipeInfoFromItemId + GetRecipeResultItemLink
    local craftingStationType, recipeListIndex, recipeIndex = GetRecipeInfoFromItemId(vItemId)
    d("GetRecipeInfoFromItemId: station=" .. tostring(craftingStationType)
      .. " listIndex=" .. tostring(recipeListIndex)
      .. " recipeIndex=" .. tostring(recipeIndex))
    if recipeListIndex and recipeIndex then
      local altResultLink = GetRecipeResultItemLink(recipeListIndex, recipeIndex, LINK_STYLE_BRACKETS)
      d("GetRecipeResultItemLink: " .. tostring(altResultLink))
    end

    -- Also try the FRC helper
    local frcResultLink = FRC.GetRecipeResultLink(itemLink, vItemId)
    d("FRC.GetRecipeResultLink: " .. tostring(frcResultLink))

    -- Check MasterMerchant
    if MasterMerchant == nil then
      d("MasterMerchant: NOT INSTALLED")
    elseif type(MasterMerchant.itemStats) ~= "function" then
      d("MasterMerchant: itemStats is not a function")
    else
      d("MasterMerchant: available")

      -- Try with the recipe link
      local stats1 = MasterMerchant:itemStats(itemLink, false)
      d("MM itemStats(recipeLink): " .. tostring(stats1))
      if stats1 then
        d("  avgPrice=" .. tostring(stats1.avgPrice)
          .. " numSales=" .. tostring(stats1.numSales)
          .. " numDays=" .. tostring(stats1.numDays)
          .. " craftCost=" .. tostring(stats1.craftCost))
      end

      -- Try with the result link
      if resultLink then
        local stats2 = MasterMerchant:itemStats(resultLink, false)
        d("MM itemStats(resultLink): " .. tostring(stats2))
        if stats2 then
          d("  avgPrice=" .. tostring(stats2.avgPrice)
            .. " numSales=" .. tostring(stats2.numSales)
            .. " numDays=" .. tostring(stats2.numDays)
            .. " craftCost=" .. tostring(stats2.craftCost))
        end
      end

      -- Try with Linkify of result itemId
      if resultLink then
        local resultItemId = GetItemLinkItemId(resultLink)
        local linkifiedResult = "|H1:item:" .. resultItemId .. ":1:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h"
        local stats3 = MasterMerchant:itemStats(linkifiedResult, false)
        d("MM itemStats(LinkifyResult): " .. tostring(stats3))
        if stats3 then
          d("  avgPrice=" .. tostring(stats3.avgPrice)
            .. " numSales=" .. tostring(stats3.numSales)
            .. " numDays=" .. tostring(stats3.numDays)
            .. " craftCost=" .. tostring(stats3.craftCost))
        end
      end
    end
    d("=== End FRC Debug ===")
  end
end
function FRC.Donate(control, mouseButton)
  local amount = 2000
  if mouseButton == 2 then
    amount = 10000
  elseif mouseButton == 3 then
    amount = 25000
  end

  SCENE_MANAGER:Show("mailSend")
  zo_callLater(function()
    ZO_MailSendToField:SetText("@tomstock")
    ZO_MailSendSubjectField:SetText("Thank you for FurnishingRecipeCollector!")
    QueueMoneyAttachment(amount)
    ZO_MailSendBodyField:TakeFocus()
  end, 200)
end
--[[
  ==============================================
  AddOn global and loading
  ==============================================
--]]
FRC = FRC
EVENT_MANAGER:RegisterForEvent(FRC.Name, EVENT_ADD_ON_LOADED, OnLoad)