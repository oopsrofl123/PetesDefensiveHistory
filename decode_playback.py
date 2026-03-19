#!/usr/bin/env python

import sys
import math
import time
import base64
import zlib
import cbor2
import numpy as np

ascii_cyan = "\033[36m"
ascii_purple = "\033[35m"
ascii_yellow = "\033[33m"
ascii_green = "\033[32m"
ascii_red = "\033[31m"
ascii_reset = "\033[0m"

def d(x):
    return x.decode() if type(x) is bytes else x


def passcolor(passes):
    return ascii_green if passes else ascii_red


def certainmark(certain):
    return "" if certain else "*"


def decode_export_blob(compressed):
    decoded = base64.b64decode(compressed)
    decompressed = zlib.decompress(decoded, wbits=-15)
    return cbor2.loads(decompressed)


def one_logic_string(ability, layers):
    string = "[" + str(ability) + ":"
    for name, summary in layers.items():
        passes, certain = summary
        string += "%s%s%s" % (passcolor(passes), name.decode(), certainmark(certain))
    string += ascii_reset + "]"
    return string


def logic_string(logic, pass_type):
    string = ""
    for logic_summary in logic:
        caster, ability_id, passes, layers = logic_summary
        if passes == pass_type:
            ability = character_abilities[caster.decode()][ability_id]
            string += one_logic_string(ability['alias'] if 'alias' in ability else ability['name'], layers)
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


def decision_string(inf):
    inference_time, inference_trace, inference_attempt, \
        event_time, event_trace, event_id, event_source, event_slot, batch_id, \
        ability_id, certain, ability_caster, \
        logic, conf, reqs = inf
    if ability_id is None:
        return "coudln't infer ability"
    else:
        return "%s%0.3f %s: event=[%s/%d], attempt=[%d], caster=[%s], time=[%0.3f]%s" % \
            (ascii_cyan, inference_time, "FINALIZED" if certain else "UNCERTAIN",
            event_id, batch_id, inference_attempt, ability_caster, event_time, ascii_reset)


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


with open(sys.argv[1], "r") as f:
    data = decode_export_blob(f.read())
    metadata = data[b'metadata']
    metadata = { k.decode(): d(v) for k, v in metadata.items() }
    print('METADATA ------------------------------------------------------------------------')
    player_guid = metadata['myGUID']
    print('Exporter:', player_guid)


    character_updates = data[b'characterUpdates']
    character_abilities = {}
    print('CHARACTERS ----------------------------------------------------------------------')
    print('got', len(character_updates), 'character updates')
    for update in character_updates:
        time, trace, characters = update
        print('    time=[%0.3f] responded to [%s]: character data:' % (time, trace.decode()))
        for char in characters:
            char = { k.decode(): d(v) for k, v in char.items() }
            if 'abilities' in char:
                character_abilities[char['GUID']] = make_abilities(char['abilities'])
            #print("        " + character_string(char))

    playback = [ ('event', e[0], [ d(x) for x in e ]) for e in data[b'playback'] ]
    print('PLAYBACK ------------------------------------------------------------------------')
    print('got', len(playback), 'events')


    # XXX: TODO: old code for matching cast events with inference events
    #cast_events = []
    #cast_times = []
    #for _, e in playback.items():
        # playback event records are not all the same structure
        #time, event, actor = e[0:3]
        #if event == "UNIT_SPELLCAST_SUCCEEDED":
            #cast_events.append(e)
            #cast_times.append(time)
    # there should be many more spellcast events than inferences, so optimize this one
    #cast_times = np.array(cast_times)


    print('INFERENCE -----------------------------------------------------------------------')
    inferences = data[b'inference']
    # Remove simulation inferences from zero knowledge solves
    inferences = [ ('inf', inf[0], [ d(x) for x in inf ]) for inf in inferences if not inf[4].decode().startswith("SIMULATE(") ]
    print('found', len(inferences), 'inference records')

    for rectype, time, record in sorted(playback + inferences, key=lambda x: x[1]):
        if rectype == "inf":
            inference_time, inference_trace, inference_attempt, \
                event_time, event_trace, event_id, event_source, event_slot, batch_id, \
                ability_id, certain, ability_caster, \
                logic, conf, reqs = record
            #best = np.argmin(np.absolute(cast_times - inference_time))
            #print(inference_time, best, ability_id, cast_events[best])
            if True or event_source == "Player-3721-0C5111C6":
                print(infer_string(record))
                print("PASS:", logic_string(logic, True))
                print("FAIL:", logic_string(logic, False))
                print("CONF:", confidence_string(conf) + " " + reqs_string(reqs))
                print(decision_string(record))
        elif rectype == "event":
            time, event = record[0:2]
            actor = ""
            if len(record) > 2:
                actor = record[2]
            if True or actor == "party3":
                #print(record)
                print("%s%0.3f %s(%s)%s" % \
                    (ascii_purple, time, event, ",".join([ str(x) for x in record[2:] ]), ascii_reset))
