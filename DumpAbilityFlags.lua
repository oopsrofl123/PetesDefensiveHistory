function pdhDump()
local output = "spell_id,spell_name,important,big_defensive,external\n"
for i = 0, 1000000 do
   local a = ""
   local matched = false
   local helpful = C_Spell.IsSpellHelpful(i)
   if C_Spell.IsSpellImportant(i) then 
   matched = true
   a = a .. "1," 
   else 
   a = a .. "0," 
   end
   if C_UnitAuras.AuraIsBigDefensive(i) then 
   matched = true
   a = a .. "1," 
   else 
   a = a .. "0,"  
   end
   if C_Spell.IsExternalDefensive(i) then 
   matched = true
   a = a .. "1," 
   else 
   a = a .. "0,"  
   end
   if helpful and matched then
      local info = C_Spell.GetSpellInfo(i)
      local name = info and info.name
      output = output .. i .. ",\"" .. name .. "\"," .. a .. "\n"
   end
end

local f = CreateFrame("Frame", "CopyFrame", UIParent, "BackdropTemplate")
f:SetSize(600, 400)
f:SetPoint("CENTER")
f:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
f:SetBackdropColor(0, 0, 0, 0.9)

local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 8, -8)
scroll:SetPoint("BOTTOMRIGHT", -30, 8)

local edit = CreateFrame("EditBox", nil, scroll)
edit:SetMultiLine(true)
edit:SetFontObject(ChatFontNormal)
edit:SetWidth(540)
edit:SetAutoFocus(false)
edit:EnableMouse(true)

scroll:SetScrollChild(edit)

edit:SetText(output)
edit:HighlightText()
end
