// #include "printLn-v1.ks"
// #include "staging-v1.ks"
// #include "steering-v1.ks"

global function logAscentHeaders {
	if homeConnection:isconnected {
		deletePath("0:/ascent.csv").
		log "time,stage,stage_solid_fuel,stage_liquid_fuel,altitude,vertical_speed,ground_speed,air_speed,orbital_velocity,apoapsis,periapsis,apoapsis_eta,q_kpa,mass,max_thrust,available_thrust,max_twr,available_twr,throttle,target_pitch,trajectory_pitch,aoa" to "0:/ascent.csv".
		set last_ascent_log_time to time:seconds.
	}
}
global last_ascent_log_time is 0.
global ascent_log_frequency is 0.2.
global function logAscent {
	parameter targetPitch is "none".
	local now is time:seconds.
	if now > (last_ascent_log_time + ascent_log_frequency) and homeConnection:isconnected {
		local trajectoryPitch is 90 - vang(UP:vector, srfPrograde:vector).
		if targetPitch = "none" set targetPitch to trajectoryPitch.
		local line is list(
			now,
			stage:number,
			stage:resourceslex["SolidFuel"]:amount,
			stage:resourceslex["LiquidFuel"]:amount,
			altitude,
			verticalSpeed,
			ship:groundSpeed,
			ship:airSpeed,
			velocity:orbit:mag,
			apoapsis,
			periapsis,
			eta:apoapsis,
			ship:q * constant:ATMtokPa,
			mass,
			maxThrust,
			availableThrust,
			ship:maxThrust * (body:radius + altitude)^2 / (ship:mass * body:mu),
			ship:availableThrust * (body:radius + altitude)^2 / (ship:mass * body:mu),
			throttle,
			targetPitch,
			trajectoryPitch,
			vang(srfPrograde:vector, ship:facing:forevector)
		).
		set last_ascent_log_time to last_ascent_log_time + ascent_log_frequency.
		log line:join(",") to "0:/ascent.csv".
	}
}

global function executeAscent {
	parameter apTarget, ascProfile is list(), incTarget is 0, twrMax is 1.8, pitchDeviationMax is 5, apTaper is 3000.

	local launchDirection is 90 - incTarget.
	local pitchTarget is 90.

	local lock pitchCurrent to 90 - vang(UP:vector, srfPrograde:vector).

	local lock pitchClamp to max(
		pitchCurrent - pitchDeviationMax,
		min(pitchCurrent + pitchDeviationMax, pitchTarget)
	).
	lock steering to heading(launchDirection, pitchClamp).

	local lock TWR to ship:maxThrust * (body:radius + altitude)^2 / (ship:mass * body:mu).
	local lock throttleTWRLimit to min(1, twrMax / max(1e-6, TWR)).

	local lock throttleApLimit to min(1, ((apTarget - apoapsis) / apTaper)^2).
	lock throttle to max(0.1, throttleTWRLimit * throttleApLimit).

	local ascentStep is 0.
	local ascentStepAltitude is ascProfile[0].
	wait 1.
	logAscentHeaders().
	stage.

	clearScreen.
	print ("Launch to " + round(apTarget/1e3,0) + "km " + incTarget + " inclination"):padright(terminal:width) AT (0,0).
	until apoapsis > apTarget {
		logAscent(pitchClamp).
		print ("Alt:      " + round(altitude, 0)):padright(terminal:width) AT (0,1).
		print ("Ap:       " + round(apoapsis, 0)):padright(terminal:width) AT (0,2).
		print ("Pitch:    " + round(pitchCurrent, 1) + " / " + round(pitchTarget, 1) + " (" + round(pitchClamp, 1) + ")"):padright(terminal:width) AT (0, 3).
		print ("TWR:      " + round(TWR(), 2)):padright(terminal:width) AT (0,4).
		print ("Throttle: " + round(throttle, 2)):padright(terminal:width) AT (0,5).
		print ("Profile:  " + ascentStep + "=" + ascentStepAltitude + "," + pitchTarget):padright(terminal:width) AT (0,6).

		if max(apoapsis-10e3, altitude) > ascentStepAltitude {
			set pitchTarget to ascProfile[ascentStep + 1].
			if (ascentStep + 2) < ascProfile:length {
				set ascentStep to ascentStep + 2.
				set ascentStepAltitude to ascProfile[ascentStep].
			}
		}
		autostage().
		wait 0.
	}

	clearScreen.
	print "Launch to " + round(apTarget/1e3,0) + "km " + incTarget + " inclination".
	print "Coasting to space".
	lock throttle to 0.
	wait 0.1.
	wait until altitude > 70e3.
}

local ASCENT_VECTOR_BORDER is 35e3.
local ETA_PID_EPSILON is 1.
local PITCH_AOA_LIMIT is 20.
local AP_PID_EPSILON is 100.
global function executeAscentPid {
	parameter apTarget, incTarget is 0, firstPitch is 80, minVerticalSpeed is 50.

	local launchDirection is 90 - incTarget.
	local pitchTarget is 90.
	
	lock steering to heading(launchDirection, pitchTarget).
	lock throttle to 1.

	clearScreen.
	wait 1.
	logAscentHeaders().
	stage.
	printLn("Ignition").
	wait until stage:ready.
	printLn("Liftoff!").
	until velocity:surface:mag >= minVerticalSpeed {
		logAscent(pitchTarget).
		wait 0.
	}

	printLn("Pitching to " + firstPitch + "°").
	set pitchTarget to firstPitch.
	awaitSteering().

	printLn("Performing gravity turn").
	until vang(srfPrograde:vector, facing:vector) < 0.3 {
		logAscent(pitchTarget).
		wait 0.
	}

	printLn("Following surface prograde").
	lock steering to srfPrograde.
	local lock pitchCurrent to 90 - vang(UP:vector, srfPrograde:vector).

	local pidThrottle is pidLoop(0.05, 0.0005, 0.01, 0.1, 1, ETA_PID_EPSILON).
	set pidThrottle:setpoint to 75.
	local wantedThrottle is 1.
	lock throttle to wantedThrottle.

	when altitude > ASCENT_VECTOR_BORDER then {
		printLn("Following orbit prograde").
		lock steering to prograde.
	}

	until apoapsis >= apTarget {
		logAscent().
		printLn("    Altitude: " + round(altitude/1e3,1) + "km", 1).
		printLn("    Apoapsis: " + round(apoapsis/1e3,1) + "km / " + round(apTarget/1e3,1) + "km", 2).
		printLn("Apoapsis ETA: " + round(eta:apoapsis,1) + "s / " + round(pidThrottle:setpoint,1) + "s", 3).
		printLn("   Periapsis: " + round(periapsis/1e3,1) + "km", 4).
		printLn("    Throttle: " + round(wantedThrottle*100,2) + "%", 5).
		printLn("       Pitch: " + round(pitchCurrent,1) + "°", 6).
		printLn("Throttle PID: P=" + round(pidThrottle:pterm, 3) + " I=" + round(pidThrottle:iterm, 3) + " D=" + round(pidThrottle:dterm, 3) + " O=" + round(pidThrottle:output, 3), 7).

		set wantedThrottle to pidThrottle:update(time:seconds, eta:apoapsis).
		autostage().
		wait 0.
	}
	
	printLn("Coasting to space").
	lock throttle to 0.
	wait 0.1.
	wait until altitude > 70e3.
}

local ASCENT_TWR_MAX is 2.
local ASCENT_TWR_MIN is 1.4.
local ASCENT_Q_MAX is 30.
local ASCENT_Q_MIN is 20.
global function executeAscentPidV2 {
	parameter apTarget, incTarget is 0, firstPitch is 80, minVerticalSpeed is 50.

	local launchDirection is 90 - incTarget.
	local pitchTarget is 90.
	
	lock steering to heading(launchDirection, pitchTarget).
	lock throttle to 1.

	clearScreen.
	wait 1.
	logAscentHeaders().
	stage.
	printLn("Ignition").
	wait until stage:ready.
	printLn("Liftoff!").
	until velocity:surface:mag >= minVerticalSpeed {
		logAscent(pitchTarget).
		wait 0.
	}

	printLn("Pitching to " + firstPitch + "°").
	set pitchTarget to firstPitch.
	awaitSteering().

	printLn("Performing gravity turn").
	until vang(srfPrograde:vector, facing:vector) < 0.3 {
		logAscent(pitchTarget).
		wait 0.
	}

	printLn("Following surface prograde").
	lock steering to srfPrograde.
	local lock pitchCurrent to 90 - vang(UP:vector, srfPrograde:vector).

	local lock twrMax to availableThrust * (body:radius + altitude)^2 / (mass * body:mu).
	local lock qFraction to 1 - min(1, max(0, ((ship:q * constant:ATMtokPa) - ASCENT_Q_MIN) / (ASCENT_Q_MAX - ASCENT_Q_MIN))).
	local lock twrLimit to ASCENT_TWR_MIN + (ASCENT_TWR_MAX - ASCENT_TWR_MIN) * qFraction.
	local lock qThrottle to choose 1 if availableThrust = 0 else min(1, max(0, twrLimit / twrMax)).
	local pidThrottle is pidLoop(0.05, 0.0005, 0.01, 0.1, 1, ETA_PID_EPSILON).
	set pidThrottle:setpoint to 75.
	local wantedThrottle is 1.
	lock throttle to min(wantedThrottle, qThrottle).

	when altitude > ASCENT_VECTOR_BORDER then {
		printLn("Following orbit prograde").
		lock steering to prograde.
	}

	local maxQ is ship:q * constant:ATMtokPa.
	until apoapsis >= apTarget {
		local currQ is ship:q * constant:ATMtokPa.
		set maxQ to max(maxQ, currQ).
		logAscent().
		printLn("    Altitude: " + round(altitude/1e3,1) + "km", 1).
		printLn("    Apoapsis: " + round(apoapsis/1e3,1) + "km / " + round(apTarget/1e3,1) + "km", 2).
		printLn("Apoapsis ETA: " + round(eta:apoapsis,1) + "s / " + round(pidThrottle:setpoint,1) + "s", 3).
		printLn("   Periapsis: " + round(periapsis/1e3,1) + "km", 4).
		printLn("       Pitch: " + round(pitchCurrent,1) + "°", 5).
		printLn("           Q: " + round(currQ,2) + "kPA", 6).
		printLn("      Q{max}: " + round(maxQ,2) + "kPA", 7).
		printLn("    TWR{max}: " + round(twrMax,2), 8).
		printLn("    TWR{lim}: " + round(twrLimit,2), 9).
		printLn("    Throt{q}: " + round(qThrottle*100,2) + "%", 10).
		printLn("  Throt{pid}: " + round(wantedThrottle*100,2) + "%", 11).
		printLn("Throttle PID: P=" + round(pidThrottle:pterm, 3) + " I=" + round(pidThrottle:iterm, 3) + " D=" + round(pidThrottle:dterm, 3) + " O=" + round(pidThrottle:output, 3), 12).

		set wantedThrottle to pidThrottle:update(time:seconds, eta:apoapsis).
		autostage().
		wait 0.
	}
	
	printLn("Coasting to space").
	lock throttle to 0.
	wait 0.1.
	wait until altitude > 70e3.
}

global function orbitalInsertion {
	parameter apTarget,
		apMaxError is 10_000,
		etaTarget is 60,
		etaMin is 30,
		peTarget is 35_000.

	clearScreen.
	print "Orbital Insertion" AT (0, 0).

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
	wait until eta:apoapsis <= etaTarget or eta:periapsis < eta:apoapsis.

	clearVecDraws().
	local vecPrograde is vecDraw(V(0,0,0), { return vPrograde * 20. }, RED, "prograde", 1, true).
	local vecSteering is vecDraw(V(0,0,0), { return vSteer * 20. }, GREEN, "steering", 1, true).

	local dThrottle is 0.1.
	lock throttle to dThrottle.
	set pidThrottle:setpoint to etaTarget.
	set pidPitch:setpoint to apTarget.
	until periapsis > peTarget or eta:apoapsis < etaMin or eta:periapsis < eta:apoapsis or availableThrust = 0 or apoapsis > (apTarget + apMaxError) {
		print ("Apoapsis:       " + round(apoapsis/1e3, 1) + "km / " + round(apTarget/1e3, 1) + "km"):padright(terminal:width) AT (0, 1).
		print ("Apoapsis Error: " + round((apoapsis - apTarget)/1e3, 1) + "km / " + round(apMaxError/1e3, 1) + "km"):padright(terminal:width) AT (0, 2).
		print ("Apoapsis ETA:   " + round(eta:apoapsis, 1) + "s / " + round(etaTarget, 1) + "s"):padright(terminal:width) AT (0, 3).
		print ("Periapsis:      " + round(periapsis/1e3, 1) + "km / " + round(peTarget/1e3, 1) + "km"):padright(terminal:width) AT (0, 4).
		print ("Pitch Angle:    " + round(pitch, 2) + "°"):padright(terminal:width) AT (0, 5).
		print ("Pitch PID:      P=" + round(pidPitch:pterm, 3) + " I=" + round(pidPitch:iterm, 3) + " D=" + round(pidPitch:dterm, 3) + " O=" + round(pidPitch:output, 3)):padright(terminal:width) AT (0, 6).
		print ("Throttle PID:   P=" + round(pidThrottle:pterm, 3) + " I=" + round(pidThrottle:iterm, 3) + " D=" + round(pidThrottle:dterm, 3) + " O=" + round(pidThrottle:output, 3)):padright(terminal:width) AT (0, 7).

		set dThrottle to pidThrottle:update(time:second, eta:apoapsis).
		set pitch to pidPitch:update(time:second, apoapsis).
		wait 0.
	}

	clearVecDraws().

	lock throttle to 0.
	lock steering to prograde.
	awaitSteering().
	wait 0.1.
}