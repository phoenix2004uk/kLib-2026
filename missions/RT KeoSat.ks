// RT KeoSat
// Script to place 4 KeoSat satellites in Keostationary orbit with 90 degree separation
// kOS terminal will prompt user to enter the satellite number [1..4] for the launch
// Deploy Antenna/Dish with AG1

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
local targetInclination is 0.
local parkingAltitude is 100000.
local targetAltitude is 2863334.
local targetPeriod is 5*3600 + 59*60 + 9.425.
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
	print "Please specify satellite designation: 1-4".
	wait until terminal:input:hasChar.
	local satNum is terminal:input:getChar().
	set ship:name to ship:name + " " + satNum.

	executeAscent(parkingAltitude, ascentProfile, targetInclination, TWR_MAX, PITCH_DEVIATION_MAX, APOAPSIS_TAPER).
	panels on.
	lights on.
	stageUntil(0).
	set core:tag to "ORBITAL_INSERTION".
}

if core:tag = "ORBITAL_INSERTION" {
	print "Orbital insertion burn".
	changeApsis(APSIS_PERIAPSIS, apoapsis).
	set core:tag to "MATCH_INCLINATION".
}

if core:tag = "MATCH_INCLINATION" {
	print "Matching inclination".

	local incRelative is getRelativeInclination(Mun).
	local nodes is getRelativeNodes(Mun).
	local whichNode is nodes["other"].
	local nextNodeAnomaly is nodes[whichNode].
	local altNextNode is getAnomalyAltitude(nextNodeAnomaly).
	local etaNextNode is getAnomalyEta(nextNodeAnomaly).
	local timeNextNode is time:seconds + etaNextNode.
	// local dv is 2 * VisViva(altNextNode, periapsis, apoapsis) * sin(incRelative / 2).
	local dv is VisViva(altNextNode, periapsis, apoapsis) * tan(incRelative).
	if whichNode = "AN" set dv to -dv.

	local mnv is node(timeNextNode, 0, dv, 0).
	add mnv.
	executeNextNode().
	remove mnv.
	set core:tag to "TRANSFER".
}

if core:tag = "TRANSFER" {
	if ship:name = "RT KeoSat 1" {
		print "Boosting orbit to " + round(targetAltitude/1e3,0) + "km".
		changeApsis(APSIS_APOAPSIS, targetAltitude).
		print "Circularizing".
		changeApsis(APSIS_PERIAPSIS, apoapsis).
	}
	else {
		local targetVesselName is "".
		if ship:name = "RT KeoSat 2" set targetVesselName to "RT KeoSat 1".
		else if ship:name = "RT KeoSat 3" set targetVesselName to "RT KeoSat 2".
		else if ship:name = "RT KeoSat 4" set targetVesselName to "RT KeoSat 3".
		else set targetVesselName to 0/0.

		print "Plotting transfer to " + targetVesselName.
		set target to Vessel(targetVesselName).
		local mnvTime is getTransferTime(target, -90).
		// TODO: we should check against burn time
		if mnvTime - time:seconds < 180 {
			print "Waiting " + (mnvTime - time:seconds + 10) + "s for next transfer".
			wait until time:seconds > mnvTime + 10.
			set mnvTime to getTransferTime(target, -90).
		}

		local posAt is body:position - positionAt(ship, mnvTime).
		local altAt is posAt:mag - body:radius.
		local transferDeltaV is VisViva(altAt, targetAltitude, periapsis) - VisViva(altAt, apoapsis, periapsis).
		local mnv is node(mnvTime, 0, 0, transferDeltaV).
		add mnv.
		executeNextNode().
		remove mnv.

		print "Circularizing".
		changeApsis(APSIS_PERIAPSIS, apoapsis).
	}
	set core:tag to "TUNING_PERIOD".
}

function secondsToTimeString {
	parameter secs.
	local h is floor(secs / 3600).
	set secs to secs - h*3600.
	local m is floor(secs / 60).
	set secs to secs - m*60.
	local s is floor(secs, 3).
	return h+"h " + m+"m " + s+"s".
}

if core:tag = "TUNING_PERIOD" {
	if abs(obt:period - targetPeriod) > 0.01 {
		print "Tuning orbit period".
		print "Current Period: " + secondsToTimeString(orbit:period).
		print "Target Period:  " + secondsToTimeString(targetPeriod).
		if orbit:period < targetPeriod {
			lock steering to prograde.
			awaitSteering().
			lock throttle to 0.0001.
			wait until orbit:period >= targetPeriod.
			lock throttle to 0.
		}
		else if orbit:period > targetPeriod {
			lock steering to retrograde.
			awaitSteering().
			lock throttle to 0.0001.
			wait until orbit:period <= targetPeriod.
			lock throttle to 0.
		}
	}

	print "Aligning panels & deploying antennae".
	toggle ag1.
}

on abort {
	lock steering to retrograde.
	awaitSteering().
	lock throttle to 1.
}

lock steering to sun:position.
print "Program complete".
wait until 0.