local hohmannTransfer is import("mnv/hohmannTransfer-v1").
local changeFlybyPe is import("mnv/changeFlybyPe-v1").
local executeNode is import("mnv/executeNode-v1").
local descent is import("descent-v1").
local altitudeSafety is import("altitudeSafety-v1").
// local printOrbit is import("util/printOrbit-v1").
clearScreen.

stage.
dmsg("Waiting for Orbit", true).
wait until status="ORBITING".
toggle ag1.
lights on.

dmsg("We're in orbit, starting Hohmann Intercept test in 10 seconds", true).
set target to Mun.
wait 10.

local hohmannResult is hohmannTransfer(Mun).
if not hohmannResult:ok {
	dmsg("Something went wrong", true).
	dmsg(hohmannResult:msg, true).
	dmsg("Shutting down", true).
	shutdown.
}

add hohmannResult:val.
executeNode:warpToNode(60).
executeNode:executeNode(60).

if not (obt:hasnextpatch and obt:nextpatch:body = Mun) {
	dmsg("We didn't make it to the Mun", true).
	dmsg("Shutting down", true).
	shutdown.
}

dmsg("Waiting for SOI change", true).
warpTo(time:seconds + eta:transition).
wait until obt:body = Mun.
dmsg("Waiting 60 seconds", true).
local now is time:seconds.
warpTo(now + 60).
wait until time:seconds - now <= 60 and kuniverse:timewarp:issettled.

dmsg("Attempt to change periapsis to 50m above the highest terrain altitude", true).
local altitudeSafetyResult is altitudeSafety:altitude(Mun).
if not altitudeSafetyResult:ok {
	dmsg("Something went wrong", true).
	dmsg(altitudeSafetyResult:msg, true).
	dmsg("Shutting down", true).
	shutdown.
}
dmsg("  max terrain altitude = " + altitudeSafetyResult:val, true).

local safeAltitudeMargin is 50.
local peMargin is 5.
local flybyResult is changeFlybyPe(altitudeSafetyResult:val + safeAltitudeMargin, 60, peMargin).
if not flybyResult:ok {
	dmsg("Something went wrong", true).
	dmsg(flybyResult:msg, true).
	dmsg("Shutting down", true).
	shutdown.
}
add flybyResult:val.
// printOrbit:print(flybyResult:val:orbit, {parameter m. dmsg("[Planned Orbit Info] " + m, true).}).

// printOrbit:print(ship, {parameter m. dmsg("[Pre-Trim Orbit Info] " + m, true).}).
dmsg("  node delta-v = " + round(flybyResult:val:deltav:mag, 3), true).
executeNode:executeNode(60).

dmsg("Trim maneuver complete", true).
// printOrbit:print(ship, {parameter m. dmsg("[Post-Trim Orbit Info] " + m, true).}).
dmsg("  target periapsis = " + round(altitudeSafetyResult:val + safeAltitudeMargin, 1), true).
dmsg("  error = " + round(obt:periapsis - (altitudeSafetyResult:val + safeAltitudeMargin), 1), true).

dmsg("Switch to descent guiadance", true).
descent().

lock steering to up.
wait until 0.