# 4080 stored authorization schema evidence

Exact independently reviewed body `A079F9A1648FCA54774DD1D8490D32C3C6B8CF91EBBB57A7D9187622DF51B32F` executed once via isolated instance3/private18084, exit0 in1.578seconds. No token, character ID, campaign value or raw load ID was emitted. No native chat/header-authentication test occurred.

```json
{"auth_character_valid":true,"auth_token_valid":true,"campaign_identity_matches":true,"gamets":272866,"generation_present":true,"load_id_sha256":"4b227777d4dd1fc61c6f884f48641d02b4d121d3fd328cb08b5531fcacdabf8a","manager_ready_matches":true,"session_present":true,"status":"ready","stored_receipt_valid":false,"switching_source_sha256":"eac727f650a9a22c1e5361d7c6a69b977ee9bb66d0e1f7a5278badc9fd71c488"}
```

Important schema interpretation: served switching source hash exactly matches local `pending-fixes/stobe-session-readiness-20261013/baseline/lib/playthrough_switching.php`. That source has no `pas_receipt_valid()` function. Its `pas_guard()` checks stored status and token/header equality directly when auto-switching is enabled. The diagnostic's false `stored_receipt_valid` therefore indicates an unavailable newer helper, not an invalid stored token. Token and character format/campaign identity are valid. Never block or classify an auth bug from the absent-helper result.

V2 diagnostic adds an explicit `auth_function_present` boolean to distinguish this case. Native header authentication remains unproven until an actual correlated request. The stored record is ready and contains a valid token; there is no evidence requiring a server auth patch on this route from this read.

V2 executed once after independent CLEAR: exact body `FCADF43315581F7072F3700018AC221EEFA0C21B80D1DB7420211744B0E1918F`, exit0 in1.442seconds. It confirmed `auth_function_present=false` and otherwise the same ready/format/campaign/generation flags and source hash. This confirms the absent-helper interpretation, not native request authentication.
