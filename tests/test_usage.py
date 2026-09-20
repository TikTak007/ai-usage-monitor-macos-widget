import unittest
from datetime import datetime

from codex_usage_monitor.usage import (
    JST,
    UsageDataError,
    describe_response_shape,
    format_jst,
    format_time_remaining,
    format_window_label,
    normalize_usage,
)


class NormalizeUsageTests(unittest.TestCase):
    def test_preserves_every_window_regardless_of_primary_secondary_position(self) -> None:
        payload = {
            "rateLimits": {
                "limitId": "codex",
                "primary": {
                    "usedPercent": 36,
                    "windowDurationMins": 10080,
                    "resetsAt": 2_000,
                },
                "secondary": {
                    "usedPercent": 22,
                    "windowDurationMins": 300,
                    "resetsAt": 1_000,
                },
            }
        }

        usage = normalize_usage(payload, now=500)

        self.assertEqual(len(usage.limits), 1)
        self.assertEqual(usage.limits[0].limit_id, "codex")
        self.assertEqual(
            [(window.label, window.remaining_percent) for window in usage.limits[0].windows],
            [("Weekly (7-day)", 64), ("5-hour", 78)],
        )

    def test_includes_all_multi_bucket_limits_and_prefers_them_over_legacy(self) -> None:
        payload = {
            "rateLimits": {
                "limitId": "codex",
                "primary": {"usedPercent": 99, "windowDurationMins": 300, "resetsAt": 1},
                "secondary": None,
            },
            "rateLimitsByLimitId": {
                "codex_bengalfox": {
                    "limitId": "codex_bengalfox",
                    "limitName": "GPT-5.3-Codex-Spark",
                    "planType": "pro",
                    "primary": {"usedPercent": 8, "windowDurationMins": 180, "resetsAt": 2},
                    "secondary": None,
                },
                "codex": {
                    "limitId": "codex",
                    "limitName": None,
                    "planType": "pro",
                    "primary": {"usedPercent": 12, "windowDurationMins": 10080, "resetsAt": 3},
                    "secondary": None,
                },
            },
        }

        usage = normalize_usage(payload, now=0)

        self.assertEqual([limit.limit_id for limit in usage.limits], ["codex", "codex_bengalfox"])
        self.assertEqual(usage.limits[0].display_name, "Codex")
        self.assertEqual(usage.limits[0].windows[0].used_percent, 12)
        self.assertEqual(usage.limits[1].display_name, "GPT-5.3-Codex-Spark")
        self.assertEqual(usage.limits[1].windows[0].label, "3-hour")

    def test_unknown_duration_is_displayable_instead_of_discarded(self) -> None:
        payload = {
            "rateLimits": {
                "primary": {"usedPercent": 10, "windowDurationMins": 90, "resetsAt": 10},
                "secondary": None,
            }
        }

        usage = normalize_usage(payload, now=0)

        self.assertEqual(usage.limits[0].windows[0].label, "90-minute")
        self.assertEqual(usage.limits[0].windows[0].remaining_percent, 90)

    def test_null_duration_is_preserved_as_unavailable(self) -> None:
        payload = {
            "rateLimits": {
                "primary": {"usedPercent": 10, "windowDurationMins": None, "resetsAt": None},
                "secondary": None,
            }
        }

        usage = normalize_usage(payload, now=0)

        self.assertEqual(usage.limits[0].windows[0].label, "Duration unavailable")

    def test_snapshot_without_windows_remains_visible(self) -> None:
        payload = {
            "rateLimitsByLimitId": {
                "future-model": {
                    "limitId": "future-model",
                    "limitName": None,
                    "primary": None,
                    "secondary": None,
                }
            }
        }

        usage = normalize_usage(payload, now=0)

        self.assertEqual(usage.limits[0].display_name, "Additional limit")
        self.assertEqual(usage.limits[0].windows, ())

    def test_rejects_out_of_range_percentage(self) -> None:
        payload = {
            "rateLimits": {
                "primary": {"usedPercent": 101, "windowDurationMins": 300, "resetsAt": 10},
                "secondary": None,
            }
        }

        with self.assertRaises(UsageDataError):
            normalize_usage(payload, now=0)

    def test_rejects_response_without_any_snapshot(self) -> None:
        with self.assertRaises(UsageDataError):
            normalize_usage({}, now=0)

    def test_response_description_includes_display_metadata_but_not_credit_details(self) -> None:
        payload = {
            "rateLimits": {
                "limitId": "codex",
                "limitName": "Codex",
                "planType": "pro",
                "primary": {"usedPercent": 12, "windowDurationMins": 300, "resetsAt": 3},
                "secondary": None,
            },
            "rateLimitsByLimitId": None,
            "rateLimitResetCredits": {"availableCount": 1, "credits": [{"id": "opaque"}]},
        }

        description = describe_response_shape(payload)

        self.assertEqual(description["rate_limits"]["limit_id"], "codex")
        self.assertEqual(description["rate_limits"]["limit_name"], "Codex")
        self.assertEqual(description["rate_limits"]["plan_type"], "pro")
        self.assertNotIn("opaque", str(description))
        self.assertTrue(description["rate_limit_reset_credits_present"])

    def test_normalizes_reset_credit_expiration_without_retaining_opaque_id(self) -> None:
        payload = {
            "rateLimits": {
                "primary": {"usedPercent": 12, "windowDurationMins": 10080, "resetsAt": 3},
            },
            "rateLimitResetCredits": {
                "availableCount": 2,
                "credits": [
                    {
                        "id": "opaque-one",
                        "resetType": "codexRateLimits",
                        "status": "available",
                        "grantedAt": 10,
                        "expiresAt": 300,
                        "title": "Full reset",
                        "description": "Ready to redeem",
                    },
                    {
                        "id": "opaque-two",
                        "resetType": "futureResetType",
                        "status": "futureStatus",
                        "grantedAt": 20,
                        "expiresAt": 200,
                    },
                ],
            },
        }

        usage = normalize_usage(payload, now=0)

        self.assertEqual(usage.reset_credits.available_count, 2)
        self.assertEqual(usage.reset_credits.nearest_expiration, 200)
        self.assertNotIn("opaque-", str(usage))

    def test_distinguishes_count_only_reset_credits(self) -> None:
        payload = {
            "rateLimits": {
                "primary": {"usedPercent": 12, "windowDurationMins": 10080, "resetsAt": 3},
            },
            "rateLimitResetCredits": {"availableCount": 1, "credits": None},
        }

        usage = normalize_usage(payload, now=0)

        self.assertEqual(usage.reset_credits.available_count, 1)
        self.assertIsNone(usage.reset_credits.credits)

    def test_rejects_invalid_reset_credit_count(self) -> None:
        payload = {
            "rateLimits": {
                "primary": {"usedPercent": 12, "windowDurationMins": 10080, "resetsAt": 3},
            },
            "rateLimitResetCredits": {"availableCount": -1, "credits": []},
        }

        with self.assertRaises(UsageDataError):
            normalize_usage(payload, now=0)


class FormattingTests(unittest.TestCase):
    def test_formats_known_and_dynamic_window_durations(self) -> None:
        self.assertEqual(format_window_label(180), "3-hour")
        self.assertEqual(format_window_label(300), "5-hour")
        self.assertEqual(format_window_label(10080), "Weekly (7-day)")
        self.assertEqual(format_window_label(60), "1-hour")
        self.assertEqual(format_window_label(1440), "1-day")
        self.assertEqual(format_window_label(45), "45-minute")

    def test_formats_timestamp_in_jst(self) -> None:
        timestamp = int(datetime(2026, 8, 8, 4, 4, tzinfo=JST).timestamp())
        self.assertEqual(format_jst(timestamp), "2026-08-08 04:04:00 JST")

    def test_formats_time_remaining(self) -> None:
        self.assertEqual(format_time_remaining(2 * 86400 + 3 * 3600 + 14 * 60, 0), "2d 3h 14m")

    def test_elapsed_reset_does_not_go_negative(self) -> None:
        self.assertEqual(format_time_remaining(1, 100), "0h 0m")


if __name__ == "__main__":
    unittest.main()
