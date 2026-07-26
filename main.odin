package main

import "core:log"
import "core:time"
import "core:math"
import pm "vendor:portmidi"
import rl "vendor:raylib"

AUDIO_BUFFER_SIZE :: 4096
SAMPLE_RATE :: 44100

// assumed C0 -> 0
key_number_to_freq :: proc(num: int) -> f32 {
    return 440.0 * math.pow(2.0, (cast(f32)num - 57.0) / 12.0)
}

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

    current_key := -1
    phase: f32 = 0.0

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
                current_key = cast(int)key
            case KEY_RELEASED:
                if key < KEY_MIN || key > KEY_MAX {
                    log.warnf("invalid key: 0x%X", key)
                }
                current_key = -1
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

        log.infof("%v", audio_buffer[122])

        if (rl.IsAudioStreamProcessed(audio_stream)) {
            freq := key_number_to_freq(current_key) if current_key != -1 else 0
            phase_inc := (cast(f32)freq / cast(f32)SAMPLE_RATE)
            for i in 0..<AUDIO_BUFFER_SIZE {
                audio_buffer[i] = math.sin_f32(2.0*math.PI*phase)
                phase += phase_inc
                if phase >= 1.0 { phase -= 1.0 }
            }
            rl.UpdateAudioStream(audio_stream, raw_data(audio_buffer[:]), AUDIO_BUFFER_SIZE)
        }

        time.sleep(30 * time.Millisecond)
    }
}
