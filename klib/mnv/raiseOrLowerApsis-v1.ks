{
	// Raise or lower an apsis at the opposing apsis
	local OrbitalMechanics is import("mech/orbitalMechanics-v1").

	function changeApsis {
		parameter targetAltitude, apsisAltitude, apsisEta.

		local targetSMA is (targetAltitude + apsisAltitude) / 2 + body:radius.
		local v0 is OrbitalMechanics:v(apsisAltitude).
		local v1 is OrbitalMechanics:v(apsisAltitude, targetSMA).
		local dV is v1 - v0.

		return ApiOK(node(time:seconds + apsisEta, 0, 0, dV)).
	}

	export(lex(
		"Ap", {
			parameter targetApoapsis.
			return changeApsis(targetApoapsis, periapsis, eta:periapsis).
		},
		"Pe", {
			parameter targetPeriapsis.
			if apoapsis < 0 {
				return ApiFail("There is no apoapsis on an open orbit").
			}
			return changeApsis(targetPeriapsis, apoapsis, eta:apoapsis).
		}
	)).
}