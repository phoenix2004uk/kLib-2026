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
local returnToParent is import("mnv/returnToParent-v1").
local atmosphericDescent is import("prg/atmosphericDescent-v1").
local staging is import("sys/staging-v1").
local stageUntil is staging:stageUntil.
local autostage is staging:autostage.
local steeringSystem is import("sys/steering-v1").
local awaitSteering is steeringSystem:awaitSteering.
local steeringSettled is steeringSystem:isSettled.
clearScreen.

// Mission Configuration
local targetBody is Mun.
local launchApoapsis is 100e3.
local launchInclination is 0.
local flybyPeriapsis is 0. // get as low as possible
local moonAscentHeading is 90. // this should probably be inclination
local moonAscentApoapsis is 14e3.
local returnPeriapsis is 35e3.

{
	// Mission Overview
	prelaunch().
	kerbinLaunch(launchApoapsis, launchInclination).
	kerbinCircularization().
	kerbinOrbit().
	transferToMoon(targetBody).
	awaitSOIChange(targetBody).
	trimMoonFlyby(flybyPeriapsis).
	moonDeorbitAtPeriapsis().
	moonDescent().
	{
		local returnToOrbit is false.
		on abort set returnToOrbit to true.
		notify("Press ABORT to launch from Mun").
		wait until returnToOrbit.

		moonAscent(moonAscentHeading, moonAscentApoapsis).
	}
	moonCircularization().
	returnToKerbin(returnPeriapsis). // currently has a manual loop to attempt return transfers
	awaitSOIChange(Kerbin).
	kerbinReentry().

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

		notify("Beginning orbital insertion").
		ascent:orbitalInsertion(launchApoapsis).
		stageUntil(3).
	}

	function kerbinCircularization {
		notify("Planning Kerbin circularization").
		local circularizeResult is circularize().
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

	function kerbinOrbit {
		notify("Kerbin orbit achieved").
		toggle ag1.
		lights on.
	}

	function transferToMoon {
		parameter targetBody.

		notify("Planning transfer to " + targetBody:name).
		dmsg("Planning transfer to " + targetBody:name, true).
		set target to targetBody.
		wait 10.

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

		notify("Trimming Mun approach").
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

		local ascentState is airlessAscent(moonAscentHeading, moonAscentApoapsis).
		if ascentState <> "ORBITING" and ascentState <> "SUB_ORBITAL" {
			notify(targetBody:name + " ascent failed - shutting down").
			dmsg(targetBody:name + " ascent failed: " + ascentState, true).
			shutdown.
		}
	}

	function moonCircularization {
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
	}

	function returnToKerbin {
		parameter returnPeriapsis.

		local returnSuccess is false.
		local attempReturn is false.

		until returnSuccess {
			notify("Press ABORT to attempt return").
			set attempReturn to false.
			on abort set attempReturn to true.

			wait until attempReturn.
			set attempReturn to false.

			notify("Planning return to Kerbin").
			dmsg("Planning return to Kerbin", true).

			local returnFromMoonResult is returnToParent(returnPeriapsis).
			if not returnFromMoonResult:val {
				notify("Return attempt failed").
				dmsg("Failed to escape " + targetBody:name + " SOI", true).
			}
			else {
				set returnSuccess to true.

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
	}

	function kerbinReentry {
		// 10 minutes before periapsis
		notify("Coasting to Kerbin reentry").
		warpTo(time:seconds + eta:periapsis - 600).
		wait until kuniverse:timewarp:issettled.

		notify("Preparing for reentry - communications disabled").
		dmsg("Beginning Kerbin reentry", true).
		toggle ag1. // disable antenna
		atmosphericDescent().
	}
}