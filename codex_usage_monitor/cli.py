from __future__ import annotations

import argparse
import json
import sys

from .app_server import AppServerClient, AppServerError
from .usage import (
    NormalizedUsage,
    UsageDataError,
    UsageLimit,
    UsageWindow,
    describe_response_shape,
    format_jst,
    format_time_remaining,
    normalize_usage,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Read Codex usage through the local codex app-server."
    )
    parser.add_argument("--codex-bin", default="codex", help="Codex executable (default: codex)")
    parser.add_argument("--json", action="store_true", help="print normalized JSON")
    parser.add_argument(
        "--describe-response",
        action="store_true",
        help="print a credential-free description of the app-server response shape",
    )
    parser.add_argument(
        "--watch-seconds",
        type=float,
        default=0,
        metavar="SECONDS",
        help="wait for account/rateLimits/updated, then refetch the full snapshot",
    )
    parser.add_argument(
        "--verify-token-refresh",
        action="store_true",
        help="ask Codex to refresh its managed auth before reading usage; no token is exposed",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=float,
        default=15,
        metavar="SECONDS",
        help="timeout for each app-server request (default: 15)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.watch_seconds < 0 or args.timeout_seconds <= 0:
        print("error: timeouts must be positive", file=sys.stderr)
        return 2
    try:
        with AppServerClient(args.codex_bin, args.timeout_seconds) as client:
            if args.verify_token_refresh:
                client.refresh_managed_auth()
                print("Codex-managed token refresh: succeeded", file=sys.stderr)
            payload = dict(client.read_rate_limits())
            usage = normalize_usage(payload)
            _print_usage(usage, args.json)
            if args.describe_response:
                print(json.dumps(describe_response_shape(payload), ensure_ascii=False, indent=2))
            if args.watch_seconds:
                print(
                    f"Watching for account/rateLimits/updated for {args.watch_seconds:g}s...",
                    file=sys.stderr,
                )
                if client.wait_for_rate_limit_update(args.watch_seconds):
                    payload = dict(client.read_rate_limits())
                    usage = normalize_usage(payload)
                    _print_usage(usage, args.json)
                    if args.describe_response:
                        print(
                            json.dumps(describe_response_shape(payload), ensure_ascii=False, indent=2)
                        )
                    print("Rate-limit update received and snapshot refreshed.", file=sys.stderr)
                else:
                    print("No rate-limit update received during the observation window.", file=sys.stderr)
        return 0
    except (AppServerError, UsageDataError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


def _print_usage(usage: NormalizedUsage, as_json: bool) -> None:
    if as_json:
        print(json.dumps({"codex": usage.to_dict()}, ensure_ascii=False, indent=2))
        return
    print("AI Usage Monitor diagnostics\n")
    for index, limit in enumerate(usage.limits):
        if index:
            print()
        _print_limit(limit, usage.updated_at)
    print(f"\nUpdated:   {format_jst(usage.updated_at)}")
    print(f"Status:    {usage.status}")


def _print_limit(limit: UsageLimit, now: int) -> None:
    print(f"{limit.display_name}:")
    print(f"Limit ID:  {limit.limit_id}")
    if limit.plan_type:
        print(f"Plan:      {limit.plan_type}")
    if limit.rate_limit_reached_type:
        print(f"Reached:   {limit.rate_limit_reached_type}")
    if limit.spend_control_reached is True:
        print("Spend:     control reached")
    if not limit.windows:
        print("Windows:   Unavailable")
        return
    for window in limit.windows:
        _print_window(window, now)


def _print_window(window: UsageWindow, now: int) -> None:
    print(f"  {window.label}:")
    print(f"    Used:      {window.used_percent}%")
    print(f"    Remaining: {window.remaining_percent}%")
    print(f"    Reset:     {format_jst(window.resets_at)}")
    print(f"    Reset in:  {format_time_remaining(window.resets_at, now)}")


if __name__ == "__main__":
    raise SystemExit(main())
