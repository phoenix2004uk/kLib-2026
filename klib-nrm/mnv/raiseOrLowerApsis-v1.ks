{
	local OrbitalMechanics is import("mech/orbitalMechanics-v1").
	local changeApsis is {
		parameter targetAltitude, apsisAltitude, apsisEta.
		return ApiOK(node(time:seconds + apsisEta, 0, 0, OrbitalMechanics:v(apsisAltitude, (targetAltitude + apsisAltitude) / 2 + body:radius) - OrbitalMechanics:v(apsisAltitude))).
	}.
	export(lex(
		"Ap", {
			parameter targetApoapsis.
			return changeApsis(targetApoapsis, periapsis, eta:periapsis).
		},
		"Pe", {
			parameter targetPeriapsis.
			if apoapsis < 0 return ApiFail("There is no apoapsis on an open orbit").
			return changeApsis(targetPeriapsis, apoapsis, eta:apoapsis).
		}
	)).
}