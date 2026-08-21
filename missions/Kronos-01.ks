// #include "../common/steering-v1.ks"
// #include "../common/staging-v1.ks"
// #include "../common/ascent-v1.ks"
// #include "../common/orbitals-v1.ks"
// #include "../common/executeNode-v1.ks"
// #include "../common/changeApsis-v1.ks"

set TWR_MAX to 1.8.
set PITCH_DEVIATION_MAX to 10.
set APOAPSIS_TAPER to 5000.
set targetInclination to 0.
set targetAltitude to 100000.
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

if status = "PRELAUNCH" {
	executeAscent(targetAltitude, ascentProfile, targetInclination, TWR_MAX, PITCH_DEVIATION_MAX, APOAPSIS_TAPER).
	panels on.
	lights on.
	stageUntil(orbitalStage).
}

if status = "SUB_ORBITAL" {
	print "Orbital insertion burn".
	changeApsis(APSIS_PERIAPSIS, apoapsis).
}

on abort {
	print "Preparing to de-orbit".
	lock throttle to 0.
	lock steering to retrograde.
	awaitSteering().
	lock throttle to 1.
	wait until availableThrust = 0 or periapsis < 35000.
	lock throttle to 0.
	lock steering to srfRetrograde.
	wait 1.
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
}

lock steering to -sun:position.
wait until 0.