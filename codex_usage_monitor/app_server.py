from __future__ import annotations

import json
import os
import select
import shutil
import subprocess
import time
from collections.abc import Mapping
from pathlib import Path
from typing import Any


class AppServerError(RuntimeError):
    """Raised when codex app-server cannot complete a protocol operation."""


class AppServerClient:
    """Small JSONL client for the stable codex app-server stdio protocol."""

    def __init__(self, codex_bin: str = "codex", timeout_seconds: float = 15.0) -> None:
        resolved = _resolve_executable(codex_bin)
        self._timeout_seconds = timeout_seconds
        self._next_request_id = 1
        self._notifications: list[dict[str, Any]] = []
        self._process = subprocess.Popen(
            [resolved, "app-server", "--listen", "stdio://"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            bufsize=1,
        )

    def __enter__(self) -> AppServerClient:
        try:
            self.initialize()
        except Exception:
            self.close()
            raise
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def initialize(self) -> None:
        self._request(
            "initialize",
            {
                "clientInfo": {
                    "name": "codex_usage_monitor",
                    "title": "AI Usage Monitor",
                    "version": "0.1.0",
                }
            },
        )
        self._send({"method": "initialized"})

    def read_rate_limits(self) -> Mapping[str, Any]:
        result = self._request("account/rateLimits/read")
        if not isinstance(result, Mapping):
            raise AppServerError("account/rateLimits/read returned a non-object result")
        return result

    def refresh_managed_auth(self) -> None:
        """Ask Codex to refresh its own auth without exposing account or token data."""
        result = self._request("account/read", {"refreshToken": True})
        if not isinstance(result, Mapping):
            raise AppServerError("account/read returned a non-object result")

    def wait_for_rate_limit_update(self, timeout_seconds: float) -> bool:
        """Return True after an update notification, False when the wait expires."""
        deadline = time.monotonic() + timeout_seconds
        while True:
            for index, message in enumerate(self._notifications):
                if message.get("method") == "account/rateLimits/updated":
                    self._notifications.pop(index)
                    return True

            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return False
            message = self._read_message(remaining, allow_timeout=True)
            if message is None:
                return False
            if message.get("method") == "account/rateLimits/updated":
                return True
            self._notifications.append(message)

    def close(self) -> None:
        if self._process.poll() is not None:
            return
        if self._process.stdin is not None:
            self._process.stdin.close()
        self._process.terminate()
        try:
            self._process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self._process.kill()
            self._process.wait(timeout=2)

    def _request(self, method: str, params: Mapping[str, Any] | None = None) -> Any:
        request_id = self._next_request_id
        self._next_request_id += 1
        message: dict[str, Any] = {"method": method, "id": request_id}
        if params is not None:
            message["params"] = dict(params)
        self._send(message)

        deadline = time.monotonic() + self._timeout_seconds
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AppServerError(f"timed out waiting for {method}")
            response = self._read_message(remaining)
            assert response is not None
            if response.get("id") != request_id:
                self._notifications.append(response)
                continue
            if "error" in response:
                error = response["error"]
                if isinstance(error, Mapping):
                    code = error.get("code", "unknown")
                    message_text = error.get("message", "unknown app-server error")
                    raise AppServerError(f"{method} failed ({code}): {message_text}")
                raise AppServerError(f"{method} failed")
            if "result" not in response:
                raise AppServerError(f"{method} response has no result")
            return response["result"]

    def _send(self, message: Mapping[str, Any]) -> None:
        if self._process.stdin is None or self._process.poll() is not None:
            raise AppServerError("codex app-server is not running")
        try:
            self._process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
            self._process.stdin.flush()
        except BrokenPipeError as exc:
            raise AppServerError(self._exit_summary()) from exc

    def _read_message(
        self, timeout_seconds: float, *, allow_timeout: bool = False
    ) -> dict[str, Any] | None:
        if self._process.stdout is None:
            raise AppServerError("codex app-server stdout is unavailable")
        ready, _, _ = select.select([self._process.stdout], [], [], timeout_seconds)
        if not ready:
            if self._process.poll() is not None:
                raise AppServerError(self._exit_summary())
            if allow_timeout:
                return None
            raise AppServerError("timed out waiting for codex app-server")
        line = self._process.stdout.readline()
        if not line:
            raise AppServerError(self._exit_summary())
        try:
            message = json.loads(line)
        except json.JSONDecodeError as exc:
            raise AppServerError("codex app-server emitted invalid JSON") from exc
        if not isinstance(message, dict):
            raise AppServerError("codex app-server emitted a non-object message")
        return message

    def _exit_summary(self) -> str:
        code = self._process.poll()
        stderr = ""
        if self._process.stderr is not None and code is not None:
            stderr = self._process.stderr.read()
        if "failed to initialize sqlite state runtime" in stderr:
            return "codex app-server could not initialize Codex state; check ~/.codex write access"
        return f"codex app-server exited unexpectedly (status {code})"


def _resolve_executable(command: str) -> str:
    if os.path.sep in command:
        path = Path(command).expanduser()
        if not path.is_file() or not os.access(path, os.X_OK):
            raise AppServerError(f"Codex executable is not runnable: {path}")
        return str(path)
    resolved = shutil.which(command)
    if resolved is None:
        raise AppServerError(f"Codex executable was not found on PATH: {command}")
    return resolved
