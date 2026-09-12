{
	local ANGLE_THRESHOLD is 0.25.
	local ROLL_THRESHOLD is 0.25.
	function isSettled {
		return abs(steeringManager:angleError) < ANGLE_THRESHOLD and abs(steeringManager:rollError) < ROLL_THRESHOLD.
	}
	function awaitSteering {
		wait 0.
		wait until isSettled().
	}
	export(lex(
		"awaitSteering", awaitSteering@,
		"isSettled", isSettled@
	)).
}