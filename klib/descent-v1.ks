{
	local printLn is import("printLn-v1"):printLn.
	local autostage is import("staging-v1"):autostage.
	local awaitSteering is import("steering-v1"):awaitSteering.

	// Vertical-speed correction time; lower reacts harder/faster.
	local VERTICAL_RESPONSE_TIME is 0.75.
	// Vertical-speed error allowed before steering recovery.
	local VERTICAL_SPEED_TOLERANCE is 0.5.
	// Ground-speed error allowed before steering/throttle correction.
	local GROUND_SPEED_TOLERANCE is 0.5.
	// Horizontal throttle change per second; higher reacts faster.
	local HORIZONTAL_THROTTLE_RATE is 0.2.
	// Initial horizontal steering bias when braking starts.
	local STEERING_INITIAL_BIAS is 0.05.
	// Bias doubling time; lower tilts horizontal faster.
	local STEERING_GROWTH_TIME is 0.75.
	// Bias halving time when vertical control is saturated.
	local STEERING_RECOVERY_TIME is 0.25.
	// Bias halving time once horizontal speed is under target.
	local STEERING_RETURN_TIME is 0.75.
	// Default vertical-speed target above the profile.
	local HIGH_DESCENT_SPEED is -60.
	// Default ground-speed target above the profile.
	local HIGH_GROUND_SPEED is 250.
	// Radar altitude, vertical-speed target, ground-speed target.
	local DESCENT_PROFILE is list(
		list(5000, -50, 200),
		list(2000, -40, 125),
		list(1000, -30, 50),
		list(500, -20, 10),
		list(200, -15, 5),
		list(100, -10, 2),
		list(50, -8, 1),
		list(20, -5, 0)
	).

	// Ground speed considered negligible.
	local HORIZONTAL_SPEED_THRESHOLD is 0.5.
	// Radar altitude to deploy landing gear.
	local GEAR_DEPLOYMENT_ALTITUDE is 1000.
	// Contact speed above which landing is considered crashed.
	local CRASHED_IMPACT_SPEED is 10.

	local function descentVector {
		parameter horizontalBias.

		local horizontalVelocity is vxcl(up:vector, ship:velocity:surface).
		if horizontalBias <= 0 or horizontalVelocity:mag <= HORIZONTAL_SPEED_THRESHOLD return up.
		return (up:vector - horizontalVelocity:normalized * horizontalBias):normalized.
	}

	local function speedsAtAltitude {
		local targetSpeed is HIGH_DESCENT_SPEED.
		local targetGroundSpeed is HIGH_GROUND_SPEED.
		for descentStep in DESCENT_PROFILE {
			if alt:radar <= descentStep[0] {
				set targetSpeed to descentStep[1].
				set targetGroundSpeed to descentStep[2].
			}
		}
		return list(targetSpeed, targetGroundSpeed).
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
		parameter horizontalThrottle, targetGroundSpeed, deltaTime.

		if groundSpeed > targetGroundSpeed + GROUND_SPEED_TOLERANCE {
			return min(
				horizontalThrottleLimit(),
				horizontalThrottle + HORIZONTAL_THROTTLE_RATE * deltaTime
			).
		}
		return max(0, horizontalThrottle - HORIZONTAL_THROTTLE_RATE * deltaTime).
	}

	local function surfaceContact {
		return status = "LANDED" or status = "SPLASHED".
	}

	local function displayDescent {
		parameter phase, targetSpeed, wantedThrottle,
			targetGroundSpeed is 0, horizontalBias is 0.

		printLn("Descent:        " + phase, 0).
		printLn("Radar:          " + round(alt:radar, 1) + " m", 1).
		printLn("Periapsis:      " + round(obt:periapsis, 1) + " m", 2).
		printLn("Vertical speed: " + round(verticalSpeed, 1) + " m/s", 3).
		printLn("Target speed:   " + round(targetSpeed, 1) + " m/s", 4).
		printLn("Ground speed:   " + round(groundSpeed, 1) + " m/s", 5).
		printLn("Ground target:  " + round(targetGroundSpeed, 1) + " m/s", 6).
		printLn("Throttle/bias:  " + round(wantedThrottle * 100, 0) + "% / " + round(horizontalBias, 2), 7).
		printLn("Status:         " + status, 8).
	}

	local function logDescent {
		parameter phase, targetSpeed, targetGroundSpeed, horizontalBias.

		dmsg(
			"Descent: " + phase +
				"; radar=" + round(alt:radar, 1) +
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
			targetSpeed,
			wantedThrottle,
			targetGroundSpeed,
			horizontalBias
		).
		logDescent("coasting to periapsis", targetSpeed, targetGroundSpeed, horizontalBias).

		if eta:periapsis > 30 {
			warpTo(time:seconds + eta:periapsis - 30).
		}

		sas off.
		lock steering to srfRetrograde.
		awaitSteering().
		wait until eta:periapsis <= 1.

		// Cancel most, but not all, horizontal velocity.
		set wantedThrottle to 1.
		logDescent("deorbit burn", targetSpeed, deorbitGroundSpeed, horizontalBias).

		until (groundSpeed <= deorbitGroundSpeed and obt:periapsis < 0) or surfaceContact() {
			displayDescent(
				"Deorbit burn",
				targetSpeed,
				wantedThrottle,
				deorbitGroundSpeed,
				horizontalBias
			).
			autostage().
			wait 0.
		}

		if not surfaceContact() {
			// Follow the vertical and horizontal speed profile.
			set wantedThrottle to 0.
			lock steering to steeringVector.

			local targetSpeeds is speedsAtAltitude().
			set targetSpeed to targetSpeeds[0].
			set targetGroundSpeed to targetSpeeds[1].
			local lastTargetSpeed is targetSpeed.
			local lastTargetGroundSpeed is targetGroundSpeed.
			local lastControlTime is time:seconds.
			local controlTime is lastControlTime.
			local deltaTime is 0.
			logDescent("guided descent", targetSpeed, targetGroundSpeed, horizontalBias).

			until (
				alt:radar <= finalDescentAltitude and
				groundSpeed <= HORIZONTAL_SPEED_THRESHOLD
			) or surfaceContact() {
				set controlTime to time:seconds.
				set deltaTime to controlTime - lastControlTime.
				set lastControlTime to controlTime.

				// Once a profile target tightens, do not relax it if
				// radar altitude subsequently increases.
				set targetSpeeds to speedsAtAltitude().
				set targetSpeed to max(targetSpeed, targetSpeeds[0]).
				set targetGroundSpeed to min(targetGroundSpeed, targetSpeeds[1]).

				if targetSpeed <> lastTargetSpeed or targetGroundSpeed <> lastTargetGroundSpeed {
					logDescent("profile step", targetSpeed, targetGroundSpeed, horizontalBias).
					set lastTargetSpeed to targetSpeed.
					set lastTargetGroundSpeed to targetGroundSpeed.
				}

				if alt:radar <= GEAR_DEPLOYMENT_ALTITUDE {
					gear on.
				}

				local verticalThrottle is descentThrottle(targetSpeed).
				local verticalThrustFraction is vdot(ship:facing:foreVector, up:vector).

				// Horizontal error controls attitude. Vertical error is first
				// handled with throttle; pull upright only when vertical control
				// is saturated, or if actual steering has crossed the horizon.
				if (verticalSpeed < targetSpeed - VERTICAL_SPEED_TOLERANCE and verticalThrottle >= 1)
					or verticalThrustFraction <= 0 {
					set horizontalBias to horizontalBias * 0.5^(deltaTime / STEERING_RECOVERY_TIME).
				}
				else if groundSpeed > targetGroundSpeed + GROUND_SPEED_TOLERANCE {
					set horizontalBias to max(
						STEERING_INITIAL_BIAS,
						horizontalBias * 2^(deltaTime / STEERING_GROWTH_TIME)
					).
				}
				else if groundSpeed < targetGroundSpeed - GROUND_SPEED_TOLERANCE {
					set horizontalBias to horizontalBias * 0.5^(deltaTime / STEERING_RETURN_TIME).
				}

				set steeringVector to descentVector(horizontalBias).
				set horizontalThrottle to adjustHorizontalThrottle(
					horizontalThrottle,
					targetGroundSpeed,
					deltaTime
				).
				set wantedThrottle to max(verticalThrottle, horizontalThrottle).

				displayDescent(
					"Guided descent",
					targetSpeed,
					wantedThrottle,
					targetGroundSpeed,
					horizontalBias
				).
				autostage().
				wait 0.
			}
		}

		if not surfaceContact() {
			// Horizontal velocity is negligible; descend upright.
			set horizontalThrottle to 0.
			set horizontalBias to 0.
			lock steering to up.
			set targetSpeed to max(targetSpeed, speedsAtAltitude()[0]).
			logDescent("final descent", targetSpeed, HORIZONTAL_SPEED_THRESHOLD, horizontalBias).

			until surfaceContact() {
				set targetSpeed to max(targetSpeed, speedsAtAltitude()[0]).
				if alt:radar <= landingAltitude {
					set targetSpeed to -abs(landingSpeed).
				}

				if alt:radar <= GEAR_DEPLOYMENT_ALTITUDE {
					gear on.
				}

				set wantedThrottle to descentThrottle(targetSpeed).

				displayDescent(
					"Final descent",
					targetSpeed,
					wantedThrottle,
					HORIZONTAL_SPEED_THRESHOLD,
					horizontalBias
				).
				autostage().
				wait 0.
			}
		}

		local impactVelocityMagnitude is ship:velocity:surface:mag.
		local resultStatus is
			choose status
			if impactVelocityMagnitude <= CRASHED_IMPACT_SPEED
			else "CRASHED".

		set wantedThrottle to 0.

		displayDescent(resultStatus, 0, wantedThrottle).
		dmsg("Descent: " + resultStatus + "; contact speed=" + round(impactVelocityMagnitude, 1) + "m/s").

		// Hold upright while the landing gear settles.
		dmsg("SAS at contact: " + sas).
		sas off.
		lock steering to up.
		wait 2.

		dmsg("SAS before steering unlock: " + sas).
		unlock throttle.
		unlock steering.
		dmsg("Steering target: " + steeringManager:target).
		dmsg("Steering enabled immediately after unlock: " + steeringManager:enabled).
		wait until not steeringManager:enabled.
		dmsg("Steering manager released; enabling SAS").
		sas on.

		return resultStatus.
	}

	export(descent@).
}