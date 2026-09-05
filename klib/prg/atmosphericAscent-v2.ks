{
	local printLn is import("util/printLn-v1"):printLn.
	local autostage is import("sys/staging-v1"):autostage.
	local twr is import("tlm/twr-v1").
	
	local ASCENT_VECTOR_BORDER is 35e3.
	local ETA_PID_EPSILON is 1.
	local PITCH_AOA_LIMIT is 20.
	local AP_PID_EPSILON is 100.
	local MIN_VERTICAL_TWR is 1.05.
	local VERTICAL_SPEED_DEFLECTION_THRESHOLD is 350.
	local MAXIMUM_DEFLECTION_ANGLE is 10.
	local DEFLECTION_ANGLE_SPEED_MULTIPLIER is MAXIMUM_DEFLECTION_ANGLE / 100.
	local ASCENT_LOG_ALTITUDE_STEP is 100.

	local function displayAscent {
		parameter apTarget, etaTarget, wantedThrottle,
			steeringVector, currQ, maxQ.

		local availableTwr is twr:available().
		local targetZenith is vang(up:vector, steeringVector).
		local facingZenith is vang(up:vector, facing:vector).
		local verticalTwr is twr:vCurrent().

		printLn("Ascent", 0).
		printLn("      Altitude: " + round(altitude/1e3, 1) + "km", 1).
		printLn("      Apoapsis: " + round(apoapsis/1e3, 1) + "km / " + round(apTarget/1e3, 1) + "km", 2).
		printLn("  Apoapsis ETA: " + round(eta:apoapsis, 1) + "s / " + round(etaTarget, 1) + "s", 3).
		printLn("     Speed V/H: " + round(verticalSpeed, 0) + " / " + round(groundSpeed, 0) + "m/s", 4).
		printLn("     Periapsis: " + round(periapsis/1e3, 1) + "km", 5).
		printLn(" Pitch tgt/act: " + round(90 - targetZenith, 1) + " / " + round(90 - facingZenith, 1) + "deg", 6).
		printLn("Throttle/Stage: " + round(wantedThrottle * 100, 0) + "% / " + stage:number, 7).
		printLn("  TWR max/vert: " + round(availableTwr, 2) + " / " + round(verticalTwr, 2), 8).
		printLn("         Q/max: " + round(currQ, 2) + " / " + round(maxQ, 2) + "kPa", 9).
	}

	local function logAscent {
		parameter phase, apTarget, etaTarget, wantedThrottle,
			steeringVector, currQ, maxQ.

		local availableTwr is twr:available().
		local currentTwr is twr:current().
		local targetZenith is vang(up:vector, steeringVector).
		local facingZenith is vang(up:vector, facing:vector).
		local verticalTwr is twr:vCurrent().

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
			"m; pitch=" + round(90 - targetZenith, 1) +
			"/" + round(90 - facingZenith, 1) +
			"deg; error=" +
			round(vang(steeringVector, facing:vector), 1) +
			"deg; throttle=" +
			round(wantedThrottle * 100, 1) +
			"%; twr=" + round(availableTwr, 2) +
			"; currentTwr=" + round(currentTwr, 2) +
			"; verticalTwr=" + round(verticalTwr, 2) +
			"; q=" + round(currQ, 2) +
			"/" + round(maxQ, 2) +
			"kPa; stage=" + stage:number
		).
	}

	local function executeAscent {
		parameter apTarget, incTarget is 0, firstPitch is 80, minVerticalSpeed is 50, throttleControlSpeed is 250.

		local launchDirection is 90 - incTarget.
		local pitchTarget is 90.
		lock steering to heading(launchDirection, pitchTarget).

		local wantedThrottle is 1.
		local lock pitchDeflection to min(
			MAXIMUM_DEFLECTION_ANGLE,
			max(
				0,
				(verticalSpeed - VERTICAL_SPEED_DEFLECTION_THRESHOLD) * DEFLECTION_ANGLE_SPEED_MULTIPLIER
			)
		).
		lock throttle to wantedThrottle.

		local lock vPrograde to
			choose srfPrograde
			if altitude < ASCENT_VECTOR_BORDER
			else prograde.

		local lock pitchHeading to 90 - vang(up:vector, vPrograde:vector).
		local lock vSteer to heading(launchDirection, pitchHeading - pitchDeflection).

		local nextLogAltitude is (floor(altitude / ASCENT_LOG_ALTITUDE_STEP) + 1) * ASCENT_LOG_ALTITUDE_STEP.
		local lock etaTarget to max(15, min(75, 15 + altitude / 1e3)).
		local lock currQ to ship:q * constant:ATMtokPa.
		local maxQ is 0.

		clearScreen.
		wait 1.
		stage.
		printLn("Ignition").
		wait until stage:ready.
		printLn("Liftoff!").
		until verticalSpeed >= minVerticalSpeed {
			set maxQ to max(maxQ, currQ).

			if altitude >= nextLogAltitude {
				logAscent(
					"ascent",
					apTarget,
					etaTarget,
					wantedThrottle,
					vSteer:vector,
					currQ,
					maxQ
				).
				set nextLogAltitude to (floor(altitude / ASCENT_LOG_ALTITUDE_STEP) + 1) * ASCENT_LOG_ALTITUDE_STEP.
			}

			autostage().
			wait 0.
		}

		printLn("Pitching to " + firstPitch + "°").
		set pitchTarget to firstPitch.

		printLn("Performing gravity turn").
		until vang(up:vector, srfPrograde:vector) > 90 - firstPitch {
			set maxQ to max(maxQ, currQ).

			if altitude >= nextLogAltitude {
				logAscent(
					"ascent",
					apTarget,
					etaTarget,
					wantedThrottle,
					vSteer:vector,
					currQ,
					maxQ
				).
				set nextLogAltitude to (floor(altitude / ASCENT_LOG_ALTITUDE_STEP) + 1) * ASCENT_LOG_ALTITUDE_STEP.
			}

			autostage().
			wait 0.
		}

		printLn("Following surface prograde").
		lock steering to vSteer.

		local pidThrottle is pidLoop(0.05, 0.0005, 0.01, 0.1, 1, ETA_PID_EPSILON).

		logAscent(
			"following prograde",
			apTarget,
			etaTarget,
			wantedThrottle,
			vSteer:vector,
			currQ,
			maxQ
		).

		local throttleControlEnabled is false.
		until apoapsis >= apTarget {
			if not throttleControlEnabled and verticalSpeed >= throttleControlSpeed {
				set throttleControlEnabled to true.
			}
			set maxQ to max(maxQ, currQ).

			displayAscent(
				apTarget,
				etaTarget,
				wantedThrottle,
				vSteer:vector,
				currQ,
				maxQ
			).

			if altitude >= nextLogAltitude {
				logAscent(
					"ascent",
					apTarget,
					etaTarget,
					wantedThrottle,
					vSteer:vector,
					currQ,
					maxQ
				).
				set nextLogAltitude to (floor(altitude / ASCENT_LOG_ALTITUDE_STEP) + 1) * ASCENT_LOG_ALTITUDE_STEP.
			}

			set pidThrottle:setpoint to etaTarget.

			local availableVerticalTwr is twr:vAvailable().
			local minThrottle is 0.
			if altitude < ASCENT_VECTOR_BORDER
			or groundSpeed < 2 * verticalSpeed {
				set minThrottle to
					choose min(1, MIN_VERTICAL_TWR / availableVerticalTwr)
					if availableVerticalTwr > 0
					else 1.
			}

			set wantedThrottle to 
				choose max(minThrottle, pidThrottle:update(time:seconds, eta:apoapsis))
				if throttleControlEnabled
				else 1.

			if autostage() {
				logAscent(
					"staged",
					apTarget,
					etaTarget,
					wantedThrottle,
					vSteer:vector,
					currQ,
					maxQ
				).
			}

			wait 0.
		}

		logAscent(
			"apoapsis target",
			apTarget,
			etaTarget,
			wantedThrottle,
			vSteer:vector,
			currQ,
			maxQ
		).

		clearScreen.
		printLn("Maintaining apoapsis").
		local pidApHold is pidLoop(0.0001, 0.00001, 0, 0, 1, AP_PID_EPSILON).
		set pidApHold:setpoint to apTarget.
		until altitude >= body:atm:height {
			if altitude >= nextLogAltitude {
				logAscent(
					"ascent",
					apTarget,
					etaTarget,
					wantedThrottle,
					vSteer:vector,
					currQ,
					maxQ
				).
				set nextLogAltitude to (floor(altitude / ASCENT_LOG_ALTITUDE_STEP) + 1) * ASCENT_LOG_ALTITUDE_STEP.
			}

			set wantedThrottle to pidApHold:update(time:seconds, apoapsis).
			autostage().
			wait 0.
		}

		lock throttle to 0.
	}

	function ascentHandoff {
		clearScreen.
		printLn("Coasting towards apoapsis").
		lock throttle to 0.
		lock steering to prograde.
		wait 0.1.
	}

	function orbitalInsertion {
		parameter apTarget,
			apMaxError is 10_000,
			etaTarget is 60,
			etaMin is 30,
			peTarget is 35_000.

		local lock handoffCondition to periapsis > peTarget or eta:apoapsis < etaMin or eta:periapsis < eta:apoapsis or apoapsis > (apTarget + apMaxError).
		if handoffCondition {
			ascentHandoff().
			return.
		}

		clearScreen.
		printLn("Orbital Insertion").

		//pidloop(Kp, Ki, Kd, min, max, epsilon)
		local pidThrottle is pidLoop(0.1, 0.001, 0.001, 0, 1, ETA_PID_EPSILON).
		local pidPitch is pidLoop(0.01, 0.001, 0.001, -PITCH_AOA_LIMIT, PITCH_AOA_LIMIT, AP_PID_EPSILON).

		local pitch is 0.
		local lock vPrograde to velocity:orbit:normalized.
		local lock vRadial to body:position:normalized.
		local lock radialPerp to vxcl(vPrograde, vRadial):normalized.
		local lock vSteer to vPrograde * cos(pitch) - radialPerp * sin(pitch).
		lock steering to vSteer.

		printLn("Orbital Insertion - awaiting atmospheric border: " + body:atm:height).
		wait until altitude > body:atm:height + 50.
		kuniverse:timewarp:cancelwarp().
		wait until kuniverse:timewarp:issettled().

		printLn("Orbital Insertion - awaiting eta:apoapsis < " + etaTarget).
		wait until eta:apoapsis <= etaTarget or eta:periapsis < eta:apoapsis.
		kuniverse:timewarp:cancelwarp().
		wait until kuniverse:timewarp:issettled().

		printLn("Orbital Insertion - raising Pe").
		local dThrottle is 0.1.
		lock throttle to dThrottle.
		set pidThrottle:setpoint to etaTarget.
		set pidPitch:setpoint to apTarget.
		until handoffCondition {
			printLn("Apoapsis:       " + round(apoapsis/1e3, 1) + "km / " + round(apTarget/1e3, 1) + "km", 1).
			printLn("Apoapsis Error: " + round((apoapsis - apTarget)/1e3, 1) + "km / " + round(apMaxError/1e3, 1) + "km", 2).
			printLn("Apoapsis ETA:   " + round(eta:apoapsis, 1) + "s / " + round(etaTarget, 1) + "s", 3).
			printLn("Periapsis:      " + round(periapsis/1e3, 1) + "km / " + round(peTarget/1e3, 1) + "km", 4).
			printLn("Pitch Angle:    " + round(pitch, 2) + "°", 5).

			set dThrottle to pidThrottle:update(time:seconds, eta:apoapsis).
			set pitch to pidPitch:update(time:seconds, apoapsis).
			autostage().
			wait 0.
		}

		ascentHandoff().
	}

	export(lex(
		"executeAscent", executeAscent@,
		"orbitalInsertion", orbitalInsertion@
	)).
}