#!/usr/bin/env python3
"""Compose original game scores and render them with an external GM SoundFont.

Python 3.10+ and the standard library suffice for --midi-only. Audio rendering
additionally requires FluidSynth, a licensed GM SoundFont and FFmpeg. No network
service is called. The melodies/arrangements below are authored for this game;
instrument samples come from the supplied SoundFont rather than oscillators.

Example:
    python tools/compose_music_v13.py --midi-only
    python tools/compose_music_v13.py --fluidsynth PATH --soundfont PATH --ffmpeg PATH

For each song FluidSynth renders three complete cycles. The middle cycle is
extracted at exact PCM sample boundaries, retaining the preceding reverb tail.
It is gain-normalized with a -1.8 dBFS peak ceiling, gently tapered over 8 ms at
the two loop edges to prevent phase clicks, then encoded as 160 kbps MP3.
Original one-cycle MIDI files and a provenance/measurement manifest are retained.
Large intermediate WAV files stay outside the Godot project by default.
"""

from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
import random
import re
import shutil
import struct
import subprocess
import sys
import wave
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import story_audio_manifest


PROJECT = Path(__file__).resolve().parents[1]
PPQ = 480
BARS = 32
BEATS = BARS * 4
SAMPLE_RATE = 44100
MAJOR = (0, 2, 4, 5, 7, 9, 11)
MINOR = (0, 2, 3, 5, 7, 8, 10)

# Zero-based GM program numbers. Every song has its own authored eight-bar theme;
# the second half develops it through a new register, answer and accompaniment.
# Phrase tokens are diatonic_degree:quarter_note_duration; r denotes a rest.
SCORES: dict[str, dict[str, Any]] = {
    "region_0": {
        "key": 62, "scale": MAJOR, "texture": "village",
        "programs": [73, 24, 49, 42, 11, 45],
        "chords": [0, 4, 5, 3, 0, 1, 4, 4],
        "theme": [
            "2:1 4:.5 5:.5 4:1 2:.5 r:.5", "1:.5 2:.5 4:1 3:1 1:1",
            "2:.5 4:.5 5:1 7:1 5:1", "4:1 2:1 1:1 r:1",
            "0:1 2:.5 4:.5 7:1 6:.5 5:.5", "3:1 5:1 4:.5 3:.5 2:1",
            "1:.5 2:.5 4:1 6:1 4:1", "3:1 1:1 2:1 r:1",
        ],
    },
    "region_1": {
        "key": 64, "scale": MINOR, "texture": "forest",
        "programs": [73, 46, 49, 42, 8, 68],
        "chords": [0, 5, 2, 6, 0, 3, 4, 4],
        "theme": [
            "4:1.5 2:.5 0:1 r:1", "2:.5 3:.5 5:1 4:1 r:1",
            "7:1 6:.5 4:.5 2:1 4:1", "3:2 1:1 r:1",
            "0:.5 2:.5 4:1 7:1 6:1", "5:1.5 3:.5 2:1 r:1",
            "1:1 4:1 3:.5 2:.5 1:1", "2:2 0:1 r:1",
        ],
    },
    "region_2": {
        "key": 67, "scale": MAJOR, "texture": "wind",
        "programs": [73, 25, 48, 45, 71, 24],
        "chords": [0, 4, 5, 3, 0, 3, 1, 4],
        "theme": [
            "0:.5 2:.5 4:1 5:.5 4:.5 2:1", "1:1 4:.5 6:.5 4:1 r:1",
            "5:.5 7:.5 9:1 7:.5 5:.5 4:1", "3:1 5:1 4:.5 2:.5 r:1",
            "7:1 4:.5 2:.5 0:1 2:1", "3:.5 4:.5 5:1 7:1 5:1",
            "6:1 4:1 2:.5 1:.5 3:1", "4:1.5 1:.5 2:1 r:1",
        ],
    },
    "region_3": {
        "key": 65, "scale": MAJOR, "texture": "water",
        "programs": [12, 46, 49, 42, 73, 0],
        "chords": [0, 2, 3, 4, 5, 3, 1, 4],
        "theme": [
            "4:.75 2:.25 0:1 2:.5 4:.5 7:1", "6:1 4:.5 2:.5 1:1 r:1",
            "3:.5 5:.5 7:1 8:.5 7:.5 5:1", "4:1.5 3:.5 1:1 r:1",
            "5:1 7:.5 9:.5 7:1 5:1", "4:.5 3:.5 5:1 2:1 r:1",
            "1:1 3:.5 5:.5 6:1 3:1", "4:.5 3:.5 1:1 2:1 r:1",
        ],
    },
    "region_4": {
        "key": 62, "scale": MINOR, "texture": "ruins",
        "programs": [8, 46, 48, 43, 70, 14],
        "chords": [0, 5, 3, 4, 0, 2, 5, 4],
        "theme": [
            "0:2 4:1 2:.5 r:.5", "5:1.5 4:.5 2:1 r:1",
            "3:1 7:1 5:1 3:1", "4:2 1:1 r:1",
            "7:1.5 4:.5 2:1 0:1", "2:1 6:1 4:1 r:1",
            "5:1.5 3:.5 2:1 1:1", "4:2 2:1 r:1",
        ],
    },
    "region_5": {
        "key": 60, "scale": MINOR, "texture": "rift",
        "programs": [42, 48, 49, 43, 60, 47],
        "chords": [0, 5, 3, 4, 0, 6, 5, 4],
        "theme": [
            "0:1 0:.5 2:.5 4:1 3:1", "5:1.5 4:.5 2:1 r:1",
            "3:.5 4:.5 5:1 7:1 5:1", "4:1 1:1 2:1 r:1",
            "7:1 4:.5 2:.5 0:1 2:1", "6:1 5:1 3:.5 2:.5 1:1",
            "5:1 3:.5 2:.5 1:1 3:1", "4:1.5 2:.5 1:1 r:1",
        ],
    },
    "region_6": {
        "key": 60, "scale": MAJOR, "texture": "island",
        "programs": [0, 46, 49, 42, 73, 8],
        "chords": [0, 3, 5, 4, 0, 2, 3, 4],
        "theme": [
            "4:1 7:1 6:.5 4:.5 2:1", "3:1.5 5:.5 4:1 r:1",
            "5:1 7:.5 9:.5 8:1 7:1", "6:1 4:1 2:1 r:1",
            "7:1.5 4:.5 2:1 0:1", "2:.5 4:.5 6:1 7:1 4:1",
            "5:1 3:1 2:.5 1:.5 3:1", "4:1 6:1 2:1 r:1",
        ],
    },
    "title": {
        "key": 62, "scale": MAJOR, "texture": "title",
        "programs": [0, 46, 49, 42, 73, 11],
        "chords": [0, 4, 5, 3, 0, 1, 3, 4],
        "theme": [
            "0:1 2:.5 4:.5 7:1 6:1", "4:1.5 2:.5 1:1 r:1",
            "5:1 7:1 9:.5 7:.5 5:1", "3:2 2:1 r:1",
            "4:1 7:1 6:.5 4:.5 2:1", "3:1 5:1 4:.5 3:.5 2:1",
            "1:1 3:.5 5:.5 7:1 5:1", "4:2 2:1 r:1",
        ],
    },
    "battle": {
        "key": 62, "scale": MINOR, "texture": "battle",
        "programs": [71, 45, 48, 43, 73, 47],
        "chords": [0, 0, 5, 6, 0, 3, 5, 4],
        "theme": [
            "0:.5 0:.5 2:.5 4:.5 3:1 2:1", "4:.5 3:.5 2:.5 0:.5 1:1 r:1",
            "5:1 7:.5 5:.5 4:.5 2:.5 3:1", "6:.5 5:.5 3:1 1:1 r:1",
            "7:.5 4:.5 7:.5 9:.5 7:1 4:1", "3:.5 5:.5 7:1 5:.5 3:.5 2:1",
            "5:.5 3:.5 2:1 1:.5 3:.5 4:1", "4:1 2:.5 1:.5 2:1 r:1",
        ],
    },
    "boss": {
        "key": 62, "scale": MINOR, "texture": "boss",
        "programs": [60, 48, 49, 43, 68, 47],
        "chords": [0, 5, 3, 4, 0, 6, 5, 4],
        "theme": [
            "0:1.5 4:.5 3:1 2:1", "5:1 4:.5 2:.5 0:1 r:1",
            "3:1 5:1 7:1 5:1", "4:1.5 2:.5 1:1 r:1",
            "7:1.5 4:.5 2:1 0:1", "6:1 5:1 3:.5 2:.5 1:1",
            "5:1 3:1 2:.5 1:.5 3:1", "4:2 1:1 r:1",
        ],
    },
}


def varlen(value: int) -> bytes:
    if value < 0:
        raise ValueError("Negative MIDI delta.")
    output = bytearray([value & 127])
    while value > 127:
        value >>= 7
        output.insert(0, (value & 127) | 128)
    return bytes(output)


@dataclass
class Track:
    name: str
    channel: int
    program: int
    volume: int
    pan: int
    events: list[tuple[int, int, bytes]] = field(default_factory=list)
    notes: int = 0

    def note(self, beat: float, duration: float, pitch: int, velocity: int) -> None:
        start = max(0, round(beat * PPQ))
        end = max(start + 1, round((beat + duration) * PPQ))
        pitch = max(24, min(108, int(pitch)))
        velocity = max(1, min(115, int(velocity)))
        self.events.append((start, 2, bytes([0x90 | self.channel, pitch, velocity])))
        self.events.append((end, 1, bytes([0x80 | self.channel, pitch, 0])))
        self.notes += 1

    def bytes(self, cycles: int) -> bytes:
        name = self.name.encode("utf-8")
        events = [(0, 0, b"\xff\x03" + varlen(len(name)) + name)]
        events.extend((0, 0, bytes([0xB0 | self.channel, cc, value])) for cc, value in (
            (0, 0), (32, 0), (7, self.volume), (10, self.pan), (11, 110), (91, 28), (93, 0)
        ))
        events.append((0, 0, bytes([0xC0 | self.channel, self.program])))
        cycle_ticks = BEATS * PPQ
        for cycle in range(cycles):
            events.extend((tick + cycle * cycle_ticks, priority, value) for tick, priority, value in self.events)
        end_tick = cycle_ticks * cycles
        events.append((end_tick + 1, 3, bytes([0xB0 | self.channel, 123, 0])))
        events.append((end_tick + 2, 4, b"\xff\x2f\x00"))
        events.sort(key=lambda event: (event[0], event[1]))
        data = bytearray()
        previous = 0
        for tick, _, value in events:
            data += varlen(tick - previous) + value
            previous = tick
        return b"MTrk" + struct.pack(">I", len(data)) + data


def pitch(score: dict[str, Any], degree: int, octave: int = 0) -> int:
    return score["key"] + 12 * (degree // 7 + octave) + score["scale"][degree % 7]


def nearest_chord_degree(degree: int, root: int) -> int:
    candidates = [root + interval + octave * 7 for interval in (0, 2, 4) for octave in range(-2, 4)]
    return min(candidates, key=lambda item: (abs(item - degree), item))


def phrase_tokens(phrase: str) -> list[tuple[int | None, float]]:
    result = []
    for token in phrase.split():
        degree, duration = token.split(":")
        result.append((None if degree == "r" else int(degree), float(duration)))
    if abs(sum(duration for _, duration in result) - 4.0) > 0.00001:
        raise ValueError(f"Phrase is not one 4/4 bar: {phrase}")
    return result


def arrange(score_id: str) -> list[Track]:
    score = SCORES[score_id]
    rng = random.Random("StarLanternIsland-score-v13:" + score_id)
    programs = score["programs"]
    tracks = [
        Track("Melody", 0, programs[0], 92, 69),
        Track("Acoustic figure", 1, programs[1], 78, 43),
        Track("Warm sustained harmony", 2, programs[2], 61, 70),
        Track("Bass", 3, programs[3], 83, 62),
        Track("Answer", 4, programs[4], 66, 85),
        Track("Orchestral detail", 5, programs[5], 65, 53),
        Track("Acoustic percussion", 9, 0, 67, 64),
    ]
    lead, accompaniment, pad, bass, answer, detail, drums = tracks
    texture = score["texture"]
    vigorous = texture in ("battle", "boss", "rift")

    def note(track: Track, beat: float, duration: float, degree: int, velocity: float, octave: int = 0, spread: float = 0.012) -> None:
        # Small deterministic timing/velocity variations; no random runtime music.
        start = max(0.0, min(BEATS - 0.02, beat + rng.uniform(-spread, spread)))
        duration = max(0.04, min(duration, BEATS - start - 0.005))
        track.note(start, duration, pitch(score, degree, octave), round(velocity + rng.uniform(-4, 4)))

    for bar in range(BARS):
        section = bar // 8
        local = bar % 8
        start = bar * 4.0
        chord = score["chords"][local]
        energy = (0.83, 0.94, 1.0, 0.9)[section]

        # Melodic development: A, embellished A, higher answer, resolving A.
        theme_index = (local + 3) % 8 if section == 2 else local
        phrase = phrase_tokens(score["theme"][theme_index])
        cursor = 0.0
        for degree, duration in phrase:
            if degree is not None:
                developed = degree + (2 if section == 2 else 0)
                if duration >= 1.0 and (abs(cursor) < 0.01 or abs(cursor - 2) < 0.01):
                    developed = nearest_chord_degree(developed, chord)
                register = -1 if texture == "rift" else 0
                if section == 2 and texture in ("title", "island", "water"):
                    register = 1
                articulation = 0.91 if texture in ("forest", "title", "island", "ruins") else 0.79
                note(lead, start + cursor, duration * articulation, developed, 79 * energy, register)
                if section == 1 and duration >= 1.5 and local % 2 == 0:
                    note(detail, start + cursor + duration - 0.35, 0.24, developed + 2, 43, 1)
            cursor += duration

        # Voicings retain a common middle register and move independent of bass.
        triad = [chord, chord + 2, chord + 4]
        voicing = [degree - 7 if degree > 5 else degree for degree in triad]
        if texture not in ("battle", "wind") or section > 0:
            for j, degree in enumerate(voicing):
                note(pad, start + j * 0.025, 3.82, degree, (49 if vigorous else 43) * energy, -1, 0.004)
        note(bass, start + 0.005, 1.65 if vigorous else 2.8, chord, 67 * energy, -2)
        if texture not in ("forest", "ruins", "island") or local % 2 == 1:
            note(bass, start + 2.0, 1.65, chord + 4, 57 * energy, -2)
        if texture in ("battle", "wind", "rift", "boss"):
            note(bass, start + 3.5, 0.33, chord + (6 if local == 7 else 2), 52 * energy, -2)

        if texture == "village":
            for i, degree in enumerate((0, 4, 2, 4, 7, 4, 2, 4)):
                note(accompaniment, start + i * 0.5, 0.44, chord + degree, (56 if i % 2 == 0 else 45) * energy, -1)
            if local in (1, 3, 5):
                for i, degree in enumerate((4, 2, 0)):
                    note(answer, start + 2.25 + i * 0.5, 0.38, chord + degree, 40, 1)
        elif texture == "forest":
            for i, degree in enumerate((0, 4, 7, 9, 7, 4)):
                note(accompaniment, start + i * (2 / 3), 0.75, chord + degree, (47 if i % 3 == 0 else 39) * energy, -1)
            if local in (0, 3, 6):
                note(answer, start + 1.5, 1.7, chord + 7, 39, 1)
            if section > 0 and local % 2 == 1:
                note(detail, start + 2.0, 1.6, chord + 2, 41, 0)
        elif texture == "wind":
            for beat in (0, 1.5, 2, 3.5):
                for j, degree in enumerate((0, 2, 4)):
                    note(accompaniment, start + beat + j * 0.019, 0.43, chord + degree, (54 if beat in (0, 2) else 43) * energy, -1)
            if section in (1, 2):
                for i, degree in enumerate((4, 2, 0, 2)):
                    note(answer, start + i, 0.65, chord + degree, 44, 0)
        elif texture == "water":
            for i, degree in enumerate((0, 4, 7, 9, 11, 9, 7, 4)):
                note(accompaniment, start + i * 0.5, 0.8, chord + degree, (44 if i % 2 else 49) * energy, -1)
            for i, degree in enumerate((0, 2, 4)):
                note(detail, start + 0.02 + i * 0.025, 3.4, chord + degree, 36, 0)
            if local % 2 == 1:
                note(answer, start + 1.0, 1.75, chord + 4, 44, 0)
        elif texture == "ruins":
            for i, degree in enumerate((0, 4, 9, 7)):
                note(accompaniment, start + i, 1.4, chord + degree, 38 * energy, -1)
            if local in (1, 4, 6):
                note(answer, start + 0.25, 2.7, chord, 45, -1)
            if local in (0, 4):
                note(detail, start + 0.08, 1.8, chord + 7, 25, 0)
        elif texture == "rift":
            for i, degree in enumerate((0, 4, 7, 4, 0, 4, 9, 4)):
                note(accompaniment, start + i * 0.5, 0.31, chord + degree, (56 if i % 2 == 0 else 45) * energy, -1)
            if local in (0, 2, 4, 6):
                note(answer, start, 1.7, chord + 4, 52 * energy, -1)
                note(detail, start + 2.0, 0.6, chord, 53, -2)
        elif texture in ("title", "island"):
            figure = (0, 4, 7, 9, 7, 4, 2, 4) if texture == "title" else (0, 7, 4, 9, 7, 11, 9, 4)
            for i, degree in enumerate(figure):
                note(accompaniment, start + i * 0.5, 0.9, chord + degree, (43 if i % 2 else 50) * energy, -1)
            if section in (1, 2) and local % 2 == 0:
                for beat, degree, duration in ((0.5, 4, 1.2), (2.0, 2, 1.6)):
                    note(answer, start + beat, duration, chord + degree, 43, 0)
            if local in (0, 4) and section > 0:
                note(detail, start + 3.0, 0.85, chord + 7, 31, 1)
        elif texture == "battle":
            for i, degree in enumerate((0, 4, 2, 4, 7, 4, 2, 4)):
                note(accompaniment, start + i * 0.5, 0.3, chord + degree, (67 if i % 2 == 0 else 54) * energy, -1)
            if section > 0:
                for i, degree in enumerate((7, 5, 4, 2)):
                    note(answer, start + i, 0.56, chord + degree, 45, 0)
            note(detail, start, 0.4, chord, 48 * energy, -2)
        elif texture == "boss":
            for i, degree in enumerate((0, 4, 7, 4, 2, 4, 7, 4)):
                note(accompaniment, start + i * 0.5, 0.32, chord + degree, (61 if i % 2 == 0 else 49) * energy, -1)
            if section in (1, 2):
                note(answer, start + 1.0, 1.5, chord + 7, 50, 0)
            for beat, strength in ((0, 61), (2.5, 48)):
                note(detail, start + beat, 0.6, chord, strength * energy, -2)

        # Acoustic percussion only; the calm regions remain mostly unmetered.
        def drum(beat: float, key: int, strength: int, duration: float = 0.11) -> None:
            drums.note(start + beat, duration, key, strength + rng.randint(-3, 3))

        if texture in ("wind", "village"):
            for beat in (0, 1, 2, 3):
                drum(beat + 0.5, 70, 28 if texture == "village" else 36)
            if texture == "wind":
                drum(0, 36, 39)
                drum(2, 37, 37)
            elif section > 0:
                drum(2, 37, 27)
        elif vigorous:
            for beat in (0, 2):
                drum(beat, 36, 56 if texture == "boss" else 46)
            for beat in (1, 3):
                drum(beat, 38 if texture == "battle" else 45, 40)
            for i in range(8):
                drum(i * 0.5, 42, 27 if i % 2 else 34)
            if local == 7:
                for beat, key in ((2.5, 47), (3, 45), (3.5, 41)):
                    drum(beat, key, 42)
            if local == 0 and section > 0:
                drum(0, 49, 34, 1.8)
        elif texture in ("water", "island") and local in (0, 4):
            drum(2.5, 81, 24, 0.3)
    return tracks


def midi_bytes(score_id: str, bpm: int, tracks: list[Track], cycles: int) -> bytes:
    title = ("Star Lantern Island / " + score_id).encode("ascii")
    tempo = round(60_000_000 / bpm)
    conductor = (
        b"\x00\xff\x03" + varlen(len(title)) + title
        + b"\x00\xff\x51\x03" + tempo.to_bytes(3, "big")
        + b"\x00\xff\x58\x04\x04\x02\x18\x08"
        + varlen(BEATS * PPQ * cycles + 3) + b"\xff\x2f\x00"
    )
    header = b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks) + 1, PPQ)
    return header + b"MTrk" + struct.pack(">I", len(conductor)) + conductor + b"".join(
        track.bytes(cycles) for track in tracks
    )


def executable(path: str | None, name: str) -> str:
    resolved = str(Path(path).resolve()) if path else shutil.which(name)
    if not resolved or not Path(resolved).is_file():
        raise ValueError(f"{name} not found; pass --{name} with its executable path.")
    return resolved


def run(command: list[str], log: Path) -> None:
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    log.write_bytes(result.stdout)
    if result.returncode:
        raise RuntimeError(f"External tool failed ({result.returncode}). See {log}")


def extract_loop(source: Path, target: Path, seconds: float) -> dict[str, float | int]:
    with wave.open(str(source), "rb") as wav:
        if wav.getsampwidth() != 2 or wav.getcomptype() != "NONE":
            raise ValueError("FluidSynth output must be uncompressed 16-bit PCM.")
        rate, channels = wav.getframerate(), wav.getnchannels()
        first = round(seconds * rate)
        last = round(seconds * 2 * rate)
        if wav.getnframes() < last:
            raise ValueError("Rendered audio is shorter than two complete musical cycles.")
        wav.setpos(first)
        samples = array.array("h", wav.readframes(last - first))
    if sys.byteorder != "little":
        samples.byteswap()
    peak = max(abs(value) for value in samples)
    if peak == 0:
        raise ValueError("Rendered loop is silent.")
    sum_squares = sum(value * value for value in samples)
    rms = math.sqrt(sum_squares / len(samples))
    # Upward gain is capped by both musical RMS and a safe pre-encode peak.
    ceiling = 32767 * 10 ** (-1.8 / 20)
    target_rms = 32767 * 10 ** (-20.5 / 20)
    gain = min(ceiling / peak, target_rms / rms)
    normalized = array.array("h", (max(-32768, min(32767, round(value * gain))) for value in samples))
    # SoundFont chorus/LFO/sample phases need not be periodic with the MIDI bar.
    # An 8 ms raised-cosine taper prevents a discontinuity without a long audible
    # gap; unlike an abrupt cut it also brings the boundary derivative to zero.
    edge_frames = min(round(rate * 0.008), (last - first) // 2)
    for frame in range(edge_frames):
        weight = 0.5 - 0.5 * math.cos(math.pi * frame / (edge_frames - 1))
        for channel in range(channels):
            head = frame * channels + channel
            tail = len(normalized) - (frame + 1) * channels + channel
            normalized[head] = round(normalized[head] * weight)
            normalized[tail] = round(normalized[tail] * weight)
    post_peak = max(abs(value) for value in normalized)
    post_rms = math.sqrt(sum(value * value for value in normalized) / len(normalized))
    # Compare derivative across the seam to ordinary PCM derivatives. Reverb and
    # instrument note-ons may create transients, so retain the actual measurement.
    seam = max(abs(normalized[channel] - normalized[-channels + channel]) for channel in range(channels))
    if sys.byteorder != "little":
        normalized.byteswap()
    with wave.open(str(target), "wb") as wav:
        wav.setnchannels(channels)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(normalized.tobytes())
    return {
        "sample_rate": rate,
        "channels": channels,
        "frames": last - first,
        "duration_seconds": round((last - first) / rate, 6),
        "gain_db": round(20 * math.log10(gain), 3),
        "peak_dbfs": round(20 * math.log10(post_peak / 32768), 3),
        "rms_dbfs": round(20 * math.log10(post_rms / 32768), 3),
        "seam_sample_delta_dbfs": round(20 * math.log10(max(1, seam) / 32768), 3),
        "edge_cosine_fade_seconds": 0.008,
    }


def verify_encoded(ffmpeg: str, mp3: Path, work: Path) -> dict[str, float | int]:
    decoded = work / (mp3.stem + ".decoded.wav")
    run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(mp3), "-c:a", "pcm_s16le", str(decoded)], work / (mp3.stem + ".decode.log"))
    with wave.open(str(decoded), "rb") as wav:
        channels, frames, rate = wav.getnchannels(), wav.getnframes(), wav.getframerate()
        values = array.array("h", wav.readframes(frames))
    if sys.byteorder != "little":
        values.byteswap()
    peak = max(abs(value) for value in values)
    clipping = sum(1 for value in values if abs(value) >= 32767)
    seam = max(abs(values[channel] - values[-channels + channel]) for channel in range(channels))
    if clipping or peak == 0:
        raise ValueError(f"MP3 validation failed for {mp3.name}: clipping={clipping}, peak={peak}.")
    return {
        "decoded_frames": frames,
        "decoded_duration_seconds": round(frames / rate, 6),
        "decoded_channels": channels,
        "decoded_peak_dbfs": round(20 * math.log10(peak / 32768), 3),
        "decoded_clipping_sample_count": clipping,
        "decoded_seam_delta_dbfs": round(20 * math.log10(max(1, seam) / 32768), 3),
    }


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--project", type=Path, default=PROJECT)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--work-dir", type=Path)
    parser.add_argument("--fluidsynth")
    parser.add_argument("--soundfont", type=Path)
    parser.add_argument("--ffmpeg")
    parser.add_argument("--midi-only", action="store_true")
    parser.add_argument("--reuse-rendered", action="store_true", help="Postprocess an existing three-cycle WAV only if its MIDI and SoundFont still match")
    parser.add_argument("--only", nargs="+", choices=list(SCORES), help="Render selected scores; keeps other manifest records")
    args = parser.parse_args()
    project = args.project.resolve()
    output = args.output_dir.resolve() if args.output_dir else project / "assets/audio_v13/music"
    work = args.work_dir.resolve() if args.work_dir else project.parents[1] / ".build-toolchain/audio/render_work"
    try:
        audio_manifest = story_audio_manifest.build_manifest(project)
        descriptors = {
            Path(entry["path"]).stem: entry
            for entry in [*audio_manifest["music"]["contexts"].values(), *audio_manifest["music"]["regions"]]
        }
        selected = args.only or list(SCORES)
        source_dir = output / "source"
        source_dir.mkdir(parents=True, exist_ok=True)
        (source_dir / ".gdignore").write_text("", encoding="utf-8")
        soundfont = args.soundfont.resolve() if args.soundfont else None
        fluidsynth = ffmpeg = None
        soundfont_sha256 = None
        if not args.midi_only:
            fluidsynth = executable(args.fluidsynth, "fluidsynth")
            ffmpeg = executable(args.ffmpeg, "ffmpeg")
            if soundfont is None or not soundfont.is_file():
                raise ValueError("Pass --soundfont with a licensed General MIDI .sf2 file.")
            soundfont_sha256 = file_hash(soundfont)
            work.mkdir(parents=True, exist_ok=True)
        index_path = source_dir / "score_manifest.json"
        previous = json.loads(index_path.read_text(encoding="utf-8")) if index_path.is_file() else {}
        records = previous.get("tracks", {})
        for score_id in selected:
            descriptor = descriptors[score_id]
            bpm = int(descriptor["bpm"])
            tempo_microseconds = round(60_000_000 / bpm)
            loop_seconds = BEATS * tempo_microseconds / 1_000_000
            tracks = arrange(score_id)
            midi = source_dir / (score_id + ".mid")
            midi.write_bytes(midi_bytes(score_id, bpm, tracks, 1))
            record: dict[str, Any] = {
                "name": descriptor["name"], "bars": BARS, "time_signature": [4, 4],
                "bpm": bpm, "tempo_microseconds": tempo_microseconds,
                "loop_seconds": round(loop_seconds, 6),
                "key_midi_note": SCORES[score_id]["key"],
                "mode": "major" if SCORES[score_id]["scale"] == MAJOR else "natural_minor",
                "note_count": sum(track.notes for track in tracks),
                "tracks": [{"name": t.name, "channel": t.channel + 1, "gm_program": t.program + 1, "notes": t.notes} for t in tracks],
                "midi": f"source/{score_id}.mid", "midi_sha256": file_hash(midi),
                "melody_provenance": "Original authored theme and arrangement in tools/compose_music_v13.py; no external melody or audio recording used.",
            }
            if args.midi_only and records.get(score_id, {}).get("midi_sha256") == record["midi_sha256"]:
                # Regenerating identical editable MIDI must not erase measurements
                # from an existing, still-matching rendered recording.
                for key in ("pcm_measurements", "mp3_measurements", "path", "bytes", "sha256", "soundfont"):
                    if key in records[score_id]:
                        record[key] = records[score_id][key]
            if not args.midi_only:
                render_midi = work / (score_id + ".three_cycles.mid")
                rendered = work / (score_id + ".three_cycles.wav")
                middle = work / (score_id + ".middle.wav")
                render_bytes = midi_bytes(score_id, bpm, tracks, 3)
                if args.reuse_rendered:
                    same_font = records.get(score_id, {}).get("soundfont", {}).get("sha256") == soundfont_sha256
                    if not (same_font and rendered.is_file() and render_midi.is_file() and render_midi.read_bytes() == render_bytes):
                        raise ValueError(f"{score_id}: existing rendered WAV/MIDI/SoundFont do not match; rerun without --reuse-rendered.")
                else:
                    render_midi.write_bytes(render_bytes)
                    run([
                        fluidsynth, "-ni", "-g", "0.6", "-r", str(SAMPLE_RATE),
                        "-F", str(rendered), "-T", "wav", "-O", "s16",
                        "-o", "synth.reverb.active=1", "-o", "synth.reverb.room-size=0.55",
                        "-o", "synth.reverb.damp=0.35", "-o", "synth.reverb.level=0.22",
                        "-o", "synth.chorus.active=0", str(soundfont), str(render_midi),
                    ], work / (score_id + ".fluidsynth.log"))
                record["pcm_measurements"] = extract_loop(rendered, middle, loop_seconds)
                mp3 = output / (score_id + ".mp3")
                run([
                    ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(middle),
                    "-map_metadata", "-1", "-codec:a", "libmp3lame", "-b:a", "160k",
                    "-ar", str(SAMPLE_RATE), "-ac", "2", "-write_xing", "1",
                    "-metadata", "title=" + descriptor["name"],
                    "-metadata", "artist=Star Lantern Island Original Score", str(mp3),
                ], work / (score_id + ".encode.log"))
                record["mp3_measurements"] = verify_encoded(ffmpeg, mp3, work)
                record["path"] = f"res://assets/audio_v13/music/{score_id}.mp3"
                record["bytes"] = mp3.stat().st_size
                record["sha256"] = file_hash(mp3)
                record["soundfont"] = {
                    "filename": soundfont.name, "sha256": soundfont_sha256,
                    "license": "res://assets/audio_v13/licenses/GeneralUser-LICENSE.txt"
                    if soundfont_sha256 == "9575028c7a1f589f5770fccc8cff2734566af40cd26ed836944e9a5152688cfe" else "Consult the supplied SoundFont license.",
                }
                print(f"RENDERED {score_id}: {loop_seconds:.2f}s, {record['note_count']} notes, "
                      f"peak {record['mp3_measurements']['decoded_peak_dbfs']:.2f} dBFS, no clipping.", flush=True)
            else:
                print(f"MIDI {score_id}: {loop_seconds:.2f}s, {record['note_count']} notes.", flush=True)
            records[score_id] = record
            # Persist completed tracks after each render; a failed later song can retry.
            index_path.write_text(json.dumps({
                "version": 1,
                "generator": "res://tools/compose_music_v13.py",
                "authorship": "Original melodies and arrangements authored for Star Lantern Island.",
                "samples": "Acoustic/orchestral General MIDI instrument samples from the identified external SoundFont; its license is separate from the score.",
                "loop_method": "Render three musical cycles at exact MIDI tempo; retain the middle cycle with the previous cycle's reverb; apply an 8 ms raised-cosine edge taper; encode with LAME gapless metadata. MP3 decoder padding may differ by approximately 1 ms on some lengths.",
                "tracks": records,
            }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        print(f"DONE: {len(selected)} scores. Editable MIDI/provenance: {source_dir}")
        return 0
    except (OSError, ValueError, TypeError, KeyError, RuntimeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
