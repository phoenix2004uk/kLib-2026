local ascent is import("prg/atmosphericAscent-v2").
local mnvCircularize is import("mnv/circularizeAtApsis-v1").
local circularizeAtAp is mnvCircularize:Ap.
local raiseOrLowerApsis is import("mnv/raiseOrLowerApsis-v1").
local orbitalMechanics is import("mech/orbitalMechanics-v1").
local velocityChangeToNode is import("mnv/velocityChangeToNode-v1").
local pExecuteNode is import("prg/executeNode-v1").
local executeNode is pExecuteNode:executeNode.
local warpToNode is pExecuteNode:warpToNode.
local steeringSystem is import("sys/steering-v1").
local awaitSteering is steeringSystem:awaitSteering.
local steeringSettled is steeringSystem:isSettled.
local staging is import("sys/staging-v1").
local stageUntil is staging:stageUntil.

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
//	body: Kerbin
//	eccentricity: < 0.0021
//	inclination: 84 - 84.5
//	altitude: 250km max
// Start Multtispectral scan with AG1
local launchInclination is 90.
local minApoapsis is 249e3.
local maxApoapsis is 250e3.
local minInclination is 84.
local maxInclination is 84.5.
local maxEccentricity is 0.0021.

// Mission Overview
if currentState = "" {
	prelaunch().
	set currentState to SaveState("launch").
}
if currentState = "launch" {
	launch(maxApoapsis, launchInclination).
	set currentState to SaveState("orbitalInsertion").
}
if currentState = "orbitalInsertion" {
	orbitalInsertion(maxApoapsis).
	set currentState to SaveState("circularization").
}
if currentState = "circularization" {
	circularization(circularizeAtAp).
	set currentState to SaveState("kerbinOrbit").
}
if currentState = "kerbinOrbit" {
	lights on.
	panels on.
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
	notify("Planning Kerbin circularization").
	local circularizeResult is circularizeDelegate().
	if not circularizeResult:ok {
		notify("Circularization failed - shutting down").
		dmsg("Circularization planning failed: " + circularizeResult:msg, true).
		shutdown.
	}

	rcs on.
	add circularizeResult:val.
	if steeringSettled() warpToNode(60).
	notify("Executing Kerbin circularization").
	executeNode(60).
	rcs off.
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