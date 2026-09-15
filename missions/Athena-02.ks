local ascent is import("prg/atmosphericAscent-v2").
local circularizeAtAp is import("mnv/circularizeAtApsis-v1"):Ap.
local changeEllipticalInclination is import("mnv/changeEllipticalInclination-v1").
local hohmannTransfer is import("mnv/hohmannTransfer-v1").
local approach is import("prg/approach-v1").
local dock is import("prg/dock-v1").
local atmosphericDescent is import("prg/atmosphericDescent-v1").
local steeringSystem is import("sys/steering-v1").
local awaitSteering is steeringSystem:awaitSteering.
local steeringSettled is steeringSystem:isSettled.
local stageUntil is import("sys/staging-v1"):stageUntil.
local pExecuteNode is import("prg/executeNode-v1").
local executeNode is pExecuteNode:executeNode.
local warpToNode is pExecuteNode:warpToNode.

// System Init
set terminal:width to 60.
set terminal:height to 15.
clearScreen.
kuniverse:timewarp:cancelwarp().
wait until kuniverse:timewarp:issettled.

// Steering Manager tuning
set steeringManager:maxStoppingTime to 1.
set steeringManager:pitchPid:kp to 1.5.
set steeringManager:pitchPid:ki to 0.
set steeringManager:pitchPid:kd to 0.05.
set steeringManager:pitchTs to 1.
set steeringManager:yawPid:kp to 1.5.
set steeringManager:yawPid:ki to 0.
set steeringManager:yawPid:kd to 0.05.
set steeringManager:yawTs to 1.
set steeringManager:rollControlAngleRange to 5.
set steeringManager:rollPid:kp to 2.
set steeringManager:rollPid:ki to 0.
set steeringManager:rollPid:kd to 0.
set steeringManager:rollTs to 0.7.
steeringManager:resetPids().

// Mission Configuration
local launchApoapsis is 100e3.
local launchInclination is 0.
local targetVesselName is "Athena-01".

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

// Mission Overview
if currentState = "" {
	prelaunch().
	set currentState to SaveState("KerbinLaunch").
}
if currentState = "KerbinLaunch" {
	launch(launchApoapsis, launchInclination).
	set currentState to SaveState("KerbinOrbitalInsertion").
}
if currentState = "KerbinOrbitalInsertion" {
	orbitalInsertion(launchApoapsis).
	set currentState to SaveState("KerbinCircularization").
}
if currentState = "KerbinCircularization" {
	circularization(circularizeAtAp).
	set currentState to SaveState("ChangeInclination").
}
if currentState = "ChangeInclination" {
	changeInclination(launchInclination).
	set currentState to "KerbinOrbit".
}
if currentState = "KerbinOrbit" {
	notify("Kerbin orbit achieved").
	notify("Deploying solar panels").
	panels on.
	lights on.
	set currentState to SaveState("TransferToTarget").
}
if currentState = "TransferToTarget" {
	set target to Vessel(targetVesselName).
	transferToTarget(target).
	set currentState to SaveState("InterceptTarget").
}
if currentState = "InterceptTarget" {
	set target to Vessel(targetVesselName).
	interceptTarget(target).
	set currentState to SaveState("ApproachTarget").
}
if currentState = "ApproachTarget" {
	set target to Vessel(targetVesselName).
	approachTarget(target).
	set currentState to SaveState("DockWithTarget").
}
if currentState = "DockWithTarget" {
	set target to Vessel(targetVesselName).
	if dockWithTarget(target) {
		set currentState to SaveState("Docked").
	}
	else {
		// We have no failure condition, so just try again in 30 seconds
		notify("Attempt to re-dock in 30 seconds").
		dmsg("Attempt to re-dock in 30 seconds", true).
		wait 30.
		reboot.
	}
}
if currentState = "Docked" {
	notify("Use ABORT to de-orbit").
	dmsg("Use ABORT to de-orbit", true).
	local proceed is false.
	on abort set proceed to true.
	wait until proceed.
	set currentState to SaveState("DeOrbit").
}
if currentState = "DeOrbit" {
	deorbit().
	set currentState to SaveState("KerbinReentry").
}
if currentState = "KerbinReentry" {
	kerbinReentry().
	set currentState to SaveState("Complete").
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
	stageUntil(2).
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
	executeNode(60).
	rcs off.
}

function changeInclination {
	parameter targetInclination.

	until not hasNode { remove nextNode. wait 0. }

	notify("Planning inclination change").
	dmsg("Planning inclination change: " + round(obt:inclination, 4) + "° -> " + round(targetInclination, 4) + "°", true).
	dmsg("  theta: " + round(targetInclination - obt:inclination, 4) + "°", true).

	local inclinationChangeResults is changeEllipticalInclination:next(targetInclination).
	if not inclinationChangeResults:ok {
		notify("Inclination change failed - shutting down").
		dmsg("Inclination planning failed: " + inclinationChangeResults:msg, true).
		shutdown.
	}

	add inclinationChangeResults:val.

	notify("Executing inclination change").
	warpToNode(60).
	executeNode(60).
	dmsg("  post-burn inclination: " + obt:inclination, true).
	dmsg("  inclination error: " + (targetInclination - obt:inclination), true).
}

function transferToTarget {
	parameter targetVessel.
	
	until not hasNode { remove nextNode. wait 0. }

	notify("Planning transfer to " + targetVessel:name).
	dmsg("Planning transfer: target=" + targetVessel, true).

	local hohmannResult is hohmannTransfer(targetVessel).
	if not hohmannResult:ok {
		notify("Transfer failed - shutting down").
		dmsg("Transfer planning failed: " + hohmannResult:msg, true).
		shutdown.
	}

	add hohmannResult:val.
	notify("Executing transfer to " + targetVessel).
	wait until hasNode.
	warpToNode(15).
	executeNode(15).
}

function interceptTarget {
	parameter targetVessel.

	until not hasNode { remove nextNode. wait 0. }

	notify("Planning intercept to " + targetVessel:name).
	dmsg("Planning intercept: target=" + targetVessel + " Ap=" + round(targetVessel:orbit:apoapsis) + "m", true).

	local circularizeResult is circularizeAtAp().
	if not circularizeResult:ok {
		notify("Circularization failed - shutting down").
		dmsg("Circularization planning failed: " + circularizeResult:msg, true).
		shutdown.
	}

	add circularizeResult:val.
	notify("Executing intercept burn").
	wait until hasNode.
	warpToNode(15).
	executeNode(15).
}

function approachTarget {
	parameter targetVessel.

	notify("Approaching " + targetVessel:name).

	local APPROACH_STEPS is list(
		list(1000, 20),
		list(100, 10),
		list(20, 2)
	).

	for approachStep in APPROACH_STEPS {
		dmsg("Approach target: " + approachStep[0] + "m @ " + approachStep[1] + "m/s", true).
		dmsg("  starting distance: " + round(target:distance) + "m", true).
		approach(targetVessel, approachStep[0], approachStep[1]).
		dmsg("  ending distance: " + round(target:distance) + "m", true).
		dmsg("  distance error: " + round(target:distance - approachStep[0]) + "m", true).
		print "".
	}

	notify("Final separation: " + round(target:distance) + "m").
	dmsg("Final separation: " + round(target:distance) + "m", true).
}

function dockWithTarget {
	parameter targetVessel.

	local shipPort is ship:dockingports[0].
	local targetPort is targetVessel:dockingports[0].

	notify("Initiating docking procedure").
	dmsg("Initiating docking procedure", true).
	local dockResult is dock(shipPort, targetPort).
	if not dockResult:ok {
		return false.
	}

	return true.
}

function deorbit {
	notify("Performing de-orbit burn").
	dmsg("Performing de-orbit burn", true).
	lock steering to retrograde.
	awaitSteering().
	lock throttle to 1.
	wait until periapsis < 35e3.
	lock throttle to 0.
	unlock steering.
}

function kerbinReentry {
	// 2 minutes before periapsis
	notify("Coasting to Kerbin reentry").
	warpTo(time:seconds + eta:periapsis - 120).
	wait until kuniverse:timewarp:issettled.

	panels off.
	notify("Beginning Kerbin reentry").
	dmsg("Beginning Kerbin reentry", true).
	atmosphericDescent().
}