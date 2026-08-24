wait until ship:unpacked.
core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
sas off.

set maxPitchDeviation to 10.
set targetPitch to 90.
lock steering to heading(90, 90).
lock throttle to 1.

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

	return pClamped.
}

when altitude > 1000 then { set targetPitch to 80. }
when altitude > 10000 then { set targetPitch to 60. }
when altitude > 15000 then { set targetPitch to 50. }
when altitude > 20000 then { set targetPitch to 40. }
when altitude > 30000 then { set targetPitch to 20. }
when altitude > 40000 then { set maxPitchDeviation to 90. }
when apoapsis > 50000 then { set targetPitch to 10. }
when apoapsis > 60000 then { set targetPitch to 0. }

wait 5.
clearScreen.
stage.

wait 5.
lock steering to heading(90, clampedPitch(targetPitch, maxPitchDeviation)).

// wait for SRB to deplete then fire second stage
wait until ship:maxthrust = 0.
stage.

wait until apoapsis > 250000.
lock throttle to 0.
lock steering to prograde.

// circularize-ish
wait until eta:apoapsis < 5.
lock throttle to 1.
wait until periapsis > 75000.
lock throttle to 0.
lock steering to retrograde.

// perform a full orbit
wait until eta:periapsis < 5.
wait until eta:apoapsis < 5.

lock throttle to 1.
wait 1.
wait until periapsis < 25000 or ship:maxthrust = 0.
lock throttle to 0.
lock steering to srfRetrograde.
wait 1.
stage.
wait until alt:radar < 10000.
stage.

wait until ship:status = "LANDED" or ship:status = "SPLASHED".
unlock steering.
wait 2.
sas on.
toggle ag1.
wait until false.