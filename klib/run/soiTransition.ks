{
	local WARP_TIME_THRESHOLD is 30.
	local SOI_SETTLE_THRESHOLD is 10.
	export(lex(
		"warpTo", {
			parameter runner.
			if warpMode = "PHYSICS" {
				kuniverse:timewarp:cancelWarp().
				wait until kuniverse:timewarp:isSettled.
			}
			local transitionUT is time:seconds + eta:transition.
			if warp = 0 and time:seconds < transitionUT - WARP_TIME_THRESHOLD {
				warpTo(transitionUT).
			}
			runner:next().
		},
		"await", {
			parameter targetBody, runner.
			if body = targetBody {
				// cancel warp and wait `SOI_SETTLE_THRESHOLD` seconds after changing SOI -> a psuedo `soi:isSettled`
				local crossingUT is time:seconds.
				kuniverse:timewarp:cancelWarp().
				wait until kuniverse:timewarp:isSettled and time:seconds > crossingUT + SOI_SETTLE_THRESHOLD.
				dmsg("Entered " + body:name + " SOI", true, true).
				runner:next().
			}
		}
	)).
}