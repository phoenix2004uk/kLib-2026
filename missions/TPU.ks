// Registry maps the stable screen name used by mission messages to the
// local telemetry definition script imported on this processor.
local SCREEN_REGISTRY is lex(
	"orbit", "tlm/screens/orbit",
	"vessel", "tlm/screens/vessel"
	// "rendezvous", "tlm/screens/rendezvous",
	// "maneuver", "tlm/screens/maneuver",
	// "program", "tlm/screens/program",
	// "moon-descent", "tlm/screens/moonDescent"
).

local DEFAULT_SCREENS is list(
	"orbit",
	"vessel"
	// "rendezvous",
	// "maneuver",
	// "program"
).

local DEFAULT_ACTIVE_SCREEN is "".

import("telemetryController-v1")(
	SCREEN_REGISTRY,
	DEFAULT_SCREENS,
	DEFAULT_ACTIVE_SCREEN
).