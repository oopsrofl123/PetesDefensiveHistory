local addonName, ns = ...

local exportFrame


local function prepareExportData()
    ns:printDebug(ns.LOGTYPE.Export, ns.LOGLEVEL.Normal, "Getting metadata")
    local metadataUpdates = ns:getMetadataUpdatesData()

    ns:printDebug(ns.LOGTYPE.Export, ns.LOGLEVEL.Normal, "Getting character data")
    local characterUpdates = ns:getCharacterUpdatesData()
    ns:printDebug(ns.LOGTYPE.Export, ns.LOGLEVEL.Normal, "Found "..#characterUpdates.." character updates")

    ns:printDebug(ns.LOGTYPE.Export, ns.LOGLEVEL.Normal, "Getting event playback data")
    local playback = ns:getPlaybackData()
    ns:printDebug(ns.LOGTYPE.Export, ns.LOGLEVEL.Normal, "Found "..#playback.." playback events")

    ns:printDebug(ns.LOGTYPE.Export, ns.LOGLEVEL.Normal, "Getting inference record data")
    local inference = {}
    for _, record in pairs(ns:getInferenceRecordData()) do
        table.insert(inference, record:strip())
    end
    ns:printDebug(ns.LOGTYPE.Export, ns.LOGLEVEL.Normal, "Found "..#inference.." inference records")

    local data = {
        addonVersion=ns.ADDON_VERSION,
        metadataUpdates=metadataUpdates,
        characterUpdates=characterUpdates,
        playback=playback,
        inference=inference
    }
    ns:setExportData(data)
    exportFrame:Show()
end


function ns:setExportData(data)
    exportFrame.data = data
    ns:updateExportString()
end


-- Whatever data is stored in the exportFrame: serialize, compress and encode it
function ns:updateExportString()
    local serializedData = C_EncodingUtil.SerializeCBOR(exportFrame.data)
    ns:printDebug(ns.LOGTYPE.Export, ns.LOGLEVEL.Normal, string.format(
        "Serialized: %0.1f kB", string.len(serializedData)/1000))
    local compressedString = C_EncodingUtil.CompressString(serializedData)
    ns:printDebug(ns.LOGTYPE.Export, ns.LOGLEVEL.Normal, string.format(
        "Compressed: %0.1f kB", string.len(compressedString)/1000))
    local finalString = C_EncodingUtil.EncodeBase64(compressedString)
    ns:printDebug(ns.LOGTYPE.Export, ns.LOGLEVEL.Normal, string.format(
        "Encoded: %0.1f kB", string.len(finalString)/1000))
    exportFrame.edit:SetText(finalString)
    exportFrame.edit:HighlightText()
end


function PetesDefensiveHistory_OnAddonCompartmentClick(addonName, buttonName)
    prepareExportData()
end


local function allocExportFrame()
    -- Create a simple frame with an editbox
    local f = CreateFrame("Frame", addonName .. "ExportFrame", UIParent, "BackdropTemplate")

    -- XXX: TODO: terrible idea for the long term. just for early devel
    f.data = nil

    f:SetPoint("CENTER")
    f:SetSize(600, 600)
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0, 0, 0, 0.9)

    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 8, -8)
    f.scroll:SetPoint("BOTTOMRIGHT", -30, 8)

    f.edit = CreateFrame("EditBox", nil, f.scroll)
    f.edit:SetMultiLine(true)
    f.edit:SetFontObject(ChatFontNormal)
    f.edit:SetWidth(540)
    f.edit:SetAutoFocus(true)
    f.edit:EnableMouse(true)

    f.scroll:SetScrollChild(f.edit)

    f.edit:SetScript("OnEscapePressed", function() f:Hide() end)

    -- Don't show until the user clicks the compartment button
    f:Hide()

    return f
end

do
    exportFrame = allocExportFrame()
    ns:updateExportString()
end
