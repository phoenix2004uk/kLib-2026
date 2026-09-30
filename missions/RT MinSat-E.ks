// RT MinSat-E
// Script to place 3 MinSat satellites in equatorial Minmus orbit with 120 degree separation
// kOS terminal will prompt user to enter the satellite number [1..3] for the launch
// Deploy Antenna/Dish with AG1

local ascent is import("prg/atmosphericAscent-v2").
local mnvCircularize is import("mnv/circularizeAtApsis-v1").
local circularizeAtAp is mnvCircularize:Ap.
local circularizeAtPe is mnvCircularize:Pe.
local raiseOrLowerApsis is import("mnv/raiseOrLowerApsis-v1").
local matchInclination is import("mnv/matchInclination-v1").
local changeEllipticalInclination is import("mnv/changeEllipticalInclination-v1").
local hohmannTransfer is import("mnv/hohmannTransfer-v1").
local changeFlybyPe is import("mnv/changeFlybyPe-v1").
local orbitalMechanics is import("mech/orbitalMechanics-v1").
local pExecuteNode is import("prg/executeNode-v1").
local executeNode is pExecuteNode:executeNode.
local warpToNode is pExecuteNode:warpToNode.
local steeringSystem is import("sys/steering-v1").
local awaitSteering is steeringSystem:awaitSteering.
local steeringSettled is steeringSystem:isSettled.
local staging is import("sys/staging-v1").
local stageUntil is staging:stageUntil.

// System Init
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
local targetBody is Minmus.
local launchApoapsis is 100e3.
local launchInclination is 0.
local parkingOrbit is 100e3.
local targetAltitude is 440e3.
local targetSMA is targetAltitude + targetBody:radius.
local targetInclination is 0.
local targetInclinationMargin is 0.1.
local targetSeparation is 120.
local transferStage is 1.
local endingStage is 0.

// Mission Overview
if currentState = "" {
	print "Please specify satellite designation: 1-3".
	wait until terminal:input:hasChar.
	local satNum is terminal:input:getChar().
	set ship:name to ship:name + " " + satNum.

	prelaunch().
	set currentState to SaveState("launch").
}
if currentState = "launch" {
	launch(launchApoapsis, launchInclination).
	set currentState to SaveState("orbitalInsertion").
}
if currentState = "orbitalInsertion" {
	orbitalInsertion(launchApoapsis).
	stageUntil(transferStage).
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
	notify("Discarding transfer stage for collision").
	trimMoonFlyby(-10e3).
	lock steering to -body:position.
	awaitSteering().
	stageUntil(endingStage).

	trimMoonFlyby(parkingOrbit).
	set currentState to SaveState("moonCapture").
}
if currentState = "moonCapture" {
	capture().
	set currentState to SaveState("changeInclination").
}
if currentState = "changeInclination" {
	changeInclination(targetInclination, targetInclinationMargin).
	set currentState to SaveState("moonCircularization").
}
if currentState = "moonCircularization" {
	circularization(circularizeAtPe).
	set currentState to SaveState("boostOrbit").
}
if currentState = "boostOrbit" {
	function getTransferTime {
		parameter targetOrbitable, targetSeparation is 0.

		local tagetAngularSpeed is 360 / targetOrbitable:obt:period.
		local shipAngularSpeed is 360 / ship:obt:period.
		local periodOfTransfer is orbitalMechanics:Ph(targetOrbitable:obt:apoapsis, ship:obt:apoapsis) / 2.
		local targetAngularMovement is tagetAngularSpeed * periodOfTransfer.
		local relativeAngularSpeed is abs(shipAngularSpeed - tagetAngularSpeed).

		local targetAngularPosition is targetOrbitable:obt:lan + targetOrbitable:obt:argumentofperiapsis + targetOrbitable:obt:trueanomaly.
		local shipAngularPosition is ship:obt:lan + ship:obt:argumentofperiapsis + ship:obt:trueanomaly.
		local phaseAngle is mod(targetAngularPosition + 360 - shipAngularPosition, 360).
		local transferAngle is mod(180 - targetAngularMovement - targetSeparation, 360).

		if targetOrbitable:obt:apoapsis < ship:obt:apoapsis {
			set phaseAngle to phaseAngle - 360.
			if phaseAngle > transferAngle set phaseAngle to phaseAngle - 360.
		}
		if targetOrbitable:obt:apoapsis > ship:obt:apoapsis and phaseAngle < transferAngle
			set phaseAngle to phaseAngle + 360.

		local transfer_eta is mod(abs(phaseAngle - transferAngle), 360) / relativeAngularSpeed.

		return time:seconds + transfer_eta.
	}
	if ship:name = "RT MinSat-E 1" {
		dmsg("Boosting orbit to " + round(targetAltitude/1e3,0) + "km", true, true).
		local boostResult is raiseOrLowerApsis:Ap(targetAltitude).
		if not boostResult:ok {
			notify("Boost failed - shutting down").
			dmsg("Boost planning failed: " + boostResult:msg, true).
			shutdown.
		}

		add boostResult:val.

		notify("Excuting boost burn").
		warpToNode(60).
		executeNode(60).
	}
	else {
		local targetVesselName is "".
		if ship:name = "RT MinSat-E 2" set targetVesselName to "RT MinSat-E 1".
		else if ship:name = "RT MinSat-E 3" set targetVesselName to "RT MinSat-E 2".
		else set targetVesselName to 0/0.

		dmsg("Plotting transfer to " + targetVesselName, true, true).
		set target to Vessel(targetVesselName).
		local mnvTime is getTransferTime(target, -targetSeparation).
		// TODO: we should check against burn time
		if mnvTime - time:seconds < 180 {
			print "Waiting " + (mnvTime - time:seconds + 10) + "s for next transfer".
			wait until time:seconds > mnvTime + 10.
			set mnvTime to getTransferTime(target, -targetSeparation).
		}

		local posAt is body:position - positionAt(ship, mnvTime).
		local altAt is posAt:mag - body:radius.
		local transferDeltaV is orbitalMechanics:vh(altAt, targetAltitude, periapsis) - orbitalMechanics:vh(altAt, apoapsis, periapsis).
		local mnv is node(mnvTime, 0, 0, transferDeltaV).
		add mnv.

		notify("Excuting boost burn").
		warpToNode(60).
		executeNode(60).
	}
		
	circularization(circularizeAtAp).

	set currentState to SaveState("tuneSMA").
}
if currentState = "tuneSMA" {
	if abs(obt:semimajoraxis - targetSMA) > 1 {
		dmsg("Tuning orbit", true, true).
		if obt:semimajoraxis < targetSMA {
			lock steering to prograde.
			awaitSteering().
			lock throttle to 0.0001.
			wait until obt:semimajoraxis >= targetSMA.
			lock throttle to 0.
		}
		else if obt:semimajoraxis > targetSMA {
			lock steering to retrograde.
			awaitSteering().
			lock throttle to 0.0001.
			wait until obt:semimajoraxis <= targetSMA.
			lock throttle to 0.
		}
	}
	set currentState to SaveState("complete").
}
if currentState = "complete" {
	on abort deorbit().

	print "Aligning panels & deploying antennae".
	toggle ag1.

	sas off.
	lock steering to -sun:position.
	awaitSteering().
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
	parameter flybyPeriapsis.

	until not hasNode { remove nextNode. wait 0. }

	notify("Trimming " + body:name + " approach").
	local peMargin is 5.

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

function capture {
	until not hasNode { remove nextNode. wait 0. }

	notify("Planning capture burn").
	dmsg("Planning capture burn", true).

	local captureResult is raiseOrLowerApsis:Ap(body:soiRadius - body:radius - 10e3).
	if not captureResult:ok {
		notify("Capture failed - shutting down").
		dmsg("Capture planning failed: " + captureResult:msg, true).
		shutdown.
	}

	add captureResult:val.

	notify("Excuting capture burn").
	warpToNode(60).
	executeNode(60).
}

function changeInclination {
	parameter targetInclination, targetInclinationMargin.

	until not hasNode { remove nextNode. wait 0. }

	local theta is targetInclination - obt:inclination.
	notify("Planning inclination change").
	dmsg("Planning inclination change: " + targetInclination, true).
	dmsg("  theta: " + round(theta,2), true).

	local planeChangeResult is changeEllipticalInclination:highest(targetInclination, targetInclinationMargin).
	if not planeChangeResult:ok {
		notify("Plane change failed - shutting down").
		dmsg("Plane change planning failed: " + planeChangeResult:msg, true).
		shutdown.
	}

	add planeChangeResult:val.

	notify("Executing inclination change").
	warpToNode(60).
	executeNode(60).
	dmsg("  post-burn inclination: " + obt:inclination, true).
	dmsg("  inclination error: " + (targetInclination - obt:inclination), true).
}

function deorbit {
	notify("Preparing to decommission via lithobraking").
	dmsg("Preparing to de-orbit", true).

	sas off.
	lock steering to retrograde.
	awaitSteering().
	lock throttle to 1.
	wait until periapsis < -10e3.
	lock throttle to 0.

	notify("De-orbit burn complete - brace for impact").
	dmsg("De-orbit burn complete: Pe = " + round(periapsis) + "m", true).
	wait until 0.
}