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

from decode_playback import d, get_metadata, get_characters, character_string, get_character_abilities


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
        inferences = [ ('inf', inf[0], [ d(x) for x in inf ])
            for inf in inferences if not inf[4].decode().startswith("SIMULATE(") ]
        inferences = [ normalize(rec, start_time) for rec in inferences ]
        print('Found', len(inferences), 'inference records')
        print(inferences[:2])

    return player_guid, metadata_updates, character_updates, playback, inferences


# Don't try to translate slot->guid here. Those mappings can change with time.
# The returned values being keyed by slot is just a minor optimization. Maybe
# get rid of it altogether.
def get_cast_events(playback):
    cast_events = {}
    cast_times = {}
    for e in ( record for rectype, time, record in playback if record[1] == 'UNIT_SPELLCAST_SUCCEEDED' ):
        # playback event records are not all the same structure
        e = [ d(x) for x in e ]
        time, event, actor_slot = e[0:3]
        if event == "UNIT_SPELLCAST_SUCCEEDED":
            cast_events.setdefault(actor_slot, []).append(e)
            cast_times.setdefault(actor_slot, []).append(time)

    # there should be many more spellcast events than inferences, so optimize this one
    for k, v in cast_times.items():
        cast_times[k] = numpy.array(cast_times[k])

    return cast_times, cast_events


# when multiple inferences derive from the same event, collapse to the final record
def collapse_inferences(inferences):
    unique_inferences = []
    for rectype, time, inf in inferences:
        event_id = inf[5]
        batch_id = inf[8]
        eventkey = event_id + "/" + str(batch_id)
        attempt = inf[2]
        if eventkey in unique_inferences:
            print('overwriting previous inf for event ID', eventkey, 'attempt', attempt)
        unique_inferences.append((rectype, time, inf))
    return unique_inferences


# Map each inference record back to a spellcast playback event and create a merged
# record. Since inferences have inferred casters as well, only consider spellcast
# events from the appropriate character.
#
# Returns None (signaling to filter out the inference) if the ability wasn't inferred.
# Needs to be scored as a false negative.
def match_inference_to_event(inf, guid_to_slot, cast_times, cast_events):
    inf = [ d(x) for x in inf ]
    inference_time, inference_trace, inference_attempt, \
        event_time, event_trace, event_id, event_source, event_slot, batch_id, \
        ability_id, certain, caster_guid, \
        logic, conf, reqs = inf
    if caster_guid is not None:
        caster_slot = guid_to_slot[caster_guid]
        best = numpy.argmin(numpy.absolute(cast_times[caster_slot] - event_time))
        event = cast_events[caster_slot][best]
        merged_record = event + inf
        return merged_record
    else:
        print('SKIPPING INFERENCE: NO INFERRED ABILITY:', inf)
        return None


# Subset the full record list `full` to a specific event and actor on which to
# calculate time diffs for alignment. Offset timestamps must be in index 0.
def get_diffs_on_subset(full, event_index, event_value, actor_index, actor_value, is_event=False):
    times = []
    diffs = []
    #recs = []
    last_time = 0
    for record in full:
        if record[event_index] == event_value and record[actor_index] == actor_value: # and (not is_event or record[4] != 361652):
            time = record[0]
            times.append(time)
            diffs.append(time - last_time)
            #recs.append(record)
            last_time = time
    return numpy.column_stack([
        numpy.array(times, dtype=float),
        numpy.array(diffs, dtype=float) ]) #, recs


# a and b are two-column matrices where the first column is offset timestamps
# and the second column is the difference in time from the previous timestamp
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
# Useful to calculate: the amount of overlap as a function of k=index, len(a)=N, len(b)=M.
# The overlap function is the sum of two linear functions with slope=1, one positive and
# one negative.
#
# L = min(N, M) is the maximum overlap between the sequences.
#
# the positive function is:  f(k) = min(1 + k, L)  -- y-intercept=1
#
#   L  ______________________    the negative function has to remove all but 1 of the L
#     /                      \   overlapping elements at the maximum k: i.e.,
#    /                        \      g(N+M-1) = L-1, so the y-intercept is (L-1)-(N+M-1), so
#   /                          \     g(k) = max(0, L-N-M+k)
# k=0                       k=N+M-1
#
# mask - when computing cross-correlation, large entries can drive the signal and
#        generate spurious correlations. to prevent this, set time differences > mask
#        to 0, removing their weight from the correlation. 
def align_one_tile(a, b, mask=4):
    print("Masking gaps")
    am = [ x if x < mask else 0 for x in a[:,1] ]
    bm = [ x if x < mask else 0 for x in b[:,1] ]
    print("Aligning a(%d) to b(%d).. " % (len(a), len(b)), end='')
    ccf = numpy.correlate(am, bm, mode='full')
    print('done.')
    k = numpy.argmax(ccf)
    N = len(a)
    M = len(b)
    L = min(N, M)
    o = lambda k: min(1 + k, L) - max(0, L - N - M + k)
    print('alignment index=', k, 'max cross-covariance=', ccf[k], '#lags evaluated=', len(ccf),
        'overlap:', o(k))

    # XXX: TODO: below is likely wrong. didn't check it very thoroughly
    astart = max(0, k-len(b))
    aend = min(k, len(a))
    print("alignment: a:", astart, aend, a[astart:aend,:].shape)
    bstart = max(0, len(b)-(k+1))
    bend = min(len(b) + len(a)-1-k, len(b))  # ends align when k=N-1
    print("alignment: b:", bstart, bend, b[bstart:bend,:].shape)
    return astart, aend, bstart, bend


# Return the time warp that must be subtracted from a's events to align with b's timeline.
#
# tile_size - break complete timeline into tiles and align each separately. this solves
#   an issue where there can be different events in the playback and combat log. for example,
#   in murder row when the fel gate is used on the last boss, there are two in-game 
#   UNIT_SPELLCAST_SUCCEEDED events fired for each player, but only one of the two is present
#   in the combat log.
#   these differences are rare enough that by breaking the timeline into several tiles, it is
#   near guaranteed that some tiles will not contain any such event disagreements and align
#   correctly.
def align_timelines(a, b, tile_size=100):
    tile_paths = {}
    atiles = numpy.array_split(a, int(len(a)/tile_size))
    last_bend = -1
    tile_path_len = 0
    tile_path_id = 1
    for atile in atiles:
        astart, aend, bstart, bend = align_one_tile(atile, b)
        a_aligned = atile[astart:aend]
        b_aligned = b[bstart:bend]
        times = numpy.column_stack([ a_aligned, b_aligned ])
        # is this tile continuous with the previous tile?
        if bstart == last_bend:
            tile_path_len = tile_path_len + 1
        else:
            print('bstart != last_bend', bstart, last_bend)
            tile_path_len = 0
            tile_path_id = tile_path_id + 1
        last_bend = bend
        tile_paths.setdefault(tile_path_id, []).append([ times, tile_path_len ])

    # given all of the per-tile alignments, find the longest tiling path
    path_lens = [ len(tiles) for path_id, tiles in tile_paths.items() ]
    longest_index = path_lens.index(max(path_lens))
    print(path_lens, longest_index)
    path = tile_paths[longest_index]
    rows = numpy.row_stack([ tile[0] for tile in path ])
    diffs = rows[:,0] - rows[:,2]  # time  differences for each event
    rows = numpy.column_stack([ rows, diffs ])
    # XXX: TODO: do a simple outlier removal like Tukey's or use the mode. median should
    # be robust enough for most cases.
    warp = numpy.median(diffs)
    print(rows)
    print(warp)
    return warp
    


def write_adjusted(filename, events, adj):
    with open(filename, 'w') as f:
        for e in events:
            f.write('\t'.join([ '%0.3f' % (e[0] - adj) ] + [ str(x).strip() for x in e[1:] ]) + '\n')


def match_inference_to_combatlog(inf, combatlog_aura_times, combatlog_auras):
    inference_time, inference_trace, inference_attempt, \
        event_time, event_trace, event_id, event_source_guid, event_slot, batch_id, \
        inferred_ability_id, certain, inferred_caster_guid, \
        logic, conf, reqs = inf
    #inference_time -= time_adj  # need to save for printing later. this doesn't do that.
    #event_time -= time_adj
    #print(event_time)
    #print(combatlog_aura_times[:-6])
    #print(inf)
    
    # use the time the event occurred, not the inference.
    # return the slice boundaries to get combatlog events within 'tolerance' seconds of
    # the inference event
    def get_near_events(event_time, combatlog_times, tolerance=1):
        combatlog_indexes = numpy.arange(len(combatlog_times))
        time_diffs = numpy.absolute(combatlog_times - event_time)
        #print(time_diffs[time_diffs < tolerance])
        indexes_within_tolerance = combatlog_indexes[time_diffs < tolerance]
        return min(indexes_within_tolerance), max(indexes_within_tolerance) + 1

    start, stop = get_near_events(event_time, combatlog_aura_times)
    #print(start,stop)
    auras = combatlog_auras[start:stop]

    # look for all possible matches
    found = []
    for a in auras:
        combatlog_time = a[0]
        combatlog_caster_guid = a[2]
        combatlog_target_guid = a[6]
        combatlog_ability_id = int(a[10])
        #print(event_time, event_source_guid, combatlog_time, combatlog_caster_guid, combatlog_target_guid, combatlog_ability_id)
        time_diff = abs(event_time - combatlog_time)
        # if inferred_caster_guid == combatlog_caster_guid and inferred_ability_id == combatlog_ability_id:
        if event_source_guid == combatlog_target_guid: # and inferred_ability_id == combatlog_ability_id:
            found.append(a)

    # get the best match (nearest time)
    found = sorted(found, key=lambda a: abs(event_time - a[0]))
    if len(found) > 0:
        a = found[0]
        combatlog_time = a[0]
        combatlog_caster_guid = a[2]
        combatlog_ability_id = int(a[10])
        time_diff = abs(event_time - combatlog_time)
        if time_diff < 0.125:
            print('match', '%0.3f'%time_diff)
            #print('MATCH: diff=%0.3f, time=[E=%0.3f, L=%0.3f], spellID=[E=%d, L=%d], caster=[E=%s, L=%s]' % \
                #(time_diff, inf[8], a[0], inferred_ability, combatlog_ability, inferred_caster, combatlog_caster))
        else:
            print('NO MATCH (0 log matches found) --------------------------------------------------')
    else:
        print('NO MATCH ------------------------------------------------------------------------')
        #print('found=', found, len(auras), inferred_caster_guid, inferred_ability_id, combatlog_caster_guid, combatlog_ability_id)
        for a in []: #auras:
            combatlog_caster = a[2]
            combatlog_ability = int(a[10])
            time_diff = abs(inf[8] - a[0])
            print(inferred_caster_guid == combatlog_caster_guid, inferred_ability_id == combatlog_ability_id, time_diff, a)
        #print("INF EVENT", inf[0:17])


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

full_combatlog = read_combatlog(combatlog_in)

# For alignment: choose an event type that isn't too frequent and is recorded and exported
# by the addon. If event is too frequent, the diffs between events could become
# so small that they approach the noise threshold. Using spell casts by the addon-exporting
# player is pretty successful.
subset_playback = \
    get_diffs_on_subset([ rec for _, _, rec in playback ], 1, "UNIT_SPELLCAST_SUCCEEDED", 2, "player", True)
subset_combatlog = \
    get_diffs_on_subset(full_combatlog, 1, "SPELL_CAST_SUCCESS", 2, addon_user_guid)

warp = align_timelines(subset_combatlog, subset_playback)
print('writing adjusted combatlog to', combatlog_out)
write_adjusted(combatlog_out, full_combatlog, warp) # combatlog_time_adj)  # =0 debugging


combatlog_auras = [ [ rec[0] - warp ] + rec[1:] for rec in full_combatlog
    if rec[1] == "SPELL_CAST_SUCCESS" or rec[1] == "SPELL_AURA_APPLIED" or rec[1] == "SPELL_AURA_REFRESH" ]
combatlog_aura_times = numpy.array([ rec[0] for rec in combatlog_auras ], dtype=float)

cast_times, cast_events = get_cast_events(playback)
unique_inferences = collapse_inferences(inferences)

guid_to_slot = {}
for rectype, time, record in sorted(playback + unique_inferences, key=lambda x: x[1]):
    if rectype == 'event':
        _, event = record[0:2]

        # These fake metadata "events" allow us to update slot <-> guid mappings and the
        # abilities of present characters.
        if event == "METADATA_DATA_UPDATE":
            print("updating metadata")
            update_index = record[2]
            metadata = get_metadata(metadata_updates, update_index)
            guid_to_slot = { k.decode(): v.decode() for k, v in metadata['GUIDToSlot'].items() }
        elif event == "CHARACTER_DATA_UPDATE":
            print("updating character data", end='')
            update_index = record[2]
            characters = get_characters(character_updates, update_index)
            for char in characters:
                #print(character_string(char))
                print("", char['playerName'], end="")
            print('')

            print('updating abilities..')
            character_abilities = get_character_abilities(characters)
    elif rectype == 'inf':
        match_inference_to_combatlog(record, combatlog_aura_times, combatlog_auras)
