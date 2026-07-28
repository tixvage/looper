package main

import "core:fmt"

Circular_Buffer :: struct($T: typeid, $N: int) {
    data: [N]T,
    head: int,
    tail: int,
    count: int,
}

cb_push :: proc(cb: ^$C/Circular_Buffer($T, $N), val: T) {
    if cb.count == N {
        cb.head = (cb.head + 1) % N
        cb.count -= 1
    }
    cb.data[cb.tail] = val
    cb.tail = (cb.tail + 1) % N
    cb.count += 1
}

cb_pop :: proc(cb: ^$C/Circular_Buffer($T, $N)) -> (T, bool) {
    if cb.count == 0 {
        return {}, false
    }
    val := cb.data[cb.head]
    cb.head = (cb.head + 1) % N
    cb.count -= 1
    return val, true
}

cb_peek :: proc(cb: ^Circular_Buffer($T, $N)) -> (T, bool) {
    if cb.count == 0 {
        return {}, false
    }
    return cb.data[cb.head], true
}

cb_is_empty :: proc(cb: ^Circular_Buffer($T, $N)) -> bool {
    return cb.count == 0
}

cb_is_full :: proc(cb: ^Circular_Buffer($T, $N)) -> bool {
    return cb.count == N
}

cb_len :: proc(cb: ^Circular_Buffer($T, $N)) -> int {
    return cb.count
}

cb_cap :: proc(cb: ^Circular_Buffer($T, $N)) -> int {
    return N
}

cb_clear :: proc(cb: ^Circular_Buffer($T, $N)) {
    cb.head = 0
    cb.tail = 0
    cb.count = 0
}
