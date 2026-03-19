#!/usr/bin/env python

import math
import time
import base64
import zlib
import cbor2
import numpy as np

ascii_cyan = "\033[36m"
ascii_green = "\033[32m"
ascii_red = "\033[31m"
ascii_reset = "\033[0m"

def passcolor(passes):
    return ascii_green if passes else ascii_red


def certainmark(certain):
    return "" if certain else "*"


def decode_export_blob(compressed):
    decoded = base64.b64decode(compressed)
    decompressed = zlib.decompress(decoded, wbits=-15)
    return cbor2.loads(decompressed)


def one_logic_string(ability_id, layers):
    string = "[" + str(ability_id) + ":"
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
            string += one_logic_string(ability_id, layers)
    return string


def confidence_string(conf):
    ability_id, certain, num_possible_solns, layers = conf
    string = "#S=%d match=[%s], layers=[" % \
        (num_possible_solns, "nil" if ability_id is None else ability_id)
    for name, summary in layers.items():
        string += passcolor(summary[0]) + name.decode() + certainmark(summary[1]) + ascii_reset
    string += "]"
    return string


def req_string(reqs):
    string = ""
    for req in reqs:
        passcolor(reqs)


def infer_string(inf):
    inference_time, inference_trace, inference_attempt, \
        event_time, event_trace, event_id, event_source, event_slot, batch_id, \
        ability_id, certain, ability_caster, \
        logic, conf, reqs = inf
    return "%0.3f %sInfer(tr(infer)=[%s], tr(event)=[%s], source=[%s], eventId=[%s/%d], attempt=[%d]%s" % \
        (inference_time, ascii_cyan, inference_trace, event_trace, event_slot, event_id, batch_id, inference_attempt, ascii_reset)
    


with open("inference_and_playback_data.txt", "r") as f:
    data = decode_export_blob(f.read())
    print(data.keys())
    metadata = data[b'metadata']
    metadata = { k.decode(): (v.decode() if type(v) is bytes else v) for k, v in metadata.items() }
    print('METADATA ------------------------------------------------------------------------')
    player_guid = metadata['myGUID']
    print('Exporter:', player_guid)


    character_updates = data[b'characterUpdates']
    print('CHARACTERS ----------------------------------------------------------------------')
    print('got', len(character_updates), 'character updates')
    for update in character_updates:
        time, trace, characters = update
        print('    time=[%0.3f] responded to [%s]: character data:' % (time, trace.decode()))
        for char in characters:
            char = { k.decode(): (v.decode() if type(v) is bytes else v) for k, v in char.items() }
            print('        ', end='')
            for k, v in char.items():
                thisv = str(v)
                if type(v) is list:
                    thisv = '[%d]' % len(v)
                if type(v) is dict:
                    thisv = '{%d}' % len(v)
                print(" " + k + "=" + thisv, end='')
            print('\n', end='')

    playback = data[b'playback']
    print('PLAYBACK ------------------------------------------------------------------------')
    print('got', len(playback), 'events')

    cast_events = []
    cast_times = []
    for e in playback:
        # playback event records are not all the same structure
        e = [ x.decode() if type(x) is bytes else x for x in e ]
        time, event, actor = e[0:3]
        if event == "UNIT_SPELLCAST_SUCCEEDED":
            cast_events.append(e)
            cast_times.append(time)

    # there should be many more spellcast events than inferences, so optimize this one
    cast_times = np.array(cast_times)


    print('INFERENCE -----------------------------------------------------------------------')
    inferences = data[b'inference']
    # Remove simulation inferences from zero knowledge solves
    inferences = [ inf for inf in inferences if not inf[4].decode().startswith("SIMULATE(") ]
    print('found', len(inferences), 'inference records')

    # for each inference, find the closest matching cast record
    for inf in inferences:
        inf = [ x.decode() if type(x) is bytes else x for x in inf ]
        inference_time, inference_trace, inference_attempt, \
        event_time, event_trace, event_id, event_source, event_slot, batch_id, \
        ability_id, certain, ability_caster, \
        logic, conf, reqs = inf
        best = np.argmin(np.absolute(cast_times - inference_time))
        #print(inference_time, best, ability_id, cast_events[best])
        if ability_id == 389539: #True or event_source == b"Player-3721-0C5111C6":
            print(infer_string(inf))
            print("PASS:", logic_string(logic, True))
            print("FAIL:", logic_string(logic, False))
            print("CONF:", confidence_string(conf))
            #print(inf)
