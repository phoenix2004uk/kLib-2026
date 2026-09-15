local ascent is import("prg/atmosphericAscent-v2").
local circularizeAtAp is import("mnv/circularizeAtApsis-v1"):Ap.
local changeEllipticalInclination is import("mnv/changeEllipticalInclination-v1").
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
local launchApoapsis is 130e3.
local launchInclination is 0.

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
	set currentState to SaveState("Complete").
}
if currentState = "Complete" {
	for en in ship:engines {
		en:shutdown().
	}
	sas off.
	lock steering to vcrs(north:vector, sun:position).
	awaitSteering().
	unlock steering.
	sas on.
	local dockingport is ship:dockingports[0].
	wait until dockingport:state<>"Ready".
	sas off.
	wait until dockingport:hasPartner.
	set currentState to SaveState("Done").
	shutdown.
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