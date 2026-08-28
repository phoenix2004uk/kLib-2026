// local matchInclination is import("mnv/matchInclination-v1").
local rendezvous is import("mnv/rendezvous-v1").
local execute is import("mnv/executeNode-v1").
clearScreen.

unset target.
wait 1.
wait until hasTarget.
{
	until not hasNode {
		remove nextNode.
		wait 1.
	}

	local result is rendezvous(target, 0).

	if (result:ok) {
		local mnvDeparture is result:val:departure.
		local mnvArrival is result:val:arrival.
		local trn is result:val:trn.

		add mnvDeparture.
		wait 0.
		{
			// DEBUG
			local shipPosition is positionAt(ship, trn:arrivalUT).
			local targetPosition is positionAt(target, trn:arrivalUT).
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

			local targetVelocity is velocityAt(target, trn:arrivalUT):orbit.
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
		wait 30.
		clearVecDraws().

		// execute:executeNode(60).
		// execute:executeNode(60).
	}
	else print result:msg.
}