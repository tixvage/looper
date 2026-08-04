package main

import pm "vendor:portmidi"

portmidi_is_error :: proc(err: pm.Error) -> bool {
    return err != pm.Error.NoError && err != pm.Error.NoData && err != pm.Error.GotData
}

