{
	local OrbitalMechanics is import("mech/orbitalMechanics-v1").
	local OrbitalParameters is import("mech/orbitalParameters-v1").
	export({
		local Pe is periapsis.
		return ApiOK(node(time:seconds + eta:periapsis, 0, 0, OrbitalMechanics:v(Pe, OrbitalParameters:a(Pe, Pe)) - OrbitalMechanics:v(Pe))).
	}).
}