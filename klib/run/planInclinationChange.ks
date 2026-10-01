{
	local changeInclinationAtNode is import("mnv/changeInclinationAtNode-v1").
	local onFail is import("run/onFail").
	function planInclinationChange {
		parameter plannerDelegate, targetInclination, thetaLim, runner.
		until not hasNode { remove nextNode. wait 0. }
		dmsg("Planning plane change", true, true).
		local planeChangeResult is plannerDelegate(targetInclination, thetaLim).
		onFail:shutdown(planeChangeResult, "Plane change").
		add planeChangeResult:val.
		runner:next().
	}
	export(lex(
		"AN", planInclinationChange@:bind(changeInclinationAtNode:AN),
		"DN", planInclinationChange@:bind(changeInclinationAtNode:DN),
		"next", planInclinationChange@:bind(changeInclinationAtNode:next),
		"last", planInclinationChange@:bind(changeInclinationAtNode:last),
		"highest", planInclinationChange@:bind(changeInclinationAtNode:highest),
		"lowest", planInclinationChange@:bind(changeInclinationAtNode:lowest)
	)).
}