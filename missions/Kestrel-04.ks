wait until ship:unpacked.
core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
sas off.

set maxPitchDeviation to 5.
set targetPitch to 90.
lock steering to heading(90, 90).
lock throttle to 1.

function clampedPitch {
	parameter tPitch, dPitch.

	return max(
		ship:prograde:pitch - dPitch,
		min(ship:prograde:pitch + dPitch, tPitch)
	).
}

when altitude > 1000 then { print "Pitch 85". set targetPitch to 85. }
when altitude > 5000 then { print "Pitch 80". set targetPitch to 80. }
when altitude > 10000 then { print "Pitch 60". set targetPitch to 60. }
when altitude > 20000 then { print "Pitch 45". set targetPitch to 45. }
when altitude > 30000 then { print "Pitch 30". set targetPitch to 30. set maxPitchDeviation to 10. }
when altitude > 40000 then { set maxPitchDeviation to 90. }
when apoapsis > 50000 then { print "Pitch 20". set targetPitch to 20. }
when apoapsis > 60000 then { print "Pitch 10". set targetPitch to 10. }
when apoapsis > 70000 then { print "Pitch 0". set targetPitch to 0. }

wait 5.
stage.

wait 5.
lock steering to heading(90, clampedPitch(targetPitch, maxPitchDeviation)).

// wait for SRB to deplete then fire second stage
wait until ship:maxthrust = 0.
stage.

wait until apoapsis > 80000.
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
wait until periapsis < 25000 or ship:maxthrust = 0.
lock throttle to 0.
lock steering to srfRetrograde.
stage.
wait until alt:radar < 10000.
stage.