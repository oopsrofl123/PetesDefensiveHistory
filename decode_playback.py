#!/usr/bin/env python

import sys
import math
import time
import base64
import zlib
import cbor2
import numpy as np
import gzip

ascii_cyan = "\033[36m"
ascii_purple = "\033[35m"
ascii_yellow = "\033[33m"
ascii_green = "\033[32m"
ascii_red = "\033[31m"
ascii_reset = "\033[0m"

def d(x):
    return x.decode() if type(x) is bytes else x

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
    match playback:
        case "AURA(add)":
            return combatlog == "SPELL_AURA_APPLIED" or combatlog == "SPELL_AURA_APPLIED_DOSE"
        case "AURA(update)":
            return combatlog == "SPELL_AURA_REFRESH" or combatlog == "SPELL_AURA_REMOVED_DOSE"
        case "FLAGS(combatDrop)":
            return combatlog == "SPELL_CAST_SUCCESS"
        case _:
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


def logic_string(logic, source, pass_type):
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


def reqs_string(reqs):
    string = "reqs: "
    for name, req in (reqs.items() if len(reqs) > 0 else {}):
        value, passes, final = req
        string += "[" + passcolor(reqs) + name.decode() + "=" + ("%0.3f" % value) + ascii_reset + "]"
    return string


def decision_string(inf, spell_names):
    inference_time, inference_trace, inference_attempt, \
        event_time, event_trace, event_id, event_source, event_slot, batch_id, \
        ability_id, certain, ability_caster, \
        logic, conf, reqs = inf
    if ability_id is None:
        return "coudln't infer ability"
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


def read_export_data(f):
    data = decode_export_blob(f.read())
    metadata_updates = data[b'metadataUpdates'] or {}
    print('METADATA ------------------------------------------------------------------------')
    print('got', len(metadata_updates), 'metadata updates')


    character_updates = data[b'characterUpdates'] or {}
    character_abilities = {}
    print('CHARACTERS ----------------------------------------------------------------------')
    print('got', len(character_updates), 'character updates')
    for index, update in character_updates.items():
        time, trace, characters = update
        print('    index=%d, time=[%0.3f] responded to [%s]: character data:' % \
            (index, time, trace.decode()))

    playback = [ ('event', e[0], [ d(x) for x in e ]) for e in data[b'playback'] ]
    print('PLAYBACK ------------------------------------------------------------------------')
    print('got', len(playback), 'events')


    print('INFERENCE -----------------------------------------------------------------------')
    inferences = data[b'inference']
    # Remove simulation inferences from zero knowledge solves
    inferences = [ ('inf', inf[0], [ d(x) for x in inf ]) for inf in inferences if not inf[4].decode().startswith("SIMULATE(") ]
    print('found', len(inferences), 'inference records')

    return metadata_updates, character_updates, playback, inferences


if __name__ == "__main__":
    with open(sys.argv[1], "r") as f:
        metadata_updates, character_updates, playback, inferences = read_export_data(f)

    spells = read_spell_names(sys.argv[2])

    for rectype, time, record in sorted(playback + inferences, key=lambda x: x[1]):
        if rectype == "event":
            time, event = record[0:2]
            print("%s%0.3f %s(%s)%s" % \
                (ascii_purple, time, event, ",".join([ str(x) for x in record[2:] ]), ascii_reset))
            if event == "METADATA_DATA_UPDATE":
                print("updating metadata")
                update_index = record[2]
                metadata = get_metadata(metadata_updates, update_index)
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
        elif rectype == "inf":
            inference_time, inference_trace, inference_attempt, \
                event_time, event_trace, event_id, event_source, event_slot, batch_id, \
                ability_id, certain, ability_caster, \
                logic, conf, reqs = record
            if True or event_source == "Player-3721-0C5111C6":
                print(infer_string(record))
                print("PASS:", logic_string(logic, event_source, True))
                print("FAIL:", logic_string(logic, event_source, False))
                print("CONF:", confidence_string(conf) + " " + reqs_string(reqs))
                print(decision_string(record, spells))
