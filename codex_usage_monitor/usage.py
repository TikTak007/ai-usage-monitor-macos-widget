from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Any
from zoneinfo import ZoneInfo


THREE_HOUR_MINS = 3 * 60
FIVE_HOUR_MINS = 5 * 60
WEEKLY_MINS = 7 * 24 * 60
JST = ZoneInfo("Asia/Tokyo")


class UsageDataError(ValueError):
    """Raised when app-server usage data is not safe to interpret."""


@dataclass(frozen=True)
class UsageWindow:
    source: str
    label: str
    used_percent: int
    remaining_percent: int
    window_duration_mins: int | None
    resets_at: int | None


@dataclass(frozen=True)
class UsageLimit:
    limit_id: str
    display_name: str
    plan_type: str | None
    rate_limit_reached_type: str | None
    spend_control_reached: bool | None
    windows: tuple[UsageWindow, ...]


@dataclass(frozen=True)
class UsageResetCredit:
    granted_at: int | None
    expires_at: int | None
    status: str
    reset_type: str
    title: str | None
    description: str | None


@dataclass(frozen=True)
class UsageResetCreditsSummary:
    available_count: int
    credits: tuple[UsageResetCredit, ...] | None

    @property
    def nearest_expiration(self) -> int | None:
        if self.credits is None:
            return None
        expirations = [
            credit.expires_at
            for credit in self.credits
            if credit.expires_at is not None
        ]
        return min(expirations) if expirations else None


@dataclass(frozen=True)
class NormalizedUsage:
    limits: tuple[UsageLimit, ...]
    reset_credits: UsageResetCreditsSummary | None
    updated_at: int
    status: str = "connected"

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def normalize_usage(payload: dict[str, Any], now: int | None = None) -> NormalizedUsage:
    limits = tuple(sorted(_parse_limits(payload), key=_limit_sort_key))
    if not limits:
        raise UsageDataError("response contains no usable rate-limit snapshots")
    return NormalizedUsage(
        limits=limits,
        reset_credits=_parse_reset_credits(payload.get("rateLimitResetCredits")),
        updated_at=int(datetime.now(timezone.utc).timestamp()) if now is None else now,
    )


def describe_response_shape(payload: dict[str, Any]) -> dict[str, Any]:
    """Return a credential-free description of the rate-limit response shape."""
    description: dict[str, Any] = {
        "top_level_keys": sorted(payload),
        "rate_limits": _describe_snapshot(payload.get("rateLimits")),
        "rate_limits_by_limit_id": {},
        "rate_limit_reset_credits_present": payload.get("rateLimitResetCredits") is not None,
    }
    by_id = payload.get("rateLimitsByLimitId")
    if isinstance(by_id, dict):
        description["rate_limits_by_limit_id"] = {
            str(limit_id): _describe_snapshot(snapshot)
            for limit_id, snapshot in sorted(by_id.items(), key=lambda item: str(item[0]))
        }
    return description


def format_window_label(duration_mins: int | None) -> str:
    if duration_mins is None:
        return "Duration unavailable"
    if duration_mins == THREE_HOUR_MINS:
        return "3-hour"
    if duration_mins == FIVE_HOUR_MINS:
        return "5-hour"
    if duration_mins == WEEKLY_MINS:
        return "Weekly (7-day)"
    if duration_mins % (24 * 60) == 0:
        days = duration_mins // (24 * 60)
        return f"{days}-day"
    if duration_mins % 60 == 0:
        hours = duration_mins // 60
        return f"{hours}-hour"
    return f"{duration_mins}-minute"


def format_jst(timestamp: int | None) -> str:
    if timestamp is None:
        return "Unavailable"
    return datetime.fromtimestamp(timestamp, timezone.utc).astimezone(JST).strftime(
        "%Y-%m-%d %H:%M:%S JST"
    )


def format_time_remaining(resets_at: int | None, now: int) -> str:
    if resets_at is None:
        return "Unavailable"
    total_minutes = max(0, resets_at - now) // 60
    days, remainder = divmod(total_minutes, 24 * 60)
    hours, minutes = divmod(remainder, 60)
    if days:
        return f"{days}d {hours}h {minutes}m"
    return f"{hours}h {minutes}m"


def _parse_limits(payload: dict[str, Any]) -> list[UsageLimit]:
    by_id = payload.get("rateLimitsByLimitId")
    if isinstance(by_id, dict) and by_id:
        limits: list[UsageLimit] = []
        for map_key, raw_snapshot in by_id.items():
            if not isinstance(raw_snapshot, dict):
                raise UsageDataError(f"rateLimitsByLimitId.{map_key} must be an object")
            limits.append(_parse_limit(str(map_key), raw_snapshot))
        return limits

    historical = payload.get("rateLimits")
    if not isinstance(historical, dict):
        return []
    fallback_id = historical.get("limitId")
    if not isinstance(fallback_id, str) or not fallback_id:
        fallback_id = "codex"
    return [_parse_limit(fallback_id, historical)]


def _parse_reset_credits(value: Any) -> UsageResetCreditsSummary | None:
    if value is None:
        return None
    if not isinstance(value, dict):
        raise UsageDataError("rateLimitResetCredits must be an object or null")
    available_count = value.get("availableCount")
    if (
        isinstance(available_count, bool)
        or not isinstance(available_count, int)
        or available_count < 0
    ):
        raise UsageDataError("rateLimitResetCredits.availableCount must be non-negative")

    raw_credits = value.get("credits")
    if raw_credits is None:
        credits = None
    elif isinstance(raw_credits, list):
        credits = tuple(
            _parse_reset_credit(raw_credit, index)
            for index, raw_credit in enumerate(raw_credits)
        )
    else:
        raise UsageDataError("rateLimitResetCredits.credits must be an array or null")

    return UsageResetCreditsSummary(available_count=available_count, credits=credits)


def _parse_reset_credit(value: Any, index: int) -> UsageResetCredit:
    field = f"rateLimitResetCredits.credits[{index}]"
    if not isinstance(value, dict):
        raise UsageDataError(f"{field} must be an object")
    credit_id = value.get("id")
    status = value.get("status")
    reset_type = value.get("resetType")
    if not isinstance(credit_id, str) or not credit_id.strip():
        raise UsageDataError(f"{field}.id must be a non-empty string")
    if not isinstance(status, str) or not status.strip():
        raise UsageDataError(f"{field}.status must be a non-empty string")
    if not isinstance(reset_type, str) or not reset_type.strip():
        raise UsageDataError(f"{field}.resetType must be a non-empty string")

    return UsageResetCredit(
        granted_at=_optional_timestamp(value.get("grantedAt"), f"{field}.grantedAt"),
        expires_at=_optional_timestamp(value.get("expiresAt"), f"{field}.expiresAt"),
        status=status,
        reset_type=reset_type,
        title=_optional_string(value.get("title"), f"{field}.title"),
        description=_optional_string(value.get("description"), f"{field}.description"),
    )


def _parse_limit(map_key: str, snapshot: dict[str, Any]) -> UsageLimit:
    raw_limit_id = snapshot.get("limitId")
    limit_id = raw_limit_id if isinstance(raw_limit_id, str) and raw_limit_id else map_key
    raw_limit_name = snapshot.get("limitName")
    limit_name = raw_limit_name if isinstance(raw_limit_name, str) and raw_limit_name.strip() else None

    windows: list[UsageWindow] = []
    for source in ("primary", "secondary"):
        raw_window = snapshot.get(source)
        if raw_window is None:
            continue
        if not isinstance(raw_window, dict):
            raise UsageDataError(f"rate limit {limit_id}.{source} must be an object or null")
        windows.append(_parse_window(source, raw_window))

    plan_type = snapshot.get("planType")
    if plan_type is not None and not isinstance(plan_type, str):
        raise UsageDataError(f"rate limit {limit_id}.planType must be a string or null")
    reached_type = snapshot.get("rateLimitReachedType")
    if reached_type is not None and not isinstance(reached_type, str):
        raise UsageDataError(
            f"rate limit {limit_id}.rateLimitReachedType must be a string or null"
        )
    spend_control_reached = snapshot.get("spendControlReached")
    if spend_control_reached is not None and not isinstance(spend_control_reached, bool):
        raise UsageDataError(
            f"rate limit {limit_id}.spendControlReached must be a boolean or null"
        )

    return UsageLimit(
        limit_id=limit_id,
        display_name=limit_name or ("Codex" if limit_id == "codex" else "Additional limit"),
        plan_type=plan_type,
        rate_limit_reached_type=reached_type,
        spend_control_reached=spend_control_reached,
        windows=tuple(windows),
    )


def _parse_window(source: str, raw: dict[str, Any]) -> UsageWindow:
    used = raw.get("usedPercent")
    duration = raw.get("windowDurationMins")
    resets_at = raw.get("resetsAt")
    if isinstance(used, bool) or not isinstance(used, int) or not 0 <= used <= 100:
        raise UsageDataError("usedPercent must be an integer from 0 through 100")
    if duration is not None and (
        isinstance(duration, bool) or not isinstance(duration, int) or duration <= 0
    ):
        raise UsageDataError("windowDurationMins must be a positive integer or null")
    if resets_at is not None and (isinstance(resets_at, bool) or not isinstance(resets_at, int)):
        raise UsageDataError("resetsAt must be an integer or null")
    return UsageWindow(
        source=source,
        label=format_window_label(duration),
        used_percent=used,
        remaining_percent=100 - used,
        window_duration_mins=duration,
        resets_at=resets_at,
    )


def _optional_timestamp(value: Any, field: str) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise UsageDataError(f"{field} must be a non-negative integer or null")
    return value


def _optional_string(value: Any, field: str) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise UsageDataError(f"{field} must be a string or null")
    stripped = value.strip()
    return stripped or None


def _limit_sort_key(limit: UsageLimit) -> tuple[int, str, str]:
    return (0 if limit.limit_id == "codex" else 1, limit.display_name.casefold(), limit.limit_id)


def _describe_snapshot(value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    return {
        "present_fields": sorted(value),
        "limit_id": value.get("limitId") if isinstance(value.get("limitId"), str) else None,
        "limit_name": value.get("limitName") if isinstance(value.get("limitName"), str) else None,
        "plan_type": value.get("planType") if isinstance(value.get("planType"), str) else None,
        "primary": _describe_window(value.get("primary")),
        "secondary": _describe_window(value.get("secondary")),
    }


def _describe_window(value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    allowed_fields = ("usedPercent", "windowDurationMins", "resetsAt")
    return {field: value.get(field) for field in allowed_fields}
