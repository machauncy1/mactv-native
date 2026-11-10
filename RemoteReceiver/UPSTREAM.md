# Protocol source

`vendor/atv-core` is taken from https://github.com/corvofeng/atv-core at
`8a4ada29bb7cad31e0315c3387b277eb9ab8c988`. Its Cargo workspace declares MIT;
the snapshot has no standalone LICENSE file. The original Cargo license metadata
and this attribution are retained; no different license is assigned to the vendored code.

MacTV changes: authenticated controller key persistence and signature verification;
random pair-verify ephemeral keys; pairing window policy; idempotent per-connection
readiness callbacks. The original macOS key/mouse injection adapter, CLI, Android
integration and web debug server are not used by the MacTV helper.

The helper communicates only through inherited stdin/stdout pipes. MacTV owns its
lifetime. Closing stdin stops the receiver and withdraws Bonjour advertisements.
