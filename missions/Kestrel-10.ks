local ascent is import("prg/atmosphericAscent-v2").
local hohmannTransfer is import("mnv/hohmannTransfer-v1").
local changeFlybyPe is import("mnv/changeFlybyPe-v1").
local pExecuteNode is import("prg/executeNode-v1").
local executeNode is pExecuteNode:executeNode.
local warpToNode is pExecuteNode:warpToNode.
local altitudeSafety is import("tlm/altitudeSafety-v1").
local descent is import("prg/airlessDescent-v2").
local airlessAscent is import("prg/airlessAscent-v1").
local circularize is import("mnv/circularizeAtAp-v1").
local matchInclination is import("mnv/matchInclination-v1").
local returnToParent is import("mnv/returnToParent-v1").
local atmosphericDescent is import("prg/atmosphericDescent-v1").
local staging is import("sys/staging-v1").
local stageUntil is staging:stageUntil.
local autostage is staging:autostage.
local steeringSystem is import("sys/steering-v1").
local awaitSteering is steeringSystem:awaitSteering.
local steeringSettled is steeringSystem:isSettled.
local rt is import("sys/remoteTech-v1").

// System Init
set terminal:width to 60.
set terminal:height to 15.
clearScreen.
kuniverse:timewarp:cancelwarp().
wait until kuniverse:timewarp:issettled.

// Mission State
local StatePath is "1:/step.json".
function SaveState {
	parameter state.
	writeJson(state, StatePath).
	return state.
}
function LoadState {
	if exists(StatePath) return readJson(StatePath).
	return "".
}
local currentState is LoadState().

// Mission Configuration
local targetBody is Mun.
local launchApoapsis is 100e3.
local launchInclination is 0.
local flybyPeriapsis is 0. // get as low as possible
local moonAscentHeading is 90. // this should probably be inclination
local moonAscentApoapsis is 14e3.
local returnPeriapsis is 35e3.

// Mission Overview
if currentState = "" {
	prelaunch().
	set currentState to SaveState("KerbinLaunch").
}
if currentState = "KerbinLaunch" {
	kerbinLaunch(launchApoapsis, launchInclination).
	set currentState to SaveState("KerbinOrbitalInsertion").
}
if currentState = "KerbinOrbitalInsertion" {
	kerbinOrbitalInsertion(launchApoapsis).
	set currentState to SaveState("KerbinCircularization").
}
if currentState = "KerbinCircularization" {
	kerbinCircularization().
	set currentState to SaveState("MatchMoonPlane").
}
if currentState = "MatchMoonPlane" {
	kerbinAdjustInclination().
	set currentState to SaveState("KerbinOrbit").
}
if currentState = "KerbinOrbit" {
	kerbinOrbit().
	set currentState to SaveState("MoonTransfer").
}
if currentState = "MoonTransfer" {
	transferToMoon(targetBody).
	set currentState to SaveState("MoonSOI").
}
if currentState = "MoonSOI" {
	awaitSOIChange(targetBody).
	set currentState to SaveState("MoonFlyby").
}
if currentState = "MoonFlyby" {
	trimMoonFlyby(flybyPeriapsis).
	set currentState to SaveState("MoonDeorbit").
}
if currentState = "MoonDeorbit" {
	moonDeorbitAtPeriapsis().
	set currentState to SaveState("MoonDescent").
}
if currentState = "MoonDescent" {
	moonDescent().
	set currentState to SaveState("MoonSurface").
}
if currentState = "MoonSurface" {
	local returnToOrbit is false.
	on abort set returnToOrbit to true.
	notify("Press ABORT to launch from " + body:name).
	wait until returnToOrbit.
	set currentState to SaveState("MoonAscent").
}
if currentState = "MoonAscent" {
	moonAscent(moonAscentHeading, moonAscentApoapsis).
	set currentState to SaveState("MoonCircularization").
}
if currentState = "MoonCircularization" {
	moonCircularization().
	set currentState to SaveState("KerbinReturn").
}
if currentState = "KerbinReturn" {
	until obt:hasnextpatch {
		notify("Press ABORT to attempt return").
		local attempReturn is false.
		on abort set attempReturn to true.

		wait until attempReturn.
		returnToKerbin(returnPeriapsis).
	}
	set currentState to SaveState("KerbinSOI").
}
if currentState = "KerbinSOI" {
	awaitSOIChange(Kerbin).
	set currentState to SaveState("KerbinReentry").
}
if currentState = "KerbinReentry" {
	kerbinReentry().
	set currentState to SaveState("Done").
}
if currentState = "Done" {
	shutdown.
}

// Mission Steps
function prelaunch {
	notify("Launch in 3 seconds").
	lights on.
	wait 3.
}

function kerbinLaunch {
	parameter launchApoapsis, launchInclination is 0.

	notify("Beginning Kerbin ascent").
	ascent:executeAscent(launchApoapsis, launchInclination).
}

function kerbinOrbitalInsertion {
	parameter launchApoapsis.

	notify("Beginning orbital insertion").
	ascent:orbitalInsertion(launchApoapsis).
	stageUntil(3).
}

function kerbinCircularization {
	until not hasNode { remove nextNode. wait 0. }
	notify("Planning Kerbin circularization").
	local circularizeResult is circularize().
	if not circularizeResult:ok {
		notify("Circularization failed - shutting down").
		dmsg("Circularization planning failed: " + circularizeResult:msg, true).
		shutdown.
	}

	rcs on.
	add circularizeResult:val.
	if steeringSettled() warpToNode(15).
	notify("Executing Kerbin circularization").
	executeNode(15).
	rcs off.
}

function kerbinAdjustInclination {
	notify("Planning to match inclination with " + targetBody:name).
	dmsg("Planning to match inclination with " + targetBody:name, true).
	until not hasNode { remove nextNode. wait 0. }
	set target to targetBody.

	local matchInclinationResult is matchInclination(targetBody).
	if not matchInclinationResult:ok {
		notify("Transfer failed - shutting down").
		dmsg("Transfer planning failed: " + matchInclinationResult:msg, true).
		shutdown.
	}

	add matchInclinationResult:val.
	notify("Matching inclination with " + targetBody:name).
	warpToNode(15).
	executeNode(15).
}

function kerbinOrbit {
	notify("Kerbin orbit achieved").
	notify("Deploying solar panels").
	panels on.
	lights on.
}

function transferToMoon {
	parameter targetBody.

	notify("Planning transfer to " + targetBody:name).
	dmsg("Planning transfer to " + targetBody:name, true).
	until not hasNode { remove nextNode. wait 0. }
	set target to targetBody.

	local hohmannResult is hohmannTransfer(targetBody).
	if not hohmannResult:ok {
		notify("Transfer failed - shutting down").
		dmsg("Transfer planning failed: " + hohmannResult:msg, true).
		shutdown.
	}

	add hohmannResult:val.
	notify("Executing transfer to " + targetBody:name).
	warpToNode(15).
	executeNode(15).

	if not (obt:hasnextpatch and obt:nextpatch:body = targetBody) {
		notify("Transfer failed - shutting down").
		dmsg("Transfer did not reach " + targetBody:name, true).
		shutdown.
	}

	notify(targetBody:name + " encounter confirmed").
	dmsg(targetBody:name + " encounter confirmed", true).

	notify("Deploying communication dish").
	for dish in rt:getAllDish() {
		dish:enable().
		dish:setTarget(Kerbin).
	}
}

function awaitSOIChange {
	parameter targetBody.

	notify("Coasting to " + targetBody:name + " SOI").
	dmsg("Awaiting SOI change to " + targetBody:name, true).
	warpTo(time:seconds + eta:transition).
	wait until obt:body = targetBody.
	kuniverse:timewarp:cancelwarp().
	wait until kuniverse:timewarp:issettled.

	// wait 10 seconds to ensure SOI transition has settled
	local soiChangeUT is time:seconds.
	warpTo(soiChangeUT + 10).
	wait until time:seconds >= soiChangeUT + 10.
	kuniverse:timewarp:cancelwarp().
	wait until kuniverse:timewarp:issettled.

	notify("Entered " + targetBody:name + " SOI").
	dmsg("SOI change complete: " + targetBody:name, true).
}

function trimMoonFlyby {
	parameter targetPeriapsis.

	until not hasNode { remove nextNode. wait 0. }

	notify("Trimming " + body:name + " approach").
	dmsg("Targeting periapsis 50 m above highest terrain", true).

	local altitudeSafetyResult is altitudeSafety:altitude(body).
	if not altitudeSafetyResult:ok {
		notify("Approach trim failed - shutting down").
		dmsg("Terrain height check failed: " + altitudeSafetyResult:msg, true).
		shutdown.
	}
	dmsg("Maximum terrain altitude: " + altitudeSafetyResult:val + " m", true).

	local safeAltitudeMargin is 50.
	local peMargin is 5.
	local flybyPeriapsis is max(
		targetPeriapsis,
		altitudeSafetyResult:val + safeAltitudeMargin
	).
	local flybyResult is changeFlybyPe(flybyPeriapsis, 60, peMargin).
	if not flybyResult:ok {
		notify("Approach trim failed - shutting down").
		dmsg("Approach trim planning failed: " + flybyResult:msg, true).
		shutdown.
	}

	add flybyResult:val.

	warpToNode(15).
	executeNode(15).

	notify(targetBody:name + " periapsis targeted: " + round(periapsis / 1e3, 0) + " km").
	dmsg("Approach trim complete", true).
	dmsg("Target periapsis: " + round(flybyPeriapsis, 1) + " m", true).
	dmsg("Periapsis error: " + round(obt:periapsis - flybyPeriapsis, 1) + " m", true).
}

function moonDeorbitAtPeriapsis {
	notify("Executing " + targetBody:name + " deorbit burn").
	dmsg("Executing " + targetBody:name + " deorbit burn", true).

	if eta:periapsis > 15 {
		local deorbitUT is time:seconds + eta:periapsis.
		warpTo(deorbitUT - 15).
		wait until time:seconds > deorbitUT - 15.
		wait until kuniverse:timewarp:issettled.
	}

	lock steering to srfRetrograde.
	awaitSteering().
	wait until eta:periapsis <= 1.

	lock throttle to 1.
	until obt:periapsis < -10e3 and groundSpeed <= 250 {
		autostage().
		wait 0.
	}
	lock throttle to 0.

	notify(targetBody:name + " descent trajectory established").
	dmsg(targetBody:name + " descent trajectory established", true).
}

function moonDescent {
	notify(targetBody:name + " descent guidance active").
	dmsg("Starting " + targetBody:name + " descent guidance", true).
	descent().
	clearScreen.

	notify("Landed on " + targetBody:name).
	dmsg(targetBody:name + " landing complete", true).
}

function moonAscent {
	parameter moonAscentHeading, moonAscentApoapsis.

	notify(targetBody:name + " ascent guidance active").
	dmsg("Starting " + targetBody:name + " ascent guidance", true).

	notify("Communication disabled").
	for dish in rt:getAllDish() {
		dish:disable().
	}

	local ascentState is airlessAscent(moonAscentHeading, moonAscentApoapsis).
	if ascentState <> "ORBITING" and ascentState <> "SUB_ORBITAL" {
		notify(targetBody:name + " ascent failed - shutting down").
		dmsg(targetBody:name + " ascent failed: " + ascentState, true).
		shutdown.
	}
}

function moonCircularization {
	until not hasNode { remove nextNode. wait 0. }

	notify("Planning " + targetBody:name + " circularization").
	local circularizeResult is circularize().
	if not circularizeResult:ok {
		notify("Circularization failed - shutting down").
		dmsg("Circularization planning failed: " + circularizeResult:msg, true).
		shutdown.
	}

	add circularizeResult:val.
	notify("Executing " + targetBody:name + " circularization").
	warpToNode(15).
	executeNode(15).

	notify(targetBody:name + " orbit achieved").
	dmsg("Stable " + targetBody:name + " orbit achieved", true).

	notify("Communication enabled").
	for dish in rt:getAllDish() {
		dish:enable().
	}
}

function returnToKerbin {
	parameter returnPeriapsis.

	notify("Planning return to Kerbin").
	dmsg("Planning return to Kerbin", true).

	local returnFromMoonResult is returnToParent(returnPeriapsis).
	if not returnFromMoonResult:val {
		notify("Return attempt failed").
		dmsg("Failed to escape " + targetBody:name + " SOI", true).
	}
	else {
		if not returnFromMoonResult:ok {
			notify("Return trajectory has additional encounter").
			dmsg("Return trajectory encounters another body before periapsis", true).
			dmsg("Proceeding with return trajectory", true).
		}

		notify("Executing Kerbin ejection burn").
		dmsg("Kerbin ejection maneuver added", true).
		warpToNode(15).
		executeNode(15).
	}
}

function kerbinReentry {
	// 10 minutes before periapsis
	notify("Coasting to Kerbin reentry").
	warpTo(time:seconds + eta:periapsis - 600).
	wait until kuniverse:timewarp:issettled.

	notify("Preparing for reentry - communications disabled").
	for dish in rt:getAllDish() {
		dish:disable().
	}
	panels off.
	dmsg("Beginning Kerbin reentry", true).
	atmosphericDescent().
}