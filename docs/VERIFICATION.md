# Verification — 27 October 2026

## Environment and build

- Xcode 27.1 (27A9275), Apple Swift 6.4, macOS 27 SDK.
- Existing starter Xcode application preserved; replaced Hello World and playground code with the inspector.
- macOS deployment target: 15.0. Swift language mode: 6. Explicit UI isolation; engine default nonisolated.
- No `AGENTS.md` originally existed. The supplied 672-line `Agent.md` was read in full and copied unchanged to `AGENTS.md`; the original remains intact.
- Debug Xcode build passed. The final Release build passed for **arm64 and x86_64** (`ONLY_ACTIVE_ARCH=NO`). `file` confirmed a universal app executable.
- The final `./scripts/check.sh` run passed **47 Swift Testing tests across 8 suites** in about 3.1 seconds, followed by a successful Release Xcode build.
- No Swift compilation warnings or errors were reported. Xcode emitted its standard AppIntents metadata-extraction warning because this app has no AppIntents dependency.
- Three local signing identities exist, but the project has no configured team or NetworkExtension entitlement. Verification used `CODE_SIGNING_ALLOWED=NO`; no identity/team or system entitlement was added.

Reproduce:

```sh
./scripts/check.sh
```

Logs: `build/verification/tests.log`, `build/verification/build.log`. Generated build products and logs are ignored by Git. Local app: `build/Build/Products/Release/Trace.app`.

## Automated coverage

- `lsof` field parsing, ownership, TCP/UDP, IPv4/IPv6, wildcard endpoints, malformed records and deduplication.
- Identity across observation/state changes and descriptor reuse with changed endpoints.
- Search, protocol/state scopes, process grouping and sorting.
- Bandwidth deltas, elapsed time, >32-bit counters, counter resets, interface changes, explicit interface selection and long sampling gaps.
- Real interface counter reads and successive loopback-interface rate measurements, including baseline reset.
- Numeric/named/IPv6 traceroute parsing, latency, timeout hops and unreachable annotations.
- Real IPv4 **and IPv6** loopback traceroutes with measured responding hops.
- Rejection of malformed destinations, shell syntax, schemes/paths/options and whitespace injection.
- Actual subprocess cancellation, timeout, nonzero exit, missing executable and output-cap termination.
- IDN/punycode normalisation, hosts/plain-domain rules, deduplication, label-boundary matching, parent rules, allow precedence and failed atomic updates.
- Independent profiles, DoH provider validation, bootstrap IP validation and construction of native DNS settings without activation.
- SQLite reopen, retention, count cap, total 32 MiB payload cap, valid UTF-8 record cap, deletion and corrupt-database errors.
- Real local diagnostics: resolver lookup, four loopback ICMP probes with 0% loss, route/DNS configuration output, and an explicit HTTPS result. No loopback TLS server was assumed. Diagnostic cancellation propagated across child checks.

Fixtures are sanitised and exist only in tests. Integration tests use actual current-user system data and loopback probes; tests do not install DNS settings or require root access.

## Interactive smoke check

The Release application launched on Apple Silicon. The desktop was initially locked, then unlocked by the user for these checks:

- All eight sidebar destinations loaded meaningful content or an explicit unavailable capability state.
- Overview rendered live measured rates, a historical rate chart, process/socket counts, interfaces and timestamps.
- Connection search filtered real rows. Selecting a socket showed process PID, executable path where available, local/remote endpoints, state and observation time.
- Selecting a process showed its grouped real endpoints and trace actions.
- A real UI-triggered trace to `127.0.0.1` produced one measured hop. Topology selection and traditional text output were inspected.
- Copy was verified by pasting the actual traceroute text into the app's input field, then restoring the target.
- The native Save panel exported `build/verification/traceroute.txt`; the saved file was read back and matched the actual loopback output.
- Local health checks displayed measured resolver timing, loopback RTT/0% loss, available route/DNS output and an honest unavailable HTTPS result for loopback.
- Protection showed a disabled activation control, the missing entitlement explanation and local-only configuration. Evaluating a domain against the empty saved profile returned an explicit hypothetical allow result.
- History survived relaunch and showed saved socket observations, traces and diagnostic reports.
- Light and dark appearances rendered correctly; Dark was restored after testing.
- Keyboard commands navigated to Overview/Settings and paused monitoring; paused live upload/download values became unavailable while previously measured chart history remained visible.
- UI inspection found a traceroute minimum-layout problem that overlapped the toolbar and a wrapping segmented-control label. Both were corrected. The rebuilt Release trace screen was re-run and visually checked successfully.

The AppKit delegate awaits cancelled child-process cleanup before termination. Repeated launch/quit checks during the final unlocked-desktop pass completed, and process inspection confirmed that the app and its traceroute child had exited before relaunch.

## Performance observations

A real `lsof -nP -i -FpcfPnT` snapshot took about **0.03 seconds wall time**, with approximately **1.6 MiB** peak footprint reported by `/usr/bin/time -lp`. A point observation of the running Debug app showed roughly **0.7% CPU and 117 MiB RSS** after several minutes. Those figures precede the MapKit redesign. With the real 3D globe, cached locations and live monitoring visible, a later two-sample `top` observation reported approximately **6% CPU and 542 MiB footprint**; `ps` reported approximately **258 MiB RSS** earlier in the same session. These tools report different memory measures. These are uncontrolled development observations, not a performance guarantee. Bandwidth uses in-process counters; only socket sampling creates periodic subprocesses. Buffers, chart history, filtering lists and persisted history are bounded.

## Unverified or deliberately unavailable

- No encrypted-DNS system activation, filtering enforcement, DNS query interception/logging, temporary system-protection suspension or background protection. The application never saves NetworkExtension preferences or changes DNS/VPN/firewall settings.
- No privileged helper, startup registration or menu-bar integration.
- Signed/notarized distribution, hardened-runtime distribution testing and App Store compatibility are not verified. The direct-distribution target is intentionally outside App Sandbox for utility-based inspection.
- Intel is compiled, not runtime-tested. macOS 15 compatibility is compiled, not tested on that OS.
- Full VoiceOver navigation, maximum-length remote traces, network roaming/sleep stress and resolver activation need further manual/entitled testing.
- Remote HTTPS/ICMP success is not asserted by loopback tests; actual destination/network policies determine their result.
- Route stability, per-process bandwidth, DNS wire latency and complete flow capture are not implemented or claimed.

## MapKit and UX redesign — 27 October 2026

The workspace was redesigned after the user's UI feedback. Overview now centres a real MapKit realistic globe and geodesic endpoint relationships, alongside a searchable destination/app inspector and compact measured bandwidth strip. The sidebar, hierarchy, connection states, app icons, inspector actions, trace timeline, health summaries, protection disclosures, and settings were refined. Technical configuration is progressively disclosed rather than filling the main workflow. Connection selection carries the IP into the connection table; Trace starts a real diagnostic. Running traces cannot be relabelled by selecting a different connection.

The native globe was launched and visually inspected on Apple Silicon; Earth imagery, night lights, native Apple Maps attribution and camera reset rendered. Initial imagery briefly appeared grey while Apple map content loaded, then rendered correctly. The first view review prompted additional camera-distance, bounded-layout and accessibility refinements. The Mac locked again before the final resizing/interaction pass, and an unlock request was made. A one-batch external IP lookup verification was requested separately; no public connection IPs were submitted without a response approving that action.

The latest executed `./scripts/check.sh` run passed **46 tests in 8 suites** and a Release build. The release product remains universal arm64/x86_64. New geography tests cover public/private/special-use IPv4/IPv6, numeric canonicalisation, response address/coordinate validation, grouping, absent-hop gaps, mocked HTTP success/errors/rate limits/body bounds, and cancellation. HTTP fixtures are immutable and confined to `Tests`; production contains no location fixtures, synthetic connections or fake route arcs. No live provider result is claimed by those tests.

IP geolocation is a separately approved, on-demand feature. The disclosure captures exact public addresses before the action; monitoring does not silently submit newly observed IPs. Apple Maps retrieves map data when the map is opened. The provider's HTTPS API and schema were checked against its primary documentation. Actual live provider behaviour, external geodesic arcs against real returned coordinates, and the final unlocked-desktop visual pass remain unverified unless recorded in a subsequent addendum.

## Final unlocked-desktop verification and polish

The user unlocked the Mac and explicitly approved one verification batch. The Release app disclosed **20 exact public destination IPs**, then submitted those addresses and a separate approximate public internet-exit lookup to ipwho.is. All 21 lookups completed successfully. No app names, ports, connection history, or private/special-use addresses were submitted. No further location batch was run. Results remained in memory while navigating and changing appearance.

Verified interactively:

- Real MapKit imagery and geodesic curves connecting the estimated internet exit to real returned destination coordinates. Selecting a destination emphasized its curve and animated camera focus. Multiple addresses at identical coordinates share a counted marker and remain individually selectable in the list.
- Selection opened the corresponding city, provider/organization, IP, connected apps and timestamp. Inspect connections carried the selected IP into a real five-row connection table. Trace route immediately probed that endpoint.
- A real remote trace reached an observed destination through **nine hops**, with eight answering routers and one unanswered hop. The text output matched the route timeline, including actual measured RTTs. Selecting the final hop focused its cached IP location; unlocated intermediate hops were not joined by invented geographic curves.
- A separate non-answering test trace showed progressive discoveries while running; Stop cancelled promptly and retained its partial eight-hop result. No traceroute process was left behind.
- The map canvas, inspector, activity strip and status bar remained visible in native compact and expanded arrangements, including a 1,000-point-wide window. Both navigation columns are explicitly bounded to their macOS layout proposals. Inner map panels no longer rely on nested native split-view minimum sizing.
- Short opacity transitions for navigation and inspector changes, animated camera focus, and progressive timeline-row arrival are implemented with Reduce Motion handling. Switching Globe/Text preserves the map instance. Live destination rows use stable app/address ordering so changing socket counts do not reorder the list under the pointer.
- Light and dark appearances were checked with actual cached locations; Dark and live monitoring were restored afterward.

Two defects discovered during these checks were corrected: the first disclosure could initially render an empty batch because separately updated presentation state was stale; it now presents an immutable item containing the exact addresses. A successful traceroute utility exit could be mistaken for reaching the destination; completion now requires the final responding hop to match the resolved numeric target, with regression coverage for timeouts and unreachable responses.

Final finishing changes restore an existing map selection when its screen is recreated, move primary trace/inspect actions above the connected-app list so they are visible sooner, allow a click anywhere in a connection row to select it, and correct singular location-count copy. The automatic selection restoration calls the same camera-focus path verified through explicit selection. Per-frame animation smoothness, full VoiceOver coverage and sleep/network-change stress are not claimed as exhaustively tested.

The final automated suite passes **47 tests in 8 suites**; the Release application compiles for arm64 and x86_64. The standard missing-AppIntents-dependency metadata warning is the only reported build warning. Geographic lookup fixtures remain confined to tests; no synthetic network data or locations are installed in production.
