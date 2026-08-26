import importlib.metadata as metadata
import shutil
import tempfile
import traceback
from pathlib import Path

from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

from .pip_exec import pip_exec

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
        application_support_dir.mkdir(parents=True, exist_ok=True)

        # pip can leave old metadata behind when updating an existing target folder. Install
        # into a fresh folder, keep the old one as a backup, then swap them. If the
        # swap fails, put the backup back.
        with tempfile.TemporaryDirectory(
            dir=application_support_dir, ignore_cleanup_errors=True
        ) as temp_dir:
            work_dir = Path(temp_dir)
            staged_dir = work_dir / "staged"
            backup_dir = work_dir / "backup"

            result = pip_exec(
                [
                    "install",
                    "--platform=any",
                    "--only-binary=:all:",
                    "--target=" + str(staged_dir),
                    "-r",
                    str(requirements_txt_path),
                ]
            )

            if result != 0:
                return False

            # no "else" is needed because on the first update there is nothing to back up
            if updated_python_modules_dir.exists():
                updated_python_modules_dir.replace(backup_dir)

            try:
                staged_dir.replace(updated_python_modules_dir)
            except Exception:
                if backup_dir.exists():
                    backup_dir.replace(updated_python_modules_dir)
                raise

        return True

    except Exception:
        traceback.print_exc()
        return False


def are_pkgs_updated() -> bool:
    return updated_python_modules_dir.exists()


def delete_updated_pkgs():
    if updated_python_modules_dir.exists():
        shutil.rmtree(updated_python_modules_dir)


def get_dependency_versions() -> list[dict]:
    def _parse_requirements(path: Path) -> list[str]:
        names: list[str] = []

        for raw_line in path.read_text().splitlines():
            line = raw_line.split("#", 1)[0].strip()
            if not line or line.startswith("-"):
                continue

            names.append(Requirement(line).name)

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
