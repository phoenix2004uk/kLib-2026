// #include "steering-v1.ks"

function isCurrentStageEngineActive {
	parameter en, at_stage.
	return at_stage = stage:number and en:ignition and not en:flameout.
}
function isEngineInStage {
	parameter en, at_stage.
	return at_stage < stage:number and en:stage = at_stage.
}
function engineStats {
	parameter at_stage is stage:number.
	local p is 0.
	local f is 0.
	local n is 0.
	for en in ship:engines {
		if isEngineInStage(en, at_stage) or isCurrentStageEngineActive(en, at_stage) {
			set f to f + en:possiblethrustat(ship:q).
			set p to p + en:ispat(ship:q).
			set n to n + 1.
		}
	}
	if n > 0 set p to p / n.
	return List(f, p).
}
function stageMass {
	parameter at_stage is stage:number.
	local total_mass is 0.
	for p in ship:parts if p:stage <= at_stage set total_mass to total_mass + p:mass.
	return total_mass.
}

global function burnDuration {
	parameter dV, at_stage is stage:number.

	local m is stageMass(at_stage).
	local e is constant:e.
	local ens is engineStats(at_stage).
	local f is ens[0].
	local p is ens[1].
	local g is constant:g0.
	if f = 0 or p = 0 return 0.

	return g * m * p * (1 - e^(-abs(dV) / (g*p))) / f.
}

global function executeNextNode {
	parameter args is lex().
	local MINUMUM_THRUST is 0.001.

	local conf is lex(
		"lead_time", 60,
		"precision", 1e-2,
		"auto_warp", 0
	).
	for k in args:keys set conf[k] to args[k].

	if not hasnode return.
	local mnv is nextnode.

	local halfBurnDuration is burnDuration(mnv:deltav:mag/2).
	local leadDuration is halfBurnDuration + conf:lead_time.
	if conf:auto_warp warpTo(time:seconds + mnv:eta - leadDuration).
	wait until mnv:eta <= leadDuration.
	kuniverse:timewarp:cancelwarp().
	wait until kuniverse:timewarp:issettled.

	lock steering to mnv:burnvector.
	awaitSteering().

	local dV0 is mnv:deltav.
	local lock max_acceleration to ship:availablethrust / ship:mass.
	local lock mnv_throttle to max(MINUMUM_THRUST, min(mnv:deltav:mag / max_acceleration, 1)).

	wait until mnv:eta <= halfBurnDuration.
	lock throttle to mnv_throttle.
	wait until vdot(dV0, mnv:deltav) < 0 or (mnv:deltav:mag < conf:precision and vdot(dV0, mnv:deltav) < 0.5).
	lock throttle to 0.
	unlock steering.
	wait 0.1.
}