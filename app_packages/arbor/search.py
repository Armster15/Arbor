from .utils import create_ytmusic_client, random_user_agent
import json
import re
from typing import Optional, Tuple
from soundcloud import SoundCloud


def search_youtube(query: str):
    ytmusic = create_ytmusic_client()

    print(f"Searching YouTube for {query}")
    raw_results = ytmusic.search(query, filter="songs", limit=15)
    print(f"Found {len(raw_results)} results from YouTube")

    results = []

    for result in raw_results:
        title = result.get("title")
        videoId = result.get("videoId")

        if not title or not videoId:
            continue

        thumbnail = result.get("thumbnails") and result["thumbnails"][-1]
        thumbnail_width = thumbnail and thumbnail.get("width")
        thumbnail_height = thumbnail and thumbnail.get("height")
        thumbnail_is_square = thumbnail_width == thumbnail_height
        thumbnail_url = thumbnail and thumbnail.get("url")

        if thumbnail_url and thumbnail_is_square:
            # upscale thumbnail image to 400x400
            thumbnail_url = re.sub(r"w\d+-h\d+", "w400-h400", thumbnail_url)
            thumbnail_width = 400
            thumbnail_height = 400
        elif videoId:
            thumbnail_url = f"https://i.ytimg.com/vi/{videoId}/maxresdefault.jpg"
        else:
            thumbnail_url = None

        artists = result.get("artists")
        if not isinstance(artists, list) or len(artists) == 0:
            artists = None
        else:
            artists = [artist["name"] for artist in artists]

        results.append(
            {
                "title": result.get("title"),
                "artists": artists,
                "url": f"https://www.youtube.com/watch?v={videoId}",
                "views": result.get("views"),
                "duration": result.get("duration"),
                "is_explicit": result.get("isExplicit"),
                "verified": False,  # youtube's search results doesn't expose if the uploader is verified
                "thumbnail_url": thumbnail_url,
                "thumbnail_is_square": thumbnail_is_square,
                "thumbnail_width": thumbnail_width,
                "thumbnail_height": thumbnail_height,
            }
        )

    data = json.dumps(results)

    return data


def search_soundcloud(query: str):
    soundcloud = SoundCloud(user_agent=random_user_agent())

    print(f"Searching SoundCloud for {query}")
    raw_results = soundcloud.search_tracks(query, limit=15)

    results = []

    def _ms_to_timestamp(ms: Optional[int]) -> Optional[str]:
        if not ms or ms <= 0:
            return None
        total_seconds = int(round(ms / 1000))
        minutes = total_seconds // 60
        seconds = total_seconds % 60
        return f"{minutes}:{seconds:02d}"

    def _normalize_artwork(
        url: Optional[str],
    ) -> Tuple[Optional[str], Optional[bool], Optional[int], Optional[int]]:
        if not url:
            return None, None, None, None
        # Prefer a square artwork; upgrade size when possible
        # Common patterns: "-large.jpg" or "-t300x300.jpg" / "-t500x500.jpg"
        new_url = re.sub(r"-large(\.[a-zA-Z0-9]+)$", r"-t500x500\1", url)
        new_url = re.sub(r"-t\d+x\d+(\.[a-zA-Z0-9]+)$", r"-t500x500\1", new_url)
        # Mark as square since SoundCloud artworks are square variants
        return new_url, True, 400, 400

    count = 0
    for track in raw_results:
        if count >= 15:
            break
        try:
            title = getattr(track, "title", None)
            permalink_url = getattr(track, "permalink_url", None)
            if not title or not permalink_url:
                continue

            # Artist list (primary uploader)
            user = getattr(track, "user", None)
            artist_name = getattr(user, "username", None) or getattr(
                user, "full_name", None
            )
            artists = [artist_name] if artist_name else ["Unknown Artist"]

            # Verified flag (boolean)
            verified = False
            if user is not None:
                try:
                    verified = bool(
                        getattr(user, "verified", False)
                        or getattr(getattr(user, "badges", None), "verified", False)
                    )
                except Exception:
                    verified = False

            # Views / plays (stringify to align with Swift model expecting String)
            views_val = getattr(track, "playback_count", None)
            views = f"{views_val:,}" if isinstance(views_val, int) else None

            # Duration (ms -> m:ss)
            full_duration = getattr(track, "full_duration", None)
            duration_ms = (
                full_duration
                if isinstance(full_duration, int)
                else getattr(track, "duration", None)
            )
            duration_str = _ms_to_timestamp(
                duration_ms if isinstance(duration_ms, int) else None
            )

            # Thumbnail
            artwork_url = getattr(track, "artwork_url", None)
            if not artwork_url and user is not None:
                artwork_url = getattr(user, "avatar_url", None)
            thumbnail_url, thumbnail_is_square, thumbnail_width, thumbnail_height = (
                _normalize_artwork(artwork_url)
            )

            results.append(
                {
                    "title": title,
                    "artists": artists,
                    "url": permalink_url,
                    "views": views,
                    "duration": duration_str,
                    "is_explicit": None,
                    "verified": verified,
                    "thumbnail_url": thumbnail_url,
                    "thumbnail_is_square": thumbnail_is_square,
                    "thumbnail_width": thumbnail_width,
                    "thumbnail_height": thumbnail_height,
                }
            )
            count += 1
        except Exception:
            # Skip any items that don't conform to expected structure
            continue

    data = json.dumps(results)
    print(f"Found {count} results from SoundCloud")

    return data
