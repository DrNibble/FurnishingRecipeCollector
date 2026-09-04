FurnishingRecipeCollector = FurnishingRecipeCollector or {}
local FRC = FurnishingRecipeCollector
FRC.Name = "FurnishingRecipeCollector"
FRC.DisplayName = "Furnishing Recipe Collector"
FRC.Author = "tomstock"
FRC.Version = "1.4.9"

FRC.logger = nil

-- Price-source mapping between LibPrice source keys and human-readable labels.
FRC.PriceSourceKeys = {
  ["Master Merchant"]      = "mm",
  ["Arkadius Trade Tools"]  = "att",
  ["Tamriel Trade Centre"]  = "ttc",
}
FRC.PriceSourceLabels = {}
for _label, _key in pairs(FRC.PriceSourceKeys) do
  FRC.PriceSourceLabels[_key] = _label
end

-- Pretty field names for the tooltip label (avoids showing raw keys like
-- "avgPrice" or "SuggestedPrice").
FRC.PriceFieldLabels = {
  ["Min"]            = "Min",
  ["Avg"]            = "Avg",
  ["Max"]            = "Max",
  ["SuggestedPrice"] = "Suggested",
  ["avgPrice"]      = "Avg",
}

-- True only when the LibPrice global is present and usable.
function FRC.LibPriceAvailable()
  return LibPrice ~= nil and type(LibPrice.ItemLinkToPriceGold) == "function"
end

FRC.defaultSetting = {
  debug = false,
  price            = "Avg",          -- existing: TTC field (Min/Avg/Max) when source == ttc
  priceSource      = "ttc",          -- NEW: LibPrice source key: "mm" | "att" | "ttc"
  priceUseLibPrice = true,           -- NEW: use LibPrice when available (else legacy TTC path)
  priceFallbackToTTC = true,        -- NEW: if selected source has no data, fall back to direct TTC (marked)
  priceShowSource  = true,           -- NEW: prefix tooltip price line with source name
  -- MM data-confidence filter (require both conditions before showing a price)
  priceMMMinSales   = 5,             -- NEW: minimum numSales for MM price to be shown
  priceMMMaxDays    = 8,             -- NEW: maximum numDays for MM price to be shown
  -- Bid/Ask spread thresholds (applies to vRecipeListing, the ask/bid ratio)
  priceListingGreenMax = 1.15,       -- NEW: ratio <= this -> green (good chance to sell at price)
  priceListingRedMin  = 1.50,       -- NEW: ratio >= this -> red (won't sell at price)
  furnishing_on = true,
  furnishing_showrecipe_on = true,
  furnishing_showrecipe_ttc_on = true,
  furnishing_showrecipe_lck_on = true,
  furnishingrecipe_on = true,
  furnishingrecipe_ttc_on = true,
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
  gui={
    lastX = 100,
    lastY = 100,
    width = 650,
    height = 550,
    sort = "Location",
    sortDirection = ZO_SORT_ORDER_UP,
    filterLocation = "All",
    filterQuality = "All",
    filterKnowledge = "All",
  },
  guiDebug={
    lastX = 100,
    lastY = 100,
    width = 650,
    height = 550,
  }
}

--------------------------------------------------------------------
-- Locals
--------------------------------------------------------------------
--ZOs local speed-up/reference variables
local tos = tostring
local LCK = LibCharacterKnowledge
local SLASH = LibSlashCommander

local slashMainCommand
local slashDebugCommand

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
      text = "Prices require the TamrielTradeCentre addon to be installed",
    },
    {
      type = "divider",
    },
    {
      type = "description",
      text = "/furrecipe - opens a window for viewing recipe list",
    },
    {
      type = "divider",
    },
   -- Existing, relabelled to clarify it only applies when source == ttc
{
  type    = "dropdown",
  name    = "TTC Price Field",
  tooltip = "Which TTC price field to display (only used when the source is Tamriel Trade Centre).",
  choices = { "Min", "Avg", "Max" },
  getFunc = function() return FRC.savedVariables.price end,
  setFunc = function(newValue) FRC.savedVariables.price = newValue end,
},
{
  type = "divider",
},
-- NEW: price source selection (LibPrice integration)
{
  type    = "dropdown",
  name    = "Price Source",
  tooltip = "Which add-on LibPrice should query for item prices.",
  choices = { "Master Merchant", "Arkadius Trade Tools", "Tamriel Trade Centre" },
  getFunc = function()
      return FRC.PriceSourceLabels[FRC.savedVariables.priceSource] or "Tamriel Trade Centre"
  end,
  setFunc = function(newValue)
      FRC.savedVariables.priceSource = FRC.PriceSourceKeys[newValue] or "ttc"
  end,
  disabled = function() return not FRC.LibPriceAvailable() end,
  warning  = "Requires the LibPrice library and the matching price add-on to be installed.",
},
{
  type    = "checkbox",
  name    = "Use LibPrice for Prices",
  tooltip = "When LibPrice is installed, use it to read prices. Disable to fall back to direct TamrielTradeCentre queries.",
  getFunc = function() return FRC.savedVariables.priceUseLibPrice end,
  setFunc = function(newValue) FRC.savedVariables.priceUseLibPrice = newValue end,
  disabled = function() return not FRC.LibPriceAvailable() end,
  requiresReload = false,
},
{
  type    = "checkbox",
  name    = "Fallback to TTC if Source Empty",
  tooltip = "If the selected source has no price for an item, fall back to a direct Tamriel Trade Centre lookup (shown as 'fallback' in the tooltip). Disable to leave the price blank instead.",
  getFunc = function() return FRC.savedVariables.priceFallbackToTTC end,
  setFunc = function(newValue) FRC.savedVariables.priceFallbackToTTC = newValue end,
  disabled = function() return not (TamrielTradeCentrePrice ~= nil) end,
  requiresReload = false,
},
{
  type    = "checkbox",
  name    = "Show Price Source in Tooltip",
  tooltip = "Prefix the price line with the name of the source add-on.",
  getFunc = function() return FRC.savedVariables.priceShowSource end,
  setFunc = function(newValue) FRC.savedVariables.priceShowSource = newValue end,
  requiresReload = false,
},
{
  type = "divider",
},
-- NEW: Master Merchant data-confidence filter
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
  disabled = function() return not (FRC.savedVariables.priceSource == "mm" and FRC.LibPriceAvailable()) end,
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
  disabled = function() return not (FRC.savedVariables.priceSource == "mm" and FRC.LibPriceAvailable()) end,
  requiresReload = false,
},
{
  type = "divider",
},
-- NEW: Bid/Ask spread color thresholds
{
  type    = "slider",
  name    = "Bid/Ask Green (sellable) up to",
  tooltip = "Bid/Ask ratio at or below this is shown green (tight spread, good chance to sell at the ask price).",
  min     = 1.00,
  max     = 2.00,
  step    = 0.05,
  default = 1.15,
  getFunc = function() return FRC.savedVariables.priceListingGreenMax end,
  setFunc = function(newValue) FRC.savedVariables.priceListingGreenMax = newValue end,
  requiresReload = false,
},
{
  type    = "slider",
  name    = "Bid/Ask Red (unsellable) from",
  tooltip = "Bid/Ask ratio at or above this is shown red (wide spread, unlikely to sell at the ask price).",
  min     = 1.00,
  max     = 3.00,
  step    = 0.05,
  default = 1.50,
  getFunc = function() return FRC.savedVariables.priceListingRedMin end,
  setFunc = function(newValue) FRC.savedVariables.priceListingRedMin = newValue end,
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
    {type = "checkbox",name = "Show Recipe TTC Value on Furnishings",getFunc = function() return FRC.savedVariables.furnishing_showrecipe_ttc_on end,setFunc = function( newValue ) FRC.savedVariables.furnishing_showrecipe_ttc_on = newValue; end,--[[warning = "",]]  requiresReload = false},
    {type = "checkbox",name = "Show Recipe Character Knowledge on Furnishings",getFunc = function() return FRC.savedVariables.furnishing_showrecipe_lck_on end,setFunc = function( newValue ) FRC.savedVariables.furnishing_showrecipe_lck_on = newValue; end,--[[warning = "",]]  requiresReload = false},
    {
      type = "divider",
    },
    {type = "checkbox",name = "Show on Furnishing Recipes",getFunc = function() return FRC.savedVariables.furnishingrecipe_on end,setFunc = function( newValue ) FRC.savedVariables.furnishingrecipe_on = newValue; end,--[[warning = "",]]  requiresReload = false},
    {type = "checkbox",name = "Show Recipe TTC Value on Furnishing Recipes",getFunc = function() return FRC.savedVariables.furnishingrecipe_ttc_on end,setFunc = function( newValue ) FRC.savedVariables.furnishingrecipe_ttc_on = newValue; end,--[[warning = "",]]  requiresReload = false},

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

  if LCK ~= nil then
    LCK.RegisterForCallback("InsertYourAddonNameHere", LCK.EVENT_INITIALIZED, function( )
      FRC.InitGui()
      FRC.InitDebugGui()
    end)
  else
    FRC.InitGui()
    FRC.InitDebugGui()
  end

  if not IsConsoleUI() then
    if SLASH ~= nil then
      slashMainCommand = SLASH:Register()
      slashMainCommand:AddAlias("/furrecipe")
      slashMainCommand:AddAlias("/frc")
      slashMainCommand:SetCallback(FurnishingRecipeCollector.FRC_Toggle)
      slashMainCommand:SetDescription("Furniture Recipe Collector")
      slashDebugCommand = SLASH:Register()
      slashDebugCommand:AddAlias("/frc_debug")
      slashDebugCommand:SetCallback(FurnishingRecipeCollector.FRC_DebugToggle)
      slashDebugCommand:SetDescription("Furniture Recipe Collector Debug")
    else
      SLASH_COMMANDS["/furrecipe"] = FurnishingRecipeCollector.FRC_Toggle
      SLASH_COMMANDS["/frc"] = FurnishingRecipeCollector.FRC_Toggle
      SLASH_COMMANDS["/frc_debug"] = FurnishingRecipeCollector.FRC_DebugToggle
    end
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