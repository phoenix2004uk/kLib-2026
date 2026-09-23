{
	local awaitSteering is import("sys/steering-v1"):awaitSteering.
	local autostage is import("sys/staging-v1"):autostage.
	local burnDuration is {
		parameter dV, at_stage is stage:number.
		local m is 0.
		local p is 0.
		local f is 0.
		local n is 0.
		local g is constant:g0.
		for p in ship:parts if p:stage <= at_stage set m to m + p:mass.
		for en in ship:engines {
			if (at_stage < stage:number and en:stage = at_stage) or (at_stage = stage:number and en:ignition and not en:flameout) {
				set f to f + en:possiblethrustat(ship:q).
				set p to p + en:ispat(ship:q).
				set n to n + 1.
			}
		}
		if n > 0 set p to p / n.
		if f = 0 or p = 0 return 0.
		return g * m * p * (1 - constant:e^(-abs(dV) / (g*p))) / f.
	}.
	export(lex(
		"burnDuration", burnDuration,
		"warpToNode", {
			parameter leadTime is 60.
			if not hasnode return.
			warpTo(time:seconds + nextnode:eta - burnDuration(nextnode:deltav:mag/2) - leadTime).
		},
		"executeNode", {
			parameter leadTime is 60.
			if not hasnode return.
			local mnv is nextnode.
			local dV0 is mnv:deltaV.
			local halfBurnDuration is burnDuration(dV0:mag/2).
			wait until mnv:eta <= halfBurnDuration + leadTime.
			kuniverse:timewarp:cancelwarp().
			wait until kuniverse:timewarp:issettled.
			lock steering to mnv:deltaV.
			awaitSteering().
			wait until mnv:eta <= halfBurnDuration.
			lock throttle to max(0.001, min(mnv:deltaV:mag * mass / max(1e-6, availableThrust), 1)).
			until dV0 * mnv:deltaV < 0 or (mnv:deltaV:mag < 1e-2 and dV0 * mnv:deltaV < 0.5) {
				autostage().
				wait 0.
			}
			lock throttle to 0.
			unlock steering.
			wait 0.1.
			remove mnv.
		}
	)).
}