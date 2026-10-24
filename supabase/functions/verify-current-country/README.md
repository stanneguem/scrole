# verify-current-country

This function validates a recent foreground GPS fix and compares the reverse-geocoded ISO-3166-1 alpha-2 country code with the country selected in the profile. It stores verification metadata only; latitude and longitude are not persisted.

## Required server configuration

Set `GEOLOCATION_VERIFY_URL` to an approved reverse-geocoding endpoint that accepts `lat` and `lon` query parameters and returns the country code in one of these response fields:

- `address.country_code`
- `country_code`
- `countryCode`

Optionally set `GEOLOCATION_VERIFY_TOKEN` if the provider requires a bearer token. Do not put provider credentials in Flutter or commit them to Git.

The function fails closed with `country_verification_not_configured` until the provider URL is configured. Choose a provider with an acceptable privacy policy, data residency, rate limits, and production SLA before enabling this flow.

## Limits

A GPS fix plus reverse geocoding is a location signal, not strong anti-spoofing proof. For high-risk actions, add platform attestation (Play Integrity / App Attest) and validate the attestation server-side. Do not use this check alone as identity verification.
