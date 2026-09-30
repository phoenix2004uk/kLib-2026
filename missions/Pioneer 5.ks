// Pioneer 5
// Kerbin Orbit and Return

set maxPitchDeviation to 5.
set targetPitch to 90.
lock steering to heading(90, 90).
lock throttle to 1.

clearScreen.

function clampedPitch {
	parameter pTarget, pMaxDeviation.

	set pCurrent to 90 - VANG(UP:vector, srfPrograde:vector).

	set pClamped to max(
		pCurrent - pMaxDeviation,
		min(pCurrent + pMaxDeviation, pTarget)
	).

	print ("Pitch: " + round(pCurrent, 1) + " / " + round(pTarget, 1) + " (" + round(pClamped, 1) + ")"):padright(terminal:width) AT (0, 0).
	print ("Alt:   " + ROUND(altitude, 0)):padright(terminal:width) AT (0,1).
	print ("Ap:    " + ROUND(apoapsis, 0)):padright(terminal:width) AT (0,2).
	print ("Vert:    " + ROUND(verticalSpeed, 0)):padright(terminal:width) AT (0,3).

	return pClamped.
}

when altitude > 1000 or verticalSpeed > 100 then { print "Pitch 80". set targetPitch to 80. }
when altitude > 5000 or verticalSpeed > 200 then { print "Pitch 60". set targetPitch to 60. }
when altitude > 10000 or verticalSpeed > 300 then { print "Pitch 40". set targetPitch to 40. }
when altitude > 20000 then { print "Pitch 30". set targetPitch to 30. }
when altitude > 30000 then { print "Pitch 20". set targetPitch to 20. set maxPitchDeviation to 10. }
when altitude > 40000 then { print "Pitch 0". set targetPitch to 0. set maxPitchDeviation to 90. }

wait 5.
stage.

wait 5.
lock steering to heading(90, clampedPitch(targetPitch, maxPitchDeviation)).

// wait for SRB to deplete then fire second stage
wait 42.5.
stage.

until apoapsis > 80000 {
	if availableThrust = 0 {
		stage.
		wait until stage:ready.
	}
	wait 0.
}
lock throttle to 0.
lock steering to prograde.

// circularize-ish
wait until eta:apoapsis < 5.
lock throttle to 1.
until periapsis > 30000 {
	if availableThrust = 0 {
		stage.
		wait until stage:ready.
	}
	wait 0.
}
// drop ascent stage
if stage:number > 2 {
	lock throttle to 0.
	wait 0.1.
	stage.
	wait until stage:ready.
	lock throttle to 1.
}
wait until periapsis > 75000.
lock throttle to 0.
lock steering to retrograde.

// perform a full orbit
wait until eta:periapsis < 5.
wait until eta:apoapsis < 5.

lock throttle to 1.
wait until periapsis < 25000 or ship:maxthrust = 0.
lock throttle to 0.
lock steering to srfRetrograde.
wait 10.
stage.
wait until alt:radar < 10000.
stage.