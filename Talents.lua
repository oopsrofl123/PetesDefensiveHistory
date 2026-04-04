local _, ns = ...


-- 4 possible mods:
--     1. boolean setter. if the amount is a boolean, then the value is simply set
--     2. non-boolean setter.
--     3. numeric change
--         3a. additive change
--         3b. multiplicative change. mult changes apply to the
--             base value. reduce mults to adds this way.
local function applyOneModifier(modifiedAbility, mod)
    ns:printDebug(ns.LOGTYPE.Talents, ns.LOGLEVEL.Verbose,
        string.format('got modifier [%d] = (%d, %s, %s, %s)',
        modifiedAbility.id, mod.id, mod.modifies,
        tostring(mod.amount), tostring(mod['mult'] or false)))

    if type(mod.amount) == "boolean" or
       mod.modifies == "duration_variable" or
       mod.modifies == "appliesOtherAura" or
       mod.modifies == "targets" then
        modifiedAbility[mod.modifies] = mod.amount
    else -- numeric case
        local change = mod.amount
        -- Reduce the multiplicative case to the additive case
        if mod['mult'] then
            change = modifiedAbility[mod.modifies] * mod.amount/100
        end
        modifiedAbility[mod.modifies] = modifiedAbility[mod.modifies] + change
    end
end



-- Returns a modified copy of baseAbility. Do not modify the values in the
-- static database of abilities.
--
-- Numeric modifiers must be applied in a specific order. First, additive
-- modifiers followed by multiplicative. To handle this, every modifier
-- for an ability must be collected before applying any changes.
function ns:applyTalentModifiers(classFile, specId, baseAbility, talentRanks)
    local modifiedAbility = ns:shallowcopy(baseAbility)
    local allMods = {}
    local classmods = ns.ClassTalentModifiers[classFile]
    local specmods = ns.SpecTalentModifiers[specId]

    -- Collect all modifiers across all talents for this ability
    ns:printDebug(ns.LOGTYPE.Talents, ns.LOGLEVEL.Verbose,
        "looking for modifiers for baseAbility=["..baseAbility.name.."]")
    for spellId, rank in pairs(talentRanks) do
        -- TalentModifiers only contains the talents relevant to our tracked abilities.
        if rank > 0 then
            -- Spell IDs are unique, so they can only be in one of the two tables
            talents = classmods[spellId] or specmods[spellId]
            if talents then
                mods = talents[rank]
                if not mods then
                    ns:printDebug(ns.LOGTYPE.Talents, ns.LOGLEVEL.Normal,
                        string.format('applyTalentModifiers: talent=[%d]: rank=[%d] does not exist',
                        spellId, rank))
                    return nil
                end
    
                -- Talents can modify multiple spells with multiple modifiers. Get
                -- just the mods that apply to this ability.
                for index, mod in pairs(mods) do
                    if baseAbility.id == mod.id then
                        table.insert(allMods, mod)
                    end
                end
            end
        end
    end

    -- To achieve the sorting below, give an integer value to each talent and
    -- then use a standard < comparator.
    local function toOrd(mod)
        local first = mod.mult and 1 or 0
        local second = mod.modifies == "hasAbility" and mod.amount == false and 100 or 0
        local third = mod.modifies == "cdr" and mod.amount == false and 100 or 0
        local fourth = mod.modifies == 'appliesOtherAura' and 1000 or 0
        return first + second + third + fourth
    end
    -- Sort additive effects before multiplicative effects and put talents
    -- that *remove* abilities at the end of the sort. This is a very brittle
    -- way to implement talents that replace other abilities and will probably
    -- break at some point.
    table.sort(allMods, function(a, b) return toOrd(a) < toOrd(b) end)
    for _, mod in pairs(allMods) do
        applyOneModifier(modifiedAbility, mod)
    end

    return modifiedAbility
end



-- based on example code here:
-- https://warcraft.wiki.gg/wiki/API_C_ClassTalents.InitializeViewLoadout
--
-- XXX: TODO: traversing this tree allocates about ~1Mb of temporary tables.
-- WoW is not particularly aggressive about garbage collection, so it may be
-- desirable to force a GC during some addon enable/disable events.
local function buildTalentToSpellMap(specId)
    local talentmap = {}
    local configId = Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID  -- convenience

    -- Have to go through Blizzard's talent view
    C_ClassTalents.InitializeViewLoadout(specId, 100)
    C_ClassTalents.ViewLoadout({})
    local configInfo = C_Traits.GetConfigInfo(configId)
    if configInfo == nil then
        ns:printDebug(string.format(ns.LOGTYPE.Talents, ns.LOGLEVEL.Error,
            "FAILED TO RETRIEVE TALENT TREE: C_Traits.GetConfigInfo(configId=[%d]), specId=[%d]",
            configId, specId))
        return
    end

    -- Traverse the tree
    for _, treeId in ipairs(configInfo.treeIDs) do
        for _, nodeId in ipairs(C_Traits.GetTreeNodes(treeId)) do
            local node = C_Traits.GetNodeInfo(configId, nodeId)
            if node and node.ID ~= 0 then    -- node.ID=0 if it isn't visible
                for choiceIndex, talentId in ipairs(node.entryIDs) do
                    local entryInfo = C_Traits.GetEntryInfo(configId, talentId)

                    -- SubTreeSelection is a special node that defines which hero talent
                    -- tree is selected. It has no associated spell and thus no spell ID, so
                    -- it needs to be added to the talent map here.
                    if node.type == Enum.TraitNodeType.SubTreeSelection then
                        talentmap[node.ID .. "_" .. choiceIndex] = {
                            spellId=-1, maxRank=-1, type=node.type, subTreeID=entryInfo.subTreeID
                        }
                    end

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
                                maxRank=node.maxRanks,
                                type=node.type,
                                subTreeID=node.subTreeID
                            }
                        end
                    end
                end
            end
        end
    end

--collectgarbage('collect')

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
        ns:printDebug(ns.LOGTYPE.Talents, ns.LOGLEVEL.Error,
            "unsupported talent encoding version (must be 2)")
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
        ns:printDebug(string.format(ns.LOGTYPE.Talents, ns.LOGLEVEL.Error,
            "talent to spell ID map failed for specId=[%s]. giving up on talent inspection",
            specId)
        )
        return nil
    end

    -- read the stream's metadata
    local stream = CreateAndInitFromMixin(ImportDataStreamMixin, talentExportString)
    local encodedSpecId = readMetadata(stream)
    if encodedSpecId ~= specId then
        ns:printDebug(ns.LOGTYPE.Talents, ns.LOGLEVEL.Error,
            "talent string encoded specialization ID " .. tostring(encodedSpecId) ..
            " but expected ID=" .. specId)
        return nil
    end

    -- The talent tree must be traversed in a specific order to matching the bits
    -- coming off of the encoded string.
    local fullRecords = {}
    local heroChoice
    -- Fun fact: this tree is not completely spec-specific even though these function
    -- names seem to imply it. The tree traversed in buildTalentToSpellMap IS spec
    -- specific. This is why there are many talentIds in this tree that are missing
    -- from the talentIdToSpellMap. E.g., when decoding a prot paladin talent string
    -- we find (talent=102502, spell=461287), a holy spec talent and the ret talent
    -- (talent=110419,spell=1261113).
    for _, talentId in ipairs(C_Traits.GetTreeNodes(C_ClassTalents.GetTraitTreeForSpec(specId))) do
        local selected, purchased, _, rank, _, choiceIndex = decodeTalent(stream)
        local spell = talentIdToSpellMap[talentId .. "_" .. choiceIndex]
        local record = {
            found=spell ~= nil,   -- in the database?
            spellId=spell and spell.spellId or -1,  -- set spell ID=-1 if not in db
            talentId=talentId,
            selected=selected,
            purchased=purchased,
            rank=rank,
            maxRank=spell and spell.maxRank or nil,
            choiceIndex=choiceIndex,
            subTreeId=spell and spell.subTreeID or nil,
            type=spell and spell.type or nil }
        table.insert(fullRecords, record)
        if record.type == Enum.TraitNodeType.SubTreeSelection then
            heroChoice = spell.subTreeID
        end
    end

    -- Only print this if the user opted in to *really* spammy debug logs
    -- Print the full records for debugging
    table.sort(fullRecords, function(a, b) return a.spellId < b.spellId end)
    ns:printDebug(ns.LOGTYPE.Talents, ns.LOGLEVEL.Verbose,
        string.format("%5s %10s %10s %5s %5s %3s %3s %5s %5s",
            "found", "spellId", "talentId", "sel", "pur", "rank", "choice", 'subtree', 'type'))
    for _, v in pairs(fullRecords) do
        ns:printDebug(ns.LOGTYPE.Talents, ns.LOGLEVEL.Verbose,
            string.format("%5s %10d %10d %5s %5s %3s %3s %5s %5s",
                tostring(v.found), v.spellId, tostring(v.talentId),
                tostring(v.selected), tostring(v.purchased), tostring(v.rank),
                tostring(v.choiceIndex), tostring(v.subTreeId), tostring(v.type)))
    end

    -- Hero talents: talents selected in the inactive hero talent tree are still marked
    -- as selected. The active hero talent tree is indicated by a special hidden choice node
    -- with type=Enum.TraitNodeType.SubTreeSelection and subTreeId equal to the selected
    -- hero tree.
    -- To build the final set of talents, keep things with no subtree (class/spec talents)
    -- or the hero subtree corresponding to the selected tree
    local talentRanks = {}
    for _, record in pairs(fullRecords) do
        if record.subTreeId == nil or record.subTreeId == heroChoice then
            talentRanks[record.spellId] = not record.selected and 0 or record.rank or record.maxRank
        end
    end
    return talentRanks
end
