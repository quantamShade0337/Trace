# Network Inspector

A native, local-first macOS network inspector built with Swift 6 and SwiftUI. The existing Xcode target and app bundle are named **Trace**; the window and display name are **Network Inspector**. Free to use, without accounts, telemetry, subscriptions, or developer-operated infrastructure. No license has been selected.

## Build and launch

Requires macOS 15 or later. Build with Xcode 27.1, Swift 6.4 and the macOS 27 SDK; this is the verified toolchain and the project uses the Xcode 27 project format. The engine itself uses Swift 6.2+ features (`@concurrent`). Development and runtime checks used Apple Silicon. The deployment target is macOS 15; execution on macOS 15 and Intel hardware has not been verified.

Open `Trace.xcodeproj`, select the **Trace** scheme and **My Mac**, then Run. No third-party packages are required. For a local build without a configured signing team:

```sh
xcodebuild -project Trace.xcodeproj -scheme Trace \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build
open build/Build/Products/Release/Trace.app
```

Run the engine's Swift Testing suite with `swift test`, or build and test with `./scripts/check.sh`. The package compiles the exact engine sources used by the app. Xcode's app scheme does not contain the separate SwiftPM test target.

Distribution needs a developer-selected bundle identifier, signing team, Developer ID signing, hardened-runtime assessment and notarization. Local unsigned builds are for development. Existing signing identities were detected, but no identity or team was selected or changed.

## Implemented

- **Overview:** an interactive MapKit globe with geodesic connection arcs after user-requested IP location lookup, a searchable destination/app inspector, direct trace/connection actions, compact measured bandwidth history and live connection/process counts. Unknown destinations remain unlocated; nothing is invented.
- **Connections:** `lsof` field-output discovery, owning process/PID, IPv4/IPv6 endpoints, local/remote ports, transport, state, observation time, search, scope filters, sortable native tables, selection inspector and copy/trace actions.
- **Processes:** socket ownership grouped by PID, sortable socket counts, process search, endpoint inspection and trace actions. An executable path is shown when AppKit can identify the running application.
- **Traceroute:** validated hostname/IPv4/IPv6-literal targets, progressive hop parsing, one probe per hop, measured latency, optional reverse resolution, hop/wait limits, cancellation, a MapKit geographic view with a selectable hop timeline, raw output, copy and text export. Missing hops stay visibly unknown. `traceroute6` is selected for IPv6 literals; hostname targets use the IPv4 utility.
- **Network Health:** an ephemeral HTTPS HEAD request, four ICMP probes with latency/loss summaries, timed system resolver lookup, default route/gateway/interface output and system DNS configuration. Checks run concurrently and return individual errors. Target servers and ordinary system resolvers receive the requested diagnostic traffic. HTTP redirects may be followed.
- **History:** SQLite observations every 30 seconds, trace output, diagnostic reports, search/type filters, copy/export, deletion, 1/7/30-day retention and bounds on record count/size and total payload. This is sampled observation history, not a complete flow log.
- **Settings:** appearance (dark/light/system), polling interval, interface selection, recording preference, retention and capability disclosures. Preferences, DNS provider configuration and rules use native local UserDefaults storage; history uses SQLite.
- **Protection foundation:** validated Cloudflare/Quad9/custom DoH configuration, independently constructed `NEDNSOverHTTPSSettings`, runtime entitlement assessment, editable profiles, atomic rule validation and local rule evaluation. This does **not** activate system protection.

Keyboard shortcuts: **⌘1** Overview, **⌘2** Connections, **⌘4** Traceroute, **⌘⇧P** pause/resume, **⌘,** Settings. Closing the last window or quitting cancels sampling and diagnostics, waits for child-process cleanup, and exits. Relaunching resumes monitoring. No login item or background helper is installed.

## Connection globe

The main workspace uses Apple's MapKit realistic globe. Drag to rotate, zoom normally, select a destination in the inspector, or use the globe/focus controls. Curves use native geodesic map polylines. The compact activity strip is measured bandwidth, not simulated packet animation. Destination cards identify the owning apps; **Inspect connections** carries the IP into the real connection table, and **Trace route** starts a diagnostic trace immediately. Router options and technical output are available progressively rather than occupying the main workflow.

Location lookup is **off until requested, for each batch**. Choose **Locate addresses**, review the exact public IP list and provider disclosure, then choose **Locate these addresses**. The app requests approximate locations from [IPWHOIS.io's public endpoint](https://ipwhois.io/documentation) over HTTPS, including an estimate of the current public internet exit IP. No process names, port numbers or history are sent. MapKit independently fetches map content from Apple as the map is viewed.

Private, link-local, loopback, multicast, documentation, carrier-grade NAT and other excluded ranges are never submitted. Each batch is capped at 64 unique public addresses. Results are kept in memory for at most 24 hours and capped at 512 cached endpoints; they are not written into history. Clear them in **Settings → Connection map**. Lookups are cancellable, response bodies are bounded, redirects are refused, and provider errors/rate limits leave ordinary monitoring running.

IP location is an estimate of an address allocation or provider location, not a device location. Anycast, VPNs, mobile networks and registrations can be misleading. The origin marker says **Your internet exit**, not your GPS location. The default camera shows the world and makes no claim about your location. Endpoint arcs are conceptual connections, not measured physical cables. On the traceroute globe, arcs join only consecutive, responding hops with location data; unknown hops are never silently bridged. Private and unanswered hops remain readable in the timeline.

Map content requires access to Apple Maps services; the optional free IP service can be unavailable or rate-limited. Neither dependency is developer-operated. No API key, account, subscription, privileged helper or location permission is added. A location lookup never enables DNS protection or changes network routing.

## Measurement boundaries

Socket discovery runs as the current user. Restricted processes and short-lived sockets may be missing; snapshots do not prove historical completeness. A process name is attribution from `lsof`, not a code-signature trust verdict. DNS names are not inferred from numeric endpoints.

Bandwidth reads `NET_RT_IFLIST2` / `if_msghdr2.ifm_data` 64-bit counters. Default mode sums active `en*` Ethernet-type interfaces, excluding loopback, bridge and tunnel counters to avoid counting the same traffic at multiple layers. A specific interface can be selected, including a tunnel or loopback interface. This is link-level traffic, including overhead, and may differ from application payload totals. Unusual virtual interfaces named `en*` can require manual selection. Counter resets, interface changes, pauses and sampling gaps start new baselines. Historical rates are never displayed as current while paused or after a failed/reset sample.

Resolver timings include utility startup and local cache effects; they are not direct DNS wire latency. An ICMP timeout may reflect filtering, and an HTTPS failure may reflect a server or TLS policy. A successful HTTP response proves connectivity to that endpoint only. Traceroute shows diagnostic probe paths, which may differ from an application's path. Optional IP geolocation is labelled as approximate, and neither geography nor response time establishes security. Route stability over time is not measured.

## DNS protection availability

**System-wide encrypted DNS, DNS interception/filter enforcement, DNS activity logs, temporary system-protection suspension and background protection are unavailable.** The activation button is disabled and explains why. No system DNS, firewall, VPN or proxy configuration is modified. A Mac may independently have encrypted DNS from another product; Inspector does not assess that product's protection state.

Apple's [DNS settings API](https://developer.apple.com/documentation/networkextension/dns-settings) supports DoH/DoT configuration with [NEDNSSettingsManager](https://developer.apple.com/documentation/networkextension/nednssettingsmanager). This repository has no NetworkExtension entitlement, configured signing team, provider extension or verified activation lifecycle. Adding an entitlement string alone does not establish distribution eligibility or enforcement. A future entitled build must load/save settings with explicit consent, handle OS approval, verify resolver behaviour and implement recovery before enabling activation. DNS settings alone do not execute this app's custom block rules; those require a separately supported and verified interception/filter integration.

Provider settings are local configuration only. The UI uses DoH; DoT activation is not implemented. A future configured external resolver would receive DNS queries. Encrypted DNS does not hide the public IP, encrypt all traffic, guarantee anonymity or block all tracking. General web traffic is never routed through a VPN exit by this app.

Profiles begin empty. There are no bundled or downloaded third-party blocklists and no claims of advertising/tracker/malware blocking. User-entered plain domains and hosts-format lists are supported. Rules normalise case, trailing dots and IDNs to punycode, deduplicate, and include subdomains at label boundaries. Allow rules always win. Lists are limited to 1 MiB and 50,000 unique rules each; invalid updates leave saved rules unchanged. Rule tests are local and make no network request.

## Local data and permissions

The direct-distribution target intentionally has App Sandbox disabled so the read-only system utilities can inspect sockets. It does not request root access or install privileged components. It uses fixed executable paths, separate argument arrays, strict target validation, bounded output, timeouts and cancellation. No shell receives user input. There is no TLS interception.

History resides in `~/Library/Application Support/Network Inspector/history.sqlite`, inside a directory created with owner-only permissions. It contains sensitive process names and endpoint metadata. Recording can be disabled; existing records remain until deleted/expired. Retention is applied on load and insert. Storage is limited to 2,000 records, 256 KiB of UTF-8 text per record and 32 MiB of encoded payload (whichever limit is reached first), plus SQLite overhead/free pages. Snapshots include at most 1,000 sockets. Deletion uses SQLite secure-delete and VACUUM; filesystem snapshots/backups may retain older data. Preferences and profiles are not removed by deleting history.

No history or process metadata is uploaded. MapKit requests map content from Apple. User-triggered diagnostics send probes/HTTPS requests and resolver queries; separately approved IP lookup batches send the displayed public addresses to ipwho.is. Trace hostname resolution is opt-in. No metadata is sent to a developer service. Exports contain the selected evidence and should be handled accordingly.

## Verification and remaining release work

See `docs/VERIFICATION.md` for the executed checks and limitations. Unit tests use sanitised fixtures; integration tests use real local sockets, counters and loopback probes. No fake production data is present.

An interactive smoke check verified all navigation destinations, live connection search/inspection, process grouping, loopback traceroute topology/text/copy/export, local health checks, saved history, rule evaluation, keyboard pause/resume and light/dark appearance. The globe itself was rendered and inspected during this redesign. The latest smaller-window refinements and a live external geolocation batch still require an unlocked desktop and explicit lookup approval; see the verification notes. Full VoiceOver navigation and real-world long-route behaviour still need manual QA. Signed/notarized distribution and system-wide DNS protection are not verified. Remote networks may suppress traceroute probes. No detailed ASN intelligence, DNSSEC/TLS certificate inspector, saved domains, anomaly alerts, menu-bar controls or startup integration is included.
