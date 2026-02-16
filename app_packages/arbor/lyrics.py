import json
from .utils import create_ytmusic_client


def get_lyrics_from_youtube(video_id: str) -> str:
    """
    Get lyrics from YouTube Music for a given video ID.

    Args:
        video_id: The YouTube video ID (e.g. "dQw4w9WgXcQ")

    Returns:
        JSON string for the payload or empty string if unavailable.
    """
    ytmusic = create_ytmusic_client()

    watch = ytmusic.get_watch_playlist(videoId=video_id, limit=1)
    browse_id = watch.get("lyrics")

    if not browse_id or not isinstance(browse_id, str):
        return ""

    lyrics = ytmusic.get_lyrics(browse_id, timestamps=True)

    if lyrics is None:
        return ""

    lyrics = lyrics.get("lyrics")

    # Has timestamps
    if isinstance(lyrics, list):
        # [ [start_time_ms: number, text: string], ... ]
        lines: list[tuple[int, str]] = [(line.start_time, line.text) for line in lyrics]
        payload = {"timed": True, "lines": [{"start_ms": int(start_ms), "text": text} for start_ms, text in lines]}
        return json.dumps(payload)

    # Does not have timestamps and is just a string separated by `\n`s
    if isinstance(lyrics, str):
        payload = {"timed": False, "lines": [{"start_ms": None, "text": text} for text in lyrics.split("\n")]}
        return json.dumps(payload)

    return ""
