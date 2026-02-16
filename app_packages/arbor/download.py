import os
import json
import tempfile
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse
import requests
from bs4 import BeautifulSoup
import yt_dlp

from .search import search_youtube
from .utils import USER_AGENT


@dataclass(frozen=True)
class DownloadOverrides:
    title: str | None = None
    artists: tuple[str, ...] | None = None


def download(url: str, overrides: DownloadOverrides | None = None):
    trimmed_url = url.strip()
    if not trimmed_url:
        raise ValueError("URL cannot be empty")

    # If the URL is a Spotify track URL, handle it specially
    spotify_track_id = _spotify_track_id(trimmed_url)
    if spotify_track_id:
        return _download_spotify(spotify_track_id, overrides=overrides)

    # Configuration options matching the command line flags
    # Options: https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/__init__.py#L776
    ydl_opts = {
        "format": "bestaudio[ext=m4a]/bestaudio",
        "nopostoverwrites": True,
        "postprocessors": [],  # No post-processors at all
        "verbose": True,  # Shows detailed output including ffmpeg usage'
        #
        # NOTE:
        # The video appears longer because without ffmpeg (and with --fixup never, which is required for no ffmpeg/ffprobe), yt-dlp can't correct
        # YouTube's mismatched duration metadata, so it keeps the raw stream length-this option is needed
        # since ffmpeg isn't available to fix it automatically.
        "fixup": "never",  # Disable all fixup post-processors
        #
        # Ensure only single videos are downloaded, no playlists
        "playlistend": 1,  # Only download the first item (single video)
        "noplaylist": True,  # Do not download playlists
        "nocheckcertificate": True,  # Ignore certificate errors (happens on physical device)
    }

    # Select iOS-writable locations
    home = Path.home()
    tmp_dir = Path(tempfile.gettempdir())
    caches_dir = home / "Library" / "Caches"
    yt_cache_dir = caches_dir / "yt-dlp"
    output_dir = tmp_dir  # Prefer tmp for downloads to avoid backups

    # Ensure directories exist
    output_dir.mkdir(parents=True, exist_ok=True)
    yt_cache_dir.mkdir(parents=True, exist_ok=True)

    # Tell yt-dlp where to write files and cache
    ydl_opts.update(
        {
            "outtmpl": str(output_dir / "%(uploader_id)s-%(id)s.%(ext)s"),
            "cachedir": str(yt_cache_dir),
        }
    )

    # Download the video
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        print(f"Downloading video from: {trimmed_url}")
        print(f"Downloading video to: {output_dir}")
        print(f"Using cache dir: {yt_cache_dir}")

        info = ydl.extract_info(trimmed_url, download=True)

        if info is None:
            raise Exception("Failed to retrieve video information (manually thrown)")

        filename = ydl.prepare_filename(info)
        full_path = os.path.abspath(filename)
        print(f"Downloaded file: {full_path}")

        title = info.get("title") or Path(full_path).stem

        artists: list[str] = []

        # the walrus operator lets us assigns values to variables as part of a larger expression
        # https://docs.python.org/3/whatsnew/3.8.html#assignment-expressions
        if (_artists := info.get("artists")) and isinstance(_artists, list):
            artists.extend(_artists)
        elif _artist := info.get("artist"):
            artists.append(_artist)
        elif _uploader := info.get("uploader"):
            artists.append(_uploader)
        elif _channel := info.get("channel"):
            artists.append(_channel)
        else:
            artists = ["Unknown Artist"]

        if overrides is not None:
            if overrides.title:
                override_title = overrides.title.strip()
                if override_title:
                    title = override_title

            if overrides.artists:
                override_artists = [
                    artist.strip() for artist in overrides.artists if artist.strip()
                ]
                if override_artists:
                    artists = override_artists

        # Choose thumbnail: prefer square art (common for music); else highest resolution
        thumbnails = info.get("thumbnails") or []
        thumbnail_info = None
        thumbnail_url = None

        def _dims(t):
            if not isinstance(t, dict):
                return (0, 0)
            w = t.get("width") or 0
            h = t.get("height") or 0
            try:
                return (int(w), int(h))
            except Exception:
                return (0, 0)

        def _area(t):
            w, h = _dims(t)
            return w * h

        def _is_square(t, tol=2):
            w, h = _dims(t)
            return w > 0 and h > 0 and abs(w - h) <= tol

        if isinstance(thumbnails, list) and thumbnails:
            square_thumbs = [t for t in thumbnails if _is_square(t)]
            if square_thumbs:
                # Largest square by area
                thumbnail_info = max(square_thumbs, key=_area)
            else:
                # Fallback: largest by area
                thumbnail_info = max(thumbnails, key=_area)
            thumbnail_url = (thumbnail_info or {}).get("url")
        else:
            # Fallback to top-level thumbnail string if thumbnails list is absent
            thumbnail_url = info.get("thumbnail")

        # Extract dimensions if available
        thumb_w = None
        thumb_h = None
        if isinstance(thumbnail_info, dict):
            try:
                w = thumbnail_info.get("width")
                h = thumbnail_info.get("height")
                thumb_w = int(w) if isinstance(w, (int, float)) else None
                thumb_h = int(h) if isinstance(h, (int, float)) else None
            except Exception:
                thumb_w = None
                thumb_h = None

        meta = {
            "path": full_path,
            "original_url": trimmed_url,
            "title": title,
            "artists": artists,
            "thumbnail_url": thumbnail_url,
            "thumbnail_width": thumb_w,
            "thumbnail_height": thumb_h,
            "thumbnail_is_square": (
                thumb_w is not None and thumb_h is not None and thumb_w == thumb_h
            ),
        }

        return json.dumps(meta)


# When given a Spotify track id, extract the track metadata (title, artist, art, etc)
# from the public Spotify embed page and then use the search_youtube function to find the
# corresponding YouTube video and download it.
def _download_spotify(
    track_id: str,
    overrides: DownloadOverrides | None = None,
):
    if not track_id:
        raise ValueError(
            "Invalid Spotify track id. Expected format: "
            "https://open.spotify.com/track/{id}"
        )

    embed_url = f"https://open.spotify.com/embed/track/{track_id}?utm_source=oembed"
    response = requests.get(embed_url, timeout=20, headers={"User-Agent": USER_AGENT})
    if response.status_code != 200:
        raise ValueError(
            f"Failed to fetch Spotify embed page (status={response.status_code})"
        )

    soup = BeautifulSoup(response.text, "html.parser")
    script = soup.find("script", id="__NEXT_DATA__")
    script_text = (script.string if script else None) or (
        script.get_text(strip=True) if script else ""
    )
    if not script_text:
        raise ValueError("Spotify embed page is missing __NEXT_DATA__ JSON")

    try:
        payload = json.loads(script_text)
    except json.JSONDecodeError as exc:
        raise ValueError("Failed to parse Spotify __NEXT_DATA__ JSON") from exc

    entity = (
        (((payload.get("props") or {}).get("pageProps") or {}).get("state") or {})
        .get("data", {})
        .get("entity")
    ) or {}

    title = (entity.get("title") or entity.get("name") or "").strip()
    artists = [
        (artist.get("name") or "").strip()
        for artist in (entity.get("artists") or [])
        if isinstance(artist, dict) and (artist.get("name") or "").strip()
    ]

    if not title or not artists:
        raise ValueError("Spotify track metadata is missing title or artists")

    search_query = " ".join([title, *artists]).strip()
    raw_results = search_youtube(search_query)

    print(f"Searching YouTube for Spotify track using search query: {search_query}")

    try:
        results = json.loads(raw_results)
    except json.JSONDecodeError as exc:
        raise ValueError("Invalid JSON returned from YouTube search") from exc

    youtube_url = (
        (results[0] or {}).get("url") if isinstance(results, list) and results else None
    )
    if not isinstance(youtube_url, str) or not youtube_url.strip():
        raise ValueError("No YouTube results found for Spotify track")

    spotify_overrides = DownloadOverrides(title=title, artists=tuple(artists))
    merged_overrides = DownloadOverrides(
        title=(
            overrides.title
            if overrides is not None and overrides.title is not None
            else spotify_overrides.title
        ),
        artists=(
            overrides.artists
            if overrides is not None and overrides.artists is not None
            else spotify_overrides.artists
        ),
    )

    return download(youtube_url.strip(), overrides=merged_overrides)


# Extract the track ID from a Spotify track URL
def _spotify_track_id(url: str) -> str | None:
    parsed = urlparse(url.strip())
    host = (parsed.hostname or "").lower()
    if parsed.scheme not in {"http", "https"} or host != "open.spotify.com":
        return None

    path_parts = [part for part in (parsed.path or "").split("/") if part]
    if len(path_parts) != 2 or path_parts[0] != "track":
        return None

    track_id = path_parts[1].strip()
    if not track_id or not track_id.isalnum():
        return None

    return track_id
