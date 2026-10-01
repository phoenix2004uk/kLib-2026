{
	export(lex(
		"warpTo", {
			parameter runner.
			if warpMode = "PHYSICS" {
				kuniverse:timewarp:cancelWarp().
				wait until kuniverse:timewarp:isSettled.
			}
			local transitionUT is time:seconds + eta:transition.
			if warp = 0 and time:seconds < transitionUT - 30 warpTo(transitionUT).
			runner:next().
		},
		"await", {
			parameter targetBody, runner.
			if body = targetBody {
				local crossingUT is time:seconds.
				kuniverse:timewarp:cancelWarp().
				wait until kuniverse:timewarp:isSettled and time:seconds > crossingUT + 10.
				dmsg("Entered " + body:name + " SOI", true, true).
				runner:next().
			}
		}
	)).
}