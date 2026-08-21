// #include "../lib-v1/steering-v1.ks"
// #include "../lib-v1/staging-v1.ks"
// #include "../lib-v1/ascent-v2.ks"
// #include "../lib-v1/circularizeAtAp-v1.ks"

set TWR_MAX to 1.8.
set PITCH_DEVIATION_MAX to 10.
set APOAPSIS_TAPER to 5000.
set targetInclination to 0.
set parkingAltitude to 100e3.
set orbitalStage to 2.
set ascentProfile to list(
	2e3, 85,
	3e3, 80,
	4e3, 75,
	5e3, 70,
	6e3, 65,
	7e3, 60,
	8e3, 55,
	9e3, 50,
	10e3, 45,
	20e3, 40,
	30e3, 30,
	40e3, 20,
	50e3, 10,
	60e3, 0
).

if status = "PRELAUNCH" {
	// executeAscent(parkingAltitude, ascentProfile, targetInclination, TWR_MAX, PITCH_DEVIATION_MAX, APOAPSIS_TAPER).
	// executeAscentPid(parkingAltitude, targetInclination).
	executeAscentPidV2(parkingAltitude, targetInclination).
	panels on.
	lights on.
	orbitalInsertion(parkingAltitude).
	stageUntil(orbitalStage).
	circularizeAtAp().
}

on abort {
	lock steering to retrograde.
	awaitSteering().
	lock throttle to 1.
	wait until periapsis < 35e3.
	lock throttle to 0.
	lock steering to srfRetrograde.
	stageUntil(0).
	wait until status = "LANDED" or status = "SPLASHED".
	unlock steering.
	wait 5.
	sas on.
}

wait until 0.