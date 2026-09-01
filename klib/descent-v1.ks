{
	local printLn is import("printLn-v1"):printLn.
	local autostage is import("staging-v1"):autostage.
	local awaitSteering is import("steering-v1"):awaitSteering.

	local CONTROL_INTERVAL is 0.1.
	local VERTICAL_RESPONSE_TIME is 1.
	local VERTICAL_SPEED_TOLERANCE is 0.5.
	local GROUND_SPEED_TOLERANCE is 0.5.
	local HORIZONTAL_THROTTLE_STEP is 0.01.
	local HORIZONTAL_SPEED_THRESHOLD is 0.5.
	local GEAR_DEPLOYMENT_ALTITUDE is 1000.
	local CRASHED_IMPACT_SPEED is 10.
	local STEERING_STEP is 0.05.
	local STEERING_RECOVERY is 0.5.
	local STEERING_RETURN is 0.9.
	local REFERENCE_GRAVITY is 1.63.

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

	local HIGH_GROUND_SPEED is 250.
	local GROUND_SPEED_STEPS is list(
		list(5000, 200),
		list(2000, 150),
		list(1000, 75),
		list(500, 25),
		list(200, 10),
		list(100, 5),
		list(50, 2),
		list(20, 0)
	).

	local function descentVector {
		parameter horizontalBias.

		local horizontalVelocity is vxcl(up:vector, ship:velocity:surface).
		if horizontalBias <= 0 or horizontalVelocity:mag <= HORIZONTAL_SPEED_THRESHOLD return up.
		return (up:vector - horizontalVelocity:normalized * horizontalBias):normalized.
	}

	local function speedAtAltitude {
		parameter profileAltitude, highSpeed, speedSteps.

		local targetSpeed is highSpeed.
		for speedStep in speedSteps {
			if profileAltitude <= speedStep[0] {
				set targetSpeed to speedStep[1].
			}
		}
		return targetSpeed.
	}

	local function descentThrottle {
		parameter targetSpeed.

		if ship:availableThrust <= 0 return 0.

		local gravity is body:mu / (body:radius + altitude)^2.
		local maxAcceleration is ship:availableThrust / ship:mass.
		local verticalThrustFraction is vdot(ship:facing:foreVector, up:vector).
		if verticalThrustFraction <= 0 return 0.
		local correctionAcceleration is (targetSpeed - verticalSpeed) / VERTICAL_RESPONSE_TIME.

		return max(
			0,
			min(
				1,
				(gravity + correctionAcceleration) / (maxAcceleration * verticalThrustFraction)
			)
		).
	}

	// Limit horizontal braking thrust so its current vertical component
	// cannot deliberately accelerate the vessel upwards.
	local function horizontalThrottleLimit {
		if ship:availableThrust <= 0 return 0.

		local verticalThrustFraction is vdot(ship:facing:foreVector, up:vector).
		if verticalThrustFraction <= 0 return 0.

		local gravity is body:mu / (body:radius + altitude)^2.
		local maxAcceleration is ship:availableThrust / ship:mass.
		return min(1, gravity / (maxAcceleration * verticalThrustFraction)).
	}

	local function adjustHorizontalThrottle {
		parameter horizontalThrottle, targetGroundSpeed.

		if verticalSpeed >= 0 return 0.

		if groundSpeed > targetGroundSpeed + GROUND_SPEED_TOLERANCE {
			return min(
				horizontalThrottleLimit(),
				horizontalThrottle + HORIZONTAL_THROTTLE_STEP
			).
		}
		return max(0, horizontalThrottle - HORIZONTAL_THROTTLE_STEP).
	}

	local function surfaceContact {
		return status = "LANDED" or status = "SPLASHED".
	}

	local function displayDescent {
		parameter phase, profileAltitude, targetSpeed, wantedThrottle,
			targetGroundSpeed is 0, horizontalBias is 0.

		printLn("Descent:        " + phase, 0).
		printLn("Radar/profile:  " + round(alt:radar, 1) + " / " + round(profileAltitude, 1) + " m", 1).
		printLn("Periapsis:      " + round(obt:periapsis, 1) + " m", 2).
		printLn("Vertical speed: " + round(verticalSpeed, 1) + " m/s", 3).
		printLn("Target speed:   " + round(targetSpeed, 1) + " m/s", 4).
		printLn("Ground speed:   " + round(groundSpeed, 1) + " m/s", 5).
		printLn("Ground target:  " + round(targetGroundSpeed, 1) + " m/s", 6).
		printLn("Throttle/bias:  " + round(wantedThrottle * 100, 0) + "% / " + round(horizontalBias, 2), 7).
		printLn("Status:         " + status, 8).
	}

	local function logDescent {
		parameter phase, profileAltitude, targetSpeed, targetGroundSpeed, horizontalBias.

		dmsg(
			"Descent: " + phase +
				"; radar=" + round(alt:radar, 1) +
				"m; profile=" + round(profileAltitude, 1) +
				"m; vertical=" + round(verticalSpeed, 1) +
				"/" + round(targetSpeed, 1) +
				"m/s; ground=" + round(groundSpeed, 1) +
				"/" + round(targetGroundSpeed, 1) +
				"m/s; bias=" + round(horizontalBias, 2)
		).
	}

	function descent {
		parameter deorbitGroundSpeed is 250,
			finalDescentAltitude is 100,
			landingAltitude is 20,
			landingSpeed is 4.

		local gravityScale is sqrt((body:mu / body:radius^2) / REFERENCE_GRAVITY).
		local profileAltitude is alt:radar / gravityScale.
		local wantedThrottle is 0.
		local horizontalThrottle is 0.
		local horizontalBias is 0.
		local targetSpeed is 0.
		local targetGroundSpeed is deorbitGroundSpeed.
		local steeringVector is up:vector.
		lock throttle to wantedThrottle.

		clearScreen.
		displayDescent(
			"Coast to periapsis",
			profileAltitude,
			targetSpeed,
			wantedThrottle,
			targetGroundSpeed,
			horizontalBias
		).
		logDescent("coasting to periapsis", profileAltitude, targetSpeed, targetGroundSpeed, horizontalBias).

		if eta:periapsis > 30 {
			warpTo(time:seconds + eta:periapsis - 30).
		}

		sas off.
		lock steering to srfRetrograde.
		awaitSteering().
		wait until eta:periapsis <= 1.

		// Cancel most, but not all, horizontal velocity.
		set wantedThrottle to 1.
		set profileAltitude to alt:radar / gravityScale.
		logDescent("deorbit burn", profileAltitude, targetSpeed, deorbitGroundSpeed, horizontalBias).

		until (groundSpeed <= deorbitGroundSpeed and obt:periapsis < 0) or surfaceContact() {
			set profileAltitude to alt:radar / gravityScale.
			displayDescent(
				"Deorbit burn",
				profileAltitude,
				targetSpeed,
				wantedThrottle,
				deorbitGroundSpeed,
				horizontalBias
			).
			autostage().
			wait CONTROL_INTERVAL.
		}

		if not surfaceContact() {
			// Follow the gravity-scaled vertical and horizontal speed profiles.
			set wantedThrottle to 0.
			lock steering to steeringVector.

			set profileAltitude to alt:radar / gravityScale.
			set targetSpeed to speedAtAltitude(profileAltitude, HIGH_DESCENT_SPEED, DESCENT_STEPS).
			set targetGroundSpeed to speedAtAltitude(profileAltitude, HIGH_GROUND_SPEED, GROUND_SPEED_STEPS).
			local lastTargetSpeed is targetSpeed.
			local lastTargetGroundSpeed is targetGroundSpeed.
			logDescent("guided descent", profileAltitude, targetSpeed, targetGroundSpeed, horizontalBias).

			until (
				profileAltitude <= finalDescentAltitude and
				groundSpeed <= HORIZONTAL_SPEED_THRESHOLD
			) or surfaceContact() {
				set profileAltitude to alt:radar / gravityScale.
				set targetSpeed to speedAtAltitude(profileAltitude, HIGH_DESCENT_SPEED, DESCENT_STEPS).
				set targetGroundSpeed to speedAtAltitude(profileAltitude, HIGH_GROUND_SPEED, GROUND_SPEED_STEPS).

				if targetSpeed <> lastTargetSpeed or targetGroundSpeed <> lastTargetGroundSpeed {
					logDescent("profile step", profileAltitude, targetSpeed, targetGroundSpeed, horizontalBias).
					set lastTargetSpeed to targetSpeed.
					set lastTargetGroundSpeed to targetGroundSpeed.
				}

				if alt:radar <= GEAR_DEPLOYMENT_ALTITUDE {
					gear on.
				}

				if verticalSpeed >= 0 {
					set horizontalBias to 0.
				}
				else if verticalSpeed < targetSpeed - VERTICAL_SPEED_TOLERANCE {
					set horizontalBias to horizontalBias * STEERING_RECOVERY.
				}
				else if groundSpeed > targetGroundSpeed + GROUND_SPEED_TOLERANCE {
					set horizontalBias to horizontalBias + STEERING_STEP.
				}
				else if groundSpeed < targetGroundSpeed - GROUND_SPEED_TOLERANCE {
					set horizontalBias to horizontalBias * STEERING_RETURN.
				}

				set steeringVector to descentVector(horizontalBias).
				set horizontalThrottle to adjustHorizontalThrottle(horizontalThrottle, targetGroundSpeed).
				set wantedThrottle to max(descentThrottle(targetSpeed), horizontalThrottle).

				displayDescent(
					"Guided descent",
					profileAltitude,
					targetSpeed,
					wantedThrottle,
					targetGroundSpeed,
					horizontalBias
				).
				autostage().
				wait CONTROL_INTERVAL.
			}
		}

		if not surfaceContact() {
			// Horizontal velocity is gone; descend upright.
			set horizontalThrottle to 0.
			set horizontalBias to 0.
			lock steering to up.
			set targetSpeed to speedAtAltitude(profileAltitude, HIGH_DESCENT_SPEED, DESCENT_STEPS).
			logDescent("final descent", profileAltitude, targetSpeed, HORIZONTAL_SPEED_THRESHOLD, horizontalBias).

			until surfaceContact() {
				set profileAltitude to alt:radar / gravityScale.
				set targetSpeed to speedAtAltitude(profileAltitude, HIGH_DESCENT_SPEED, DESCENT_STEPS).
				if profileAltitude <= landingAltitude {
					set targetSpeed to -abs(landingSpeed).
				}

				if alt:radar <= GEAR_DEPLOYMENT_ALTITUDE {
					gear on.
				}

				set wantedThrottle to descentThrottle(targetSpeed).

				displayDescent(
					"Final descent",
					profileAltitude,
					targetSpeed,
					wantedThrottle,
					HORIZONTAL_SPEED_THRESHOLD,
					horizontalBias
				).
				autostage().
				wait CONTROL_INTERVAL.
			}
		}

		local impactVelocityMagnitude is ship:velocity:surface:mag.
		local resultStatus is
			choose status
			if impactVelocityMagnitude <= CRASHED_IMPACT_SPEED
			else "CRASHED".

		set wantedThrottle to 0.

		displayDescent(resultStatus, profileAltitude, 0, wantedThrottle).
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