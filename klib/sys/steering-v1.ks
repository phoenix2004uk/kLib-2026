{
	local ANGLE_THRESHOLD is 0.25.
	local ROLL_THRESHOLD is 1.
	local SETTLE_RATE_TIME is 1.
	local ANGLE_RATE_THRESHOLD is (ANGLE_THRESHOLD / SETTLE_RATE_TIME) * constant:degToRad.
	local ROLL_RATE_THRESHOLD is (ROLL_THRESHOLD / SETTLE_RATE_TIME) * constant:degToRad.

	function isSteeringSettled {
		if not steeringManager:enabled return true.

		if abs(steeringManager:angleError) >= ANGLE_THRESHOLD {
			return false.
		}

		local pitchErrorRate is steeringManager:pitchPid:changeRate.
		local yawErrorRate is steeringManager:yawPid:changeRate.

		return pitchErrorRate^2 + yawErrorRate^2 < ANGLE_RATE_THRESHOLD^2.
	}

	function isRollSettled {
		if not steeringManager:enabled return true.

		// ROLLPID is not updated while roll control is gated.
		if abs(steeringManager:angleError) >= steeringManager:rollControlAngleRange {
			return false.
		}

		if abs(steeringManager:rollError) >= ROLL_THRESHOLD {
			return false.
		}

		return abs( steeringManager:rollPid:changeRate) < ROLL_RATE_THRESHOLD.
	}

	function isSettled {
		parameter includeRoll is false.

		return isSteeringSettled() and (not includeRoll or isRollSettled()).
	}

	function awaitSteering {
		parameter includeRoll is false.

		// Ensure SteeringManager has processed at least one physics update
		// for the current steering target.
		wait 0.
		wait until isSettled(includeRoll).
	}

	function awaitRoll {
		awaitSteering(true).
	}

	export(lex(
		"awaitSteering", awaitSteering@,
		"awaitRoll", awaitRoll@,
		"isSteeringSettled", isSteeringSettled@,
		"isRollSettled", isRollSettled@,
		"isSettled", isSettled@
	)).
}