{
	function isSettled {
		return vang(ship:facing:vector, steeringManager:target:vector) < 0.25.
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