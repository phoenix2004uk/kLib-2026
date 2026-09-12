local ascent is import("prg/atmosphericAscent-v2").
local mnvCircularize is import("mnv/circularizeAtApsis-v1").
local circularizeAtAp is mnvCircularize:Ap.
local circularizeAtPe is mnvCircularize:Pe.
local raiseOrLowerApsis is import("mnv/raiseOrLowerApsis-v1").
local orbitalMechanics is import("mech/orbitalMechanics-v1").
local velocityChangeToNode is import("mnv/velocityChangeToNode-v1").
local matchInclination is import("mnv/matchInclination-v1").
local hohmannTransfer is import("mnv/hohmannTransfer-v1").
local altitudeSafety is import("tlm/altitudeSafety-v1").
local changeFlybyPe is import("mnv/changeFlybyPe-v1").
local pExecuteNode is import("prg/executeNode-v1").
local executeNode is pExecuteNode:executeNode.
local warpToNode is pExecuteNode:warpToNode.
local steeringSystem is import("sys/steering-v1").
local awaitSteering is steeringSystem:awaitSteering.
local steeringSettled is steeringSystem:isSettled.
local staging is import("sys/staging-v1").
local stageUntil is staging:stageUntil.
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
//	body: Mun
//	eccentricity: < 0.0021
//	inclination: 84.9 - 85.5
//	altitude: 250km max
// Start scan with AG1
local targetBody is Mun.
local launchApoapsis is 100e3.
local launchInclination is 0.
local minApoapsis is 249e3.
local maxApoapsis is 250e3.
local minInclination is 84.9.
local maxInclination is 85.5.
local maxEccentricity is 0.0021.

// Mission Overview
if currentState = "" {
	prelaunch().
	set currentState to SaveState("launch").
}
if currentState = "launch" {
	launch(launchApoapsis, launchInclination).
	set currentState to SaveState("orbitalInsertion").
}
if currentState = "orbitalInsertion" {
	orbitalInsertion(launchApoapsis).
	set currentState to SaveState("circularization").
}
if currentState = "circularization" {
	circularization(circularizeAtAp).
	set currentState to SaveState("MatchMoonPlane").
}
if currentState = "MatchMoonPlane" {
	kerbinAdjustInclination().
	set currentState to SaveState("KerbinOrbit").
}
if currentState = "KerbinOrbit" {
	notify("Kerbin orbit achieved").
	notify("Deploying solar panels").
	panels on.
	lights on.
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
	local flybyPeriapsis is (minApoapsis + maxApoapsis) / 2.
	trimMoonFlyby(flybyPeriapsis).
	set currentState to SaveState("moonCircularization").
}
if currentState = "moonCircularization" {
	circularization(circularizeAtPe).
	set currentState to SaveState("changeInclination").
}
if currentState = "changeInclination" {
	until obt:inclination >= minInclination and obt:inclination <= maxInclination {
		changeInclination(minInclination, maxInclination).
	}
	set currentState to SaveState("trimApoapsis").
}
if currentState = "trimApoapsis" {
	until apoapsis >= minApoapsis and apoapsis <= maxApoapsis {
		trimApoapsis(minApoapsis, maxApoapsis).
	}
	set currentState to SaveState("trimEccentricity").
}
if currentState = "trimEccentricity" {
	until obt:eccentricity <= maxEccentricity {
		circularization(circularizeAtAp).
	}
	set currentState to SaveState("scan").
}
if currentState = "scan" {
	ag1 on.
	set currentState to SaveState("complete").
}
if currentState = "complete" {
	on abort deorbit().
	sas off.
	lock steering to -sun:position.
	awaitSteering().
	unlock steering.
	sas on.
	wait 60.
	reboot.
}

// Mission Steps
function prelaunch {
	notify("Launch in 3 seconds").
	lights on.
	wait 3.
}

function launch {
	parameter launchApoapsis, launchInclination is 0.

	notify("Beginning Kerbin ascent").
	ascent:executeAscent(launchApoapsis, launchInclination).
}

function orbitalInsertion {
	parameter launchApoapsis.

	notify("Beginning orbital insertion").
	ascent:orbitalInsertion(launchApoapsis).
	stageUntil(0).
}

function circularization {
	parameter circularizeDelegate.
	until not hasNode { remove nextNode. wait 0. }
	notify("Planning " + body:name + " circularization").
	local circularizeResult is circularizeDelegate().
	if not circularizeResult:ok {
		notify("Circularization failed - shutting down").
		dmsg("Circularization planning failed: " + circularizeResult:msg, true).
		shutdown.
	}

	rcs on.
	add circularizeResult:val.
	if steeringSettled() warpToNode(60).
	notify("Executing " + body:name + " circularization").
	warpToNode(60).
	executeNode(60).
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
	warpToNode(60).
	executeNode(60).
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
	warpToNode(60).
	executeNode(60).

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

	warpToNode(60).
	executeNode(60).

	notify(targetBody:name + " periapsis targeted: " + round(periapsis / 1e3, 0) + " km").
	dmsg("Approach trim complete", true).
	dmsg("Target periapsis: " + round(flybyPeriapsis, 1) + " m", true).
	dmsg("Periapsis error: " + round(obt:periapsis - flybyPeriapsis, 1) + " m", true).
}

function changeInclination {
	parameter minInclination, maxInclination.

	if obt:inclination >= minInclination and obt:inclination <= maxInclination return.

	until not hasNode { remove nextNode. wait 0. }

	local targetInclination is (minInclination + maxInclination) / 2.
	local theta is targetInclination - obt:inclination.

	notify("Planning inclination change").
	dmsg("Planning inclination change: " + minInclination + "-" + maxInclination, true).
	dmsg("  theta: " + round(theta,2), true).

	local earliestUT is time:seconds + 120.
	local utAN is time:seconds + orbitalMechanics:etaAN().
	local utDN is time:seconds + orbitalMechanics:etaDN().
	if utAN < earliestUT set utAN to utAN + obt:period.
	if utDN < earliestUT set utDN to utDN + obt:period.

	local utNode is utAN.
	if utDN < utAN {
		set utNode to utDN.
		set theta to -theta.
	}

	local futureShipRaw is positionAt(ship, utNode).
	local shipVelocityAtNode is velocityAt(ship, utNode):orbit.

	local vecRadial is (futureShipRaw - body:position):normalized.
	local rotatedVelocityVector is angleAxis(-theta, vecRadial) * shipVelocityAtNode.

	add velocityChangeToNode(
		utNode,
		futureShipRaw - body:position,
		shipVelocityAtNode,
		rotatedVelocityVector
	).

	notify("Executing inclination change").
	warpToNode(60).
	executeNode(60).
	dmsg("  post-burn inclination: " + obt:inclination, true).
	dmsg("  inclination error: " + (targetInclination - obt:inclination), true).
}

function trimApoapsis {
	parameter minApoapsis, maxApoapsis.

	if obt:apoapsis >= minApoapsis and obt:apoapsis <= maxApoapsis return.

	until not hasNode { remove nextNode. wait 0. }
	local targetApoapsis is (minApoapsis + maxApoapsis) / 2.
	
	notify("Planning apoapsis trim").
	dmsg("Planning apoapsis trim: " + targetApoapsis, true).

	local trimResult is raiseOrLowerApsis:Ap(targetApoapsis).
	if not trimResult:ok {
		notify("Apoapsis trim failed - shutting down").
		dmsg("Apoapsis trim planning failed: " + trimResult:msg, true).
		shutdown.
	}

	add trimResult:val.

	warpToNode(60).
	executeNode(60).

	notify("Apoapsis achieved: " + round(apoapsis / 1e3, 0) + " km").
	dmsg("Apoapsis trim complete", true).
	dmsg("Target apoapsis: " + round(targetApoapsis, 1) + " m", true).
	dmsg("Apoapsis error: " + round(obt:apoapsis - targetApoapsis, 1) + " m", true).
}

function deorbit {
	notify("Preparing to decommission via lithobraking").
	dmsg("Preparing to de-orbit", true).

	sas off.
	lock steering to retrograde.
	awaitSteering().
	lock throttle to 1.
	wait until periapsis < -10e3 or ship:thrust = 0.
	lock throttle to 0.

	notify("De-orbit burn complete - brace for impact").
	dmsg("De-orbit burn complete: Pe = " + round(periapsis) + "m", true).
	wait until 0.
}