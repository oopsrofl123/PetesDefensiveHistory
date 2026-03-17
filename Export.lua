local addonName, ns = ...

local exportFrame --= allocExportFrame()

function PetesDefensiveHistory_OnAddonCompartmentClick(addonName, buttonName)
    local data = ns:exportPlayback()
print("exporting event playback data")
    ns:addToExportData(data)
    exportFrame:Show()
end


-- XXX: TODO: terrible idea for the long term. just for early devel
function ns:addToExportData(x)
    if exportFrame.data then
        exportFrame.data = exportFrame.data .. '\n' .. x
    else
        exportFrame.data = x
    end
    ns:updateExportString()
end

function ns:updateExportString()
    local compressedString = C_EncodingUtil.CompressString(exportFrame.data or '')
    local finalString = C_EncodingUtil.EncodeBase64(compressedString)
    exportFrame.edit:SetText(not exportFrame.data and '' or finalString)
    exportFrame.edit:HighlightText()
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

    f:Show()

    return f
end

do
    exportFrame = allocExportFrame()
    ns:updateExportString()
end
