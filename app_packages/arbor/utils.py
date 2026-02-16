import requests
import yt_dlp
from ytmusicapi import YTMusic


def random_user_agent():
    """
    Internal method in yt_dlp that gets a random user agent within the last ~6 months
    https://github.com/yt-dlp/yt-dlp/blob/8d6e0b29bf15365638e0ceeb803a274e4db6157d/yt_dlp/utils/networking.py#L17
    """
    try:
        return (
            yt_dlp.utils.networking.random_user_agent()  # pyright: ignore [reportAttributeAccessIssue]
        )
    except Exception:
        # https://stackoverflow.com/a/52738630
        return yt_dlp.utils.std_headers[  # pyright: ignore [reportAttributeAccessIssue]
            "User-Agent"
        ]


def create_ytmusic_client():
    """
    Create a YTMusic client with a random user agent since by default it hardcodes
    a really old user agent from 2021.
    """
    session = requests.Session()
    session.headers.update({"user-agent": random_user_agent()})
    return YTMusic(
        requests_session=session
    )  # pyright: ignore [reportUnknownReturnType]
