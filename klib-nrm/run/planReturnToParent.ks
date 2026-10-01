{
	local returnToParent is import("mnv/returnToParent-v1").
	local onFail is import("run/onFail").
	local format is import("util/format-v1").
	local RETURN_TO_PARENT is "Return to parent".
	export({
		parameter returnPeriapsis, runner.
		until not hasNode { remove nextNode. wait 0. }
		dmsg("Planning return to " + runner:fetch("Home") + " at " + format:distance(returnPeriapsis), true, true).
		local returnToParentResult is returnToParent(returnPeriapsis).
		if not returnToParentResult:val onFail:shutdown(returnToParentResult, RETURN_TO_PARENT).
		if not returnToParentResult:ok onFail:reboot(60, returnToParentResult:msg, RETURN_TO_PARENT).
		runner:next().
	}).
}