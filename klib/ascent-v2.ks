// #include "kldr-stub.ks"
{
	local printLn is import("printLn-v1"):printLn.
	local autostage is import("staging-v1"):autostage.
	local awaitSteering is import("steering-v1"):awaitSteering.
	
	local ASCENT_VECTOR_BORDER is 35e3.
	local ETA_PID_EPSILON is 1.
	local PITCH_AOA_LIMIT is 20.
	local AP_PID_EPSILON is 100.

	local function executeAscent {
		parameter apTarget, incTarget is 0, firstPitch is 80, minVerticalSpeed is 50.

		local launchDirection is 90 - incTarget.
		local pitchTarget is 90.
		lock steering to heading(launchDirection, pitchTarget).

		local wantedThrottle is 1.
		lock throttle to wantedThrottle.

		clearScreen.
		wait 1.
		stage.
		printLn("Ignition").
		wait until stage:ready.
		printLn("Liftoff!").
		wait until verticalSpeed >= minVerticalSpeed.

		printLn("Pitching to " + firstPitch + "°").
		set pitchTarget to firstPitch.
		awaitSteering().

		printLn("Performing gravity turn").
		wait until vang(srfPrograde:vector, facing:vector) < 0.3.

		printLn("Following surface prograde").
		when altitude > ASCENT_VECTOR_BORDER then printLn("Following orbit prograde").
		local lock vPrograde to choose prograde if altitude > ASCENT_VECTOR_BORDER else srfPrograde.
		local lock pitchCurrent to 90 - vang(UP:vector, vPrograde:vector).
		lock steering to vPrograde.

		local pidThrottle is pidLoop(0.05, 0.0005, 0.01, 0.1, 1, ETA_PID_EPSILON).
		set pidThrottle:setpoint to 75.

		local lock currQ to ship:q * constant:ATMtokPa.
		local maxQ is ship:q * constant:ATMtokPa.

		until apoapsis >= apTarget {
			set maxQ to max(maxQ, currQ).
			printLn("    Altitude: " + round(altitude/1e3,1) + "km", 1).
			printLn("    Apoapsis: " + round(apoapsis/1e3,1) + "km / " + round(apTarget/1e3,1) + "km", 2).
			printLn("Apoapsis ETA: " + round(eta:apoapsis,1) + "s / " + round(pidThrottle:setpoint,1) + "s", 3).
			printLn(" Speed{vert}: " + round(verticalSpeed,0) + "m/s", 4).
			printLn(" Speed{horz}: " + round(ship:groundSpeed,0) + "m/s", 5).
			printLn("   Periapsis: " + round(periapsis/1e3,1) + "km", 6).
			printLn("       Pitch: " + round(pitchCurrent,1) + "°", 7).
			printLn("           Q: " + round(currQ,2) + "kPA", 8).
			printLn("      Q{max}: " + round(maxQ,2) + "kPA", 9).

			set wantedThrottle to choose 1 if altitude > 60e3 else pidThrottle:update(time:seconds, eta:apoapsis).
			autostage().
			wait 0.
		}
		
		clearScreen.
		printLn("Coasting to space").
		lock throttle to 0.
		wait 0.1.
		wait until altitude > 70e3.
	}

	function orbitalInsertion {
		parameter apTarget,
			apMaxError is 10_000,
			etaTarget is 60,
			etaMin is 30,
			peTarget is 35_000.

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
		awaitSteering().
		printLn("Orbital Insertion - awaiting eta:apoapsis < " + etaTarget).
		wait until eta:apoapsis <= etaTarget or eta:periapsis < eta:apoapsis.
		printLn("Orbital Insertion - raising Pe").

		local dThrottle is 0.1.
		lock throttle to dThrottle.
		set pidThrottle:setpoint to etaTarget.
		set pidPitch:setpoint to apTarget.
		until periapsis > peTarget or eta:apoapsis < etaMin or eta:periapsis < eta:apoapsis or apoapsis > (apTarget + apMaxError) {
			printLn("Apoapsis:       " + round(apoapsis/1e3, 1) + "km / " + round(apTarget/1e3, 1) + "km", 1).
			printLn("Apoapsis Error: " + round((apoapsis - apTarget)/1e3, 1) + "km / " + round(apMaxError/1e3, 1) + "km", 2).
			printLn("Apoapsis ETA:   " + round(eta:apoapsis, 1) + "s / " + round(etaTarget, 1) + "s", 3).
			printLn("Periapsis:      " + round(periapsis/1e3, 1) + "km / " + round(peTarget/1e3, 1) + "km", 4).
			printLn("Pitch Angle:    " + round(pitch, 2) + "°", 5).

			set dThrottle to pidThrottle:update(time:second, eta:apoapsis).
			set pitch to pidPitch:update(time:second, apoapsis).
			autostage().
			wait 0.
		}

		clearScreen.
		printLn("Coasting towards apoapsis").
		lock throttle to 0.
		lock steering to prograde.
		awaitSteering().
		wait 0.1.
	}

	export(lex(
		"executeAscent", executeAscent@,
		"orbitalInsertion", orbitalInsertion@
	)).
}