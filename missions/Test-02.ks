local rendezvous is import("mnv/rendezvous-v1").
local printOrbit is import("util/printOrbit-v1").
clearScreen.

dmsg("Print Orbit Info for: ship").
printOrbit:print(ship, {parameter line. dmsg("[Orbit Info] " + line, true).}).
dmsg("Print Orbit Info for: orbit").
printOrbit:print(orbit, {parameter line. dmsg("[Orbit Info] " + line, true).}).
dmsg("Print Orbit Info for: Kerbin").
printOrbit:print(Kerbin, {parameter line. dmsg("[Orbit Info] " + line, true).}).
dmsg("Print Orbit Info for: Kerbin:orbit").
printOrbit:print(Kerbin:orbit, {parameter line. dmsg("[Orbit Info] " + line, true).}).
dmsg("Print Orbit Info for: createOrbit(0,1,0,0,0,0,0,body)").
printOrbit:print(createOrbit(0,1,0,0,0,0,0,body), {parameter line. dmsg("[Orbit Info] " + line, true).}).

set target to "".
wait 1.
wait until not hasTarget.
wait until hasTarget.
until not hasNode {
	remove nextNode.
	wait 1.
}

local startUT is time:seconds.
local result is rendezvous(target, 0).
local endUT is time:seconds.
print("  started at = " + startUT).
print("  ended at = " + endUT).
// local result is rendezvous(target:orbit, 0).
// local result is rendezvous(createOrbit(
// 	target:orbit:inclination,
// 	target:orbit:eccentricity,
// 	target:orbit:semimajoraxis,
// 	target:orbit:lan,
// 	target:orbit:argumentofperiapsis,
// 	target:orbit:meananomalyatepoch,
// 	target:orbit:epoch,
// 	target:orbit:body
// ), 0).
// local result is rendezvous(createOrbit(
// 	0, 0, 300e3, 0, 0, 0, 0, body
// ), 0).

if (result:ok) {
	local mnvDeparture is result:val:departure.
	local mnvArrival is result:val:arrival.

	add mnvDeparture.
	wait 0.
	{
		// DEBUG
		local shipPosition is positionAt(ship, mnvArrival:time).
		local targetPosition is positionAt(target, mnvArrival:time).
		local vecSeparation is targetPosition - shipPosition.
		local distance is vecSeparation:mag.

		local vecShipRadius is shipPosition - body:position.
		local vecTargetRadius is targetPosition - body:position.

		clearVecDraws().
		vecDraw(V(0,0,0), shipPosition, RED, "ship future", 1, true, 0.1).
		vecDraw(V(0,0,0), targetPosition, GREEN, "target future", 1, true, 0.1).
		vecDraw(shipPosition, vecSeparation, CYAN, "distance", 1, true, 0.1).
		vecDraw(body:position, vecShipRadius, YELLOW, "ship radius", 1, true, 0.1).
		vecDraw(body:position, vecTargetRadius, MAGENTA, "target radius", 1, true, 0.1).

		local targetVelocity is velocityAt(target, mnvArrival:time):orbit.
		local vecTargetRadiusHat is vecTargetRadius:normalized.

		// Remove the radial component, leaving pure prograde tangent
		local vecTargetTangent is targetVelocity - vecTargetRadiusHat * vdot(targetVelocity, vecTargetRadiusHat).
		local vecTargetTangentHat is vecTargetTangent:normalized.
		local phase is arctan2(
			vdot(vecShipRadius, vecTargetTangentHat),
			vdot(vecShipRadius, vecTargetRadiusHat)
		).
		print("  target distance at intercept = " + distance).
		print("  target phase at intercept = " + phase).
	}

	add mnvArrival.
	wait 60.
	clearVecDraws().
}
else print result:msg.