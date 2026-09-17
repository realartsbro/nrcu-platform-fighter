extends SceneTree
# Environment probe for the lab runtime: window/screen/DPI facts.
func _init() -> void:
    await process_frame
    await process_frame
    var w := DisplayServer.window_get_size()
    print("window_size=", w)
    print("screen_scale=", DisplayServer.screen_get_scale())
    print("screen_count=", DisplayServer.get_screen_count())
    for i in DisplayServer.get_screen_count():
        print("screen[", i, "]_size=", DisplayServer.screen_get_size(i), " usable=", DisplayServer.screen_get_usable_rect(i), " scale=", DisplayServer.screen_get_scale(i))
    print("screen_dpi=", DisplayServer.screen_get_dpi())
    quit()
