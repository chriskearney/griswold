# dmgbuild settings: lays out the installer window without needing Finder.
import os.path

app = defines["app"]
background = defines["background"]

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon_locations = {
    os.path.basename(app): (180, 214),
    "Applications": (480, 214),
}
window_rect = ((240, 180), (660, 448))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = "auto"
include_list_view_settings = "auto"
arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
