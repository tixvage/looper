package main

import sdl "vendor:sdl2"

// audio engine
AUDIO_BUFFER_SIZE :: 1024
SAMPLE_RATE :: 44100
SAMPLE_STEP :: 1.0 / cast(f32)SAMPLE_RATE

// looper
LOOPER_BPM :: 120
LOOPER_BEATS_PER_BAR :: 4
LOOPER_BARS :: 1

// window
FPS :: 60
WINDOW_WIDTH :: 1200
WINDOW_HEIGHT :: 720

// keyboard
KEYBOARD_BASE_NOTE :: 48
KEYBOARD_KEYS :: [?]sdl.Keycode{
    .Z, .S, .X, .D, .C,
    .V, .G, .B, .H, .N,
    .J, .M, .COMMA, .L, .PERIOD,
}

// minilab3
KEY_PRESSED    :: 0x90
KEY_RELEASED   :: 0x80
PAD_PRESSED    :: 0x99
PAD_RELEASED   :: 0x89
KNOB_MODIFIED  :: 0xB0

KEY_MIN :: 0x00
KEY_MAX :: 0x78

PAD_MIN :: 0x24
PAD_MAX :: 0x33

VELOCITY_MIN :: 0
VELOCITY_MAX :: 127
