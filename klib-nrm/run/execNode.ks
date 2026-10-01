{
	local prgExecuteNode is import("prg/executeNode-v1").
	local requireNode is {
		if not hasNode {
			dmsg("No maneuver nodes in the flight-plan - shutting down", true, true).
			shutdown.
		}
	}.
	local settleWarp is {
		kuniverse:timewarp:cancelWarp().
		wait until kuniverse:timewarp:isSettled.
	}.
	export(lex(
		"warpTo", {
			parameter leadTime, runner.
			requireNode().
			if warpMode = "PHYSICS" settleWarp().
			local preburnUT is time:seconds + nextNode:eta - leadTime - prgExecuteNode:burnDuration(nextNode:deltav:mag / 2).
			if warp = 0 and time:seconds < preburnUT - 30 warpTo(preburnUT).
			runner:next().
		},
		"exec", {
			parameter leadTime, mnvType, runner.
			requireNode().
			if nextNode:eta < leadTime + prgExecuteNode:burnDuration(nextNode:deltav:mag / 2) {
				dmsg("Executing " + mnvType, true, true).
				settleWarp().
				local rcsState is rcs.
				rcs on.
				local completed is prgExecuteNode:executeNode(leadTime).
				if not rcsState rcs off.
				if not completed {
					dmsg("Maneuver execution failed - Not enough DeltaV", true, true).
					shutdown.
				}
				runner:next().
			}
		}
	)).
}