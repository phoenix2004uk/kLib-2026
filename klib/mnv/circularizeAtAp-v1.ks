{
	local OrbitalMechanics is import("OrbitalMechanics-v1").
	local OrbitalParameters is import("OrbitalParameters-v1").
	function circularizeAtAp {
		if apoapsis < 0 {
			return ApiFail("There is no apoapsis on a hyperbolic trajectory").
		}
		local burnTime is time:seconds + eta:apoapsis.
		local v0 is OrbitalMechanics:v(apoapsis).
		local v1 is OrbitalMechanics:v(apoapsis, OrbitalParameters:a(apoapsis, apoapsis)).
		local dV is v1 - v0.
		local mnv is node(burnTime, 0, 0, dV).
		return ApiOK(mnv).
	}
	export(circularizeAtAp@).
}