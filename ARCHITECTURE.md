# Architecture

## Source layout

`Trace/MyApp.swift` owns one `AppModel` and the native window/commands. `ContentView` hosts the eight destinations in a `NavigationSplitView`. `Trace/Features` contains focused SwiftUI screens and UI state. Engine code in `Trace/Engine` is compiled into the app by Xcode's synchronised source group and independently as the `NetworkCore` SwiftPM target for testing. There are no external packages.

| Area | Responsibility |
| --- | --- |
| Core | Typed errors and bounded, cancellable subprocess execution |
| Monitoring | `lsof` records, endpoints, stable socket identity, process groups and query predicates |
| Bandwidth | 64-bit route-interface counters, elapsed-time rates and baseline recovery |
| Tracing | Safe destination validation, incremental hop parser and traceroute execution |
| Geography | Public-address validation, bounded opt-in IP location lookup, destination grouping and truthful geographic route segments |
| NetworkHealth | Concurrent HTTPS, resolver, ICMP, route and DNS checks |
| Protection | Provider validation/settings construction, capability inspection, normalisation and independent matching |
| Persistence | Actor-confined SQLite operations, transactions, retention and bounded observations |

## Isolation and lifecycle

The app uses Swift 6 language mode and nonisolated default isolation. UI observable state is explicitly `@MainActor`. `ConnectionService.snapshot` and `CommandRunner.run` use `@concurrent`; parsing and child process management stay off the main actor. `BandwidthService`, `HistoryStore` and `IPGeolocationService` are actors. Sendable value snapshots cross into UI state. No `@unchecked Sendable` or unsafe nonisolated state is used in production. The immutable, request-driven test URLProtocol fixture restates the framework’s inherited unchecked conformance.

Two cancellable app-owned loops sample bandwidth once per second and sockets every 2/3/5/10 seconds. A single window prevents duplicate sampling. Pausing stops observations and resets bandwidth's baseline; closing the window cancels both loops and active diagnostics. Probe tasks remain cancellable and keep partial trace output. UI state is retained for the app's lifetime. An AppKit application delegate defers termination while cancelled tasks finish child-process cleanup; closing the last window exits. Relaunch starts monitoring. No helper or extension is installed.

A `Process`, pipe and descriptors belong entirely to a single concurrent runner invocation. stdout/stderr share a nonblocking pipe, drained every 60 ms with a 4 MiB cap. Input is a fixed executable plus a separate argument array, never shell text. A monotonic clock bounds duration. Cancellation/timeout terminates only that child; SIGKILL is the final cleanup fallback. A cancelled command never fabricates successful output. `lsof` exit 1 with empty output is a valid empty snapshot; other errors are surfaced. The last successful socket snapshot is retained and marked stale on failure.

Diagnostics run in structured `async let` children. The ephemeral URLSession disables cookies and caches and bounds HTTPS request duration; cancellation propagates to the request and child utility processes. Individual check failures remain evidence rather than failing unrelated checks. The app does not evaluate internet-wide health from one result.

## Observation semantics

Socket identity combines PID, descriptor, transport and endpoints. Time/state updates do not change selection identity; descriptor reuse with different endpoints creates a new identity. This remains a best-effort socket snapshot: identical PID/descriptor/endpoints across process reuse cannot establish flow continuity. History is labelled accordingly.

Bandwidth parses variable-length `NET_RT_IFLIST2` messages with bounds checks and unaligned loads. Interface names come from interface indices. Rates are counter differences divided by monotonic elapsed time. Automatic mode selects active `en*` Ethernet-type interfaces; manual mode selects exactly one interface. Loopback/tunnel/bridge layers are not summed with their underlying physical interfaces. Changed interface sets, decreasing counters, missing interfaces or gaps of 10 seconds or more produce no rate and establish a fresh baseline. The ring contains at most 120 samples.

Traces use one probe per hop, up to 64 hops and a 1–5 second wait. Numeric IPv6 targets select `traceroute6`; hostnames use IPv4 traceroute. Reverse DNS is opt-in. Parsing preserves raw lines, timeout count, annotations and measured probe RTT. A route with multiple responders at one TTL displays its first responder; raw output remains authoritative. A successful process exit means the probe run finished, not that every hop answered or the target was reached.

## Persistence and privacy

`HistoryStore` opens a SQLite handle inside each actor operation and closes it before returning; no pointer crosses isolation boundaries. Inserts and pruning share a transaction. Prepared statements bind external values with buffers held alive through `sqlite3_step`; SQL-interpolated values are bounded numeric limits only. Retention uses the selected 1/7/30-day policy on both reads and writes. Count is capped at 2,000 and cumulative encoded payload at 32 MiB; individual text records cap at 256 KiB on a valid UTF-8 boundary. Snapshot text caps at 1,000 rows. SQLite overhead/free pages add to physical file size. No database migration beyond the version-one additive table/index is currently needed.

The history directory is created owner-only. SQLite secure-delete is enabled; Delete All runs VACUUM. App preferences, provider selection and profiles use UserDefaults with validated Codable payloads. Invalid saved rule/provider payloads produce an explanation and safe defaults. Bandwidth chart history is memory-only. Rule text is not logged as network activity. No history or process metadata is uploaded, no analytics SDK is present and no developer backend is contacted. The user may explicitly approve a public-IP lookup batch as described below.

## Geographic workspace

`NetworkGlobeView` uses SwiftUI MapKit with realistic imagery, native geodesic `MapPolyline` contours, selectable annotations and explicit camera controls. It never synthesises positions for unknown endpoints. `GlobePin` and `GlobeArc` are presentation values; the engine supplies validated coordinates. The destination list is the accessible, textual alternative. Map imagery comes from Apple, and native attribution is preserved. Reduce Motion removes camera animations. The camera recentres on a selected location or a newly located origin, not on every poll.

`RemoteDestination` groups observed sockets by canonical remote numeric address, preserving all process associations. Overview arcs link the approximate public exit to known remote locations and are labelled as conceptual endpoint relationships. `GeographicSegment.trace` joins only consecutive hop numbers with actual responding addresses and known locations. Missing/time-out/unlocated hops create gaps. IP geolocation is never treated as measured packet routing or a trust verdict.

`LocationLookupButton` snapshots up to 64 uncached public addresses into a disclosure popover. Only its explicit approval action invokes `GeographyModel.locate`; subsequent polls and new traces do not automatically expand the approved list. No approval is remembered across batches. The model retains at most 512 locations for up to 24 hours in memory and exposes progress, cancellation and errors. The public exit estimate expires too. Clearing the map never deletes network history, and deleting history never enables lookups.

`IPGeolocationService` uses a cookie/credential/cache-free ephemeral URLSession against fixed HTTPS `ipwho.is` endpoints. It requests only location/organisation fields, bounds bodies at 64 KiB, validates response address identity and coordinate ranges, refuses redirects and explicitly cancels the data task when finished. Private/reserved/non-numeric targets are rejected before any request. A rate limit stops the batch rather than repeatedly retrying. URLs contain only validated public numeric addresses; process names, ports and history never enter the request. Provider errors affect only the map layer.

## Protection boundary

The protection engine is independent of monitoring and diagnostics. `DNSProvider.makeSettings` validates a resolver and creates an `NEDNSOverHTTPSSettings` value without installing it. `ProtectionCapability` reads the current code-signing entitlement; the UI remains unavailable even if an entitlement is present because activation has not been implemented/verified. There are no preference-save calls or network configuration mutations.

Matching uses normalised punycode domains and sets of allow/block rules. Evaluating one domain checks its bounded label suffixes; an allow match takes precedence over any block match. Plain-domain/hosts-format parsing strips comments, normalises and deduplicates the full update before committing. Limits are 1 MiB / 50,000 rules per list. The three local profiles start empty and may be renamed/edited. Saved-rule evaluation is explicitly hypothetical, not an enforcement verdict.

A future DNS integration must supply its own entitled installation, approval, resolver verification, recovery, logging and background lifecycle. DNS settings configuration does not itself intercept queries for custom filtering. Adding such an integration must not change monitoring reliability or route general web traffic through a VPN exit.

## Verification strategy

Swift Testing exercises exact engine source, including parsing, identity, process grouping, query/sort semantics, IPv4/IPv6, >32-bit counters, resets, interface changes, real counter differences, traceroute, input validation, cancellation, timeout, IDN matching, allow precedence, profiles, provider construction, SQLite reload/retention/deletion/corruption loopback diagnostics, public/reserved IPv4/IPv6 classification, provider response validation, hermetic HTTP errors/body limits/cancellation, destination grouping and geographic trace gaps. Test databases use unique temporary directories. Fixtures appear only under `Tests`.

`./scripts/check.sh` runs the tests and a Release Xcode build without selecting a signing identity. Release readiness still requires broader resizing/VoiceOver/long-route QA, oldest-OS testing, a distribution identity/notarization flow and separate DNS integration verification. Detailed results live in `docs/VERIFICATION.md`.
