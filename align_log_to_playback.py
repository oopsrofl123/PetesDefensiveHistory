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
import matplotlib.pyplot as plt
from dtw import dtw
from collections import defaultdict

from decode_playback import d, get_metadata, get_characters, character_string, get_character_abilities, event_type_match, read_spell_names


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
    unique_inferences = {}
    for rectype, time, inf in inferences:
        event_id = inf[5]
        batch_id = inf[8]
        eventkey = event_id + "/" + str(batch_id)
        attempt = inf[2]
        #if eventkey in unique_inferences:
            #print('overwriting previous inf for event ID', eventkey, 'attempt', attempt)
        unique_inferences[eventkey] = (rectype, time, inf)
    return list(unique_inferences.values())


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


# Get the longest diagonal walk in the path matrix. Could also return a list of all
# diagonal walks greater than some minimal length. These should all give the same
# constant warp, so only serves as a sanity check.
def extract_longest_exact(a, b, apath, bpath, tol=0.1):
    best_len, best_start_k = 0, 0
    curr_len, curr_start_k = 0, 0
    for k in range(1, len(apath)):  # k=0 is invalid
        if apath[k] == apath[k-1] + 1 and bpath[k] == bpath[k-1] + 1 and \
            abs(a[apath[k]] - b[bpath[k]]) <= tol:
            if curr_len == 0:
                curr_start_k = k
            curr_len += 1
        else:
            curr_len = 0
        if curr_len > best_len:
            best_len = curr_len
            best_start_k = curr_start_k

    start = best_start_k
    end = start + best_len - 1

    return apath[start], apath[end], bpath[start], bpath[end]


def align_timelines(a, b):
    alignment = dtw(a[:,1], b[:,1], keep_internals=True)
    print(alignment)
    plot = alignment.plot(type='threeway')
    print(plot)
    plt.savefig("dtw_alignment.png", dpi=300, bbox_inches="tight")
    plt.close() 
    astart, aend, bstart, bend = \
        extract_longest_exact(a[:,1], b[:,1], alignment.index1, alignment.index2)
    warp = a[astart,0] - b[bstart,0]
    print(numpy.column_stack([ a[astart:aend,:], b[bstart:bend,:] ]))
    print('longest exact match:', 'warp:', warp, aend-astart+1, astart, bend, bstart, bend)
    return warp


def write_adjusted(filename, events, adj):
    with open(filename, 'w') as f:
        for e in events:
            f.write('\t'.join([ '%0.3f' % (e[0] - adj) ] + [ str(x).strip() for x in e[1:] ]) + '\n')


def match_inference_to_combatlog(inf, combatlog_event_times, combatlog_events, tolerance=0.100):
    inference_time, inference_trace, inference_attempt, \
        event_time, event_trace, event_id, event_source_guid, event_slot, batch_id, \
        inferred_ability_id, certain, inferred_caster_guid, \
        logic, conf, reqs = inf
    
    # use the time the event occurred, not the inference time, which is not particularly
    # return the slice boundaries to get combatlog events within 'tolerance' seconds of
    # the inference event
    def get_near_events(event_time, combatlog_times):
        combatlog_indexes = numpy.arange(len(combatlog_times))
        time_diffs = numpy.absolute(combatlog_times - event_time)
        indexes_within_tolerance = combatlog_indexes[time_diffs < tolerance]
        if len(indexes_within_tolerance) == 0:
            return []
        else:
            return combatlog_events[min(indexes_within_tolerance):(max(indexes_within_tolerance) + 1)]

    events = get_near_events(event_time, combatlog_event_times)

    found = [ { 'diff': abs(event_time - e[0]), 'time': e[0], 'event': e[1], 'caster_guid': e[2], 'target_guid': e[6], 'ability_id': int(e[10]) }
        for e in events if event_source_guid == e[6] ]
    found = sorted(found, key=lambda e: e['diff'])
    return found


# Suppress scientific notation
numpy.set_printoptions(suppress=True)

addon_export_in = sys.argv[1]
addon_export_out = pathlib.Path(addon_export_in).with_suffix('.aligned.txt')
print(addon_export_out)

combatlog_in = sys.argv[2]
combatlog_out = pathlib.Path(combatlog_in).with_suffix('.aligned.txt')
print(combatlog_out)

spells = read_spell_names(sys.argv[3])


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
write_adjusted(combatlog_out, full_combatlog, warp)


combatlog_events = [ [ rec[0] - warp ] + rec[1:] for rec in full_combatlog
    if rec[1] == "SPELL_CAST_SUCCESS" or rec[1] == "SPELL_AURA_APPLIED" or rec[1] == "SPELL_AURA_REFRESH" ]
combatlog_event_times = numpy.array([ rec[0] for rec in combatlog_events ], dtype=float)

cast_times, cast_events = get_cast_events(playback)
unique_inferences = collapse_inferences(inferences)


class InferenceScore:
    def __init__(self):
        self.no_log = defaultdict(int)
        self.no_inference = defaultdict(lambda: defaultdict(int))
        self.num_no_inference = 0
        self.inference = defaultdict(list)
        self.data = {}
        self.false_positives = defaultdict(list)

    # Did this player respond to LibSpec?
    def set_character_data(self, char):
        self.data = char

    def player_label(self):
        return "%s (%s): %s %s %s" % \
            (self.data['playerName'],
             self.data['GUID'],
             self.data['raceName'],
             self.data['specName'] if 'specName' in self.data else 'unknown',
             self.data['classFile'])

    def talents_known(self):
        return 'talentExportString' in self.data

    def add_not_logged(self, trace):
        self.no_log[trace] = self.no_log[trace] + 1

    def add_no_inference(self, trace, log_records):
        self.num_no_inference = self.num_no_inference + 1
        for rec in log_records:
            self.no_inference[rec['ability_id']][trace] = \
                self.no_inference[rec['ability_id']][trace] + 1

    def add_inference(self, ability_id, matches, all_records):
        self.inference[ability_id].append(len(matches))
        if not matches:
            self.false_positives[ability_id].append([
                (spells[rec['ability_id']], rec['event']) for rec in all_records ])

    def print_false_positives(self):
        for ability, records in self.false_positives.items():
            print(spells[ability], ability)
            for rec in records:
                print('    ', rec)

    def nolog_str(self):
        return '    No log: ' + ', '.join([ '%s: %d' % (k, v) for k, v in self.no_log.items() ])

    def noinfer_str(self):
        string = '    No infer: %d times' % self.num_no_inference
        for ability_id, traces in self.no_inference.items():
            string = string + '\n        ' + spells[ability_id] + ": " + ', '.join([ '%s: %d' % (k, v) for k, v in traces.items() ])
        return string
    
    def infer_str(self):
        return '\n'.join([ ('    %s: %d+ %d-') % \
            (spells[ability_id], len(results) - results.count(0), results.count(0)) for ability_id, results in self.inference.items() ])

    def __str__(self):
        return '\n'.join([ self.nolog_str(), self.noinfer_str(), self.infer_str() ])

    def __repr__(self):
        return self.__str__()

guid_to_slot = {}

scores = defaultdict(InferenceScore)

quiet = True
for rectype, time, record in sorted(playback + unique_inferences, key=lambda x: x[1]):
    if rectype == 'event':
        _, event = record[0:2]

        # These fake metadata "events" allow us to update slot <-> guid mappings and the
        # abilities of present characters.
        if event == "METADATA_DATA_UPDATE":
            if not quiet: print("updating metadata")
            update_index = record[2]
            metadata = get_metadata(metadata_updates, update_index)
            if not quiet: print(metadata)    # way too spammy
            if metadata['GUIDToSlot']:
                guid_to_slot = { k.decode(): v.decode() for k, v in metadata['GUIDToSlot'].items() }
            if metadata['slotToGUID']:
                slot_to_guid = { k.decode(): v.decode() for k, v in metadata['slotToGUID'].items() }
        elif event == "CHARACTER_DATA_UPDATE":
            if not quiet: print("updating character data", end=' ')
            update_index = record[2]
            characters = get_characters(character_updates, update_index)
            for char in characters:
                guid = char['GUID']
                scores[guid].set_character_data(char)
                #print(character_string(char))    # just for finding field names
                if not quiet: print(char['playerName'] + ("*" if scores[guid].talents_known() else ""), end=" ")
            if not quiet: print('')

            if not quiet: print('updating abilities..')
            character_abilities = get_character_abilities(characters)
    elif rectype == 'inf':
        inference_time, inference_trace, inference_attempt, \
            event_time, event_trace, event_id, event_source_guid, event_slot, batch_id, \
            inferred_ability_id, certain, inferred_caster_guid, \
            logic, conf, reqs = record

        # until proven otherwise, score this under the event source actor 
        actor = event_source_guid

        # all combat log records in a small time interval around the event that triggered inference
        log_records = match_inference_to_combatlog(record, combatlog_event_times, combatlog_events)
        if not log_records:
            scores[actor].add_not_logged(event_trace)
            #print("NO LOG", spells[inferred_ability_id] if inferred_ability_id is not None else "none", slot_to_guid[event_slot])
        else:
            # did we infer this ability?
            if inferred_ability_id:
                # if we made an inference, assign the score to our guessed caster
                # XXX: TODO: would be ideal to get an exact combat log match from which
                # the true caster and spell ID could be derived.
                actor = inferred_caster_guid

                # Does the combat log indicate that this ability was cast near the event time?
                matches = [ rec for rec in log_records
                    if spells[rec['ability_id']] == spells[inferred_ability_id] and
                        rec['caster_guid'] == inferred_caster_guid and
                        event_type_match(rec['event'], event_trace)]

                scores[actor].add_inference(inferred_ability_id, matches, log_records)
            else:
                # did we know the abilities of the player that initiated the event?
                # we can infer externals on such a player, but not that player's own abilities
                scores[actor].add_no_inference(event_trace, log_records)


for guid, score in scores.items():
    print(score.player_label(), '-------------------------------------------------------------')
    print(score)
    score.print_false_positives()
