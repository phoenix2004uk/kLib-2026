{
	local airlessAscent is import("prg/airlessAscent-v1").
	export({
		parameter ascentHeading, ascentApoapsis, runner.
		dmsg(body:name + " ascent guidance active", true, true).
		local ascentState is airlessAscent(ascentHeading, ascentApoapsis).
		if ascentState <> "ORBITING" and ascentState <> "SUB_ORBITAL" {
			notify(body:name + " ascent failed - shutting down").
			dmsg(body:name + " ascent failed: " + ascentState, true).
			shutdown.
		}
		runner:next().
	}).
}