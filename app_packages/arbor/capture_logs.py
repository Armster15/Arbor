import contextlib
import io
import traceback
from typing import Callable, TypeVar

T = TypeVar("T")


def capture_logs(func: Callable[..., T], *args, **kwargs) -> tuple[T | None, str]:
    """Run a callable while capturing stdout/stderr; returns (result or None, log text)."""
    log_buffer = io.StringIO()
    result: T | None = None

    with contextlib.redirect_stdout(log_buffer), contextlib.redirect_stderr(log_buffer):
        try:
            result = func(*args, **kwargs)
        except Exception:
            traceback.print_exc()

    return result, log_buffer.getvalue()
