{
	// Perform a Hohmann Transfer between 2 (almost) circular orbits

	local OrbitalMechanics is import("mech/orbitalMechanics-v1").
	local OrbitalParameters is import("mech/orbitalParameters-v1").

	function getTransferTime {
		parameter targetOrbitable.

		local targetOrbit is targetOrbitable:orbit.

		local targetAltitudeEstimate is targetOrbit:semimajoraxis - body:radius.
		local shipAltitudeEstimate is obt:semimajoraxis - body:radius.

		local targetAngularSpeed is 360 / targetOrbit:period.
		local shipAngularSpeed is 360 / obt:period.
		local transferPeriod is OrbitalMechanics:P((targetAltitudeEstimate + shipAltitudeEstimate) / 2).
		local transferHalfPeriod is transferPeriod / 2.
		local targetAngularMovement is targetAngularSpeed * transferHalfPeriod.
		local relativeAngularSpeed is abs(shipAngularSpeed - targetAngularSpeed).

		local targetAngularPosition is mod(
			targetOrbit:lan + targetOrbit:argumentofperiapsis + targetOrbit:trueanomaly,
			360
		).
		local shipAngularPosition is mod(
			obt:lan + obt:argumentofperiapsis + obt:trueanomaly,
			360
		).
		local phaseAngle is mod(targetAngularPosition + 360 - shipAngularPosition, 360).
		local transferAngle is mod(180 - targetAngularMovement, 360).

		if targetAltitudeEstimate < shipAltitudeEstimate {
			set phaseAngle to phaseAngle - 360.
			if phaseAngle > transferAngle set phaseAngle to phaseAngle - 360.
		}
		if targetAltitudeEstimate > shipAltitudeEstimate and phaseAngle < transferAngle {
			set phaseAngle to phaseAngle + 360.
		}

		local transfer_eta is mod(abs(phaseAngle - transferAngle), 360) / relativeAngularSpeed.

		return time:seconds + transfer_eta.
	}

	function hohmannTransfer {
		parameter targetOrbitable.

		local mnvTime is getTransferTime(targetOrbitable).
		local departureAltitude is body:altitudeOf(positionAt(ship, mnvTime)).
		local arrivalAltitudeEstimate is targetOrbitable:orbit:semimajoraxis - body:radius.
		local v0 is OrbitalMechanics:v(departureAltitude).
		local v1 is OrbitalMechanics:v(departureAltitude, OrbitalParameters:a(departureAltitude, arrivalAltitudeEstimate)).
		local dV is v1 - v0.

		return ApiOK(node(mnvTime, 0, 0, dV)).
	}
	export(hohmannTransfer@).
}