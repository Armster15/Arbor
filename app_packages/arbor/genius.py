# Logic comes from https://github.com/rramiachraf/dumb

import requests
import urllib.parse
from bs4 import BeautifulSoup
import json
from difflib import SequenceMatcher
import re
from .utils import USER_AGENT


def _genius_api_request(url: str) -> requests.Response | None:
    try:
        resp = requests.get(url, timeout=30, headers={"User-Agent": USER_AGENT})
        resp.raise_for_status()
    except requests.RequestException:
        print("cannot reach Genius servers")
        return None

    return resp


def _search_genius_songs(query: str) -> list[dict] | None:
    url = f"https://genius.com/api/search/multi?q={urllib.parse.quote(query)}"

    resp = _genius_api_request(url)

    if resp is None:
        return None

    if resp.headers.get("content-type", "").startswith("text/html"):
        print("Cloudflare got in the way")
        return None

    try:
        payload = resp.json()
    except json.JSONDecodeError:
        print("something went wrong")
        return None

    sections = payload.get("response", {}).get("sections", [])

    # Only keep the "song" section
    for section in sections:
        if section.get("type") == "song":
            results = []
            hits = section.get("hits", [])
            for hit in hits:
                if "result" in hit:
                    results.append(hit["result"])
            return results

    return None


def _get_lyrics_with_url_from_genius(url: str) -> str | None:
    resp = _genius_api_request(url)

    if resp is None:
        return None

    soup = BeautifulSoup(resp.text, "html.parser")

    # Remove lyric headers
    for header in soup.select("[class^='LyricsHeader']"):
        header.decompose()

    lines = []

    for container in soup.select("[data-lyrics-container='true']"):
        # Convert <br> to newline
        for br in container.find_all("br"):
            br.replace_with("\n")

        text = container.get_text()
        lines.append(text)

    # Join containers with a newline and normalize spacing
    lyrics = "\n".join(lines)

    # Cleanup excessive blank lines
    lyrics = "\n".join(line.rstrip() for line in lyrics.splitlines()).strip()

    return lyrics


def get_lyrics_from_genius(title: str, primary_artist: str) -> str:
    songs = _search_genius_songs(title + " " + primary_artist)

    if songs is None:
        return ""

    if len(songs) == 0:
        # Sometimes a song will be like "Where Have You Been (TikTok Version)," which won't yield results
        # on Genius. So for these cases, we strip the parentheses and the text inside them and try again.
        if ("(" in title and ")" in title) or ("[" in title and "]" in title):
            # Strip all parentheses and brackets and the text inside them and try again
            new_title = re.sub(r"[\(\[][^\)\]]*[\)\]]", "", title).strip()
            return get_lyrics_from_genius(new_title, primary_artist)

        return ""

    # Selects the song dict whose title is most similar to `title`
    best_match_song = max(
        songs, key=lambda song: SequenceMatcher(None, title, song["title"]).ratio()
    )

    url = best_match_song["url"]

    lyrics = _get_lyrics_with_url_from_genius(url)

    if lyrics is None:
        return ""

    payload = {
        "timed": False,
        "lines": [{"start_ms": None, "text": text} for text in lyrics.split("\n")],
    }

    return json.dumps(payload, ensure_ascii=False)
