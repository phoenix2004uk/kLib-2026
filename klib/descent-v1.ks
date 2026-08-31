{
	local printLn is import("printLn-v1"):printLn.
	local autostage is import("staging-v1"):autostage.
	local awaitSteering is import("steering-v1"):awaitSteering.

	local CONTROL_INTERVAL is 0.1.
	local VERTICAL_RESPONSE_TIME is 1.
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

	local function descentThrottle {
		parameter targetSpeed.

		if ship:availableThrust <= 0 return 0.

		local gravity is body:mu / (body:radius + altitude)^2.
		local maxAcceleration is ship:availableThrust / ship:mass.
		local verticalThrustFraction is max(
			0.01,
			vdot(ship:facing:foreVector, up:vector)
		).
		local correctionAcceleration is (targetSpeed - verticalSpeed) / VERTICAL_RESPONSE_TIME.

		return max(
			0,
			min(
				1,
				(gravity + correctionAcceleration) / (maxAcceleration * verticalThrustFraction)
			)
		).
	}

	local function surfaceContact {
		return status = "LANDED" or status = "SPLASHED".
	}

	local function displayDescent {
		parameter phase, targetSpeed, wantedThrottle, targetGroundSpeed is 0.

		printLn("Descent:        " + phase, 0).
		printLn("Radar altitude: " + round(alt:radar, 1) + " m", 1).
		printLn("Periapsis:      " + round(obt:periapsis, 1) + " m", 2).
		printLn("Vertical speed: " + round(verticalSpeed, 1) + " m/s", 3).
		printLn("Target speed:   " + round(targetSpeed, 1) + " m/s", 4).
		printLn("Ground speed:   " + round(groundSpeed, 1) + " m/s", 5).
		printLn("Ground target:  " + round(targetGroundSpeed, 1) + " m/s", 6).
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
		parameter deorbitGroundSpeed is 250,
			horizontalBrakeAltitude is 1000,
			horizontalSpeedLimit is 1,
			landingAltitude is 20,
			landingSpeed is 4,
			impactSpeedLimit is 10.

		local wantedThrottle is 0.
		local targetSpeed is 0.
		lock throttle to wantedThrottle.

		clearScreen.
		displayDescent("Coast to periapsis", targetSpeed, wantedThrottle).
		logDescent("coasting to periapsis", targetSpeed).

		if eta:periapsis > 30 {
			warpTo(time:seconds + eta:periapsis - 30).
		}

		sas off.
		lock steering to srfRetrograde.
		awaitSteering().
		wait until eta:periapsis <= 1.

		// Cancel most, but not all, horizontal velocity.
		set wantedThrottle to 1.
		logDescent("deorbit burn", targetSpeed).

		until (groundSpeed <= deorbitGroundSpeed and obt:periapsis < 0) or surfaceContact() {

			displayDescent("Deorbit burn", targetSpeed, wantedThrottle, deorbitGroundSpeed).
			autostage().
			wait CONTROL_INTERVAL.
		}

		if not surfaceContact() {
			// Continue bleeding horizontal velocity while controlling descent rate.
			set wantedThrottle to 0.
			lock steering to descentVector(horizontalSpeedLimit).
			set targetSpeed to descentSpeedAtAltitude(alt:radar).
			logDescent("controlled descent", targetSpeed).

			until alt:radar <= horizontalBrakeAltitude or surfaceContact() {
				set targetSpeed to descentSpeedAtAltitude(alt:radar).
				set wantedThrottle to descentThrottle(targetSpeed).

				displayDescent("Controlled descent", targetSpeed, wantedThrottle, horizontalSpeedLimit).
				autostage().
				wait CONTROL_INTERVAL.
			}
		}

		if not surfaceContact() {
			// From here the priority is removing the remaining horizontal speed.
			gear on.
			set targetSpeed to descentSpeedAtAltitude(alt:radar).
			logDescent("horizontal braking", targetSpeed).

			until groundSpeed <= horizontalSpeedLimit or surfaceContact() {
				set targetSpeed to descentSpeedAtAltitude(alt:radar).
				set wantedThrottle to descentThrottle(targetSpeed).

				displayDescent("Horizontal braking", targetSpeed, wantedThrottle, horizontalSpeedLimit).
				autostage().
				wait CONTROL_INTERVAL.
			}
		}

		if not surfaceContact() {
			// Horizontal velocity is gone; descend upright.
			lock steering to up.
			logDescent("vertical landing", targetSpeed).

			until surfaceContact() {
				set targetSpeed to descentSpeedAtAltitude(alt:radar).
				if alt:radar <= landingAltitude {
					set targetSpeed to -abs(landingSpeed).
				}

				set wantedThrottle to descentThrottle(targetSpeed).

				displayDescent("Vertical landing", targetSpeed, wantedThrottle).
				autostage().
				wait CONTROL_INTERVAL.
			}
		}

		local impactVelocityMagnitude is ship:velocity:surface:mag.
		local resultStatus is
			choose status
			if impactVelocityMagnitude <= impactSpeedLimit
			else "CRASHED".

		set wantedThrottle to 0.

		displayDescent(resultStatus, 0, wantedThrottle).
		dmsg("Descent: " + resultStatus + "; contact speed=" + round(impactVelocityMagnitude, 1) + "m/s").

		// Hold upright while the landing gear settles.
		lock steering to up.
		wait 2.

		unlock throttle.
		unlock steering.
		wait 0.
		sas on.

		return resultStatus.
	}

	export(descent@).
}