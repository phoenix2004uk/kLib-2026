{
	local printLn is import("util/printLn-v1"):printLn.
	local autostage is import("sys/staging-v1"):autostage.
	local twr is import("tlm/twr-v1").
	local createSmoothThrottle is import("sys/smoothThrottle-v1").

	// Tuned ascent guidance parameters.
	local FIRST_PITCH is 80. // Initial gravity-turn pitch after vertical launch.
	local MIN_VERTICAL_SPEED is 50. // Vertical speed before starting the gravity turn.
	local THROTTLE_CONTROL_SPEED is 250. // Vertical speed before ETA throttle control may reduce thrust.
	local MIN_VERTICAL_TWR is 1.05. // Minimum supported vertical TWR while the trajectory still needs lift.
	local VERTICAL_TWR_RELEASE_RATIO is 2. // Horizontal/vertical speed ratio that permits the TWR floor to release.
	local VERTICAL_SPEED_DEFLECTION_THRESHOLD is 350. // Vertical speed where steering deflection begins.
	local VERTICAL_SPEED_FULL_DEFLECTION is 450. // Vertical speed where maximum steering deflection is reached.
	local MAXIMUM_DEFLECTION_ANGLE is 10. // Maximum pitch deflection below the prograde-derived heading.
	local ASCENT_VECTOR_BORDER is 35e3. // Altitude where steering changes from surface to orbital prograde.
	local ETA_TARGET_MIN is 15. // Minimum apoapsis ETA target during ascent.
	local ETA_TARGET_MAX is 75. // Maximum apoapsis ETA target during ascent.
	local ETA_TARGET_ALTITUDE_STEP is 1e3. // Metres of altitude per extra second of target ETA.

	// Tuned controller parameters.
	local ETA_PID_EPSILON is 1. // ETA PID deadband.
	local ASCENT_PID_KP is 5e-2. // Main-ascent ETA PID proportional gain.
	local ASCENT_PID_KI is 5e-4. // Main-ascent ETA PID integral gain.
	local ASCENT_PID_KD is 1e-2. // Main-ascent ETA PID derivative gain.
	local ASCENT_PID_MIN is 0.1. // Main-ascent ETA PID minimum throttle.
	local AP_PID_EPSILON is 100. // Apoapsis PID deadband in metres.
	local AP_HOLD_PID_KP is 1e-4. // Apoapsis-hold PID proportional gain.
	local AP_HOLD_PID_KI is 1e-5. // Apoapsis-hold PID integral gain.
	local AP_HOLD_PID_KD is 0. // Apoapsis-hold PID derivative gain.
	local INSERTION_THROTTLE_PID_KP is 0.1. // Orbital-insertion ETA PID proportional gain.
	local INSERTION_THROTTLE_PID_KI is 1e-3. // Orbital-insertion ETA PID integral gain.
	local INSERTION_THROTTLE_PID_KD is 1e-3. // Orbital-insertion ETA PID derivative gain.
	local INSERTION_THROTTLE_MIN is 0.01. // Orbital-insertion minimum powered throttle.
	local INSERTION_PITCH_PID_KP is 1e-2. // Orbital-insertion apoapsis PID proportional gain.
	local INSERTION_PITCH_PID_KI is 1e-3. // Orbital-insertion apoapsis PID integral gain.
	local INSERTION_PITCH_PID_KD is 1e-3. // Orbital-insertion apoapsis PID derivative gain.
	local PITCH_AOA_LIMIT is 20. // Maximum insertion pitch offset from prograde.

	// Fixed operational constants.
	local DEFLECTION_ANGLE_SPEED_MULTIPLIER is MAXIMUM_DEFLECTION_ANGLE / (VERTICAL_SPEED_FULL_DEFLECTION - VERTICAL_SPEED_DEFLECTION_THRESHOLD). // Deflection degrees per m/s above threshold.
	local ASCENT_LOG_ALTITUDE_STEP is 100. // Altitude interval between ascent log samples.
	local EAST_LAUNCH_HEADING is 90. // Equatorial eastward launch heading.
	local VERTICAL_PITCH is 90. // Straight-up pitch and zenith-to-pitch conversion.
	local IGNITION_DELAY is 1. // Delay before ignition/staging sequence.
	local INSERTION_ATMOSPHERE_MARGIN is 50. // Clearance above the atmosphere before insertion timing.
	local INSERTION_INITIAL_THROTTLE is 0.1. // Initial throttle when beginning orbital insertion.
	local HANDOFF_DELAY is 0.1. // Brief yield after handing steering to prograde.
	local THROTTLE_MIN is 0. // Fully closed throttle.
	local THROTTLE_MAX is 1. // Fully open throttle.

	// Default orbital-insertion targets.
	local INSERTION_AP_MAX_ERROR is 10e3. // Maximum allowed apoapsis overshoot.
	local INSERTION_ETA_TARGET is 60. // Target apoapsis ETA during insertion.
	local INSERTION_ETA_MIN is 30. // Minimum useful apoapsis ETA before handing off.
	local INSERTION_PE_TARGET is 35e3. // Periapsis target for insertion completion.

	function ascentEtaTarget {
		return max(
			ETA_TARGET_MIN,
			min(
				ETA_TARGET_MAX,
				ETA_TARGET_MIN + altitude / ETA_TARGET_ALTITUDE_STEP
			)
		).
	}

	function ascentSteeringDirection {
		parameter launchDirection.

		local guidancePrograde is
			choose srfPrograde
			if altitude < ASCENT_VECTOR_BORDER
			else prograde.
		local progradePitch is VERTICAL_PITCH - vang(up:vector, guidancePrograde:vector).
		local pitchDeflection is min(
			MAXIMUM_DEFLECTION_ANGLE,
			max(
				0,
				(verticalSpeed - VERTICAL_SPEED_DEFLECTION_THRESHOLD) * DEFLECTION_ANGLE_SPEED_MULTIPLIER
			)
		).

		return heading(launchDirection, progradePitch - pitchDeflection).
	}

	function minimumAscentThrottle {
		if altitude >= ASCENT_VECTOR_BORDER
		and groundSpeed >= VERTICAL_TWR_RELEASE_RATIO * verticalSpeed return THROTTLE_MIN.

		local availableVerticalTwr is twr:vAvailable().
		if availableVerticalTwr <= 0 return THROTTLE_MAX.

		return min(THROTTLE_MAX, MIN_VERTICAL_TWR / availableVerticalTwr).
	}

	function nextAscentLogAltitude {
		return (floor(altitude / ASCENT_LOG_ALTITUDE_STEP) + 1) * ASCENT_LOG_ALTITUDE_STEP.
	}

	function createAscentLogState {
		return lex(
			"maxQ", 0,
			"nextAltitude", nextAscentLogAltitude()
		).
	}

	function reportAscent {
		parameter phase, apTarget, wantedThrottle, currentQ, maxQ,
			showDisplay, writeLog.

		local etaTarget is ascentEtaTarget().
		local availableTwr is twr:available().
		local currentTwrValue is twr:current().
		local steeringVector is steeringManager:target:vector.
		local targetZenith is vang(up:vector, steeringVector).
		local facingZenith is vang(up:vector, facing:foreVector).
		local verticalTwr is currentTwrValue * cos(facingZenith).
		local targetPitch is VERTICAL_PITCH - targetZenith.
		local facingPitch is VERTICAL_PITCH - facingZenith.

		if showDisplay {
			printLn("Ascent", 0).
			printLn("       Altitude: " + round(altitude/1e3, 1) + "km", 1).
			printLn("       Apoapsis: " + round(apoapsis/1e3, 1) + "km / " + round(apTarget/1e3, 1) + "km", 2).
			printLn("   Apoapsis ETA: " + round(eta:apoapsis, 1) + "s / " + round(etaTarget, 1) + "s", 3).
			printLn("      Speed V/H: " + round(verticalSpeed, 0) + " / " + round(groundSpeed, 0) + "m/s", 4).
			printLn("      Periapsis: " + round(periapsis/1e3, 1) + "km", 5).
			printLn("  Pitch tgt/act: " + round(targetPitch, 1) + " / " + round(facingPitch, 1) + "deg", 6).
			printLn("Target Throttle: " + round(wantedThrottle * 100, 0) + "% / Stage: " + stage:number, 7).
			printLn("Actual Throttle: " + round(throttle * 100, 0) + "%", 8).
			printLn("   TWR avl/vert: " + round(availableTwr, 2) + " / " + round(verticalTwr, 2), 9).
			printLn("          Q/max: " + round(currentQ, 2) + " / " + round(maxQ, 2) + "kPa", 10).
		}

		if writeLog {
			dmsg(
				"Ascent: " + phase +
				"; ut=" + round(time:seconds, 1) +
				"; altitude=" + round(altitude, 0) +
				"m; apoapsis=" + round(apoapsis, 0) +
				"/" + round(apTarget, 0) +
				"m; eta=" + round(eta:apoapsis, 1) +
				"/" + round(etaTarget, 1) +
				"s; vertical=" + round(verticalSpeed, 1) +
				"m/s; ground=" + round(groundSpeed, 1) +
				"m/s; periapsis=" + round(periapsis, 0) +
				"m; pitch=" + round(targetPitch, 1) +
				"/" + round(facingPitch, 1) +
				"deg; error=" + round(vang(steeringVector, facing:foreVector), 1) +
				"deg; wantedThrottle=" + round(wantedThrottle * 100, 1) +
				"%; throttle=" + round(throttle * 100, 1) +
				"%; twr=" + round(availableTwr, 2) +
				"; currentTwr=" + round(currentTwrValue, 2) +
				"; verticalTwr=" + round(verticalTwr, 2) +
				"; q=" + round(currentQ, 2) +
				"/" + round(maxQ, 2) +
				"kPa; stage=" + stage:number
			).
		}
	}

	function updateAscentTelemetry {
		parameter logState, apTarget, wantedThrottle, showDisplay is false.

		local currentQ is ship:q * constant:ATMtokPa.
		local altitudeLogDue is altitude >= logState:nextAltitude.
		set logState["maxQ"] to max(logState:maxQ, currentQ).

		if showDisplay or altitudeLogDue {
			reportAscent(
				"ascent",
				apTarget,
				wantedThrottle,
				currentQ,
				logState:maxQ,
				showDisplay,
				altitudeLogDue
			).
		}

		if altitudeLogDue {
			set logState["nextAltitude"] to nextAscentLogAltitude().
		}
	}

	function logAscentEvent {
		parameter logState, phase, apTarget, wantedThrottle.

		local currentQ is ship:q * constant:ATMtokPa.
		reportAscent(
			phase,
			apTarget,
			wantedThrottle,
			currentQ,
			logState:maxQ,
			false,
			true
		).
	}

	function verticalLaunch {
		parameter logState, apTarget, launchDirection.

		lock steering to heading(launchDirection, VERTICAL_PITCH).
		lock throttle to THROTTLE_MAX.

		clearScreen.
		wait IGNITION_DELAY.
		stage.
		printLn("Ignition").
		wait until stage:ready.
		printLn("Liftoff!").

		until verticalSpeed >= MIN_VERTICAL_SPEED {
			updateAscentTelemetry(logState, apTarget, THROTTLE_MAX).
			autostage().
			wait 0.
		}
	}

	function startGravityTurn {
		parameter logState, apTarget, launchDirection.

		printLn("Pitching to " + FIRST_PITCH + "°").
		lock steering to heading(launchDirection, FIRST_PITCH).

		printLn("Performing gravity turn").
		until vang(up:vector, srfPrograde:vector) > VERTICAL_PITCH - FIRST_PITCH {
			updateAscentTelemetry(logState, apTarget, THROTTLE_MAX).
			autostage().
			wait 0.
		}
	}

	function followAscentTrajectory {
		parameter logState, apTarget, launchDirection, smoothThrottle.

		printLn("Following surface prograde").
		lock steering to ascentSteeringDirection(launchDirection).

		local pidThrottle is pidLoop(
			ASCENT_PID_KP,
			ASCENT_PID_KI,
			ASCENT_PID_KD,
			ASCENT_PID_MIN,
			THROTTLE_MAX,
			ETA_PID_EPSILON
		).
		local wantedThrottle is THROTTLE_MAX.
		local throttleControlEnabled is false.
		lock throttle to smoothThrottle:current().

		logAscentEvent(logState, "following prograde", apTarget, wantedThrottle).

		until apoapsis >= apTarget {
			if not throttleControlEnabled
			and verticalSpeed >= THROTTLE_CONTROL_SPEED {
				set throttleControlEnabled to true.
			}

			updateAscentTelemetry(logState, apTarget, wantedThrottle, true).
			set pidThrottle:setpoint to ascentEtaTarget().
			set wantedThrottle to
				choose max(
					minimumAscentThrottle(),
					pidThrottle:update(time:seconds, eta:apoapsis)
				)
				if throttleControlEnabled
				else THROTTLE_MAX.
			smoothThrottle:setTarget(wantedThrottle).

			if autostage() {
				logAscentEvent(logState, "staged", apTarget, wantedThrottle).
			}

			wait 0.
		}

		logAscentEvent(logState, "apoapsis target", apTarget, wantedThrottle).
	}

	function maintainApoapsis {
		parameter logState, apTarget, launchDirection, smoothThrottle.

		clearScreen.
		printLn("Maintaining apoapsis").
		lock steering to ascentSteeringDirection(launchDirection).

		local pidApHold is pidLoop(
			AP_HOLD_PID_KP,
			AP_HOLD_PID_KI,
			AP_HOLD_PID_KD,
			THROTTLE_MIN,
			THROTTLE_MAX,
			AP_PID_EPSILON
		).
		set pidApHold:setpoint to apTarget.

		smoothThrottle:reset(THROTTLE_MIN).
		local wantedThrottle is THROTTLE_MIN.
		lock throttle to smoothThrottle:current().

		until altitude >= body:atm:height {
			updateAscentTelemetry(logState, apTarget, wantedThrottle).
			set wantedThrottle to pidApHold:update(time:seconds, apoapsis).
			smoothThrottle:setTarget(wantedThrottle).
			autostage().
			wait 0.
		}

		lock throttle to THROTTLE_MIN.
	}

	function insertionComplete {
		parameter apTarget, apMaxError, etaMin, peTarget.

		return periapsis > peTarget
		or eta:apoapsis < etaMin
		or eta:periapsis < eta:apoapsis
		or apoapsis > apTarget + apMaxError.
	}

	function displayOrbitalInsertion {
		parameter apTarget, apMaxError, etaTarget, peTarget, pitchOffset.

		printLn("Apoapsis:       " + round(apoapsis/1e3, 1) + "km / " + round(apTarget/1e3, 1) + "km", 1).
		printLn("Apoapsis Error: " + round((apoapsis - apTarget)/1e3, 1) + "km / " + round(apMaxError/1e3, 1) + "km", 2).
		printLn("Apoapsis ETA:   " + round(eta:apoapsis, 1) + "s / " + round(etaTarget, 1) + "s", 3).
		printLn("Periapsis:      " + round(periapsis/1e3, 1) + "km / " + round(peTarget/1e3, 1) + "km", 4).
		printLn("Pitch Angle:    " + round(pitchOffset, 2) + "°", 5).
	}

	function performOrbitalInsertion {
		parameter apTarget, apMaxError, etaTarget, etaMin, peTarget.

		clearScreen.
		printLn("Orbital Insertion").

		local pidThrottle is pidLoop(
			INSERTION_THROTTLE_PID_KP,
			INSERTION_THROTTLE_PID_KI,
			INSERTION_THROTTLE_PID_KD,
			INSERTION_THROTTLE_MIN,
			THROTTLE_MAX,
			ETA_PID_EPSILON
		).
		local pidPitch is pidLoop(
			INSERTION_PITCH_PID_KP,
			INSERTION_PITCH_PID_KI,
			INSERTION_PITCH_PID_KD,
			-PITCH_AOA_LIMIT,
			PITCH_AOA_LIMIT,
			AP_PID_EPSILON
		).
		local pitchOffset is 0.
		local insertionThrottle is INSERTION_INITIAL_THROTTLE.
		local lock vPrograde to velocity:orbit:normalized.
		local lock vRadial to body:position:normalized.
		local lock radialPerp to vxcl(vPrograde, vRadial):normalized.
		local lock vSteer to vPrograde * cos(pitchOffset) - radialPerp * sin(pitchOffset).
		lock steering to vSteer.

		printLn("Orbital Insertion - awaiting atmospheric border: " + body:atm:height).
		wait until altitude > body:atm:height + INSERTION_ATMOSPHERE_MARGIN.
		kuniverse:timewarp:cancelwarp().
		wait until kuniverse:timewarp:issettled().

		printLn("Orbital Insertion - awaiting eta:apoapsis < " + etaTarget).
		wait until eta:apoapsis <= etaTarget or eta:periapsis < eta:apoapsis.
		kuniverse:timewarp:cancelwarp().
		wait until kuniverse:timewarp:issettled().

		printLn("Orbital Insertion - raising Pe").		
		local smoothThrottle is createSmoothThrottle().
		smoothThrottle:setTarget(insertionThrottle).
		lock throttle to smoothThrottle:current().
		set pidThrottle:setpoint to etaTarget.
		set pidPitch:setpoint to apTarget.

		until insertionComplete(apTarget, apMaxError, etaMin, peTarget) {
			displayOrbitalInsertion(
				apTarget,
				apMaxError,
				etaTarget,
				peTarget,
				pitchOffset
			).
			set insertionThrottle to pidThrottle:update(time:seconds, eta:apoapsis).
			smoothThrottle:setTarget(insertionThrottle).
			set pitchOffset to pidPitch:update(time:seconds, apoapsis).
			autostage().
			wait 0.
		}
	}

	function ascentHandoff {
		clearScreen.
		printLn("Coasting towards apoapsis").
		lock throttle to THROTTLE_MIN.
		lock steering to prograde.
		wait HANDOFF_DELAY.
	}

	function executeAscent {
		parameter apTarget, incTarget is 0.

		local launchDirection is EAST_LAUNCH_HEADING - incTarget.
		local logState is createAscentLogState().

		verticalLaunch(logState, apTarget, launchDirection).
		startGravityTurn(logState, apTarget, launchDirection).

		local smoothThrottle is createSmoothThrottle().
		followAscentTrajectory(
			logState,
			apTarget,
			launchDirection,
			smoothThrottle
		).
		maintainApoapsis(
			logState,
			apTarget,
			launchDirection,
			smoothThrottle
		).
	}

	function orbitalInsertion {
		parameter apTarget,
			apMaxError is INSERTION_AP_MAX_ERROR,
			etaTarget is INSERTION_ETA_TARGET,
			etaMin is INSERTION_ETA_MIN,
			peTarget is INSERTION_PE_TARGET.

		if insertionComplete(apTarget, apMaxError, etaMin, peTarget) {
			ascentHandoff().
			return.
		}

		performOrbitalInsertion(
			apTarget,
			apMaxError,
			etaTarget,
			etaMin,
			peTarget
		).
		ascentHandoff().
	}

	export(lex(
		"executeAscent", executeAscent@,
		"orbitalInsertion", orbitalInsertion@
	)).
}