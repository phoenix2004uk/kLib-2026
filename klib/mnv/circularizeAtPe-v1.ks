// #include "../kldr-stub.ks"
{
	local OrbitalMechanics is import("OrbitalMechanics-v1").
	local OrbitalParameters is import("OrbitalParameters-v1").
	function circularizeAtPe {
		local burnTime is time:seconds + eta:periapsis.
		local v0 is OrbitalMechanics:v(periapsis).
		local v1 is OrbitalMechanics:v(periapsis, OrbitalParameters:a(periapsis, periapsis)).
		local dV is v1 - v0.
		local mnv is node(burnTime, 0, 0, dV).
		add mnv.
	}
	export(circularizeAtPe@).
}