package main

import "core:log"
import "core:time"
import pm "vendor:portmidi"

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
            case KEY_RELEASED:
                if key < KEY_MIN || key > KEY_MAX {
                    log.warnf("invalid key: 0x%X", key)
                }
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

        time.sleep(30 * time.Millisecond)
    }
}
