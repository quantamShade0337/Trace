# Network Inspector design

## Scene and theme

A Mac user at their desk investigating an unfamiliar app connection should see a calm spatial overview, with readable evidence alongside it. Dark-first is an explicit repository requirement, with complete light support.

## Visual hierarchy

The MapKit globe is the main canvas. Compact overview metrics and a narrow measured activity strip support it. A right-hand destination list and inspector connect the map to actions. Avoid a dashboard made of oversized cards. Screens use concise 22-point titles; 13-point body text, 11-point secondary text, and monospaced endpoints establish hierarchy without oversized marketing headlines.

## Colour and surfaces

Native system appearances with cool charcoal surfaces in dark mode, pale neutral surfaces in light mode. One muted blue accent marks selected destinations and primary actions. Use semantic foreground colours and a single hairline separator between major workspaces. Map imagery is real Apple Maps content, never a fake globe image.

## Layout

A compact 190–220-point native sidebar. Consistent 20–24-point content gutters; compact 8–12-point control spacing. Overview pairs the globe with a 300-point inspection panel; smaller windows scroll the detail panel rather than hide actions. A compact chart stays below the geographic canvas. Tables remain available for raw socket investigation.

## Components

App icons where available, plain-language connection states, a selectable destination list with location/ownership/context, a restrained toolbar, and inline capability explanations. Technical output, probe options and provider configuration use disclosure. Empty geographic states explain how to locate real public addresses instead of drawing imaginary routes.

## Globe and motion

Use MapKit realistic imagery, selectable annotations and geodesic curves. Endpoint arcs mean an approximate relationship, not a measured physical cable path. Traceroute arcs only join consecutive geolocated responding hops, never silently bridge unknown hops. Camera focus follows explicit selection; gradual route discovery is useful feedback. Honour Reduce Motion. Do not continuously spin the globe or animate unmeasured packet traffic.

## Privacy UX

Each location batch is user-triggered and discloses public addresses sent to ipwho.is, including a lookup of the current public exit address for the approximate origin. No process names, ports or history are uploaded. No GPS permission is needed. Apple Maps retrieves map content from Apple. Unknown/private addresses remain in the textual inspector.
