{
	local awaitSteering is import("sys/steering-v1"):awaitSteering.
	local APPROACH_SPEED_THRESHOLD is 0.1.
	local MATCH_SPEED_THRESHOLD is 0.1.
	local ACCELERATION_LIMIT is 1. // m/s^2
	local VELOCITY_SETTLE_TIME is 2.

	function getApproachVector {
		parameter targetVessel, approachSpeed.

		local relativeVelocity is targetVessel:velocity:orbit - ship:velocity:orbit.
		local approachVelocity is targetVessel:position:normalized * approachSpeed.

		return relativeVelocity + approachVelocity.
	}

	function getApproachThrust {
		parameter velocityError.

		if ship:availableThrust = 0 return 0.
		local availableAcceleration is ship:availableThrust / ship:mass.

		local wantedAcceleration is min(
			ACCELERATION_LIMIT,
			velocityError / VELOCITY_SETTLE_TIME
		).

		return min(1, wantedAcceleration / availableAcceleration).
	}

	function closestApproach {
		parameter targetVessel.
		
		return vdot(
			targetVessel:position,
			targetVessel:velocity:orbit - ship:velocity:orbit
		) >= 0.
	}

	function setRelativeVelocity {
		parameter targetVessel, approachSpeed, threshold.

		local lock approachVector to getApproachVector(targetVessel, approachSpeed).

		lock steering to approachVector.
		awaitSteering().

		lock throttle to getApproachThrust(approachVector:mag).
		wait until approachVector:mag < threshold.

		lock throttle to 0.
		unlock steering.
		unlock approachVector.
	}

	function approachTarget {
		parameter targetVessel, approachSpeed.

		setRelativeVelocity(
			targetVessel,
			approachSpeed,
			APPROACH_SPEED_THRESHOLD
		).
	}

	function matchVelocity {
		parameter targetVessel.

		setRelativeVelocity(
			targetVessel,
			0,
			MATCH_SPEED_THRESHOLD
		).
	}

	function approach {
		parameter targetVessel, targetSeparation, approachSpeed.

		until targetVessel:distance <= targetSeparation {
			approachTarget(targetVessel, approachSpeed).
			lock steering to getApproachVector(targetVessel, 0).

			wait until targetVessel:distance <= targetSeparation or closestApproach(targetVessel).

			matchVelocity(targetVessel).
			lock steering to getApproachVector(targetVessel, approachSpeed).
			wait 0.
		}
	}

	export(approach@).
}