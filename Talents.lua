local _, ns = ...


-- based on example code here:
-- https://warcraft.wiki.gg/wiki/API_C_ClassTalents.InitializeViewLoadout
local function buildTalentToSpellMap(specId)
    local talentmap = {}
    local configId = Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID  -- convenience

    -- Have to go through Blizzard's talent view
    C_ClassTalents.InitializeViewLoadout(specId, 100)
    C_ClassTalents.ViewLoadout({})
    local configInfo = C_Traits.GetConfigInfo(configId)
    if configInfo == nil then
        ns:printDebug(string.format(
            "FAILED TO RETRIEVE TALENT TREE: C_Traits.GetConfigInfo(configId=[%d]), specId=[%d]",
            configId, specId))
        return
    end

    -- Traverse the tree
    for _, treeId in ipairs(configInfo.treeIDs) do
        for _, nodeId in ipairs(C_Traits.GetTreeNodes(treeId)) do
            local node = C_Traits.GetNodeInfo(configId, nodeId)
            if node and node.ID ~= 0 then    -- node.ID=0 if it isn't visible
                for choiceIndex, talentId in pairs(node.entryIDs) do
                    local entryInfo = C_Traits.GetEntryInfo(configId, talentId)
                    if entryInfo and entryInfo.definitionID then
                        local definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                        if definitionInfo.spellID then
                            -- Each node contains a list of talents to handle choice nodes.
                            -- The list index is encoded as an integer in the export stream,
                            -- so have to match it. To flatten the returned structure, name all
                            -- talents by {talentId}_{choiceIndex}.
                            talentmap[node.ID .. "_" .. choiceIndex] = {
                                -- We HAVE to record maxRanks because the talent string uses it for
                                -- compression. If the player has the maximum rank purchased, then
                                -- the 6 bit integer encoding the number of ranks is skipped.
                                spellId=definitionInfo.spellID,
                                maxRank=node.maxRanks
                            }
                        end
                    end
                end
            end
        end
    end
    return talentmap 
end



-- The talent string header is laid out as:
--         1111 1111    2222 2222 2222 2222    3333...3333
--         version      specId                 treeHash (128 bits)
local function readMetadata(stream)
    local version = stream:ExtractValue(8)
    local specID = stream:ExtractValue(16)
    local _ = stream:ExtractValue(128)  -- The treeHash is a 128bits. Fire them straight into /dev/null.

    -- 2 is the serialization version for Midnight. No need for backward compatibility
    if  C_Traits.GetLoadoutSerializationVersion() ~= 2 or version ~= 2 then
        ns:printDebug("unsupported talent encoding version (must be 2)")
        return nil
    end
    return specID
end



-- Each talent selection is encoded in at most 6 fields, but a full decoding
-- requires the talent database's "maxRank" field. This function just decodes
-- the 6 fields.
--
-- Fields are only allocated if certain previous conditions are satisfied.
-- The field layout (each number representing one bit) is:
--
--     123444444566
--
-- Indentation below means that the bit only exists if the parent bit was true.
-- Field 1: is the talent learned?
--     Field 2: is the talent purchased?
--         Field 3: if the talent is purchased, is it at max rank?
--             Field 4: if the talent is not max rank, what rank is it?
--         Field 5: is the talent a choice node?
--             Field 6: if the talent is a choice node, which was selected?
--
-- Field 1 and 2 are interesting: field 1 is true for talents that are known
-- but did not cost any talent points. There are usually 2-3 of these in the
-- class tree. Surprisingly, field 1 is true for the root ability of ALL hero
-- talent trees, meaning the inactive hero tree cannot be identified by this
-- talent alone. If fields 1 and 2 are both true, the talent is known and
-- cost talent points. It is never the case that field 1 is false and field 2
-- is true.
--
-- The only important return values are:
--     - choiceIndex: is 1 unless encoded otherwise.
--     - rank: nil if the talent is known at maximum rank, otherwise integer
--             representing known rank.
-- Values are returned as nils rather than false to emphasize that they were
-- not present in the bit stream, which is slightly different from their meaning.
local function decodeTalent(stream)
    -- Decode a single bit as a boolean
    local function readbool(stream) return stream:ExtractValue(1) == 1 end

    local selected = nil
    local purchased = nil
    local rank = nil
    local choiceNode = false
    local choiceIndex = 1     -- choice index is 1-based
    local notMaxRank = true

    selected = readbool(stream)                           -- field 1
    if selected then
        purchased = readbool(stream)                      -- field 2
        if purchased then
            notMaxRank = readbool(stream)                 -- field 3
            if notMaxRank then
                rank = stream:ExtractValue(6)             -- field 4
            end
            choiceNode = readbool(stream)                 -- field 5
            if choiceNode then
                choiceIndex = stream:ExtractValue(2) + 1  -- field 6 (+1 = index is 1-based)
            end
        end
    end
    return selected, purchased, notMaxRank, rank, choiceNode, choiceIndex
end



-- Build a table mapping spell ID -> ranks purchased. Although the function
-- is called get _Talent_ ranks, the keys of the returned table are indeed
-- spell IDs.
function ns:getTalentRanks(specId, talentExportString)
    -- there's no point in decoding the string if we can't map the talents to spells
    local talentIdToSpellMap = buildTalentToSpellMap(specId)
    if not talentIdToSpellMap then
        ns:printDebug(string.format(
            "talent to spell ID map failed for specId=[%s]. giving up on talent inspection",
            specId)
        )
        return nil
    end

    -- read the stream's metadata
    local stream = CreateAndInitFromMixin(ImportDataStreamMixin, talentExportString)
    local encodedSpecId = readMetadata(stream)
    if encodedSpecId ~= specId then
        ns:printDebug("talent string encoded specialization ID " ..
            tostring(encodedSpecId) ..
            " but expected ID=" .. specId)
        return nil
    end

    -- The talent tree must be traversed in a specific order to matching the bits
    -- coming off of the encoded string.
    local talentRanks = {}
    local forDebugging = {}
    -- Fun fact: this tree is not completely spec-specific even though these function
    -- names seem to imply it. The tree traversed in buildTalentToSpellMap IS spec
    -- specific. This is why there are many talentIds in this tree that are missing
    -- from the talentIdToSpellMap. E.g., when decoding a prot paladin talent string
    -- we find (talent=102502, spell=461287), a holy spec talent and the ret talent
    -- (talent=110419,spell=1261113).
    for _, talentId in ipairs(C_Traits.GetTreeNodes(C_ClassTalents.GetTraitTreeForSpec(specId))) do
        local selected, purchased, _, rank, _, choiceIndex = decodeTalent(stream)
        local spell = talentIdToSpellMap[talentId .. "_" .. choiceIndex]
        local debugRecord = { spell ~= nil, spell and spell.spellId or 0,
            talentId, selected, purchased, rank, choiceIndex }
        table.insert(forDebugging, debugRecord)
        if spell then
            talentRanks[spell.spellId] = not selected and 0 or rank or spell.maxRank
        end
    end

    -- all debugging below
    --table.sort(forDebugging, function(a, b) return a[3] <= b[3] end)
    ns:printDebug(string.format("%5s %10s %10s %5s %5s %3s %3s",
        "found", "spellId", "talentId", "sel", "pur", "rank", "choice"))
    for _, v in pairs(forDebugging) do
        ns:printDebug(string.format("%5s %10d %10d %5s %5s %3s %3s",
            tostring(v[1]), v[2], tostring(v[3]), tostring(v[4]),
            tostring(v[5]), tostring(v[6]), tostring(v[7])))
    end
    return talentRanks
end
