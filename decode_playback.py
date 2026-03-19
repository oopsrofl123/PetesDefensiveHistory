#!/usr/bin/env python

import math
import time
import base64
import zlib
import cbor2
import numpy as np

def decode_export_blob(compressed):
    decoded = base64.b64decode(compressed)
    decompressed = zlib.decompress(decoded, wbits=-15)
    return cbor2.loads(decompressed)
    
with open("inference_and_playback_data.txt", "r") as f:
    data = decode_export_blob(f.read())
    metadata = data[b'metadata']
    metadata = { k.decode(): (v.decode() if type(v) is bytes else v) for k, v in metadata.items() }
    print('METADATA ------------------------------------------------------------------------')
    player_guid = metadata['myGUID']
    print('Exporter:', player_guid)


    characters = data[b'characters']
    print('CHARACTERS ----------------------------------------------------------------------')
    print('got', len(characters), 'characters')
    for char in characters:
        char = { k.decode(): (v.decode() if type(v) is bytes else v) for k, v in char.items() }
        print(char['playerName'], char['GUID'], char['raceName'], char['specName'], char['classFile'])

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
        inference_time, inference_trace, inference_attempt, \
        event_time, event_trace, event_id, event_source, event_slot, batch_id, \
        ability_id, certain, ability_caster, \
        logic, conf, reqs = inf
        best = np.argmin(np.absolute(cast_times - inference_time))
        #print(inference_time, best, ability_id, cast_events[best])
        print(inf)
