package main

import "core:log"
import "core:time"
import "core:math"
import pm "vendor:portmidi"
import rl "vendor:raylib"

portmidi_is_error :: proc(err: pm.Error) -> bool {
    return err != pm.Error.NoError && err != pm.Error.NoData && err != pm.Error.GotData
}

AUDIO_BUFFER_SIZE :: 1024
SAMPLE_RATE :: 44100
SAMPLE_STEP :: 1.0 / cast(f32)SAMPLE_RATE

// assumed C0 -> 0
key_number_to_hertz :: proc(num: int) -> f32 {
    return 440.0 * math.pow(2.0, (cast(f32)num - 57.0) / 12.0)
}

w :: proc(hertz: f32) -> f32 {
    return math.PI * 2.0 * hertz
}

Osc_Type :: enum {
    OSC_SINE = 0,
    OSC_SQUARE,
    OSC_TRIANGLE,
    OSC_SAW_ANA,
    OSC_SAW_DIG,
    OSC_NOISE
}

osc :: proc(hertz: f32, dt: f32, type: Osc_Type) -> f32 {
    #partial switch type {
    case .OSC_SINE:
        return math.sin_f32(w(hertz) * dt)
    case .OSC_SQUARE:
        return 1.0 if math.sin_f32(w(hertz) * dt) > 0.0 else -1.0
    case .OSC_TRIANGLE:
        return math.asin_f32(math.sin_f32(w(hertz) * dt)) * (2.0 / math.PI)
    case:
        return 0.0
    }
}

Synthesizer :: struct { 
    // oscillator
    sine_strength: f32,
    square_strength: f32,
    triangle_strength: f32,
    // envelope
    attack_time: f32,
    decay_time: f32,
    sustain_level: f32,
    release_time: f32,
}

synthesizer_create_default :: proc() -> Synthesizer {
    return {
        sine_strength = 1.0,
        square_strength = 0.03,
        triangle_strength = 0.2,
        attack_time = 0.02,
        decay_time = 0.05,
        sustain_level = 0.7,
        release_time = 0.1,
    }
}

synthesizer_sample :: proc(synth: Synthesizer, note: ^Note) -> f32 {
    hertz := key_number_to_hertz(note.semitone + KEY_MIN)
    sample: f32 = 0.0

    sample += synth.sine_strength * osc(hertz, note.sample_dt, .OSC_SINE)
    sample += synth.square_strength * osc(hertz, note.sample_dt, .OSC_SQUARE)
    sample += synth.triangle_strength * osc(hertz, note.sample_dt, .OSC_TRIANGLE)

    total_strength := synth.sine_strength + synth.square_strength + synth.triangle_strength
    if total_strength > 1.0 {
        sample /= total_strength
    }

    dt := note.sample_dt
    env: f32 = 1.0
    if dt < synth.attack_time {
        env = dt / synth.attack_time
    } else if dt < synth.attack_time + synth.decay_time {
        t := (dt - synth.attack_time) / synth.decay_time
        env = 1.0 - (1.0 - synth.sustain_level) * t
    } else if note.playing {
        env = synth.sustain_level
    } else {
        release_dt := dt - f32(note.finish_time) / SAMPLE_RATE
        env = synth.sustain_level * (1.0 - release_dt / synth.release_time)
        if env <= 0.0 {
            note.active = false
            return 0.0
        }
    }
    sample *= env * note.velocity

    note.sample_dt += SAMPLE_STEP
    return sample
}


Null_Instrument :: struct {}

Instrument :: union {
    Null_Instrument,
    Synthesizer,
}

Note :: struct {
    // still pressed
    playing: bool,
    // sound status
    active: bool,
    semitone: int,
    velocity: f32,
    start_time: u64,
    finish_time: u64,
    sample_dt: f32
}

// max note count that can be active at the same time
MAX_PLAYING_NOTE_COUNT_PER_TRACK :: 50

Track :: struct {
    instrument: Instrument,
    gain: f32,
    notes: Circular_Buffer(Note, MAX_PLAYING_NOTE_COUNT_PER_TRACK),
    buffer: [AUDIO_BUFFER_SIZE]f32,
}

track_create :: proc() -> Track {
    return {
        instrument = Null_Instrument{},
        gain = 1.0,
        notes = {},
        buffer = {},
    }
}

track_destroy :: proc(track: ^Track) { }

track_render :: proc(track: ^Track) {
    switch inst in track.instrument {
    case Synthesizer:
        for i in 0..<AUDIO_BUFFER_SIZE {
            sample: f32 = 0.0
            for j in 0..<cb_len(&track.notes) {
                n := &track.notes.data[j]
                if !n.active { continue }
                sample += synthesizer_sample(inst, n)
            }

            track.buffer[i] = sample
        }
    case Null_Instrument:
    }
}

Song :: struct {
    tracks: [dynamic]Track,
    active_track_index: uint,
    buffer: [AUDIO_BUFFER_SIZE]f32,
    stream: rl.AudioStream,
}

song_create :: proc() -> Song {
    rl.SetAudioStreamBufferSizeDefault(AUDIO_BUFFER_SIZE);
    stream := rl.LoadAudioStream(SAMPLE_RATE, 32, 1);
    rl.PlayAudioStream(stream);
    return {
        tracks = make([dynamic]Track),
        active_track_index = 0,
        buffer = {},
        stream = stream,
    }
}

song_render :: proc(song: ^Song) {
    if (rl.IsAudioStreamProcessed(song.stream)) {
        for &it in song.tracks {
            track_render(&it)
        }
        for i in 0..<AUDIO_BUFFER_SIZE {
            sample: f32 = 0.0
            for it in song.tracks {
                sample += it.buffer[i] * it.gain
            }

            song.buffer[i] = sample
        }

        rl.UpdateAudioStream(song.stream, raw_data(song.buffer[:]), AUDIO_BUFFER_SIZE)
    }

}

track_note_on :: proc(track: ^Track, semitone: int, velocity: f32) {
    note := Note{
        playing = true,
        active = true,
        semitone = semitone,
        velocity = velocity,
        sample_dt = 0,
    }
    cb_push(&track.notes, note)
}

track_note_off :: proc(track: ^Track, semitone: int) {
    for i in 0..<cb_len(&track.notes) {
        n := &track.notes.data[i]
        if n.semitone == semitone && n.playing {
            n.playing = false
            n.finish_time = u64(n.sample_dt * SAMPLE_RATE)
            break
        }
    }
}

// computer keyboard play keys, ordered by pitch (Z = C3, MIDI 48)
KEYBOARD_BASE_NOTE :: 48
KEYBOARD_KEYS :: [?]rl.KeyboardKey{
    .Z, .S, .X, .D, .C,
    .V, .G, .B, .H, .N,
    .J, .M, .COMMA, .L, .PERIOD,
}

main :: proc() {
    context.logger = log.create_console_logger(opt = log.Options{.Level})

    if err := pm.Initialize(); portmidi_is_error(err) {
        log.errorf("%s", pm.GetErrorText(err))
    }
    defer pm.Terminate()

    log.infof("total devices %d", pm.CountDevices())
    device_id := pm.GetDefaultInputDeviceID()
    // had to force this
    device_id = 3
    log.infof("default input device id %d", device_id)

    device_info := pm.GetDeviceInfo(device_id)
    if device_info != nil {
        log.infof("%v", device_info^)
    } else {
        log.errorf("device_info is nil")
    }

    stream: pm.Stream = nil
    if err := pm.OpenInput(&stream, device_id, nil, 0, nil, nil); portmidi_is_error(err) {
        log.errorf("%s", pm.GetErrorText(err))
    }
    defer pm.Close(stream)

    rl.InitAudioDevice()
    defer rl.CloseAudioDevice()

    rl.InitWindow(800, 480, "looper")
    rl.SetTargetFPS(60)
    defer rl.CloseWindow()

    song := song_create()
    append(&song.tracks, track_create())
    song.tracks[0].instrument = synthesizer_create_default()
    song.tracks[0].gain = 0.3

    for !rl.WindowShouldClose() {
        track := &song.tracks[song.active_track_index]
        for key, i in KEYBOARD_KEYS {
            if rl.IsKeyPressed(key) {
                track_note_on(track, KEYBOARD_BASE_NOTE + i, 1.0)
            }
            if rl.IsKeyReleased(key) {
                track_note_off(track, KEYBOARD_BASE_NOTE + i)
            }
        }

        err := pm.Poll(stream)
        if cast(int)err > 2 {
            log.errorf("%s", pm.GetErrorText(err))
            break
        }
        buffer_size :: 10
        event_buffer: [buffer_size]pm.Event
        pm.Read(stream, raw_data(event_buffer[:]), buffer_size)

        for e in event_buffer {
            if e.timestamp == 0 {
                continue
            }
            event, key, velocity := pm.MessageStatus(e.message), pm.MessageData1(e.message), pm.MessageData2(e.message)

            switch event {
            case KEY_PRESSED:
                if key < KEY_MIN || key > KEY_MAX {
                    log.warnf("invalid key: 0x%X", key)
                }
                semitone := cast(int)(key - KEY_MIN)
                track_note_on(&song.tracks[song.active_track_index], semitone, cast(f32)velocity / 127.0)
            case KEY_RELEASED:
                if key < KEY_MIN || key > KEY_MAX {
                    log.warnf("invalid key: 0x%X", key)
                }
                semitone := cast(int)(key - KEY_MIN)
                track_note_off(&song.tracks[song.active_track_index], semitone)
            case PAD_PRESSED:
                if key < PAD_MIN || key > PAD_MAX {
                    log.warnf("invalid pad: 0x%X", key)
                }
            case PAD_RELEASED:
                if key < PAD_MIN || key > PAD_MAX {
                    log.warnf("invalid pad: 0x%X", key)
                }
            case KNOB_MODIFIED:
                log.warnf("todo: knobs")
            case:
                log.warnf("unhandled event: 0x%X", event)
            }
        }

        song_render(&song)

        rl.BeginDrawing()
        rl.ClearBackground(rl.GetColor(0x181818))
        rl.EndDrawing()

    }
}
