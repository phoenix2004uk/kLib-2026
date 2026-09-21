{
	local OrbitalMechanics is import("mech/orbitalMechanics-v1").
	local OrbitalParameters is import("mech/orbitalParameters-v1").
	export({
		local Ap is apoapsis.
		if Ap < 0 {
			return ApiFail("There is no apoapsis on a hyperbolic trajectory").
		}
		return ApiOK(node(time:seconds + eta:apoapsis, 0, 0,  OrbitalMechanics:v(Ap, OrbitalParameters:a(Ap, Ap)) - OrbitalMechanics:v(Ap))).
	}).
}