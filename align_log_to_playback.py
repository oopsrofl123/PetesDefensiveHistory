#!/usr/bin/env python

import sys
import math
import time
import base64
import zlib
import cbor2
import numpy
from time import mktime, strptime
import pathlib


def d(x):
    return x.decode() if type(x) is bytes else x


# Map absolute timestamps to offset timestamps (i.e., first entry in the log is time=0).
def read_combatlog(filename):
    decoded_events = []
    start_time = None
    last_time = 0
    with open(filename, "r") as f:
        for line in f:
            s = line.split(' ')
            date, time_with_hyphen = s[0:2]
            data = ' '.join(s[3:])  # skip a field - wow puts 2 spaces after the time
            # example line: 3/17/2026 03:09:23.744-4
            # not sure what this "-4" bit is, just throwing it away
            time, msecs = time_with_hyphen.split('.')
            msecs = int(msecs.split('-')[0])
            # convert time to a single numeric value
            time = mktime(strptime(date + " " + time, "%m/%d/%Y %H:%M:%S"))
            if start_time is None:
                start_time = time
            time_offset = time - start_time + msecs/1000
            time_diff = time_offset - last_time
            decoded_events.append([ time_offset ] + data.split(','))
    return decoded_events

    
# Just read and decode the blob exported from the addon
def read_addon_export(filename):
    def decode_export_blob(compressed):
        decoded = base64.b64decode(compressed)
        all_records = zlib.decompress(decoded, wbits=-15)
        return cbor2.loads(all_records)

    with open(filename, "r") as f:
        data = decode_export_blob(f.read())
        metadata_updates = data[b'metadataUpdates']
        player_guid = metadata_updates[0][b'myGUID'].decode()
        print('Exporter:', player_guid)

        character_updates = data[b'characterUpdates']
        print('CHARACTERS ------------------------------------------------------------')
        print('Found', len(character_updates), 'character updates')

        def normalize(record, start):
            result = [ record[0], record[1] - start ] + \
                [ d(x) for x in record[2:] ]
            result[2][3 if record[0] == 'inf' else 0] -= start
            return result

        playback = [ ('event', e[0], [ d(x) for x in e ]) for e in data[b'playback'] ]
        print('PLAYBACK ------------------------------------------------------------------------')
        print('got', len(playback), 'events')
        start_time = playback[0][1]  # applies to both events and inferences
        playback = [ normalize(rec, start_time) for rec in playback ]
        print(playback[:2])

        print('INFERENCE -----------------------------------------------------------------------')
        inferences = data[b'inference']
        # Remove simulation inferences from zero knowledge solves
        inferences = [ ('inf', inf[0], [ d(x) for x in inf ]) for inf in inferences if not inf[4].decode().startswith("SIMULATE(") ]
        inferences = [ normalize(rec, start_time) for rec in inferences ]
        print('Found', len(inferences), 'inference records')
        print(inferences[:2])

    return player_guid, metadata_updates, character_updates, playback, inferences


# Map each inference record back to a spellcast playback event and create a merged
# record. Since inferences have inferred casters as well, only consider spellcast
# events from the appropriate character.
def get_inferences_to_assess(playback, inferences):
    cast_events = {}
    cast_times = {}
    for e in ( e for e in playback if e[1] == 'UNIT_SPELLCAST_SUCCEEDED' ):
        # playback event records are not all the same structure
        e = [ x.decode() if type(x) is bytes else x for x in e ]
        time, event, actor = e[0:3]
        if event == "UNIT_SPELLCAST_SUCCEEDED":
            cast_events.setdefault(actor, []).append(e)
            cast_times.setdefault(actor, []).append(time)

    # there should be many more spellcast events than inferences, so optimize this one
    for k, v in cast_times.items():
        cast_times[k] = numpy.array(cast_times[k])

    # when multiple inferences derive from the same event, collapse to the final record
    unique_inferences = {}
    for inf in inferences:
        event_id = inf[5]
        batch_id = inf[8]
        eventkey = event_id + "/" + str(batch_id)
        attempt = inf[2]
        if eventkey in unique_inferences:
            print('overwriting previous inf for event ID', eventkey, 'attempt', attempt)
        unique_inferences[eventkey] = inf

    records_to_assess = {}
    # inference records are uniformly structured. to map to a spellcast record, find
    # the closest one to the event that triggered the inference.
    for eventkey, inf in unique_inferences.items():
        inf = [ x.decode() if type(x) is bytes else x for x in inf ]
        inference_time, inference_trace, inference_attempt, \
            event_time, event_trace, event_id, event_source, event_slot, batch_id, \
            ability_id, certain, ability_caster, \
            logic, conf, reqs = inf
        if ability_caster is not None:
            best = numpy.argmin(numpy.absolute(cast_times[ability_caster] - event_time))
            event = cast_events[ability_caster][best]
            merged_record = event + inf
            records_to_assess.setdefault(ability_caster, []).append(merged_record)
        else:
            print('NO CASTER:',inf)

    return records_to_assess
            

# Subset the full record list `full` to a specific event and actor on which to
# calculate time diffs for alignment. Offset timestamps must be in index 0.
def get_diffs_on_subset(full, event_index, event_value, actor_index, actor_value):
    times = []
    diffs = []
    last_time = 0
    for record in full:
        if record[event_index] == event_value and record[actor_index] == actor_value:
            time = record[0]
            times.append(time)
            diffs.append(time - last_time)
            last_time = time
    return numpy.column_stack([
        numpy.array(times, dtype=float),
        numpy.array(diffs, dtype=float) ])


# a and b are two-column matrices where the first column is offset timestamps
# and the second column is the difference in time from the previous timestamp
def align_timelines(a, b):
    print("Aligning a(%d) to b(%d).. " % (len(a), len(b)), end='')
    ccf = numpy.correlate(a[:,1], b[:,1], mode='full')
    print('done.')
    k = numpy.argmax(ccf)
    print('alignment index=', k, 'max cross-covariance=', ccf[k], '#lags evaluated=', len(ccf))

    # Returned values for mode='full': array of len(log) + len(playback) - 1
    # index=0: 1 element overlap: playback's last element with log's first element.
    #                                        aaaaaaaaaaaaaaaaaaaaaa
    #    bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    #
    # index=k: k < len(log) is a k+1 element overlap, specifically
    # playback's rightmost k+1 elements with log's k+1 leftmost elements.
    #
    #                                        aaaaaaaaaaaaaaaaaaaaaa
    #                bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    #                                        ^^^^^^^^^^^^^ = index+1
    # index=k: k >= len(log), the playback is shifted far enough that its leftmost elements
    # overlap log's rightmost elements.
    #                                        aaaaaaaaaaaaaaaaaaaaaa
    #                                                    bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    #
    # N.B., python slices [a:b] are right-open: [a,b) and python indexes are 0-based.
    #
    # Useful to calculate: the amount of overlap as a function of index
    # len(a)=N, len(b)=M
    # index=0: overlap=1
    # index=1: overlap=2
    # ...
    # index=N-1: overlap=N
    # index=N: overlap=N-1
    # index=N+M-1: overlap=1
    #
    # Calculate the overlapping regions corresponding to a shift of index=k
    # XXX: TODO: below is likely wrong. didn't check it very thoroughly
    astart = max(0, k-len(b))
    aend = min(k, len(a))
    print("alignment: a:", astart, aend, a[astart:aend,:].shape)
    bstart = max(0, len(b)-(k+1))
    bend = min(len(b) + len(a)-1-k, len(b))  # ends align when k=N-1
    print("alignment: b:", bstart, bend, b[bstart:bend,:].shape)
    return a[astart:aend,:], b[bstart:bend,:]


def write_adjusted(filename, events, adj):
    with open(filename, 'w') as f:
        for e in events:
            f.write('\t'.join([ '%0.3f' % (e[0] - adj) ] + [ str(x) for x in e[1:] ]) + '\n')


# Suppress scientific notation
numpy.set_printoptions(suppress=True)

addon_export_in = sys.argv[1]  #"inference_and_playback_data.txt"
addon_export_out = pathlib.Path(addon_export_in).with_suffix('.aligned.txt')
print(addon_export_out)

combatlog_in = sys.argv[2]      #"WoWCombatLog-031826_055026.txt"
combatlog_out = pathlib.Path(combatlog_in).with_suffix('.aligned.txt')
print(combatlog_out)


addon_user_guid, metadata_updates, character_updates, playback, inferences = \
    read_addon_export(addon_export_in)

#guid_to_slot = { k.decode(): v.decode() for k, v in metadata['GUIDToSlot'].items() }
#
#player_name_to_slot = { k.decode(): v.decode() for k, v in metadata['playerNameToSlot'].items() }
#slot_to_player_name = { v: k for k, v in player_name_to_slot.items() }

full_playback = playback

print(addon_user_guid)

full_combatlog = read_combatlog(combatlog_in)


# For alignment: choose an event type that isn't too frequent and is one recorded and exported
# by the addon. If an event is chosen that's too frequent, the diffs between events could become
# so small that they approach the noise threshold. Using spell casts by the addon-exporting
# player is pretty successful.
#
# XXX: TODO: The addon exporter can be different from the combat logger here, but I don't know
# if the event timestamps will align as well. Needs testing.
subset_playback = get_diffs_on_subset([ rec for _, _, rec in full_playback ], 1, "UNIT_SPELLCAST_SUCCEEDED", 2, "player")
subset_combatlog = get_diffs_on_subset(full_combatlog, 1, "SPELL_CAST_SUCCESS", 2, addon_user_guid)

# only returns the overlapping interval. absolute times are used, so this interval
# adjustment can be applied to the full combatlog/playback and 0 will always denote
# the start of the overlap.
aligned_combatlog, aligned_playback = align_timelines(subset_combatlog, subset_playback)
result = numpy.column_stack([ aligned_combatlog, aligned_playback ])

# Only overlapping portions of each file are written out
combatlog_time_adj = float(aligned_combatlog[0,0])
playback_time_adj = float(aligned_playback[0,0])
print('combat log adj.:', combatlog_time_adj, 'playback event time adj.:', playback_time_adj)

print('writing adjusted combatlog to', combatlog_out)
write_adjusted(combatlog_out, full_combatlog, combatlog_time_adj)

#result[:,0] -= combatlog_time_adj
#result[:,2] -= playback_time_adj
#print(result[:8,:])

#inferences_to_assess = get_inferences_to_assess(playback, inferences)

print("Inferences to assess (by caster):")
for caster, inflist in inferences_to_assess.items():
    #slot = guid_to_slot[caster]
    #player = slot_to_player_name[slot]
    print("    %s(%s)=%s: %d" % (caster, len(inflist)))


def get_near_events(inf, combatlog_events, combatlog_times, tolerance=1):
    inferred_caster = inf[16]
    inferred_ability = inf[14]
    # DO NOT use the mapped spell cast because not all abilities require a button press
    # (e.g., GoAK cheat death). use the time the event occurred
    #playback_time = inf[0] - playback_time_adj
    playback_time = inf[8] #- playback_time_adj

    combatlog_indexes = numpy.arange(len(combatlog_events))
    time_diffs = numpy.absolute(combatlog_times - playback_time)
    indexes_within_tolerance = combatlog_indexes[time_diffs < tolerance]
    events_within_tolerance = combatlog_events[min(indexes_within_tolerance):(1+max(indexes_within_tolerance))]
    return events_within_tolerance


combatlog_auras = [ [ rec[0] - combatlog_time_adj ] + rec[1:] for rec in full_combatlog
    if rec[1] == "SPELL_CAST_SUCCESS" or rec[1] == "SPELL_AURA_APPLIED" or rec[1] == "SPELL_AURA_REFRESH" ]
combatlog_aura_times = numpy.array([ rec[0] for rec in combatlog_auras ], dtype=float)

for rectype, time, record in sorted(playback + inferences, key=lambda x: x[1]):
    if rectype == 'event':
        if event == "METADATA_DATA_UPDATE":
            print("updating metadata")
            update_index = record[2]
            metadata = get_metadata(update_index)
        elif event == "CHARACTER_DATA_UPDATE":
            print("updating character data")
            update_index = record[2]
            characters = get_characters(update_index)
            for char in characters:
                print(character_string(char))

            print('updating abilities..')
            character_abilities = get_character_abilities(characters)
    elif rectype == 'inf':
        ""

for caster, inflist in inferences_to_assess.items():
    print(caster)
    for inf in inflist:
        inf[0] = inf[0] - playback_time_adj  # nearest cast event time
        inf[5] = inf[5] - playback_time_adj  # time inference succeeded
        inf[8] = inf[8] - playback_time_adj  # time of event that initiated inference
        auras = get_near_events(inf, combatlog_auras, combatlog_aura_times)

        # look for a match
        inferred_caster = inf[16]
        inferred_ability = inf[14]
        found = []
        for a in auras:
            combatlog_caster = a[2]
            combatlog_ability = int(a[10])
            time_diff = abs(inf[8] - a[0])
            if inferred_caster == combatlog_caster and inferred_ability == combatlog_ability:
                found.append(a)

        found = sorted(found, key=lambda a: abs(inf[8] - a[0]))
        a = found[0]
        combatlog_caster = a[2]
        combatlog_ability = int(a[10])
        time_diff = abs(inf[8] - a[0])
        if len(found) > 0 and time_diff < 0.125:
            print('match', '%0.3f'%time_diff)
            #print('MATCH: diff=%0.3f, time=[E=%0.3f, L=%0.3f], spellID=[E=%d, L=%d], caster=[E=%s, L=%s]' % \
                #(time_diff, inf[8], a[0], inferred_ability, combatlog_ability, inferred_caster, combatlog_caster))
        else:
            print('NO MATCH ------------------------------------------------------------------------')
            print('found=', found, len(auras), inferred_caster, inferred_ability, combatlog_caster, combatlog_ability)
            for a in auras:
                combatlog_caster = a[2]
                combatlog_ability = int(a[10])
                time_diff = abs(inf[8] - a[0])
                print(inferred_caster == combatlog_caster, inferred_ability == combatlog_ability, time_diff, a)
            print("INF EVENT", inf[0:17])
