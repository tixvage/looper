package main

import "core:log"
import "core:time"
import "core:math"
import "base:runtime"
import pm "vendor:portmidi"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"

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
        attack_time = 0.01,
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
    if note.duration > 0.0 && dt >= note.duration && note.playing {
        note.playing = false
        note.finish_time = u64(dt * SAMPLE_RATE)
    }
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

// not to be confused with actual audio sample, this 'Sample' refers to an asset, a pre-recorded audio file that gets loaded into the memory
Sample :: struct {
    data: []f32,
}

sample_create_from_file :: proc(path: string) -> Sample {
    return {
        data = load_wav_samples(path)
    }
}

// ...
sample_sample :: proc(sample: Sample, note: ^Note) -> f32 {
    i := int(note.sample_dt * SAMPLE_RATE)
    if i >= len(sample.data) {
        note.active = false
        return 0.0
    }
    note.sample_dt += SAMPLE_STEP
    return sample.data[i] * note.velocity
}


Null_Instrument :: struct {}

Instrument :: union {
    Null_Instrument,
    Synthesizer,
    Sample,
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
    sample_dt: f32,
    duration: f32
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
    case Sample:
        for i in 0..<AUDIO_BUFFER_SIZE {
            sample: f32 = 0.0
            for j in 0..<cb_len(&track.notes) {
                n := &track.notes.data[j]
                if !n.active { continue }
                sample += sample_sample(inst, n)
            }
            track.buffer[i] = sample
        }
    case Null_Instrument:
    }
}

song_render :: proc(song: ^Song) {
    for &it in song.tracks {
        track_render(&it)
    }
    for i in 0..<AUDIO_BUFFER_SIZE {
        looper_step(song)
        sample: f32 = 0.0
        for it in song.tracks {
            sample += it.buffer[i] * it.gain
        }

        song.buffer[i] = sample
    }
}

Looper_Note :: struct {
    track: int,
    beat: f32,
    semitone: int,
    velocity: f32,
    length: f32
}

Looper :: struct {
    bpm: u32,
    beats_per_bar: u32,
    bars: u32,
    pattern: [dynamic]Looper_Note,
    frame: u64,
    beat_frames: u64,
    cursor: int
}

looper_create :: proc(bpm: u32, beats_per_bar: u32, bars: u32) -> Looper {
    return {
        bpm = bpm,
        beats_per_bar = beats_per_bar,
        bars = bars,
        beat_frames = u64(60.0 / f64(bpm) * f64(SAMPLE_RATE)),
    }
}

looper_add_note :: proc(l: ^Looper, track: int, beat: f32, semitone: int, velocity: f32, length: f32) {
    note: Looper_Note = {
        track = track,
        beat = beat,
        semitone = semitone,
        velocity = velocity,
        length = length
    }
    i := 0
    for i < len(l.pattern) && l.pattern[i].beat <= beat {
        i += 1
    }
    inject_at(&l.pattern, i, note)
}

looper_step :: proc(song: ^Song) {
    l := &song.looper
    loop_frames := f64(u64(l.bars) * u64(l.beats_per_bar) * l.beat_frames)
    beat_seconds := 60.0 / f64(l.bpm)

    cur := f64(l.frame)
    for l.cursor < len(l.pattern) {
        note_frame := f64(l.pattern[l.cursor].beat) * f64(l.beat_frames)
        if note_frame > cur {
            break
        }
        note := &l.pattern[l.cursor]
        if note.track < len(song.tracks) {
            duration := f32(f64(note.length) * beat_seconds)
            track_note_on(&song.tracks[note.track], note.semitone, note.velocity, duration)
        }
        l.cursor += 1
    }

    l.frame += 1
    if f64(l.frame) >= loop_frames {
        l.frame = 0
        l.cursor = 0
    }
}

Song :: struct {
    tracks: [dynamic]Track,
    active_track_index: uint,
    device: ma.device,
    buffer: [AUDIO_BUFFER_SIZE]f32,
    render_frame_offset: u32,
    looper: Looper,
}

song_create :: proc() -> ^Song {
    song := new(Song)
    song.tracks = make([dynamic]Track)
    song.active_track_index = 0

    config := ma.device_config_init(ma.device_type.playback)
    config.sampleRate = SAMPLE_RATE
    config.playback.format = ma.format.f32
    config.playback.channels = 1
    config.periodSizeInFrames = AUDIO_BUFFER_SIZE
    config.dataCallback = audio_data_callback
    config.pUserData = song

    if result := ma.device_init(nil, &config, &song.device); result != .SUCCESS {
        log.errorf("failed to init audio device: %v", result)
    }
    if result := ma.device_start(&song.device); result != .SUCCESS {
        log.errorf("failed to start audio device: %v", result)
    }
    return song
}

audio_data_callback :: proc "c" (pDevice: ^ma.device, pOutput, pInput: rawptr, frameCount: u32) {
    context = runtime.default_context()
    song := cast(^Song)pDevice.pUserData
    out := cast([^]f32)pOutput

    offset := song.render_frame_offset
    for i in 0..<cast(int)frameCount {
        if offset == 0 {
            song_render(song)
        }
        out[i] = song.buffer[offset]
        offset += 1
        if offset == AUDIO_BUFFER_SIZE {
            offset = 0
        }
    }
    song.render_frame_offset = cast(u32)offset
}

track_note_on :: proc(track: ^Track, semitone: int, velocity: f32, duration: f32) {
    note := Note{
        playing = true,
        active = true,
        semitone = semitone,
        velocity = velocity,
        sample_dt = 0,
        duration = duration,
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

    if sdl.Init(sdl.INIT_VIDEO) != 0 {
        log.errorf("failed to init sdl: %s", sdl.GetError())
    }
    defer sdl.Quit()

    window := sdl.CreateWindow("looper", sdl.WINDOWPOS_UNDEFINED, sdl.WINDOWPOS_UNDEFINED, WINDOW_WIDTH, WINDOW_HEIGHT, sdl.WINDOW_SHOWN)
    if window == nil {
        log.errorf("failed to create window: %s", sdl.GetError())
    }
    defer sdl.DestroyWindow(window)

    renderer := sdl.CreateRenderer(window, -1, sdl.RENDERER_ACCELERATED)
    if renderer == nil {
        log.errorf("failed to create renderer: %s", sdl.GetError())
    }
    defer sdl.DestroyRenderer(renderer)

    song := song_create()
    defer ma.device_uninit(&song.device)

    song.looper = looper_create(LOOPER_BPM, LOOPER_BEATS_PER_BAR, 1)
    looper_add_note(&song.looper, 0, 0, 0, 1.0, 0)
    looper_add_note(&song.looper, 0, 1, 0, 1.0, 0)
    looper_add_note(&song.looper, 0, 2, 0, 1.0, 0)
    looper_add_note(&song.looper, 0, 3, 0, 1.0, 0)

    append(&song.tracks, track_create())
    song.tracks[0].instrument = sample_create_from_file("tick.wav")
    song.tracks[0].gain = 0.3

    append(&song.tracks, track_create())
    song.tracks[1].instrument = synthesizer_create_default()
    song.tracks[1].gain = 0.3
    song.active_track_index = 1

    frame_ns: u64 = 1_000_000_000 / FPS
    perf_freq := sdl.GetPerformanceFrequency()

    running := true
    for running {
        frame_start := sdl.GetPerformanceCounter()
        track := &song.tracks[song.active_track_index]

        event: sdl.Event
        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                running = false
            case .KEYDOWN:
                if event.key.repeat != 0 {
                    continue
                }
                for key, i in KEYBOARD_KEYS {
                    if event.key.keysym.sym == key {
                        track_note_on(track, KEYBOARD_BASE_NOTE + i, 1.0, 0)
                        break
                    }
                }
            case .KEYUP:
                for key, i in KEYBOARD_KEYS {
                    if event.key.keysym.sym == key {
                        track_note_off(track, KEYBOARD_BASE_NOTE + i)
                        break
                    }
                }
            }
        }

        if stream != nil {
            err := pm.Poll(stream)
            if portmidi_is_error(err) {
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
                    track_note_on(&song.tracks[song.active_track_index], semitone, cast(f32)velocity / 127.0, 0)
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
        }

        sdl.SetRenderDrawColor(renderer, color_unpack(BACKGROUND_COLOR))
        sdl.RenderClear(renderer)
        line_offset := cast(i32)(f32(WINDOW_WIDTH - BAR_LINE_OFFSET_START - BAR_LINE_OFFSET_END) / f32(LOOPER_BEATS_PER_BAR))
        for i in 0..<LOOPER_BEATS_PER_BAR {
            if i == 0 do sdl.SetRenderDrawColor(renderer, color_unpack(BAR_FIRST_LINE_COLOR))
            else do sdl.SetRenderDrawColor(renderer, color_unpack(BAR_OTHER_LINE_COLOR))
            sdl.RenderFillRect(renderer, &{i32(i) * line_offset + BAR_LINE_OFFSET_START, 0, BAR_LINE_WIDTH, WINDOW_HEIGHT})
        }
        sdl.RenderPresent(renderer)

        frame_end := sdl.GetPerformanceCounter()
        elapsed_ns := (frame_end - frame_start) * 1_000_000_000 / perf_freq
        if elapsed_ns < frame_ns {
            sdl.Delay(u32((frame_ns - elapsed_ns) / 1_000_000))
        }
    }
}
