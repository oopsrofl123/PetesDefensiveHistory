#!/usr/bin/env python

import math
import time
import base64
import zlib
import cbor2
import numpy
import shlex   # not exactly what WoW uses. just want to preserve quoted spaces
from time import mktime, strptime
import pathlib

def read_combatlog(filename):
    decoded_events = []
    start_time = None
    last_time = 0
    with open(filename, "r") as f:
        for line in f:
            date, time_with_hyphen, data = shlex.split(line)
            # example line: 3/17/2026 03:09:23.744-4
            # not sure what this "-4" bit is, just throwing it away
            time, msecs = time_with_hyphen.split('.')
            msecs = int(msecs.split('-')[0])
            # convert time to a single numeric value
            time = mktime(strptime(date + " " + time, "%m/%d/%Y %H:%M:%S"))
            if start_time is None:
                start_time = time
            time_offset = time - start_time + msecs/1000
            #time_diff = time_offset - last_time
            decoded_events.append([ time_offset ] + data.split(','))
    return decoded_events

    
# Return normalized timestamped playback data. Can't calculate timestamp diffs here
# because this is reading the whole file. Diffs should only be calculated for a subset
# of specific, reliable events like casts by the logging player.
def read_playback(filename):
    def decode_export_blob(compressed):
        decoded = base64.b64decode(compressed)
        all_records = zlib.decompress(decoded, wbits=-15)
        return all_records

    decoded_events = []
    start_time = None
    last_time = 0
    with open(filename, "r") as f:
        # There are two stages of compress/encode for technical reasons..
        blob = decode_export_blob(decode_export_blob(f.read()))
        events = cbor2.loads(blob)
        for e in events:
            t = e[0]
            if start_time is None:
                start_time = math.floor(t)
            e[0] = t - start_time
            e[1:] = [ x.decode() if type(x) is bytes else x for x in e[1:] ]
            decoded_events.append(e)
    return decoded_events


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
    ccf = numpy.correlate(a[:,1], b[:,1], mode='full')
    k = numpy.argmax(ccf)
    print(k, ccf[k], len(ccf))

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
    # For index=k, the overlapping regions are:
    #     a[start=max(0, index-len(a)), end=min(index, len(a))]
    #     b[start=max(0, len(b)-(index+1)), end=len(b)-max(0, index-len(a))]
    astart = max(0, k-len(a))
    aend = min(k+1, len(a))
    bstart = max(0, len(b)-(k+1))
    bend = len(b) - max(0, k-len(a))
    return a[astart:aend,:], b[bstart:bend,:]

combatlog_in = "WoWCombatLog-031726_030615.txt"
combatlog_out = pathlib.Path(combatlog_in).with_suffix('.aligned.txt')
print(combatlog_out)
playback_in = "export_data_event_playback.txt"
playback_out = pathlib.Path(playback_in).with_suffix('.aligned.txt')
print(playback_out)

full_combatlog = read_combatlog(combatlog_in)
subset_combatlog = get_diffs_on_subset(full_combatlog, 1, "SPELL_CAST_SUCCESS", 2, "Player-1129-0BF36258")

full_playback = read_playback(playback_in)
subset_playback = get_diffs_on_subset(full_playback, 1, "UNIT_SPELLCAST_SUCCEEDED", 2, "player")


aligned_combatlog, aligned_playback = align_timelines(subset_combatlog, subset_playback)
result = numpy.column_stack([ aligned_combatlog, aligned_playback ])
numpy.set_printoptions(suppress=True)
print(result[:8,:])

# Only overlapping portions of each file are written out
combatlog_adj = aligned_combatlog[0,0]
playback_adj = aligned_playback[0,0]
final_record_time = max(aligned_combatlog[aligned_combatlog.shape[0]-1, 0] - combatlog_adj,
    aligned_playback[aligned_playback.shape[0]-1, 0] - playback_adj)
with open(combatlog_out, 'w') as f:
    for record in full_combatlog:
        record[0] -= round(combatlog_adj, 3)
        if record[0] >= 0 and record[0] <= final_record_time:
            record[0] = '%0.3f' % record[0]
            f.write('\t'.join([ str(x) for x in record ]) + '\n')

with open(playback_out, 'w') as f:
    for record in full_playback:
        record[0] -= round(playback_adj, 3)
        if record[0] >= 0 and record[0] <= final_record_time:
            record[0] = '%0.3f' % record[0]
            f.write('\t'.join([ str(x) for x in record ]) + '\n')
