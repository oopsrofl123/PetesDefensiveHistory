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
                                -- We HAVE to record maxRanks because the talent string uses it
                                -- for compression. If the player has the maximum rank purchased,
                                -- then the 6 bit wide integer encoding the number of ranks is skipped
                                -- and field1=true implies maxRank
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



-- Build a table mapping spell ID -> ranks purchased. Although the function
-- is called get _Talent_ ranks, the keys of the returned table are indeed
-- spell IDs.
-- If a talent is unknown (i.e. rank=0), it is *NOT IN* the returned dict.
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

    -- The talent tree must be traversed in a specific order matching the bits coming off
    -- of the encoded string. Bits are only allocated in the stream if previous conditions
    -- are satisfied. The field layout (1 char per bit) is:
    --            123444444566
    -- Indentation below means that the bit only exists if the parent bit was true.
    -- Field 1: is the talent selected?
    --     Field 2: is the talent purchased at all?
    --         Field 3: if the talent is purchased, is it at max rank?
    --             Field 4: if the talent is not max rank, what rank is it?
    --         Field 5: is the talent a choice node?
    --             Field 6: if the talent is a choice node, which was selected?

    -- Handy decoder for single bit booleans
    local function readbool(stream) return stream:ExtractValue(1) == 1 end

    local talentRanks = {}
    for _, talentId in ipairs(C_Traits.GetTreeNodes(C_ClassTalents.GetTraitTreeForSpec(specId))) do
        local rank = 0
        local choiceIndex = 1    -- choice is index=1 unless there is a choice node
        local notMaxRank         -- seems this will never be unset if the talent exists

        -- Read 1 bit from field 1
        if readbool(stream) then
            -- Read 1 bit from field 2
            if readbool(stream) then
                -- Read 1 bit from field 3
                notMaxRank = readbool(stream)  -- have to save this flag for later
                if notMaxRank then
                    -- Read 6 bits from field 4
                    rank = stream:ExtractValue(6)
                else
                    rank = 1
                end

                -- Read 1 bit from field 5
                if readbool(stream) then
                    choiceIndex = stream:ExtractValue(2) + 1
                end
            end
        end

        local spell = talentIdToSpellMap[talentId .. "_" .. choiceIndex]
        if spell then
            talentRanks[spell.spellId] = notMaxRank and rank or spell.maxRank
        end
    end
    return talentRanks
end
