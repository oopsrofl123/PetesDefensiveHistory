local addonName, ns = ...

local ldb = LibStub('LibDataBroker-1.1')

ns.ldbObject = ldb:NewDataObject(addonName, {
    type="launcher",
    text=addonName,
    icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
    OnClick=function(self, mouseButton)
        if mouseButton == "LeftButton" then
            if IsShiftKeyDown() then
                -- Export replay
                ns:prepareExportData()
            else
                -- Open addon settings
                Settings.OpenToCategory(ns.optionsCategory:GetID())
            end
        elseif mouseButton == "RightButton" then
            -- Show the zero knowledge solution UI
            ns.groupSolutionUI:Show()
        end
    end,
    OnTooltipShow=function(tooltip)
        if not tooltip or not tooltip.AddLine then return end
        tooltip:AddLine("|cFFFFFFFF" .. addonName .. "|r v" ..
            C_AddOns.GetAddOnMetadata(addonName, 'Version')) -- 1, 1, 1)
        tooltip:AddLine(" ")
        tooltip:AddLine("Inference attempts this session: |cFFFFFFFF" .. ns.numInferenceAttempts)
        tooltip:AddLine(" ")
        local replays = ns:GetOption('enableReplays')
        tooltip:AddLine(string.format("Logic tracing and replays: %s|r",
            replays and "|cFF00FF00enabled" or "|cFFFF0000disabled"))
        if replays then
            tooltip:AddLine("    Inference records: |cFFFFFFFF" .. #ns:getInferenceRecordData())
            tooltip:AddLine("    Replay events: |cFFFFFFFF" .. #ns:getPlaybackData())
        end
        tooltip:AddLine(" ")
        UpdateAddOnCPUUsage()
        UpdateAddOnMemoryUsage()
        tooltip:AddLine(string.format("CPU: %0.1f CPU seconds, Memory: %0.1f MB",
            GetAddOnCPUUsage('PetesDefensiveHistory') / 1000,
            GetAddOnMemoryUsage('PetesDefensiveHistory') / 1000))
        tooltip:AddLine(" ")
        tooltip:AddLine("Left Click: |cFFFFFFFFOpen AddOn options")
        tooltip:AddLine("Right Click: |cFFFFFFFFShow group solutions")
        tooltip:AddLine("Shift + Left Click: |cFFFFFFFFExport replay")
    end,
})
