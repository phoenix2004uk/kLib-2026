{
	local matchInclination is import("mnv/matchInclination-v1").
	local onFail is import("run/onFail").
	export({
		parameter targetOrbitable, whichNode, errorMargin, runner.
		until not hasNode { remove nextNode. wait 0. }
		dmsg("Planning to match inclination with " + targetOrbitable:name, true, true).
		local matchInclinationResult is matchInclination(targetOrbitable, whichNode, errorMargin).
		onFail:shutdown(matchInclinationResult, "Inclination change").
		add matchInclinationResult:val.
		runner:next().
	}).
}