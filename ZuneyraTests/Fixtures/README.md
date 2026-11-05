# Generated test audio

`silence-with-cover.mp3` contains 0.2 seconds of generated mono silence (8 kHz,
32 kbps MP3), with a generated 1×1 solid-color PNG embedded as ID3v2.3 cover art.
It contains no third-party music or artwork. Used to verify cache removal and
reconstruction from the managed audio file.

Audio generated locally with FFmpeg's `anullsrc` and `libmp3lame`; the PNG was
created with Core Graphics and ImageIO.

`Formats/` contains two-second 440 Hz synthetic signals generated with
`scripts/generate-format-fixtures.sh` (FFmpeg). MP3, AAC/M4A, ALAC/M4A, FLAC,
WAV, and AIFF fixtures exercise actual decoding and frame seeking. Tags include
generated titles, disc/track numbers, and ReplayGain fields where supported.
No user music is included. These samples do not establish every bit depth,
channel layout, encoder delay, or hardware output combination.

`Formats/test-lyrics.flac` adds generated timestamped lyrics to the FLAC fixture
to verify that legacy library rows can discover embedded lyrics during rescanning.
