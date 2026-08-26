import json
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from .utils import random_user_agent


_TRANSLATE_URL = "https://translate.googleapis.com/translate_a/single"
_TRANSLATE_TIMEOUT_SECONDS = 5 * 60


# Yes yes, we have to use `urllib` to make the request, we can't use `requests`.
#
# Why? Google is apparently rejecting requests based on how certain networking libraries deliver them.
# This goes beyond doing things like modifying the user agent or other headers.
# 
# Below is an analysis of what networking libraries do/don't work:
#   Bun fetch (JS)            -> 200
#   urllib.request (Python)   -> 200
#   requests (Python)         -> 429
#   httpx (Python)            -> 429
#
# Google can form an informal client fingerprint from various factors in the network stack beyond the HTTP request, including:
# - IP address
# - TLS handshake characteristics
# - whether HTTP/1.1 or HTTP/2 was negotiated
# - header ordering, casing, defaults, and compression support
# - whether connections are reused or multiple connections are opened
#
# What's crazy to me is standard HTTP servers only receive a parsed, normalized HTTP request.
# Google's edge servers terminate the TCP, TLS, and HTTP connections, so they're probably inspecting
# the TLS handshake metadata and raw HTTP details like header ordering/casing before the normalized request ever
# reaches the Translate service
def _google_translate(text: str) -> tuple[str, str | None]:
    query = urlencode(
        [
            ("client", "gtx"),
            ("sl", "auto"),
            ("tl", "en"),
            ("dt", "t"),
            ("dt", "rm"),
            ("q", text),
        ]
    )
    request = Request(
        f"{_TRANSLATE_URL}?{query}",
        headers={"User-Agent": random_user_agent(), "Accept": "*/*"},
    )

    with urlopen(request, timeout=_TRANSLATE_TIMEOUT_SECONDS) as response:
        data = json.load(response)

    segments = data[0]
    translation = "".join(
        segment[0]
        for segment in segments
        if segment and isinstance(segment[0], str)
    )
    romanization = next(
        (
            segment[3]
            for segment in reversed(segments)
            if len(segment) > 3 and isinstance(segment[3], str)
        ),
        None,
    )

    return translation, romanization


def translate(text: str | list[str]) -> str:
    texts = [text] if isinstance(text, str) else text
    translations: list[str] = []
    romanizations: list[str | None] = []

    for item in texts:
        translation, romanization = _google_translate(item)
        translations.append(translation)
        romanizations.append(romanization)

    return json.dumps(
        {
            "translations": translations,
            "romanizations": romanizations,
        },
        ensure_ascii=False,
    )
