"""Seed only the isolated CI simulator with a paused queue for layout checks."""
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
entry = "76DA53CD-6760-4938-A96A-9E267BA82711"
second = "A44C0656-BA8C-4442-B7BE-CA61BA44980A"
song = {
    "id": "dQw4w9WgXc", "title": "Never Gonna Give You Up",
    "artist": "Rick Astley", "duration": "3:33",
    "thumbnailURL": "https://i.ytimg.com/vi/dQw4w9WgXc/hqdefault.jpg",
}
snapshot = {
    "version": 1, "favorites": [], "playlists": [], "history": [], "searches": [],
    "queue": {
        "entries": [{"id": entry, "song": song}, {"id": second, "song": song}],
        "order": [entry, second], "currentID": entry,
        "repeatMode": "off", "isShuffled": False,
    },
}
path.write_text(json.dumps(snapshot), encoding="utf-8")
