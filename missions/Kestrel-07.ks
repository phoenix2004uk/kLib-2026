// #include "../common/steering-v1.ks"
// #include "../common/staging-v1.ks"
// #include "../common/ascent-v1.ks"
// #include "../common/orbitals-v1.ks"
// #include "../common/seekNode-v1.ks"
// #include "../common/executeNode-v1.ks"
// #include "../common/changeApsis-v1.ks"

set TWR_MAX to 1.8.
set PITCH_DEVIATION_MAX to 10.
set APOAPSIS_TAPER to 5000.
set targetInclination to 0.
set parkingAltitude to 150000.
set orbitalStage to 2.
set ascentProfile to list(
	1e3, 85,
	2e3, 80,
	3e3, 75,
	4e3, 70,
	5e3, 65,
	6e3, 60,
	8e3, 55,
	10e3, 45,
	20e3, 40,
	30e3, 30,
	40e3, 20,
	50e3, 10,
	60e3, 0
).
set targetBody to Mun.
set targetBodyAltitude to (targetBody:orbit:periapsis + targetBody:orbit:apoapsis) / 2.
set flybyAltitude to 30000.
set returnPeriapsis to 35000.

if status = "PRELAUNCH" {
	executeAscent(parkingAltitude, ascentProfile, targetInclination, TWR_MAX, PITCH_DEVIATION_MAX, APOAPSIS_TAPER).
	panels on.
	lights on.
	toggle ag1.
	stageUntil(orbitalStage).
}

if status = "SUB_ORBITAL" {
	print "Orbital insertion burn".
	changeApsis(APSIS_PERIAPSIS, apoapsis).
	set core:tag to "TRANSFER".
}

if core:tag = "TRANSFER" {
	set target to targetBody.
	
	print "Plotting transfer to " + targetBody:name.
	local mnvTime is getTransferTime(targetBody, 0).
	// TODO: we should check against burn time
	if mnvTime - time:seconds < 180 {
		wait 180.
		set mnvTime to getTransferTime(targetBody, 0).
	}

	local posAt is body:position - positionAt(ship, mnvTime).
	local altAt is posAt:mag - body:radius.
	local transferDeltaV is VisViva(altAt, targetBodyAltitude, periapsis) - VisViva(altAt, apoapsis, periapsis).

	local mnv is node(mnvTime, 0, 0, transferDeltaV).
	add mnv.
	seekNode(mnv, list("time", "prograde"), {
		parameter mnv.
		if not mnv:orbit:hasnextpatch return -1e9.
		if mnv:orbit:nextpatch:body <> Mun return -1e9.
		return -abs(mnv:orbit:nextpatch:periapsis - flybyAltitude).
	}).
	executeNextNode().
	remove mnv.

	set core:tag to "WAITING_SOI".
}

if core:tag = "WAITING_SOI" {
	print "Awaiting SOI change".
	lock steering to -sun:position.
	awaitSteering().
	wait until orbit:body = targetBody.
	wait 30.
	set core:tag to "WAITING_CORRECTION".
}

if core:tag = "WAITING_CORRECTION" {
	print "Correcting flyby altitude".

	local mnv is node(time:seconds + 600, 0, 0, 0).
	add mnv.
	seekNode(mnv, list("radial", "prograde"), {
		parameter mnv.
		return -abs(mnv:orbit:periapsis - flybyAltitude).
	}).
	executeNextNode().
	remove mnv.

	set core:tag to "WAITING_PERIAPSIS".
}

if core:tag = "WAITING_PERIAPSIS" {
	print "Orbital insertion burn".
	changeApsis(APSIS_APOAPSIS, periapsis).
	set core:tag to "MUN_ORBIT".
}

if core:tag = "MUN_ORBIT" {
	print "Orbiting Mun".
	
	local mnv is node(time:seconds + getOrbitPeriod(apoapsis, periapsis) * 2, 0, 0, 300).
	add mnv.
	seekNode(mnv, list("time", "prograde"), {
		parameter mnv.
		if not mnv:orbit:hasnextpatch return -1e9.
		if mnv:orbit:nextpatch:body <> Kerbin return -1e9.
		return -abs(mnv:orbit:nextpatch:periapsis - returnPeriapsis).
	}).
	executeNextNode().
	remove mnv.

	set core:tag to "WAITING_ESCAPE".
}

if core:tag = "WAITING_ESCAPE" {
	print "Escaping Mun".
	lock steering to -sun:position.
	awaitSteering().
	wait until orbit:body = Kerbin.
	wait 30.
	set core:tag to "WAITING_REENTRY".
}

if core:tag = "WAITING_REENTRY" {
	print "Re-entry".
	wait until altitude < body:atm:height.
	toggle ag1.
	lock steering to srfRetrograde.
	awaitSteering().
	stage.

	wait until alt:radar < 10000.
	stageUntil(0).
	wait until alt:radar < 1000.
	gear on.

	wait until ship:status = "LANDED" or ship:status = "SPLASHED".
	lock steering to up.
	wait 2.
	sas on.
	unlock steering.
	set core:tag to ship:status.
}

wait until 0.