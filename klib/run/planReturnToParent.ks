{
	local returnToParent is import("mnv/returnToParent-v1").
	local onFail is import("run/onFail").
	local format is import("util/format-v1").
	local REBOOT_TIMER is 60.
	local RETURN_TO_PARENT is "Return to parent".
	export({
		parameter returnPeriapsis, runner.
		until not hasNode { remove nextNode. wait 0. }
		local home is runner:fetch("Home").
		dmsg("Planning return to " + home + " at " + format:distance(returnPeriapsis), true, true).
		local returnToParentResult is returnToParent(returnPeriapsis).
		// TODO: Use same pattern as `planHohmannTransfer` once `returnToParent` removes enouncter logic
		if not returnToParentResult:val {
			onFail:shutdown(returnToParentResult, RETURN_TO_PARENT).
		}

		if not returnToParentResult:ok {
			onFail:reboot(REBOOT_TIMER, returnToParentResult:msg, RETURN_TO_PARENT).
		}
		// returnToParent already adds the node to the flight-path, unlike other maneuver scripts
		runner:next().
	}).
}