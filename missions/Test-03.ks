local ascent is import("ascent-v2").
local hohmannTransfer is import("mnv/hohmannTransfer-v1").
local changeFlybyPe is import("mnv/changeFlybyPe-v1").
local executeNode is import("mnv/executeNode-v1").
local altitudeSafety is import("altitudeSafety-v1").
local descent is import("descent-v2").
local airlessAscent is import("airlessAscent-v1").
local circularize is import("mnv/circularizeAtAp-v1").
local returnFromMoon is import("mnv/returnFromMoon-v1").
local atmosphericDescent is import("atmosphericDescent-v1").
local staging is import("staging-v1").
local stageUntil is staging:stageUntil.
local autostage is staging:autostage.
local awaitSteering is import("steering-v1"):awaitSteering.
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
		dmsg("Use ABORT to trigger ascent", true).

		wait until returnToOrbit.
		dmsg("Ascending in 10 seconds", true).
		wait 10.
		moonAscent(moonAscentHeading, moonAscentApoapsis).
	}
	moonCircularization().
	returnToKerbin(returnPeriapsis). // currently has a manual loop to attempt return transfers
	awaitSOIChange(Kerbin).
	kerbinReentry().

	// Mission Steps
	function prelaunch {
		dmsg("Launching in 10 seconds", true).
		wait 10.
	}

	function kerbinLaunch {
		parameter launchApoapsis, launchInclination is 0.
		ascent:executeAscent(launchApoapsis, launchInclination).
		ascent:orbitalInsertion(launchApoapsis).
		stageUntil(3).
	}

	function kerbinCircularization {
		local circularizeResult is circularize().
		if not circularizeResult:ok {
			dmsg("Failed to plan maneuver", true).
			shutdown.
		}

		add circularizeResult:val.
		executeNode:warpToNode(15).
		executeNode:executeNode(15).
	}

	function kerbinOrbit {
		toggle ag1.
		lights on.
	}

	function transferToMoon {
		parameter targetBody.

		dmsg("Preparing trasfer to: " + targetBody, true).
		set target to targetBody.
		wait 10.

		local hohmannResult is hohmannTransfer(targetBody).
		if not hohmannResult:ok {
			dmsg("Something went wrong", true).
			dmsg(hohmannResult:msg, true).
			dmsg("Shutting down", true).
			shutdown.
		}

		add hohmannResult:val.
		executeNode:warpToNode(15).
		executeNode:executeNode(15).

		if not (obt:hasnextpatch and obt:nextpatch:body = targetBody) {
			dmsg("We didn't make it to " + targetBody:name, true).
			dmsg("Shutting down", true).
			shutdown.
		}
	}

	function awaitSOIChange {
		parameter targetBody.

		dmsg("Waiting for SOI change: " + targetBody:name, true).
		warpTo(time:seconds + eta:transition).
		wait until obt:body = targetBody.
		kuniverse:timewarp:cancelwarp().
		wait until kuniverse:timewarp:issettled.

		// wait 30 seconds to ensure SOI transition has settled
		local soiChangeUT is time:seconds.
		warpTo(soiChangeUT + 30).
		wait until time:seconds >= soiChangeUT + 30.
		kuniverse:timewarp:cancelwarp().
		wait until kuniverse:timewarp:issettled.
	}

	function trimMoonFlyby {
		parameter targetPeriapsis.
		dmsg("Attempt to change periapsis to 50m above the highest terrain altitude", true).
		local altitudeSafetyResult is altitudeSafety:altitude(body).
		if not altitudeSafetyResult:ok {
			dmsg("Something went wrong", true).
			dmsg(altitudeSafetyResult:msg, true).
			dmsg("Shutting down", true).
			shutdown.
		}
		dmsg("  max terrain altitude = " + altitudeSafetyResult:val, true).

		local safeAltitudeMargin is 50.
		local peMargin is 5.
		local flybyPeriapsis is max(targetPeriapsis, altitudeSafetyResult:val + safeAltitudeMargin).
		local flybyResult is changeFlybyPe(flybyPeriapsis, 60, peMargin).
		if not flybyResult:ok {
			dmsg("Something went wrong", true).
			dmsg(flybyResult:msg, true).
			dmsg("Shutting down", true).
			shutdown.
		}
		add flybyResult:val.
		dmsg("  node delta-v = " + round(flybyResult:val:deltav:mag, 3), true).
		executeNode:warpToNode(15).
		executeNode:executeNode(15).

		dmsg("Trim maneuver complete", true).
		dmsg("  target periapsis = " + round(altitudeSafetyResult:val + safeAltitudeMargin, 1), true).
		dmsg("  error = " + round(obt:periapsis - (altitudeSafetyResult:val + safeAltitudeMargin), 1), true).
	}

	function moonDeorbitAtPeriapsis {
		dmsg("Performing de-orbit burn", true).

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
	}

	function moonDescent {
		dmsg("Switch to descent guiadance", true).
		descent().
		clearScreen.
	}

	function moonAscent {
		parameter moonAscentHeading, moonAscentApoapsis.
		local ascentState is airlessAscent(moonAscentHeading, moonAscentApoapsis).
		if ascentState <> "ORBITING" and ascentState <> "SUB_ORBITAL" {
			dmsg("Ascent failed: " + ascentState, true).
			shutdown.
		}
	}

	function moonCircularization {
		local circularizeResult is circularize().
		if not circularizeResult:ok {
			dmsg("Failed to plan maneuver", true).
			shutdown.
		}

		add circularizeResult:val.
		executeNode:warpToNode(15).
		executeNode:executeNode(15).
		dmsg("We should be in a stable orbit", true).
	}

	function returnToKerbin {
		parameter returnPeriapsis.
		local returnSuccess is false.
		local attempReturn is false.

		until returnSuccess {
			dmsg("Use ABORT to trigger return attempt", true).
			set attempReturn to false.
			on abort set attempReturn to true.

			wait until attempReturn.
			set attempReturn to false.

			local returnFromMoonResult is returnFromMoon(returnPeriapsis).
			if not returnFromMoonResult:val {
				dmsg("Looks like we failed to escape this SOI", true).
			}
			else {
				set returnSuccess to true.
				if not returnFromMoonResult:ok {
					dmsg("Looks like we will make another encounter before periapsis", true).
					dmsg("Proceeding anyway", true).
				}

				dmsg("Ejection burn added to flight-plan", true).
				executeNode:warpToNode(15).
				executeNode:executeNode(15).
			}
		}
	}

	function kerbinReentry {
		// 10 minutes before periapsis
		warpTo(time:seconds + eta:periapsis - 600).
		wait until kuniverse:timewarp:issettled.

		atmosphericDescent().
	}
}