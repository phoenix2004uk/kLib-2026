// SCAN Maxwell 1
// Radar Altimetry scan of Kerbin
// Altitude = 250km
// Ecc < 0.0021
// 83.1 <= Inc <= 83.6
// Start scan with AG1

local deps is list(
	"steering-v1",
	"staging-v1",
	"ascent-v1",
	"orbitals-v1",
	"seekNode-v1",
	"executeNode-v1",
	"changeApsis-v1"
).
if homeConnection:isConnected {
	for file in deps copyPath("0:/common/" + file, "1:/" + file).
}
for file in deps runOncePath("1:/" + file).

local TWR_MAX is 1.8.
local PITCH_DEVIATION_MAX is 10.
local APOAPSIS_TAPER is 5000.
local launchInclination is 90.
local targetInclinationMin is 83.1.
local targetInclinationMax is 83.6.
local maxEccentricity is 0.0021.
local parkingAltitude is 249500.
local ascentProfile is list(
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
	executeAscent(parkingAltitude, ascentProfile, launchInclination, TWR_MAX, PITCH_DEVIATION_MAX, APOAPSIS_TAPER).
	panels on.
	lights on.
	stageUntil(0).
	set core:tag to "ORBITAL_INSERTION".
}

if core:tag = "ORBITAL_INSERTION" {
	print "Orbital insertion burn".
	changeApsis(APSIS_PERIAPSIS, apoapsis).
	set core:tag to "TUNING_ORBIT".
}

local lock vslNormal to vcrs(body:position, velocity:orbit).

if core:tag = "TUNING_ORBIT" {
	if orbit:inclination < targetInclinationMin {
		print "Tuning orbit inclination (increase)".
		lock steering to lookDirUp(-vslNormal, body:position).
		awaitSteering().
		wait until latitude > 5.
		wait until latitude < 5.
		lock throttle to 1.
		wait until orbit:inclination >= targetInclinationMin.
		lock throttle to 0.
		wait 0.
	}

	if orbit:inclination > targetInclinationMax {
		print "Tuning orbit inclination (decrease)".
		lock steering to lookDirUp(vslNormal, body:position).
		awaitSteering().
		wait until latitude > 5.
		wait until latitude < 5.
		lock throttle to 1.
		wait until orbit:inclination <= targetInclinationMax.
		lock throttle to 0.
		wait 0.
	}

	if orbit:eccentricity > maxEccentricity {
		print "Tuning orbit eccentricity".
		wait until eta:apoapsis < 5.
		lock steering to prograde.
		awaitSteering().

		until orbit:eccentricity < maxEccentricity {
			wait until eta:apoapsis < 10.
			lock throttle to 1.
			wait until eta:apoapsis > 10 or orbit:eccentricity < maxEccentricity.
			lock throttle to 0.
			wait 0.
		}
	}
}

on abort {
	lock steering to retrograde.
	awaitSteering().
	lock throttle to 1.
}

print "Aligning panels & deploying radar".
toggle ag1.
lock steering to sun:position.
print "Program complete".
wait until 0.