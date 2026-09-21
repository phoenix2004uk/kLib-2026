{
	local lock shipForce to mass * body:mu / (body:radius + altitude)^2.
	local lock facingZenith to vang(up:vector, facing:vector).
	local availableTwr is {
		return availableThrust / shipForce.
	}.
	local currentTwr is {
		return ship:thrust / shipForce.
	}.
	export(lex(
		"available", availableTwr,
		"vAvailable", { return availableTwr() * cos(facingZenith). },
		"hAvailable", { return availableTwr() * sin(facingZenith). },
		"current", currentTwr,
		"vCurrent", { return currentTwr() * cos(facingZenith). },
		"hCurrent", { return currentTwr() * sin(facingZenith). }
	)).
}