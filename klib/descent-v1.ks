{
	local autostage is import("staging-v1"):autostage.
	local awaitSteering is import("steering-v1"):awaitSteering.

	local CONTROL_INTERVAL is 0.1.
	local THROTTLE_STEP is 0.05.

	local function descentVector {
		if verticalSpeed >= 0 or groundSpeed < 1 return up.
		return srfRetrograde.
	}

	local function adjustDescentThrottle {
		parameter wantedThrottle, targetVerticalSpeed.

		if verticalSpeed < targetVerticalSpeed {
			return min(1, wantedThrottle + THROTTLE_STEP).
		}
		return max(0, wantedThrottle - THROTTLE_STEP).
	}

	local function descentComplete {
		return status = "LANDED" or status = "SPLASHED".
	}

	function descent {
		parameter deorbitGroundSpeed is 50,
			descentSpeed is 30,
			horizontalBrakeAltitude is 500,
			horizontalSpeedLimit is 1,
			landingSpeed is 2.

		local wantedThrottle is 0.
		lock throttle to wantedThrottle.

		// Coast to periapsis, then cancel most horizontal surface velocity.
		if eta:periapsis > 30 {
			warpTo(time:seconds + eta:periapsis - 30).
		}

		lock steering to srfRetrograde.
		awaitSteering().
		wait until eta:periapsis <= 1.

		set wantedThrottle to 1.
		until groundSpeed <= deorbitGroundSpeed or descentComplete() {
			autostage().
			wait CONTROL_INTERVAL.
		}

		// Descend while continuing to bleed horizontal velocity.
		set wantedThrottle to 0.
		lock steering to descentVector().
		until alt:radar <= horizontalBrakeAltitude or descentComplete() {
			set wantedThrottle to adjustDescentThrottle(
				wantedThrottle,
				-descentSpeed
			).
			autostage().
			wait CONTROL_INTERVAL.
		}

		// Get the landing gear out and remove the remaining horizontal speed.
		gear on.
		until groundSpeed <= horizontalSpeedLimit or descentComplete() {
			set wantedThrottle to adjustDescentThrottle(
				wantedThrottle,
				-landingSpeed
			).
			autostage().
			wait CONTROL_INTERVAL.
		}

		// Final vertical descent.
		lock steering to up.
		until descentComplete() {
			set wantedThrottle to adjustDescentThrottle(
				wantedThrottle,
				-landingSpeed
			).
			autostage().
			wait CONTROL_INTERVAL.
		}

		set wantedThrottle to 0.
		wait 0.
		unlock throttle.
		unlock steering.

		return status.
	}

	export(descent@).
}