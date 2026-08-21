// #include "orbitals-v1.ks"
// #include "executeNode-v1.ks"

declare global APSIS_PERIAPSIS is 0.
declare global APSIS_APOAPSIS is 1.
global function changeApsis {
	parameter whichApsis, altTarget, mnv_args is lex().
	local qApsis is choose periapsis if whichApsis = APSIS_APOAPSIS else apoapsis.
	local burnTime is time:seconds + (choose eta:periapsis if whichApsis = APSIS_APOAPSIS else eta:apoapsis).
	local v0 is VisViva(qApsis).
	local v1 is VisViva(qApsis, qApsis, altTarget).
	local dV is v1 - v0.
	local mnv is node(burnTime, 0, 0, dV).
	add mnv.
	executeNextNode(mnv_args).
	remove mnv.
}