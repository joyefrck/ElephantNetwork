# Privacy and secret-handling contract

Elephant Network stores the authenticated Xboard session in platform-protected
storage. Passwords are never persisted. Tokens, quick-login URLs, and full
subscription URLs must never be written to logs, analytics, crash reports, or
diagnostic exports.

The client may request account information, subscription data, and quick-login
links from the configured Elephant Network Xboard service. Transaction and
support pages are rendered from the same service in an embedded browser where
supported, with a system-browser fallback when the embedded runtime is absent.

Signing out stops the Elephant Network-managed connection and removes only the
managed subscription. User-created FlClash profiles remain local and untouched.
