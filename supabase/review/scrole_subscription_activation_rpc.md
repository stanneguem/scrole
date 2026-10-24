# Trusted subscription activation

`scrole_activate_subscription` is a service-role-only RPC for the future verified payment webhook. It creates a Pro/Premium subscription idempotently by provider reference, refuses a second active subscription, grants the included profile certification and writes an audit record.

It deliberately does not process payments itself. The caller must verify the provider signature and successful payment before invoking the RPC. Renewals must use `scrole_renew_subscription` with explicit event/community selections.
