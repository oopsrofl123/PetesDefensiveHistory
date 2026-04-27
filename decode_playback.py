#!/usr/bin/env python

import sys
import math
import time
import base64
import zlib
import cbor2
import numpy as np
import gzip
from collections import defaultdict


ascii_cyan = "\033[36m"
ascii_purple = "\033[35m"
ascii_yellow = "\033[33m"
ascii_green = "\033[32m"
ascii_red = "\033[31m"
ascii_reset = "\033[0m"

def d(x):
    return x.decode() if type(x) is bytes else x


# Handle the few different formats of combat log events we care about. Also apply
# a time warp if desired.
#
# Return tuple format:
#   (time, event name, caster (GUID), target (GUID), ability ID)
def normalize_combatlog_event(e, warp=0):
    return (e[0] - warp, e[1], e[2],
        e[2] if e[1] == "SPELL_CAST_SUCCESS" else e[6], int(e[10]))


def read_spell_names(filename):
    spells = {}
    openf = gzip.open if filename.endswith('.gz') else open

    with openf(filename, 'rt') as f:
        for line in f:
            if not line.startswith('ID'):
                s = line.split(',')
                spells[int(s[0])] = ','.join(s[1:]).strip().strip('"')
    return spells


def event_type_match(combatlog, playback):
    if playback == "AURA(add)":
        return combatlog == "SPELL_AURA_APPLIED" or combatlog == "SPELL_AURA_APPLIED_DOSE"
    elif playback == "AURA(update)":
        return combatlog == "SPELL_AURA_REFRESH" or combatlog == "SPELL_AURA_REMOVED_DOSE"
    elif playback == "FLAGS(combatDrop)":
        return combatlog == "SPELL_CAST_SUCCESS"
    elif playback == "FLAGS(feign)":
        return combatlog == "SPELL_CAST_SUCCESS"
    elif playback == "UNIT_SPELLCAST_SUCCEEDED":
        return combatlog == "SPELL_CAST_SUCCESS"
    else:
        return False


def passcolor(passes):
    return ascii_green if passes else ascii_red


def certainmark(certain):
    return "" if certain else "*"


def decode_export_blob(compressed):
    decoded = base64.b64decode(compressed)
    decompressed = zlib.decompress(decoded, wbits=-15)
    return cbor2.loads(decompressed)


def one_logic_string(ability, source, caster, layers):
    string = "[" + str(ability) + ":"
    for name, summary in layers.items():
        passes, certain = summary
        # XXX: disable until fix guid/slot maps
        string += "%s%s%s%s" % (passcolor(passes), name.decode(), "" if True or source == caster else "_" + caster, certainmark(certain))
    string += ascii_reset + "]"
    return string


def logic_string(logic, source, pass_type, character_abilities):
    string = ""
    for logic_summary in logic:
        caster, ability_id, passes, layers = logic_summary
        if passes == pass_type:
            ability = character_abilities[caster.decode()][ability_id]
            string += one_logic_string(ability['alias'] if 'alias' in ability else ability['name'], source, d(caster), layers)
    return string


def confidence_string(conf):
    ability_id, certain, num_possible_solns, layers = conf
    string = "#S=%d match=[%s], layers=[" % \
        (num_possible_solns, "nil" if ability_id is None else ability_id)
    for name, summary in layers.items():
        string += passcolor(summary[0]) + name.decode() + certainmark(summary[1]) + ascii_reset
    string += "]"
    return string


def reqs_met(reqs):
    met = True
    for name, req in (reqs.items() if len(reqs) > 0 else {}):
        passes, final, value = req
        met = met and passes
    return met


def reqs_string(reqs):
    string = "reqs: "
    for name, req in (reqs.items() if len(reqs) > 0 else {}):
        passes, final, value = req
        string += "[" + passcolor(passes) + name.decode() + "=" + ("%0.3f" % value) + ascii_reset + "]"
    return string


def decision_string(inf, spell_names):
    inference_time, inference_trace, inference_attempt, \
        event_time, event_trace, event_id, event_source, event_slot, batch_id, \
        ability_id, certain, ability_caster, \
        logic, conf, reqs = inf
    meets_reqs = reqs_met(reqs)
    if ability_id is None or not meets_reqs:
        return "couldn't infer ability: " + ("no ability" if ability_id is None else "reqs not met")
    else:
        return "%s%0.3f %s: ability=[%s], event=[%s/%d], attempt=[%d], caster=[%s], time=[%0.3f]%s" % \
            (ascii_cyan, inference_time, "FINALIZED" if certain else "UNCERTAIN",
            spell_names[ability_id], event_id, batch_id, inference_attempt, ability_caster, event_time, ascii_reset)


def infer_string(inf):
    inference_time, inference_trace, inference_attempt, \
        event_time, event_trace, event_id, event_source, event_slot, batch_id, \
        ability_id, certain, ability_caster, \
        logic, conf, reqs = inf
    return "%s%0.3f Infer(tr(infer)=[%s], tr(event)=[%s], source=[%s], eventId=[%s/%d], attempt=[%d]%s" % \
        (ascii_yellow, inference_time, inference_trace, event_trace, event_slot, event_id, batch_id, inference_attempt, ascii_reset)
    

def make_abilities(abils):
    result = {}
    for a in abils:
        a = { k.decode(): d(v) for k, v in a.items() }
        result[a['id']] = a
    return result


def character_string(char):
    string = ""
    for k, v in char.items():
        thisv = str(v)
        if type(v) is list:
            thisv = '[%d]' % len(v)
        if type(v) is dict:
            thisv = '{%d}' % len(v)
        string += (" " if string != "" else "") + k + "=" + thisv
    return string


# Get the metadata at this time
def get_metadata(metadata_updates, metadata_index):
    meta = metadata_updates[metadata_index]
    meta = { k.decode(): d(v) for k, v in meta.items() }
    return meta
    

def get_characters(character_updates, update_index):
    update = character_updates[update_index]
    time, trace, characters = update
    return [ { d(k): d(v) for k, v in char.items() } for char in characters ]
    

# Return the character abilities at this time
def get_character_abilities(characters):
    character_abilities = {}
    for char in characters:
        if 'abilities' in char:
            character_abilities[char['GUID']] = make_abilities(char['abilities'])
    return character_abilities


def read_export_data(f, quiet=False):
    data = decode_export_blob(f.read())

    addon_version = data.get(b'addonVersion', b'not encoded').decode()
    if not quiet:
        print('ADDON VERSION -------------------------------------------------------------------')
        print(addon_version)

    metadata_updates = data[b'metadataUpdates'] or {}
    if not quiet:
        print('METADATA ------------------------------------------------------------------------')
        print('got', len(metadata_updates), 'metadata updates')


    character_updates = data[b'characterUpdates'] or {}
    character_abilities = {}
    if not quiet:
        print('CHARACTERS ----------------------------------------------------------------------')
        print('got', len(character_updates), 'character updates')
    for index, update in character_updates.items():
        time, trace, characters = update
        if not quiet:
            print('    index=%d, time=[%0.3f] responded to [%s]: character data:' % \
                (index, time, trace.decode()))

    start_time = data[b'playback'][0][0]
    playback = [ ('event', e[0] - start_time, [e[0]-start_time] + [ d(x) for x in e[1:] ]) for e in data[b'playback'] ]
    if not quiet:
        print('PLAYBACK ------------------------------------------------------------------------')
        print('got', len(playback), 'events')


    if not quiet: print('INFERENCE -----------------------------------------------------------------------')
    inferences = data[b'inference']
    # Remove simulation inferences from zero knowledge solves
    inferences = [ ('inf', inf[0] - start_time, [inf[0]-start_time] + [ d(x) for x in inf[1:] ]) for inf in inferences if not inf[4].decode().startswith("SIMULATE(") ]
    if not quiet: print('found', len(inferences), 'inference records')

    return addon_version, metadata_updates, character_updates, playback, inferences


# exported from AbilityDb.lua
all_tracked_abilities = [
    "Shadowmeld",
    "Stoneform",
    "Anti-Magic Shell",
    "Icebound Fortitude",
    "Vampiric Blood",
    "Pillar of Frost",
    "Blur",
    "Metamorphosis",
    "Last Resort",
    "Untethered Rage",
    "Fiery Brand",
    "Barkskin",
    "Celestial Alignment",
    "Incarnation: Chosen of Elune",
    "Berserk",
    "Incarnation: Avatar of Ashamane",
    "Berserk",
    "Incarnation: Guardian of Ursoc",
    "Ironbark",
    "Dragonrage",
    "Obsidian Scales",
    "Time Dilation",
    "Survival of the Fittest",
    "Trueshot",
    "Aspect of the Turtle",
    "Exhilaration",
    "Feign Death",
    "Takedown",
    "Arcane Surge",
    "Ice Block",
    "Ice Cold",
    "Mirror Image",
    "Alter Time",
    "Combustion",
    "Greater Invisibility",
    "Fortifying Brew",
    "Life Cocoon",
    "Invoke Niuzao, the Black Ox",
    "Blessing of Sacrifice",
    "Divine Protection",
    "Divine Shield",
    "Blessing of Protection",
    "Blessing of Spellwarding",
    "Blessing of Freedom",
    "Unbound Freedom",
    'Wake of Ashes',
    'Avenging Crusader',
    "Avenging Wrath",
    "Ardent Defender",
    "Guardian of Ancient Kings",
    "Gift of the Golden Valkyr",
    "Sentinel",
    "Dispersion",
    "Desperate Prayer",
    "Pain Suppression",
    "Divine Hymn",
    "Guardian Spirit",
    "Voidform",
    "Vanish",
    "Cloak of Shadows",
    "Evasion",
    "Adrenaline Rush",
    "Shadow Dance",
    "Shadow Blades",
    "Astral Shift",
    "Ascendance",
    "Doom Winds",
    "Unending Resolve",
    "Die by the Sword",
    "Avatar",
    "Avatar of the Storm",
    "Enraged Regeneration",
    "Shield Wall"
]


if __name__ == "__main__":
    with open(sys.argv[1], "r") as f:
        addon_version, metadata_updates, character_updates, playback, inferences = read_export_data(f)

    spells = read_spell_names(sys.argv[2])

    confp = defaultdict(float)
    buffs_by_player = defaultdict(list)
    debuffs_by_player = defaultdict(list)
    maybe_stoneform = defaultdict(dict)
    update_count_per_aura = defaultdict(lambda: defaultdict(int))
    for rectype, time, record in sorted(playback + inferences, key=lambda x: x[1]):
        if rectype == "event":
            time, event = record[0:2]
            print("%s%0.3f %s(%s)%s" % \
                (ascii_purple, time, event, ",".join([ str(x) for x in record[2:] ]), ascii_reset))
            if event == "METADATA_UPDATE":
                print("updating metadata")
                update_index = record[2]
                metadata = get_metadata(metadata_updates, update_index)
                print(metadata)
            elif event == "CHARACTER_DATA_UPDATE":
                print("updating character data")
                update_index = record[2]
                characters = get_characters(character_updates, update_index)
                for char in characters:
                    print(character_string(char))

                print('updating abilities..')
                character_abilities = get_character_abilities(characters)
            else:
                actor = ""

            # This processing does nothing, but is left as a framework to test ideas
            if event == "UNIT_AURA":
                time = round(time, 3)
                if len(record) == 5:
                    slot, payload, raw_auras = record[2:]
                else:
                    slot, payload, raw_auras, _ = record[2:]

                if raw_auras and isinstance(raw_auras, list):
                    # serializer encodes a list rather than dict if only one aura is present
                    # overwrite with a dict that returns the one present aura data no matter
                    # what key is used.
                    auras = defaultdict(lambda: raw_auras[0][:])
                else:
                    auras = raw_auras

                for aura in payload.get(b'addedAuras', []):
                    aid = aura[b'auraInstanceID']
                    if auras and auras[aid][5]:
                        buffs_by_player[slot].append(aid)
                    if auras and auras[aid][6]:
                        debuffs_by_player[slot].append(aid)

                remlist = payload.get(b'removedAuraInstanceIDs', [])
                uplist = payload.get(b'updatedAuraInstanceIDs', [])
                removed_debuffs = [ a for a in remlist if a in debuffs_by_player[slot] ]
                updated_debuffs = [ a for a in uplist if a in debuffs_by_player[slot] ]
                added_buffs = [ a for a in payload.get(b'addedAuras', [])
                    if a[b'auraInstanceID'] in buffs_by_player[slot] ]

                if removed_debuffs and added_buffs:
                    for aura in added_buffs:
                        aid = aura[b'auraInstanceID']
                        flags = auras[aid][0:5]
                        if not any(flags):
                            True or print('MAYBE STONEFORM', aid, slot, flags)
                            maybe_stoneform[slot][aid] = time

                for aid in remlist:
                    if aid in buffs_by_player[slot]:
                        if aid in maybe_stoneform[slot]:
                            prevtime = maybe_stoneform[slot][aid]
                            duration = time - prevtime
                            True or print('removing MAYBE STONEFORM', aid, slot, maybe_stoneform[slot][aid], 'at', time)
                            diff = round(abs(duration - 8), 3)
                            if diff < 0.25:
                                True or print(prevtime, time,'LIKELY STONEFORM', aid, slot, diff)
                            else:
                                True or print(prevtime, time,'REJECT STONEFORM', aid, slot, diff)
                            del maybe_stoneform[slot][aid]
                        buffs_by_player[slot].remove(aid)
                    if aid in debuffs_by_player[slot]:
                        debuffs_by_player[slot].remove(aid)

                for aid in uplist:
                    if aid in debuffs_by_player[slot]:
                        update_count_per_aura[slot][aid] += 1
        elif rectype == "inf":
            inference_time, inference_trace, inference_attempt, \
                event_time, event_trace, event_id, event_source, event_slot, batch_id, \
                ability_id, certain, ability_caster, \
                logic, conf, reqs = record
            print(infer_string(record))
            print("PASS:", logic_string(logic, event_source, True, character_abilities))
            print("FAIL:", logic_string(logic, event_source, False, character_abilities))
            print("CONF:", confidence_string(conf) + " " + reqs_string(reqs))
            print(decision_string(record, spells))

    for slot, upcounts in update_count_per_aura.items():
        for aid, count in sorted(upcounts.items(), key=lambda x: x[1], reverse=True): #[:10]:
            print(slot, aid, count)

    for event_data, diff in confp.items():
        if diff < 0.15:
            print('CONFP', event_data, diff)
