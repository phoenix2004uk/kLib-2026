{
	local printLn is import("printLn-v1"):printLn.
	local autostage is import("staging-v1"):autostage.
	local awaitSteering is import("steering-v1"):awaitSteering.

	// PID tuning: Kp, Ki, Kd, epsilon.
	local VERTICAL_PID is list(0.75, 0, 0.1, 0.25).
	local HORIZONTAL_PID is list(0.75, 0.03, 0.05, 0.5).

	// Radar altitude, vertical speed, maximum horizontal speed.
	// Targets are linearly interpolated between profile rows.
	local DESCENT_PROFILE is list(
		list(10000, -60, 250),
		list(5000, -50, 200),
		list(2000, -40, 125),
		list(1000, -30, 50),
		list(500, -20, 10),
		list(200, -15, 5),
		list(100, -10, 2),
		list(50, -8, 0),
		list(25, -4, 0),
		list(0, -2, 0)
	).

	local GEAR_DEPLOYMENT_ALTITUDE is 1000.
	local CRASHED_IMPACT_SPEED is 10.

	local function descentTargets {
		parameter bottomAltRadar.

		local firstStep is DESCENT_PROFILE[0].
		if bottomAltRadar >= firstStep[0] {
			return list(firstStep[1], firstStep[2], 0).
		}

		from {local profileIndex is 1.}
		until profileIndex >= DESCENT_PROFILE:length
		step {set profileIndex to profileIndex + 1.}
		do {
			local upperStep is DESCENT_PROFILE[profileIndex - 1].
			local lowerStep is DESCENT_PROFILE[profileIndex].
			if bottomAltRadar >= lowerStep[0] {
				local fraction is (bottomAltRadar - lowerStep[0]) / (upperStep[0] - lowerStep[0]).
				return list(
					lowerStep[1] + (upperStep[1] - lowerStep[1]) * fraction,
					lowerStep[2] + (upperStep[2] - lowerStep[2]) * fraction,
					profileIndex
				).
			}
		}

		local lastIndex is DESCENT_PROFILE:length - 1.
		return list(
			DESCENT_PROFILE[lastIndex][1],
			DESCENT_PROFILE[lastIndex][2],
			lastIndex
		).
	}

	// Construct the required thrust-acceleration vector.
	// Vertical control has priority over horizontal braking.
	local function descentControl {
		parameter verticalPid, horizontalPid,
			targetVerticalSpeed, maxGroundSpeed, fallbackVector.

		if ship:availableThrust <= 0 {
			return list(fallbackVector, 0, 0, 0).
		}

		local gravityAcceleration is body:mu / (body:radius + altitude)^2.
		local maxThrustAcceleration is ship:availableThrust / ship:mass.
		local controlTime is time:seconds.

		// PID output is net vertical acceleration correction.
		// Add gravity to obtain the required vertical thrust component.
		set verticalPid:setpoint to targetVerticalSpeed.
		set verticalPid:minOutput to -gravityAcceleration.
		set verticalPid:maxOutput to maxThrustAcceleration - gravityAcceleration.
		local verticalThrustAcceleration is gravityAcceleration + verticalPid:update(controlTime, verticalSpeed).

		// Give horizontal braking whatever acceleration remains after
		// satisfying the requested vertical thrust component.
		local maxHorizontalAcceleration is sqrt(max(0, maxThrustAcceleration^2 - verticalThrustAcceleration^2)).
		set horizontalPid:setpoint to maxGroundSpeed.
		set horizontalPid:minOutput to -maxHorizontalAcceleration.
		set horizontalPid:maxOutput to 0.

		local horizontalThrustAcceleration is 0.
		if groundSpeed <= horizontalPid:epsilon {
			set horizontalPid:ki to 0.
			horizontalPid:reset().
		}
		else {
			set horizontalThrustAcceleration to -horizontalPid:update(controlTime, groundSpeed).
		}

		// Horizontal thrust may brake but never accelerate the vessel
		// sideways to chase a target after an overshoot.
		local horizontalVelocity is vxcl(up:vector, ship:velocity:surface).

		// Keep a positive UP component during a horizontal burn.
		if horizontalThrustAcceleration > 0 {
			set verticalThrustAcceleration to min(
				maxThrustAcceleration,
				max(1e-6, verticalThrustAcceleration)
			).
			set horizontalThrustAcceleration to min(
				horizontalThrustAcceleration,
				sqrt(
					max(
						0,
						maxThrustAcceleration^2 - verticalThrustAcceleration^2
					)
				)
			).
		}

		local thrustAccelerationVector is up:vector * verticalThrustAcceleration.
		if horizontalThrustAcceleration > 0 and
			horizontalVelocity:mag > 0 {
			set thrustAccelerationVector to thrustAccelerationVector - horizontalVelocity:normalized * horizontalThrustAcceleration.
		}

		if thrustAccelerationVector:mag <= 0 {
			return list(
				up:vector,
				0,
				verticalThrustAcceleration,
				horizontalThrustAcceleration
			).
		}

		return list(
			thrustAccelerationVector:normalized,
			min(
				1,
				thrustAccelerationVector:mag / maxThrustAcceleration
			),
			verticalThrustAcceleration,
			horizontalThrustAcceleration
		).
	}

	local function surfaceContact {
		return status = "LANDED" or status = "SPLASHED".
	}

	local function displayDescent {
		parameter phase, bottomAltRadar, targetVerticalSpeed, maxGroundSpeed,
			wantedThrottle, verticalThrustAcceleration is 0,
			horizontalThrustAcceleration is 0.

		printLn("Descent:        " + phase, 0).
		printLn("Radar/Bottom:   " + round(alt:radar, 1) + " m / " + round(bottomAltRadar, 1) + " m", 1).
		printLn("Periapsis:      " + round(obt:periapsis, 1) + " m", 2).
		printLn(
			"Vertical speed: " + round(verticalSpeed, 1) +
			" / " + round(targetVerticalSpeed, 1) + " m/s",
			3
		).
		printLn(
			"Ground speed:   " + round(groundSpeed, 1) +
			" / " + round(maxGroundSpeed, 1) + " m/s",
			4
		).
		printLn(
			"Thrust accel:   " +
			round(verticalThrustAcceleration, 2) + " / " +
			round(horizontalThrustAcceleration, 2) + " m/s^2",
			5
		).
		printLn(
			"Throttle:       " +
			round(wantedThrottle * 100, 0) + "%",
			6
		).
		printLn(
			"Zenith:         " +
			round(vang(ship:facing:foreVector, up:vector), 1) + " deg",
			7
		).
		printLn("Status:         " + status, 8).
	}

	local function logDescent {
		parameter phase, bottomAltRadar, targetVerticalSpeed, maxGroundSpeed,
			wantedThrottle, steeringVector.

		dmsg(
			"Descent: " + phase +
				"; radar=" + round(alt:radar, 1) +
				"m; bottom=" + round(bottomAltRadar, 1) +
				"m; vertical=" + round(verticalSpeed, 1) +
				"/" + round(targetVerticalSpeed, 1) +
				"m/s; ground=" + round(groundSpeed, 1) +
				"/" + round(maxGroundSpeed, 1) +
				"m/s; throttle=" +
				round(wantedThrottle * 100, 0) +
				"%; zenith=" +
				round(vang(steeringVector, up:vector), 1)
		).
	}

	function descent {
		local wantedThrottle is 0.
		local targetVerticalSpeed is 0.
		local maxGroundSpeed is DESCENT_PROFILE[0][2].
		local steeringVector is up:vector.
		local verticalThrustAcceleration is 0.
		local horizontalThrustAcceleration is 0.
		lock throttle to wantedThrottle.

		local vesselBounds is ship:bounds.
		local boundedByLandingLegs is false.
		local lock bottomAltRadar to vesselBounds:bottomAltRadar.

		clearScreen.
		displayDescent(
			"Coast to periapsis",
			bottomAltRadar,
			targetVerticalSpeed,
			maxGroundSpeed,
			wantedThrottle
		).
		logDescent(
			"coasting to periapsis",
			bottomAltRadar,
			targetVerticalSpeed,
			maxGroundSpeed,
			wantedThrottle,
			steeringVector
		).

		if eta:periapsis > 30 {
			warpTo(time:seconds + eta:periapsis - 30).
		}

		sas off.
		lock steering to srfRetrograde.
		awaitSteering().
		wait until eta:periapsis <= 1.

		// Lower periapsis below the surface while removing most
		// horizontal velocity.
		set wantedThrottle to 1.
		logDescent(
			"deorbit burn",
			bottomAltRadar,
			targetVerticalSpeed,
			maxGroundSpeed,
			wantedThrottle,
			srfRetrograde:vector
		).

		until (groundSpeed <= DESCENT_PROFILE[0][2] and obt:periapsis < 0) or surfaceContact() {
			displayDescent(
				"Deorbit burn",
				bottomAltRadar,
				targetVerticalSpeed,
				DESCENT_PROFILE[0][2],
				wantedThrottle
			).

			if autostage() set vesselBounds to ship:bounds.

			wait 0.
		}

		if not surfaceContact() {
			set wantedThrottle to 0.
			set steeringVector to up:vector.
			lock steering to
				choose lookDirUp(steeringVector, sun:position)
				if maxGroundSpeed <= 0
				else steeringVector.

			local verticalPid is pidLoop(
				VERTICAL_PID[0],
				VERTICAL_PID[1],
				VERTICAL_PID[2],
				0,
				0,
				VERTICAL_PID[3]
			).
			local horizontalPid is pidLoop(
				HORIZONTAL_PID[0],
				HORIZONTAL_PID[1],
				HORIZONTAL_PID[2],
				0,
				0,
				HORIZONTAL_PID[3]
			).

			local targetProfile is descentTargets(bottomAltRadar).
			set targetVerticalSpeed to targetProfile[0].
			set maxGroundSpeed to targetProfile[1].
			local currentProfileSegment is targetProfile[2].

			logDescent(
				"guided descent",
				bottomAltRadar,
				targetVerticalSpeed,
				maxGroundSpeed,
				wantedThrottle,
				steeringVector
			).

			until surfaceContact() {
				set targetProfile to descentTargets(bottomAltRadar).

				// Once the descent profile progresses, never relax it if
				// radar altitude subsequently increases.
				set targetVerticalSpeed to max(
					targetVerticalSpeed,
					targetProfile[0]
				).
				set maxGroundSpeed to min(
					maxGroundSpeed,
					targetProfile[1]
				).

				if targetProfile[2] > currentProfileSegment {
					set currentProfileSegment to targetProfile[2].
					logDescent(
						"profile segment",
						bottomAltRadar,
						targetVerticalSpeed,
						maxGroundSpeed,
						wantedThrottle,
						steeringVector
					).
				}

				// re-calculate bounds once the landing legs are fully deployed
				if not boundedByLandingLegs and legs {
					set boundedByLandingLegs to true.
					set vesselBounds to ship:bounds.
				}

				if not gear and bottomAltRadar <= GEAR_DEPLOYMENT_ALTITUDE {
					gear on.
				}

				local descentCommand is descentControl(
					verticalPid,
					horizontalPid,
					targetVerticalSpeed,
					maxGroundSpeed,
					steeringVector
				).
				set steeringVector to descentCommand[0].
				set wantedThrottle to descentCommand[1].
				set verticalThrustAcceleration to descentCommand[2].
				set horizontalThrustAcceleration to descentCommand[3].

				displayDescent(
					"Guided descent",
					bottomAltRadar,
					targetVerticalSpeed,
					maxGroundSpeed,
					wantedThrottle,
					verticalThrustAcceleration,
					horizontalThrustAcceleration
				).

				if autostage() set vesselBounds to ship:bounds.

				wait 0.
			}
		}

		local impactVelocityMagnitude is ship:velocity:surface:mag.
		local resultStatus is
			choose status
			if impactVelocityMagnitude <= CRASHED_IMPACT_SPEED
			else "CRASHED".

		set wantedThrottle to 0.

		displayDescent(resultStatus, bottomAltRadar, 0, 0, wantedThrottle).
		dmsg(
			"Descent: " + resultStatus +
			"; contact speed=" +
			round(impactVelocityMagnitude, 1) + "m/s"
		).

		// Hold upright while the landing gear settles.
		lock steering to lookDirUp(up:vector, sun:position).
		wait 10.

		unlock throttle.
		unlock steering.
		wait until not steeringManager:enabled.
		sas on.

		return resultStatus.
	}

	export(descent@).
}