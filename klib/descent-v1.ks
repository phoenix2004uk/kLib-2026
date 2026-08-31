{
	local printLn is import("printLn-v1"):printLn.
	local autostage is import("staging-v1"):autostage.
	local awaitSteering is import("steering-v1"):awaitSteering.

	local CONTROL_INTERVAL is 0.1.
	local THROTTLE_STEP is 0.01.
	local VERTICAL_SPEED_TOLERANCE is 0.5.

	local HIGH_DESCENT_SPEED is -60.
	local DESCENT_STEPS is list(
		list(5000, -50),
		list(2000, -40),
		list(1000, -30),
		list(500, -20),
		list(200, -15),
		list(100, -10),
		list(50, -8),
		list(20, -5)
	).

	local function descentVector {
		parameter horizontalSpeedLimit is 1.

		if verticalSpeed >= 0 or groundSpeed < horizontalSpeedLimit return up.
		return srfRetrograde.
	}

	local function descentSpeedAtAltitude {
		parameter radarAltitude.

		local targetSpeed is HIGH_DESCENT_SPEED.
		for descentStep in DESCENT_STEPS {
			if radarAltitude <= descentStep[0] {
				set targetSpeed to descentStep[1].
			}
		}
		return targetSpeed.
	}

	local function adjustDescentThrottle {
		parameter wantedThrottle, targetSpeed.

		if verticalSpeed < targetSpeed - VERTICAL_SPEED_TOLERANCE {
			return min(1, wantedThrottle + THROTTLE_STEP).
		}
		if verticalSpeed > targetSpeed + VERTICAL_SPEED_TOLERANCE {
			return max(0, wantedThrottle - THROTTLE_STEP).
		}
		return wantedThrottle.
	}

	local function descentComplete {
		return status = "LANDED" or status = "SPLASHED".
	}

	local function displayDescent {
		parameter phase, targetSpeed, wantedThrottle.

		printLn("Descent:        " + phase, 0).
		printLn("Radar altitude: " + round(alt:radar, 1) + " m", 1).
		printLn("Periapsis:      " + round(obt:periapsis, 1) + " m", 2).
		printLn("Vertical speed: " + round(verticalSpeed, 1) + " m/s", 3).
		printLn("Target speed:   " + round(targetSpeed, 1) + " m/s", 4).
		printLn("Ground speed:   " + round(groundSpeed, 1) + " m/s", 5).
		printLn("Surface speed:  " + round(ship:velocity:surface:mag, 1) + " m/s", 6).
		printLn("Throttle:       " + round(wantedThrottle * 100, 0) + "%", 7).
		printLn("Status:         " + status, 8).
	}

	local function logDescent {
		parameter phase, targetSpeed.

		dmsg(
			"Descent: " + phase +
			"; radar=" + round(alt:radar, 1) +
			"m; vertical=" + round(verticalSpeed, 1) +
			"m/s; ground=" + round(groundSpeed, 1) +
			"m/s; target=" + round(targetSpeed, 1) + "m/s"
		).
	}

	function descent {
		parameter deorbitPeriapsis is -100,
			horizontalBrakeAltitude is 200,
			horizontalSpeedLimit is 1,
			landingAltitude is 10,
			landingSpeed is 4.

		local wantedThrottle is 0.
		local targetSpeed is 0.
		lock throttle to wantedThrottle.

		clearScreen.
		displayDescent("Coast to periapsis", targetSpeed, wantedThrottle).
		logDescent("coasting to periapsis", targetSpeed).

		if eta:periapsis > 30 {
			warpTo(time:seconds + eta:periapsis - 30).
		}

		lock steering to srfRetrograde.
		awaitSteering().
		wait until eta:periapsis <= 1.

		// Only burn enough to ensure the resulting orbit intersects the surface.
		logDescent("deorbit burn", targetSpeed).
		set wantedThrottle to 1.
		until obt:periapsis <= deorbitPeriapsis or descentComplete() {
			displayDescent("Deorbit burn", targetSpeed, wantedThrottle).
			autostage().
			wait CONTROL_INTERVAL.
		}

		// Descend on surface-retrograde while progressively reducing
		// the allowed vertical speed as terrain approaches.
		set wantedThrottle to 0.
		lock steering to descentVector(horizontalSpeedLimit).
		set targetSpeed to descentSpeedAtAltitude(alt:radar).
		logDescent("controlled descent", targetSpeed).

		until alt:radar <= horizontalBrakeAltitude or descentComplete() {
			set targetSpeed to descentSpeedAtAltitude(alt:radar).
			set wantedThrottle to adjustDescentThrottle(
				wantedThrottle,
				targetSpeed
			).

			displayDescent("Controlled descent", targetSpeed, wantedThrottle).
			autostage().
			wait CONTROL_INTERVAL.
		}

		// Close to the surface, finish cancelling horizontal velocity.
		gear on.
		set targetSpeed to descentSpeedAtAltitude(alt:radar).
		logDescent("horizontal braking", targetSpeed).

		until groundSpeed <= horizontalSpeedLimit or descentComplete() {
			set targetSpeed to descentSpeedAtAltitude(alt:radar).
			set wantedThrottle to adjustDescentThrottle(
				wantedThrottle,
				targetSpeed
			).

			displayDescent("Horizontal braking", targetSpeed, wantedThrottle).
			autostage().
			wait CONTROL_INTERVAL.
		}

		// Horizontal velocity is gone; stay upright and continue following
		// the altitude steps until the final landing speed.
		lock steering to up.
		set targetSpeed to descentSpeedAtAltitude(alt:radar).
		logDescent("vertical landing", targetSpeed).

		until descentComplete() {
			set targetSpeed to descentSpeedAtAltitude(alt:radar).
			if alt:radar <= landingAltitude {
				set targetSpeed to -abs(landingSpeed).
			}

			set wantedThrottle to adjustDescentThrottle(
				wantedThrottle,
				targetSpeed
			).

			displayDescent("Vertical landing", targetSpeed, wantedThrottle).
			autostage().
			wait CONTROL_INTERVAL.
		}

		set wantedThrottle to 0.
		displayDescent("Complete", 0, wantedThrottle).
		logDescent("complete", 0).

		wait 0.
		unlock throttle.
		unlock steering.

		return status.
	}

	export(descent@).
}