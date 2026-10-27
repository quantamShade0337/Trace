Product Vision

Build a premium, native macOS application that combines network visibility, diagnostics, and privacy protection.

The application should allow users to understand what their Mac is doing on the network, investigate individual connections, trace network routes, monitor network health, and protect DNS activity without routing normal internet traffic through a VPN.

The product should be useful to both everyday Mac users and technically advanced users.

This is a real, distributable application, not a prototype or a visual demonstration.

### Core principles

1. Privacy without changing the user's public IP.
2. Accurate, transparent network monitoring.
3. Meaningful security protection without expensive infrastructure.
4. Exceptional native macOS design.
5. Local-first operation with no accounts or subscriptions.
6. Low system overhead and reliable background operation.
7. No fabricated information, security claims, or functionality.

**Target:** macOS 15+, Apple Silicon first, with Intel support where practical.

**Licensing:** Prepare the project for an open-source release. Do not choose a license without explicit approval.

---

## 2. Agent Responsibilities

Act as a senior macOS systems engineer, network security engineer, Swift developer, and Apple-platform product designer.

Take ownership of the technical implementation.

- Inspect the repository and existing code before making changes.
- Research relevant Apple SDK interfaces and platform restrictions using available local documentation.
- Make reasonable engineering decisions independently.
- Implement working functionality rather than stopping at planning.
- Maintain clear architecture and readable code.
- Build and test after substantial changes.
- Fix errors before declaring completion.
- Never fabricate implementation status or test results.
- Explicitly identify unsupported capabilities and permission requirements.
- Preserve working functionality when extending the application.

Do not ask unnecessary questions.

Escalate decisions involving elevated privileges, security-sensitive system changes, signing entitlements, or irreversible operations.

---

## 3. Technology Stack

### Application

- Swift 6
- SwiftUI
- AppKit where necessary
- macOS 15+
- Xcode

### System integration

- Foundation
- Darwin networking interfaces
- Network.framework
- NetworkExtension where supported and properly entitled
- Supported macOS diagnostic utilities
- SystemConfiguration where appropriate

### Persistence

- SQLite or SwiftData
- Local-only storage
- Configurable retention and deletion

### Concurrency

- Swift structured concurrency
- Actors for shared mutable state
- AsyncStream where appropriate
- Cancellation-aware background operations

Do not use Electron, embedded web dashboards, private APIs, or unnecessary third-party dependencies.

---

## 4. Application Architecture

Maintain distinct modules with clear responsibilities.

### Core

Shared models, configuration, errors, utilities, and dependency injection.

### Monitoring

Connection discovery, process attribution, sampling, and observation state.

### Bandwidth

System-wide throughput monitoring and historical measurements.

### Tracing

Traceroute execution, parsing, route models, and interactive visualisation.

### NetworkHealth

DNS latency, connectivity diagnostics, packet loss, and network quality measurements.

### Protection

DNS configuration, encrypted DNS, filtering policies, provider selection, and protection status.

### Persistence

Connection snapshots, diagnostic history, preferences, and retention.

### Features

SwiftUI screens, view models, navigation, and presentation components.

### Settings

Permissions, startup behaviour, DNS providers, filtering profiles, and privacy controls.

Keep the protection engine independent from the network inspector.

A failure in monitoring must not disable protection, and a failure in protection must not crash monitoring.

Do not introduce unnecessary packages, abstraction layers, or microservices.

---

## 5. Network Inspector

Implement real network monitoring.

### Required functionality

- Active network connections.
- Owning process name and PID where available.
- Local and remote IP addresses.
- Local and remote ports.
- Transport protocol.
- Connection state.
- Observation timestamps.
- Search, sorting, and filtering.
- Process grouping and inspection.
- Pause and resume monitoring.
- Local connection history.

Investigate supported macOS interfaces and diagnostic utilities, including `lsof` and `nettop`, before selecting a monitoring backend.

### Data integrity

- Never fabricate connections.
- Never invent per-process bandwidth.
- Never confuse sampled observations with complete flow history.
- Never claim all connections are visible if permissions or APIs restrict visibility.
- Distinguish measured, inferred, and unavailable data.
- Show explicit errors when monitoring fails.

Monitoring must not block the main actor.

Use bounded sampling and memory consumption.

---

## 6. Interactive Connection Tracing

Connection tracing is a flagship feature.

Users should be able to select a remote connection and trace the network path toward its destination.

### Functionality

- IPv4 traceroute.
- IPv6 support where feasible.
- Progressive hop discovery.
- Hop numbers and responding addresses.
- Round-trip latency measurements.
- DNS hostname resolution where available.
- Timeout and unreachable-hop handling.
- Trace cancellation.
- Configurable maximum hops and timeouts.
- Traditional textual trace output.
- Copy and export functionality.

Use a dedicated `TracerouteService`.

Execute diagnostic utilities using validated arguments and safe process APIs. Never interpolate untrusted addresses into shell commands.

Do not automatically request root access.

### Visualisation

Build a premium, interactive SwiftUI topology view.

- Display each discovered hop as a node.
- Connect nodes in sequence.
- Animate discovery progressively.
- Differentiate destination, intermediate, and timed-out hops.
- Allow selecting a hop for details.
- Handle long routes gracefully.
- Support keyboard navigation and accessibility.
- Avoid misleading geographic placement.

A traceroute measures diagnostic probe paths, not necessarily the exact path of an existing application connection.

Never represent inferred paths as verified.

---

## 7. Encrypted DNS Protection

Build an optional DNS privacy and protection subsystem.

This is not a commercial VPN.

### Primary requirements

- Support encrypted DNS using DNS-over-HTTPS and/or DNS-over-TLS.
- Allow users to choose compatible DNS providers.
- Support custom resolver configuration where feasible.
- Preserve the user's ordinary public IP address.
- Do not tunnel general web traffic through shared VPN exit servers.
- Do not require developer-operated infrastructure.
- Allow protection to be enabled and disabled.
- Clearly display actual protection status.
- Explain permission requirements.

Potential providers include Cloudflare, Quad9, and other compatible public resolvers.

Do not hardcode the application to a single provider.

### macOS integration

Investigate supported Apple DNS configuration mechanisms and NetworkExtension capabilities.

Validate entitlement, signing, installation, and deployment requirements before implementing system-wide protection.

Do not assume a DNS settings API provides access to every DNS request.

Do not claim system-wide DNS enforcement until verified.

If system-wide DNS configuration is unavailable, implement a clearly labelled supported alternative rather than silently simulating protection.

### Privacy guarantees

Encrypted DNS protects DNS queries between the device and its configured resolver.

It does not:

- Encrypt all internet traffic.
- Hide the user's public IP address.
- Guarantee anonymity.
- Prevent every tracking technique.
- Guarantee avoidance of CAPTCHAs or bot challenges.

Never market DNS protection as a full VPN.

---

## 8. DNS-Based Filtering

Implement optional domain-based filtering where supported.

### Features

- Advertising-domain blocking.
- Tracker-domain blocking.
- Known malicious-domain blocking.
- Custom allowlists.
- Custom blocklists.
- Protection profiles.
- Temporary protection suspension.
- Rule explanations.
- Locally stored configuration.

Use reputable, openly licensed filtering sources.

Respect redistribution terms and update policies.

### Filtering engine

- Parse and normalise domains safely.
- Handle internationalised domain names.
- Deduplicate rules.
- Support efficient matching.
- Keep memory usage bounded.
- Apply updates atomically.
- Avoid blocking critical connectivity unintentionally.
- Allow users to restore defaults.

Filtering must not interfere with unrelated network traffic.

Do not promise that DNS filtering can block every advertisement or tracker.

### DNS activity logging

If supported by the selected system integration, provide:

- Queried domain.
- Timestamp.
- Resolver response.
- Allowed or blocked status.
- Matching filtering rule.
- Query latency.

Do not fabricate DNS activity from unrelated network observations.

---

## 9. Protection Profiles

Support configurable protection profiles.

Suggested defaults:

**Standard**

- Encrypted DNS.
- Minimal filtering.
- Prioritise compatibility.

**Privacy**

- Encrypted DNS.
- Advertising and tracking protection.
- Balanced filtering.

**Strict**

- Encrypted DNS.
- Expanded blocking.
- Clear warnings about possible website breakage.

Users must be able to customise profiles.

Do not claim a profile is active unless the underlying protection mechanism is actually operating.

---

## 10. Background Protection

Design protection to remain operational when the main application window closes.

Requirements:

- Clear protection status.
- Menu bar access.
- User-controlled startup behaviour.
- Safe enable/disable controls.
- Recovery after network changes.
- Recovery after sleep and wake.
- Proper shutdown and cleanup.
- No hidden background activity.

Use supported macOS background execution and extension mechanisms.

Do not assume a regular application process will remain alive after quitting.

Background protection must be implemented through an appropriate supported mechanism and verified before being advertised as reliable.

---

## 11. Network Health Diagnostics

Build a dedicated network diagnostics module.

### Diagnostics

- Connectivity status.
- DNS resolution latency.
- Round-trip latency.
- Packet loss where measurable.
- Network interface status.
- Gateway information where available.
- Route stability.
- DNS configuration.
- Traceroute-based investigation.

Present actual measurements with timestamps and relevant context.

Do not create an arbitrary security score.

If a health score is introduced, its calculation must be transparent and based on measurable criteria.

Do not confuse general network quality with security.

---

## 12. User Interface

The application should feel like a premium Apple-platform utility.

### Visual direction

- Minimalist.
- Dark-first.
- Full light-mode support.
- Monochrome foundation.
- Restrained accent colour.
- High-quality typography.
- Generous but deliberate spacing.
- Professional data tables.
- Subtle micro-interactions.
- Clear information hierarchy.

Avoid:

- Glassmorphism.
- Excessive gradients.
- Neon hacker aesthetics.
- Decorative emojis.
- Fake terminal animations.
- Oversized dashboard cards.
- Unnecessary modal dialogs.
- Web-style interfaces that ignore macOS conventions.

### Main navigation

- Overview
- Connections
- Processes
- Traceroute
- Network Health
- Protection
- History
- Settings

Use native navigation and platform conventions.

### Interaction quality

- Keyboard shortcuts.
- Context menus.
- Search and filters.
- Resizable windows.
- Accessible controls.
- Informative tooltips.
- Proper loading states.
- Clear error states.
- Permission explanations.
- Responsive updates.

Every visible control must perform a real action or be explicitly disabled.

---

## 13. Performance Requirements

This is a continuously running utility.

Performance is a first-class requirement.

- Minimise idle CPU usage.
- Avoid unnecessary polling.
- Avoid excessive subprocess spawning.
- Batch persistence operations.
- Use bounded caches.
- Avoid unbounded connection history.
- Prevent redundant SwiftUI updates.
- Cancel obsolete tasks.
- Handle rapid network changes.
- Recover cleanly from subprocess failures.

Measure performance during development.

Do not optimise based solely on assumptions.

---

## 14. Security and Privacy

The application handles sensitive network metadata.

### Requirements

- Local-first operation.
- No accounts.
- No developer-operated backend.
- No analytics or telemetry by default.
- No automatic upload of network history.
- Configurable history retention.
- User-controlled data deletion.
- Safe subprocess execution.
- Strict input validation.
- Secure handling of configuration.
- Minimal privileges.
- Clear consent for protection changes.

Never:

- Disable System Integrity Protection.
- Bypass macOS security mechanisms.
- Install privileged components silently.
- Use undocumented privilege escalation.
- Modify firewall rules without explicit authorisation.
- Redirect general traffic through third-party VPN infrastructure.
- Intercept TLS application content.
- Claim protections that have not been verified.

External DNS resolvers and blocklist providers may receive the requests necessary to deliver their services. Disclose these dependencies.

---

## 15. Testing

Write automated tests for:

- Connection parsing.
- Process attribution.
- Connection deduplication.
- Bandwidth calculations.
- Traceroute parsing.
- IPv4 and IPv6 handling.
- Trace cancellation.
- DNS provider configuration.
- Domain matching.
- Filtering rule precedence.
- Blocklist parsing.
- Profile switching.
- History retention.
- Error recovery.

Use captured, sanitised diagnostic fixtures.

Mocks are permitted in tests and explicitly labelled preview modes, not as substitutes for real production functionality.

Where possible, add integration tests for actual network behaviour.

---

## 16. Development and Verification

For substantial changes:

1. Inspect the relevant existing code.
2. Identify the smallest coherent implementation.
3. Implement it.
4. Add relevant tests.
5. Build the application.
6. Run tests.
7. Fix introduced failures.
8. Verify real functionality where possible.
9. Document limitations.
10. Summarise completed work.

Do not stop at scaffolding when a working implementation is feasible.

Do not claim successful compilation without actually compiling.

Do not claim network protection works merely because the interface displays an enabled state.

Security-sensitive changes require explicit verification.

---

## 17. Implementation Priorities

Build incrementally.

### Phase 1 — Core Inspector

- Native application shell.
- Real connection monitoring.
- Process inspection.
- Search and filtering.
- Bandwidth overview.
- Basic history.

### Phase 2 — Tracing

- Traceroute engine.
- Progressive results.
- Interactive topology.
- Trace details.
- Export.

### Phase 3 — Network Health

- DNS latency diagnostics.
- Connectivity checks.
- Packet loss measurements.
- Route analysis.

### Phase 4 — DNS Protection

- Investigate macOS DNS integration.
- Validate entitlements.
- Implement supported encrypted DNS configuration.
- Verify actual resolver usage.
- Build provider selection and protection status.

### Phase 5 — Filtering

- Domain filtering engine.
- Rule management.
- Protection profiles.
- Blocklist updates.
- DNS activity logging where supported.

### Phase 6 — Background Operation

- Reliable background protection.
- Menu bar controls.
- Startup configuration.
- Sleep/wake recovery.
- Distribution and signing validation.

Do not rush into privileged system components before the read-only inspector is reliable.

---

## 18. Documentation

Maintain:

- `README.md`
- `ARCHITECTURE.md`
- `AGENTS.md`

Document:

- Installation.
- Build requirements.
- Supported macOS versions.
- Required permissions.
- Network monitoring limitations.
- DNS protection limitations.
- External provider dependencies.
- Privacy implications.
- Known issues.

Do not document planned features as though they are implemented.

---

## 19. Definition of Done

A feature is complete when:

- It behaves as intended.
- It uses real data.
- It handles errors and unavailable capabilities.
- It is integrated into the application.
- Relevant tests pass.
- The project builds.
- Its limitations are accurately communicated.

When hardware, entitlements, signing, or permissions prevent verification, state that explicitly.

---

## 20. Final Product Philosophy

Build a network utility that people genuinely want to keep running on their Macs.

The application should make complex networking understandable without sacrificing technical accuracy.

Protection must be meaningful, transparent, and unobtrusive.

The app should improve users' privacy without unnecessarily changing their network identity, breaking websites, or introducing subscription costs.

Every visualisation must represent real information.

Every security claim must be defensible.

Every feature must serve a purpose.

**Build something powerful, beautiful, reliable, free, and worth using every day.**
