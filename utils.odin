package main

import "core:log"
import "core:strings"
import "core:math"
import pm "vendor:portmidi"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"

portmidi_is_error :: proc(err: pm.Error) -> bool {
    return err != pm.Error.NoError && err != pm.Error.NoData && err != pm.Error.GotData
}

load_wav_samples :: proc(path_s: string, allocator := context.allocator) -> []f32 {
    cfg := ma.decoder_config_init(ma.format.f32, 1, SAMPLE_RATE)
    dec: ma.decoder

    path := strings.clone_to_cstring(path_s, context.temp_allocator)
    defer delete(path)

    if res := ma.decoder_init_file(path, &cfg, &dec); res != .SUCCESS {
        log.errorf("failed to decode %s: %v", path, res)
        return {}
    }
    defer ma.decoder_uninit(&dec)

    frames: u64
    if res := ma.decoder_get_length_in_pcm_frames(&dec, &frames); res != .SUCCESS {
        log.errorf("failed to get length of %s: %v", path, res)
        return {}
    }

    data := make([]f32, frames, allocator)
    read: u64
    if res := ma.decoder_read_pcm_frames(&dec, raw_data(data), frames, &read); res != .SUCCESS {
        log.errorf("failed to read %s: %v", path, res)
        return {}
    }

    return data[:read]
}

color_unpack :: proc(hex: u32) -> (u8, u8, u8, u8) {
    return u8(hex >> 24 & 0xFF), u8(hex >> 16 & 0xFF), u8(hex >> 8 & 0xFF), u8(hex >> 0 & 0xFF)
}


draw_filled_circle :: proc(renderer: ^sdl.Renderer, center_x, center_y, radius: i32) {
    for y in -radius..=radius {
        half_width := i32(math.sqrt_f32(f32(radius * radius - y * y)))
        sdl.RenderDrawLine(renderer, center_x - half_width, center_y + y, center_x + half_width, center_y + y)
    }
}
