// #include "staging-v1.ks"
// #include "steering-v1.ks"

global function executeAscent {
	parameter altTarget, ascProfile is list(), incTarget is 0, twrMax is 1.8, pitchDeviationMax is 5, apTaper is 3000.

	local launchDirection is 90 - incTarget.
	local pitchTarget is 90.

	local lock pitchCurrent to 90 - vang(UP:vector, srfPrograde:vector).

	local lock pitchClamp to max(
		pitchCurrent - pitchDeviationMax,
		min(pitchCurrent + pitchDeviationMax, pitchTarget)
	).
	lock steering to heading(launchDirection, pitchClamp).

	local lock TWR to ship:maxThrust * (body:radius + altitude)^2 / (ship:mass * body:mu).
	local lock throttleTWRLimit to min(1, twrMax / max(1e-6, TWR)).

	local lock throttleApLimit to min(1, ((altTarget - apoapsis) / apTaper)^2).
	lock throttle to max(0.1, throttleTWRLimit * throttleApLimit).

	local ascentStep is 0.
	local ascentStepAltitude is ascProfile[0].
	wait 5.
	stage.

	clearScreen.
	print ("Launch to " + round(altTarget/1e3,0) + "km " + incTarget + " inclination"):padright(terminal:width) AT (0,0).
	until apoapsis > altTarget {
		print ("Alt:       " + round(altitude, 0)):padright(terminal:width) AT (0,1).
		print ("Ap:        " + round(apoapsis, 0)):padright(terminal:width) AT (0,2).
		print ("Pitch:     " + round(pitchCurrent, 1) + " / " + round(pitchTarget, 1) + " (" + round(pitchClamp, 1) + ")"):padright(terminal:width) AT (0, 3).
		print ("TWR:       " + round(TWR(), 2)):padright(terminal:width) AT (0,4).
		print ("Throttle : " + round(throttle, 2)):padright(terminal:width) AT (0,5).

		if (max(apoapsis-10e3, altitude) > ascentStepAltitude) and ((ascentStep + 2) < ascProfile:length) {
			set pitchTarget to ascProfile[ascentStep + 1].
			set ascentStep to ascentStep + 2.
			set ascentStepAltitude to ascProfile[ascentStep].
		}
		autostage().
		wait 0.1.
	}

	clearScreen.
	print "Launch to " + round(altTarget/1e3,0) + "km " + incTarget + " inclination".
	print "Coasting to space".
	lock throttle to 0.
	wait 0.1.
	wait until altitude > 70e3.

	if apoapsis < altTarget {
		lock steering to prograde.
		awaitSteering().
		lock throttle to 0.1.
		until apoapsis >= altTarget {
			autostage().
			wait 0.
		}
		lock throttle to 0.
		wait 0.1.
	} else if apoapsis > altTarget {
		lock steering to retrograde.
		awaitSteering().
		lock throttle to 0.1.
		until apoapsis <= altTarget {
			autostage().
			wait 0.
		}
		lock throttle to 0.
		wait 0.1.
	}
}