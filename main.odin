package main

import "core:log"
import "core:time"
import "core:math"
import pm "vendor:portmidi"
import rl "vendor:raylib"

AUDIO_BUFFER_SIZE :: 4096
SAMPLE_RATE :: 44100

// assumed C0 -> 0
key_number_to_hertz :: proc(num: int) -> f32 {
    return 440.0 * math.pow(2.0, (cast(f32)num - 57.0) / 12.0)
}

osc :: proc() -> f32 {
    return 0.0
}

Note :: struct {
    active: bool,
    dt: f32
}

notes: [KEY_MAX-KEY_MIN]Note

main :: proc() {
    context.logger = log.create_console_logger(opt = log.Options{.Level})

    if err := pm.Initialize(); cast(int)err > 2 {
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
    }

    stream: pm.Stream = nil
	if err := pm.OpenInput(&stream, device_id, nil, 0, nil, nil); cast(int)err > 2 {
        log.errorf("%s", pm.GetErrorText(err))
    }
    defer pm.Close(stream)

    rl.InitAudioDevice()
    defer rl.CloseAudioDevice()

    rl.SetAudioStreamBufferSizeDefault(AUDIO_BUFFER_SIZE);
    audio_buffer: [AUDIO_BUFFER_SIZE]f32
    audio_stream := rl.LoadAudioStream(SAMPLE_RATE, 32, 1);
    rl.UpdateAudioStream(audio_stream, raw_data(audio_buffer[:]), AUDIO_BUFFER_SIZE)
    rl.PlayAudioStream(audio_stream);

    hertz: f32 = 0.0

    for {
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
                notes[key - KEY_MIN].active = true
            case KEY_RELEASED:
                if key < KEY_MIN || key > KEY_MAX {
                    log.warnf("invalid key: 0x%X", key)
                }
                notes[key - KEY_MIN].active = false
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

        if (rl.IsAudioStreamProcessed(audio_stream)) {
            audio_buffer = {}
            for i in 0..<AUDIO_BUFFER_SIZE {
                sample: f32 = 0.0
                dt_step := 1.0 / cast(f32)SAMPLE_RATE

                for j in 0..<len(notes) {
                    n := &notes[j]
                    if !n.active { continue }
                    current_key := cast(int)j + KEY_MIN
                    key_hertz := key_number_to_hertz(current_key)
                    sample += math.sin_f32(2.0 * math.PI * key_hertz * n.dt)
                    n.dt += dt_step
                }

                audio_buffer[i] = sample * 0.3

            }
            rl.UpdateAudioStream(audio_stream, raw_data(audio_buffer[:]), AUDIO_BUFFER_SIZE)
        }

        time.sleep(30 * time.Millisecond)
    }
}
