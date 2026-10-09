import unittest
from unittest.mock import Mock

from codex_usage_monitor.app_server import AppServerClient


class AppServerNotificationTests(unittest.TestCase):
    def test_refresh_auth_discards_account_details(self) -> None:
        client = object.__new__(AppServerClient)
        client._request = Mock(
            return_value={"account": {"email": "private@example.com"}, "requiresOpenaiAuth": True}
        )

        self.assertIsNone(client.refresh_managed_auth())
        client._request.assert_called_once_with("account/read", {"refreshToken": True})

    def test_watch_timeout_is_not_an_error(self) -> None:
        client = object.__new__(AppServerClient)
        client._notifications = []
        client._read_message = Mock(return_value=None)

        self.assertFalse(client.wait_for_rate_limit_update(0.01))

    def test_queued_rate_limit_notification_is_detected(self) -> None:
        client = object.__new__(AppServerClient)
        client._notifications = [
            {"method": "account/rateLimits/updated", "params": {"rateLimits": {}}}
        ]
        client._read_message = Mock()

        self.assertTrue(client.wait_for_rate_limit_update(0.01))
        client._read_message.assert_not_called()


if __name__ == "__main__":
    unittest.main()
