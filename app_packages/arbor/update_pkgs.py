from pathlib import Path
from .pip_exec import pip_exec
import importlib.metadata as metadata
import re
import shutil
import traceback
from packaging.utils import canonicalize_name

# Base folders
__dirname = Path(__file__).resolve().parent  # node.js my beloved
root_dir = __dirname.parent.parent
application_support_dir = Path.home() / "Library" / "Application Support"

# Core files/dirs
python_modules_dir = root_dir / "python_modules"
updated_python_modules_dir = application_support_dir / "updated_python_modules"
requirements_txt_path = root_dir / "requirements.txt"


def update_pkgs() -> bool:
    try:
        result = pip_exec(
            [
                "install",
                "--platform=any",
                "--only-binary=:all:",
                "--upgrade",
                "--target=" + str(updated_python_modules_dir),
                "-r",
                str(requirements_txt_path),
            ]
        )
        success = result == 0
    except Exception:
        success = False
        traceback.print_exc()

    return success


def are_pkgs_updated() -> bool:
    return updated_python_modules_dir.exists()


def delete_updated_pkgs():
    if updated_python_modules_dir.exists():
        shutil.rmtree(updated_python_modules_dir)


def get_dependency_versions() -> list[dict]:
    # Parses a requirements.txt file and returns a list of package names
    def _parse_requirements(path: Path) -> list[str]:
        names: list[str] = []

        for raw_line in path.read_text().splitlines():
            line = raw_line.split("#", 1)[0].strip()
            if not line or line.startswith("-"):
                continue

            name = re.split(r"[<>=!~\[]", line, maxsplit=1)[0].strip()
            if name:
                names.append(name)

        return names

    # Returns a dictionary of package names and their versions from a given directory
    def _versions_for_path(path: Path) -> dict[str, str]:
        if not path.exists():
            return {}

        versions: dict[str, str] = {}

        for dist in metadata.distributions(path=[str(path)]):
            name = dist.metadata.get("Name")
            if not name:
                continue

            versions[canonicalize_name(name)] = dist.version

        return versions

    requirement_names = _parse_requirements(requirements_txt_path)
    base_versions = _versions_for_path(python_modules_dir)
    updated_versions = _versions_for_path(updated_python_modules_dir)

    output: list[dict] = []

    for name in requirement_names:
        # Canonicalize because PyPI names and installed dist metadata can differ (yt-dlp -> yt_dlp)
        normalized = canonicalize_name(name)

        output.append(
            {
                "name": name,
                "base_version": base_versions.get(normalized),
                "updated_version": updated_versions.get(normalized),
            }
        )

    return output
