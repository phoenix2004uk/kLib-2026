{
	local lock localGravity to body:mu / (body:radius + altitude)^2.
	local lock shipForce to mass * localGravity.
	local lock facingZenith to vang(up:vector, facing:vector).

	function availableTwr {
		return ship:availableThrust / shipForce.
	}

	function availableVerticalTwr {
		return availableTwr() * cos(facingZenith).
	}

	function availableHorizontalTwr {
		return availableTwr() * sin(facingZenith).
	}

	function currentTwr {
		return ship:thrust / shipForce.
	}

	function currentVerticalTwr {
		return currentTwr() * cos(facingZenith).
	}

	function currentHorizontalTwr {
		return currentTwr() * sin(facingZenith).
	}

	export(lex(
		"available", availableTwr@,
		"vAvailable", availableVerticalTwr@,
		"hAvailable", availableHorizontalTwr@,
		"current", currentTwr@,
		"vCurrent", currentVerticalTwr@,
		"hCurrent", currentHorizontalTwr@
	)).
}