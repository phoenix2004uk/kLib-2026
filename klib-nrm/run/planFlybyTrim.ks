{
	local altitudeSafety is import("tlm/altitudeSafety-v1").
	local changeFlybyPe is import("mnv/changeFlybyPe-v1").
	local onFail is import("run/onFail").
	local format is import("util/format-v1").
	export({
		parameter bodyFlybyPeriapsis, leadTime, ensureSafeAltitude, runner.
		until not hasNode { remove nextNode. wait 0. }
		dmsg("Trimming " + body:name + " approach", true, true).
		local targetedFlybyPeriapsis is bodyFlybyPeriapsis.
		if ensureSafeAltitude {
			local altitudeSafetyResult is altitudeSafety:altitude(body).
			onFail:shutdown(altitudeSafetyResult, "Approach trim", "Terrain height check").
			set targetedFlybyPeriapsis to max(bodyFlybyPeriapsis, altitudeSafetyResult:val + 100).
			dmsg("     Minimum Pe = " + format:distance(bodyFlybyPeriapsis), true).
			dmsg("    Terrain max = " + format:distance(altitudeSafetyResult:val), true).
			dmsg("    Targeted Pe = " + format:distance(targetedFlybyPeriapsis), true).
		}
		runner:share("targetedFlybyPeriapsis", targetedFlybyPeriapsis).
		local flybyResult is changeFlybyPe(targetedFlybyPeriapsis, leadTime).
		onFail:shutdown(flybyResult, "Approach trim").
		add flybyResult:val.
		runner:next().
	}).
}