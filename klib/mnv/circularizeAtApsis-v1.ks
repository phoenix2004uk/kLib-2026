{
	local OrbitalMechanics is import("mech/orbitalMechanics-v1").

	function circularize {
		parameter apsisAltitude, apsisEta.
		local burnTime is time:seconds + apsisEta.
		local v0 is OrbitalMechanics:v(apsisAltitude).
		local v1 is OrbitalMechanics:v(apsisAltitude, apsisAltitude + body:radius).
		local dV is v1 - v0.
		local mnv is node(burnTime, 0, 0, dV).
		return ApiOK(mnv).
	}

	export(lex(
		"Pe", {
			return circularize(periapsis, eta:periapsis).
		},
		"Ap", {
			if apoapsis < 0 {
				return ApiFail("There is no apoapsis on an open orbit").
			}
			return circularize(apoapsis, eta:apoapsis).
		}
	)).
}