from .capture_logs import capture_logs
from .download import download
from .genius import get_lyrics_from_genius
from .lyrics import get_lyrics_from_youtube
from .pip_exec import pip_exec
from .search import search_youtube, search_soundcloud
from .translate import translate
from .update_pkgs import (
    update_pkgs,
    are_pkgs_updated,
    delete_updated_pkgs,
    get_dependency_versions,
)

version = "1.0.0"
