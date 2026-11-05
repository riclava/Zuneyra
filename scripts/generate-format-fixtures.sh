#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=ZuneyraTests/Fixtures/Formats
mkdir -p "$out"
base=(-hide_banner -loglevel error -y -f lavfi -i 'sine=frequency=440:sample_rate=44100:duration=2' -metadata title='Format Test' -metadata artist='Generated' -metadata album='Codec Matrix' -metadata track='2' -metadata disc='2' -metadata REPLAYGAIN_TRACK_GAIN='-6.0 dB' -metadata REPLAYGAIN_TRACK_PEAK='0.8')
ffmpeg "${base[@]}" -c:a libmp3lame -id3v2_version 3 "$out/test.mp3"
ffmpeg "${base[@]}" -c:a aac "$out/test-aac.m4a"
ffmpeg "${base[@]}" -c:a alac "$out/test-alac.m4a"
ffmpeg "${base[@]}" -c:a flac -sample_fmt s32 "$out/test.flac"
ffmpeg "${base[@]}" -c:a pcm_s16le "$out/test.wav"
ffmpeg "${base[@]}" -c:a pcm_s16be "$out/test.aiff"
ffmpeg -hide_banner -loglevel error -y -i "$out/test.flac" -c:a copy -metadata lyrics='[00:00.50]Generated lyric' "$out/test-lyrics.flac"
