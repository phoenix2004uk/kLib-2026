// #include "orbitalParameters-v1.ks"
// #include "orbitalMechanics-v1.ks"
// #include "executeNode-v1.ks"

global function circularizeAtAp {
	parameter mnv_args is lex().

	local burnTime is time:seconds + eta:apoapsis.
	local v0 is OrbitalMechanics:v(apoapsis).
	local v1 is OrbitalMechanics:v(apoapsis, OrbitalParameters:a(apoapsis, apoapsis)).
	local dV is v1 - v0.
	local mnv is node(burnTime, 0, 0, dV).
	add mnv.
	executeNextNode(mnv_args).
	remove mnv.
}