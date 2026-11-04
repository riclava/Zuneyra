# Generated test audio

`silence-with-cover.mp3` contains 0.2 seconds of generated mono silence (8 kHz,
32 kbps MP3), with a generated 1×1 solid-color PNG embedded as ID3v2.3 cover art.
It contains no third-party music or artwork. Used to verify cache removal and
reconstruction from the managed audio file.

Audio generated locally with FFmpeg's `anullsrc` and `libmp3lame`; the PNG was
created with Core Graphics and ImageIO.
