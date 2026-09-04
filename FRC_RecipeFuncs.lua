FurnishingRecipeCollector = FurnishingRecipeCollector or {}
local FRC = FurnishingRecipeCollector

--------------------------------------------------------------------
-- Locals
--------------------------------------------------------------------
local tos = tostring
local LCK = LibCharacterKnowledge

local function Linkify(itemId)
  return "|H1:item:"..itemId..":1:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h"
end
local function GetItemlinkDetails(itemLinkOrItemId)
  local vItemLink, vItemId

  if type(itemLinkOrItemId) == "string" then
    vItemLink = itemLinkOrItemId
    vItemId = GetItemLinkItemId(vItemLink)
  else
    vItemId = itemLinkOrItemId
    vItemLink = Linkify(vItemId)
  end

  return vItemLink, vItemId
end

--------------------------------------------------------------------
-- Price lookup
-- Centralises all price fetching behind one source-agnostic helper.
-- Uses LibPrice (Sharlikran fork), which provides ItemLinkToBidAskSpread.
--
-- Returns:
--   price              (number|nil)  gold price to display
--   spreadRatio        (number|nil)  Bid/Ask ratio from ItemLinkToBidAskSpread
--                                   (vRecipeListing in the tooltip)
--   sourceLabel        (string)      human source name for the tooltip
--   fieldName          (string|nil)  price field used (Avg/Min/Max/avgPrice/...)
--   spreadLabel        (string|nil)  human label for the Bid/Ask line
--   priceProfitable    (boolean|nil) true only for the MM source when
--                                   craftCost > 0 and craftCost < avgPrice
--                                   (profitable to craft & sell); nil otherwise
--
-- The Bid/Ask spread is computed by the REAL LibPrice function
-- ItemLinkToBidAskSpread (verified in the attached LibPrice.lua). It is NOT
-- synthesized from avgPrice.
--------------------------------------------------------------------
function FRC.GetRecipePrice(itemLink)
  local sv          = FRC.savedVariables or {}
  local useLib     = sv.priceUseLibPrice ~= false and FRC.LibPriceAvailable()
  local sourceKey  = sv.priceSource or "ttc"
  local sourceLabel = FRC.PriceSourceLabels[sourceKey] or "Tamriel Trade Centre"

  -- Bid/Ask spread is computed from the selected source via the real LibPrice
  -- function. It is gated on priceUseLibPrice so that disabling LibPrice restores
  -- v1.4.9 exactly (no Bid/Ask line). It is independent of the price-display
  -- path below, so a trustworthy MM price is NOT required to show the spread.
  local spreadRatio, spreadLabel = nil, nil
  if useLib and itemLink ~= nil then
    spreadRatio, spreadLabel = FRC.GetBidAskSpread(itemLink, sourceKey)
    -- Label the spread with its source so it is clear the Bid/Ask reflects the
    -- selected source (e.g. "Master Merchant Bid/Ask") even when the PRICE line
    -- has fallen back to TTC.
    if spreadLabel ~= nil then
      spreadLabel = (sourceLabel or "Source") .. " Bid/Ask"
    end
  end

  -- ----- Path A: LibPrice -------------------------------------------------
  if useLib and itemLink ~= nil then
    local data = LibPrice.ItemLinkToPriceData(itemLink, sourceKey)
    local src = data and data[sourceKey]

    if sourceKey == "ttc" then
      -- TTC: preserve the user's Min/Avg/Max field selection ourselves.
      if src then
        local field = sv.price or "Avg"
        local price = src[field]
        if price ~= nil then
          return price, spreadRatio, sourceLabel, field, spreadLabel, nil
        end
      end

    elseif sourceKey == "mm" then
      -- MM: only show the price if the data is trustworthy: enough sales AND
      -- recent enough. Both thresholds are user-configurable saved vars.
      -- Uses ItemLinkToPriceData (not ItemLinkToPriceGold) so we can read
      -- numSales / numDays, which ItemLinkToPriceGold discards.
      if src and src.avgPrice and src.numSales and src.numDays
         and src.numSales > (sv.priceMMMinSales or 5)
         and src.numDays  < (sv.priceMMMaxDays  or 8) then
        -- Profitable to craft & sell when the crafting cost is strictly below
        -- the average sale price. craftCost is only present for the MM source.
        -- Guard against unknown/zero craftCost (0 = no data) so we never color
        -- a price green from missing craft-cost data.
        local priceProfitable =
            src.craftCost ~= nil and src.craftCost > 0
            and src.avgPrice ~= nil
            and src.craftCost < src.avgPrice
        return src.avgPrice, spreadRatio, sourceLabel, "avgPrice",
               spreadLabel, priceProfitable
      end
      -- Data present but not trustworthy (few sales or stale): do NOT show a
      -- price for this source. Fall through to the optional TTC fallback.

    else -- "att" and any future source
      local gold, sKey, fName = LibPrice.ItemLinkToPriceGold(itemLink, sourceKey)
      if gold ~= nil then
        return gold, spreadRatio, FRC.PriceSourceLabels[sKey] or sourceLabel,
               fName, spreadLabel, nil
      end
    end

    -- Selected source had no (trustworthy) data: optional fallback to direct TTC.
    -- The spread stays from the selected source (computed above); only the
    -- price line falls back, and it is labeled as a fallback.
    if sv.priceFallbackToTTC ~= false then
      local price, _, field = FRC.GetTTCPriceDirect(itemLink, sv)
      if price ~= nil then
        return price, spreadRatio,
               "Tamriel Trade Centre (fallback from " .. sourceLabel .. ")",
               field, spreadLabel, nil
      end
    end
    return nil, spreadRatio, sourceLabel, nil, spreadLabel, nil
  end

  -- ----- Path B: legacy direct TamrielTradeCentre --------------------------
  -- Reached when LibPrice is absent or priceUseLibPrice is off. No Bid/Ask
  -- line is shown in this path (spreadRatio stays nil).
  local price, _, field = FRC.GetTTCPriceDirect(itemLink, sv)
  if price ~= nil then
    return price, nil, "Tamriel Trade Centre", field, nil, nil
  end

  -- ----- Path C: nothing available ---------------------------------------
  return nil, spreadRatio, sourceLabel, nil, spreadLabel, nil
end

-- Bid/Ask spread via the REAL LibPrice.ItemLinkToBidAskSpread function.
-- Respects the selected source (passed as the source allowlist).
-- Uses ONLY the "gold" currency entry; if gold is absent or bid/ask missing,
-- returns nil (the tooltip then omits the Bid/Ask line or shows "no data").
-- Returns: ratio = ask.value / bid.value (>= 1.0), human label ("Bid/Ask").
function FRC.GetBidAskSpread(itemLink, sourceKey)
  if not (LibPrice and type(LibPrice.ItemLinkToBidAskSpread) == "function") then
    return nil, nil
  end
  if itemLink == nil then return nil, nil end

  local spread = LibPrice.ItemLinkToBidAskSpread(itemLink, sourceKey)
  local gold = spread and spread.gold
  local ask = gold and gold.ask
  local bid = gold and gold.bid

  if not ask or not bid or not ask.value or not bid.value or bid.value <= 0 then
    return nil, nil
  end

  return ask.value / bid.value, "Bid/Ask"
end

-- Legacy direct TamrielTradeCentre lookup, shared by the LibPrice fallback
-- and the no-LibPrice path. Returns price, listings, fieldName.
function FRC.GetTTCPriceDirect(itemLink, sv)
  if TamrielTradeCentrePrice == nil or itemLink == nil then return nil, nil, nil end
  local priceTable = TamrielTradeCentrePrice:GetPriceInfo(itemLink)
  if priceTable == nil then return nil, nil, nil end
  local field = (sv and sv.price) or "Avg"
  return priceTable[field], priceTable["EntryCount"], field
end

--------------------------------------------------------------------
-- Recipe Functions
--------------------------------------------------------------------
function FRC.GetRecipeDetail(itemLinkOrItemID)

  local vItemLink, vItemId = GetItemlinkDetails(itemLinkOrItemID)
  local vItemType, vSpecialType = GetItemLinkItemType(vItemLink)
  local vItemName = GetItemLinkName(vItemLink)
  local vItemFunctionalQuality = GetItemLinkFunctionalQuality(vItemLink)

  local vFolioItemLinkId, vFolioItemLink, vFolioItemName = nil, nil, nil
  local vRecipeItemLinkId, vRecipeItemLink, vRecipeItemName = nil, nil, nil
  local vGrabBagItemLinkId, vGrabBagItemLink, vGrabBagItemName = nil, nil, nil
  local vResultLinkId, vResultLink, vResultName = nil, nil, nil
  local vLocation, vRecipePrice, vRecipeListing = nil, nil, nil
  local vRecipePriceSource, vRecipePriceField = nil, nil
  local vRecipePriceSpreadLabel = nil
  local vRecipePriceProfitable = nil

  if FRC.Data.Folios[vItemId] ~= nil then
    -- This is a folio
    vFolioItemLink, vFolioItemLinkId = GetItemlinkDetails(vItemId)
    vFolioItemName = vItemName
  elseif FRC.Data.FurnisherDocuments[vItemId] ~= nil then
    -- This is a grab bag
    vGrabBagItemLink, vGrabBagItemLinkId = GetItemlinkDetails(vItemId)
    vGrabBagItemName = vItemName
  elseif FRC.Data.Misc[vItemId] ~= nil then
    -- This is a recipe with special location
    vRecipeItemLink, vRecipeItemLinkId = GetItemlinkDetails(vItemId)
    vRecipeItemName = GetItemLinkName(vRecipeItemLink)
    vLocation = FRC.Data.Misc[vRecipeItemLinkId].location
    vResultLink, vResultLinkId = GetItemlinkDetails(GetItemLinkRecipeResultItemLink(Linkify(vRecipeItemLinkId)))
    vResultName = GetItemLinkName(vResultLink)
  elseif vSpecialType == SPECIALIZED_ITEMTYPE_RECIPE_ALCHEMY_FORMULA_FURNISHING
    or vSpecialType == SPECIALIZED_ITEMTYPE_RECIPE_BLACKSMITHING_DIAGRAM_FURNISHING
    or vSpecialType == SPECIALIZED_ITEMTYPE_RECIPE_CLOTHIER_PATTERN_FURNISHING
    or vSpecialType == SPECIALIZED_ITEMTYPE_RECIPE_ENCHANTING_SCHEMATIC_FURNISHING
    or vSpecialType == SPECIALIZED_ITEMTYPE_RECIPE_JEWELRYCRAFTING_SKETCH_FURNISHING
    or vSpecialType == SPECIALIZED_ITEMTYPE_RECIPE_PROVISIONING_DESIGN_FURNISHING
    or vSpecialType == SPECIALIZED_ITEMTYPE_RECIPE_WOODWORKING_BLUEPRINT_FURNISHING then
      --This is a furnishing recipe
      vRecipeItemLink, vRecipeItemLinkId = GetItemlinkDetails(vItemId)
      vRecipeItemName = GetItemLinkName(vRecipeItemLink)
      vResultLink, vResultLinkId = GetItemlinkDetails(GetItemLinkRecipeResultItemLink(Linkify(vRecipeItemLinkId)))
      vResultName = GetItemLinkName(vResultLink)

      --Loop through each folio looking for recipe
      for i_key,i_value in pairs(FRC.Data.Folios) do
        for j_key,j_value in pairs(FRC.Data.Folios[i_key]) do
          -- if FRC.logger ~= nil then FRC.logger:Verbose("==============================") end
          -- if FRC.logger ~= nil then FRC.logger:Verbose("Folio: "..tos(i_key).." "..Linkify(i_key)) end
          -- if FRC.logger ~= nil then FRC.logger:Verbose("Recipe ID: "..tos(FRC.Data.Folios[i_key][j_key]).." "..Linkify(FRC.Data.Folios[i_key][j_key])) end
          -- if FRC.logger ~= nil then FRC.logger:Verbose("Result Link ID: "..vResultLinkId..resultLink ) end
          -- if FRC.logger ~= nil then FRC.logger:Verbose("Search ID: "..itemLinkId.." "..itemLink) end

          if FRC.Data.Folios[i_key][j_key] == vItemId then
            --if FRC.logger ~= nil then FRC.logger:Verbose(Linkify(i).." "..Linkify(FRC.Data.Folios[i_key][j_key]).." "..Linkify(vItemId)) end
            vFolioItemLink, vFolioItemLinkId = GetItemlinkDetails(i_key)
            vFolioItemName = GetItemLinkName(vFolioItemLink)
            break
          end
        end
        if vFolioItemLinkId ~= nil then
          break
        end
      end
      if vFolioItemLinkId == nil then
        --Loop through each grabn bag looking for recipe, if not found earlier
        for i_key,i_value in pairs(FRC.Data.FurnisherDocuments) do
          for j_key,j_value in pairs(FRC.Data.FurnisherDocuments[i_key]) do
            -- if FRC.logger ~= nil then FRC.logger:Verbose("==============================") end
            -- if FRC.logger ~= nil then FRC.logger:Verbose("FurnisherDocuments: "..tos(i_key).." "..Linkify(i_key)) end
            -- if FRC.logger ~= nil then FRC.logger:Verbose("Recipe ID: "..tos(FRC.Data.FurnisherDocuments[i_key][j_key]).." "..Linkify(FRC.Data.FurnisherDocuments[i_key][j_key])) end
            -- if FRC.logger ~= nil then FRC.logger:Verbose("Result Link ID: "..vResultLinkId..resultLink ) end
            -- if FRC.logger ~= nil then FRC.logger:Verbose("Search ID: "..itemLinkId.." "..itemLink) end

            if FRC.Data.FurnisherDocuments[i_key][j_key] == vItemId then
              --if FRC.logger ~= nil then FRC.logger:Verbose(Linkify(i).." "..Linkify(FRC.Data.FurnisherDocuments[i_key][j_key]).." "..Linkify(vItemId)) end
              vGrabBagItemLink, vGrabBagItemLinkId = GetItemlinkDetails(i_key)
              vGrabBagItemName = GetItemLinkName(vGrabBagItemLink)
              break
            end
          end
          if vGrabBagItemLinkId ~= nil then
            break
          end
        end
      end
  elseif vItemType == ITEMTYPE_FURNISHING then
    --This is a furnishing item
    -- local craftingStationType, recipeListIndex,recipeIndex = GetRecipeInfoFromItemId(vItemId)
    -- local recipeListName, numRecipes, upIcon, downIcon, overIcon, _, recipeListCreateSound = GetRecipeListInfo(recipeListIndex)
    -- local known_, name_, numIngredients_, provisionerLevelReq_, qualityReq_, specialIngredientType_, requiredCraftingStationType_, resultItemId_ GetRecipeInfo(recipeListIndex,recipeIndex)
    -- local link = GetRecipeIngredientItemLink(recipeListIndex, recipeIndex, i, LINK_STYLE_BRACKETS)
    vResultLink, vResultLinkId = GetItemlinkDetails(vItemId)
    vResultName = GetItemLinkName(vResultLink)

    --Loop through each folio looking for recipe
    for i_key,i_value in pairs(FRC.Data.Folios) do
      for j_key,j_value in pairs(FRC.Data.Folios[i_key]) do
        local vSearchResultLink = GetItemLinkRecipeResultItemLink(Linkify(FRC.Data.Folios[i_key][j_key]))
        local vSearchResultLinkId = GetItemLinkItemId(vSearchResultLink)

        if vResultLinkId == vSearchResultLinkId then
          --if FRC.logger ~= nil then FRC.logger:Verbose(Linkify(i).." "..Linkify(FRC.Data.Folios[i_key][j_key]).." "..Linkify(vItemId)) end
          vFolioItemLink, vFolioItemLinkId = GetItemlinkDetails(i_key)
          vFolioItemName = GetItemLinkName(vFolioItemLink)
          vRecipeItemLink, vRecipeItemLinkId = GetItemlinkDetails(FRC.Data.Folios[i_key][j_key])
          vRecipeItemName = GetItemLinkName(vRecipeItemLink)
          break
        end
      end
      if vFolioItemLinkId ~= nil then
        break
      end
    end
    if vFolioItemLinkId == nil then
      --Loop through each grabn bag looking for recipe, if not found earlier
      for i_key,i_value in pairs(FRC.Data.FurnisherDocuments) do
        for j_key,j_value in pairs(FRC.Data.FurnisherDocuments[i_key]) do
          local vSearchResultLink, vSearchResultLinkId = GetItemlinkDetails(GetItemLinkRecipeResultItemLink(Linkify(FRC.Data.FurnisherDocuments[i_key][j_key])))

          if vResultLinkId == vSearchResultLinkId then
            --if FRC.logger ~= nil then FRC.logger:Verbose(Linkify(i).." "..Linkify(FRC.Data.FurnisherDocuments[i_key][j_key]).." "..Linkify(vItemId)) end
            vGrabBagItemLink, vGrabBagItemLinkId = GetItemlinkDetails(i_key)
            vGrabBagItemName = GetItemLinkName(vGrabBagItemLink)
            vRecipeItemLink, vRecipeItemLinkId = GetItemlinkDetails(FRC.Data.FurnisherDocuments[i_key][j_key])
            vRecipeItemName = GetItemLinkName(vRecipeItemLink)
            break
          end
        end
        if vGrabBagItemLinkId ~= nil then
          break
        end
      end
    end
    if vFolioItemLinkId == nil and vGrabBagItemLinkId == nil then
      --Loop through each misc looking for recipe, if not found earlier
      for i_key,i_value in pairs(FRC.Data.Misc) do
        local vSearchResultLink, vSearchResultLinkId = GetItemlinkDetails(GetItemLinkRecipeResultItemLink(Linkify(i_key)))

        if vResultLinkId == vSearchResultLinkId then
          --if FRC.logger ~= nil then FRC.logger:Verbose(Linkify(i).." "..Linkify(FRC.Data.Misc[i_key]).." "..Linkify(vItemId)) end
          vRecipeItemLink, vRecipeItemLinkId = GetItemlinkDetails(i_key)
          vRecipeItemName = GetItemLinkName(vRecipeItemLink)
          vLocation = FRC.Data.Misc[vRecipeItemLinkId].location
          break
        end
      end
    end
    if vFolioItemLinkId == nil and vGrabBagItemLinkId == nil and vLocation == nil then
      if LCK ~= nil then
        local souceItemId =LCK.GetSourceItemIdFromResultItem(vResultLink)
        if souceItemId ~= 0 then
          vRecipeItemLink, vRecipeItemLinkId = GetItemlinkDetails(LCK.GetSourceItemIdFromResultItem(vResultLink))
          vRecipeItemName = GetItemLinkName(vRecipeItemLink)
        end
      end
    end
  end

  -- vRecipePrice:      gold amount (number|nil)
  -- vRecipeListing:    Bid/Ask spread ratio from LibPrice.ItemLinkToBidAskSpread
  --                     (number|nil) — colored green/red in the tooltip
  -- vRecipePriceSource: human label for the price source line
  -- vRecipePriceField:  price field used (Avg/Min/Max/avgPrice/...)
  -- vRecipePriceSpreadLabel: "<Source> Bid/Ask" label for the spread line
  -- vRecipePriceProfitable: true only for MM when craftCost < avgPrice
  --                     (price value colored green in the tooltip)
  vRecipePrice, vRecipeListing, vRecipePriceSource, vRecipePriceField,
  vRecipePriceSpreadLabel, vRecipePriceProfitable =
      FRC.GetRecipePrice(vRecipeItemLink)
  
   return vItemId, vItemName, vItemFunctionalQuality, vItemType, vSpecialType,
         vFolioItemLinkId, vFolioItemLink, vFolioItemName,
         vRecipeItemLinkId, vRecipeItemLink, vRecipeItemName,
         vGrabBagItemLinkId, vGrabBagItemLink, vGrabBagItemName,
         vLocation, vResultLinkId, vResultLink, vResultName,
         vRecipePrice, vRecipeListing, vRecipePriceSource, vRecipePriceField,
         vRecipePriceSpreadLabel, vRecipePriceProfitable
end

function FRC.GetWritVendorContainerStats(vendorContainerLinkId)
  local vVendorCharacterString = ""
  local vVendorRecipeCount = nil
  local container = FRC.Data.Folios[vendorContainerLinkId] or FRC.Data.FurnisherDocuments[vendorContainerLinkId]

  if container == nil then
    return
  end
  vVendorRecipeCount = table.getn(container)

  if LCK ~= nil then
    if container ~= nil then
      local tChars = {}
      local charactercolor = ""

      for j,recipeId in ipairs(container) do
        local knowl = LCK.GetItemKnowledgeList(recipeId, nil,nil)

        for i, knowledge in ipairs(knowl) do
          if knowledge["knowledge"] == LCK.KNOWLEDGE_KNOWN then
            if tChars[knowledge["id"]] == nil then
              tChars[knowledge["id"]] = 1
            else
              tChars[knowledge["id"]] = tChars[knowledge["id"]] + 1
            end
          elseif knowledge["knowledge"] == LCK.KNOWLEDGE_UNKNOWN then
            if tChars[knowledge["id"]] == nil then
              tChars[knowledge["id"]] = 0
            end
          end
        end
      end

      local chrList=LCK.GetCharacterList( nil )

      for i, chr in ipairs(chrList) do
        if tChars[chr["id"]] ~= nil then

          if tChars[chr["id"]] == 0 then
            charactercolor = FRC.savedVariables.colorAllUnknown
          elseif tChars[chr["id"]] == table.getn(container) then
            charactercolor = FRC.savedVariables.colorAllKnown
          else
            charactercolor = FRC.savedVariables.colorAllPartial
          end
          if vVendorCharacterString ~= "" then
            vVendorCharacterString = vVendorCharacterString..", "
          end
          vVendorCharacterString = vVendorCharacterString..string.format("|c%06X%s|r", charactercolor, chr["name"].." ("..tChars[chr["id"]].."/"..table.getn(container)..")")
        end
      end
    end
  end
  return vVendorCharacterString, vVendorRecipeCount
end

function FRC.GetRecipeKnowledge(vRecipeItemLinkOrItemId)
  local vCharacterStringLong = ""
  local vCharacterStringShort = ""
  local vCharTrackedCount = 0
  local vCharKnownCount = 0

  local _, vRecipeItemId = GetItemlinkDetails(vRecipeItemLinkOrItemId)

  if LCK ~= nil then
    local tChars= LCK.GetItemKnowledgeList(vRecipeItemId,nil,nil)
    local charColor = nil

    for i, chr in ipairs(tChars) do
      if chr["knowledge"] == LCK.KNOWLEDGE_KNOWN then
        vCharTrackedCount = vCharTrackedCount + 1
        vCharKnownCount = vCharKnownCount + 1
        charColor = FRC.savedVariables.colorCharKnown
      elseif chr["knowledge"] == LCK.KNOWLEDGE_UNKNOWN then
        vCharTrackedCount = vCharTrackedCount + 1
        charColor = FRC.savedVariables.colorCharUnknown
      end

      if chr["knowledge"] == LCK.KNOWLEDGE_KNOWN or chr["knowledge"] == LCK.KNOWLEDGE_UNKNOWN then
        if vCharacterStringLong ~= "" then
          vCharacterStringLong = vCharacterStringLong..", "
        end
        vCharacterStringLong = vCharacterStringLong..string.format("|c%06X%s|r", charColor, chr["name"])
      end
    end
    if vCharKnownCount == 0 then
      vCharacterStringShort = string.format("|c%06X%s|r", FRC.savedVariables.colorAllUnknown, tos(vCharKnownCount).."/"..tos(vCharTrackedCount))
    elseif vCharKnownCount == vCharTrackedCount then
      vCharacterStringShort = string.format("|c%06X%s|r", FRC.savedVariables.colorAllKnown, tos(vCharKnownCount).."/"..tos(vCharTrackedCount))
    else
      vCharacterStringShort = string.format("|c%06X%s|r", FRC.savedVariables.colorAllPartial, tos(vCharKnownCount).."/"..tos(vCharTrackedCount))
    end
  end
  return vCharacterStringLong, vCharacterStringShort, vCharTrackedCount, vCharKnownCount
end