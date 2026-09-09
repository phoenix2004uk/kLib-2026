{
	local OrbitalMechanics is import("mech/orbitalMechanics-v1").
	local circularize is{
		parameter apsisAltitude,apsisEta.
		return ApiOK(node(time:seconds+apsisEta,0,0,OrbitalMechanics:v(apsisAltitude,apsisAltitude+body:radius)-OrbitalMechanics:v(apsisAltitude))).
	}.
	export(lex(
		"Pe",{
			return circularize(periapsis,eta:periapsis).
		},
		"Ap",{
			if apoapsis<0 return ApiFail("There is no apoapsis on an open orbit").
			return circularize(apoapsis,eta:apoapsis).
		}
	)).
}