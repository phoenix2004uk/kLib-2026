print "v1.1".
wait until ship:unpacked.
core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
sas off.

function VisViva {
	parameter
		altQuery is altitude,
		r1 is periapsis,
		r2 is apoapsis,
		whichBody is body.

	local rQuery is altQuery + whichBody:radius.
	local smaQuery is (r1 + r2) / 2 + whichBody:radius.

	return sqrt( whichBody:mu * ( 2/rQuery - 1/smaQuery ) ).
}
function getOrbitPeriod {
	parameter Ap, Pe.
	local sma is (Ap + Pe) / 2 + body:radius.
	return 2 * constant:pi * sqrt(sma^3 / body:mu).
}
function getTransferTime {
	parameter targetOrbitable, targetSeparation is 0.

	local tagetAngularSpeed is 360 / targetOrbitable:obt:period.
	local shipAngularSpeed is 360 / ship:obt:period.
	local periodOfTransfer is getOrbitPeriod(targetOrbitable:obt:apoapsis, ship:obt:apoapsis) / 2.
	local targetAngularMovement is tagetAngularSpeed * periodOfTransfer.
	local relativeAngularSpeed is abs(shipAngularSpeed - tagetAngularSpeed).

	local targetAngularPosition is targetOrbitable:obt:lan + targetOrbitable:obt:argumentofperiapsis + targetOrbitable:obt:trueanomaly.
	local shipAngularPosition is ship:obt:lan + ship:obt:argumentofperiapsis + ship:obt:trueanomaly.
	local phaseAngle is mod(targetAngularPosition + 360 - shipAngularPosition, 360).
	local transferAngle is mod(180 - targetAngularMovement - targetSeparation, 360).

	if targetOrbitable:obt:apoapsis < ship:obt:apoapsis {
		set phaseAngle to phaseAngle - 360.
		if phaseAngle > transferAngle set phaseAngle to phaseAngle - 360.
	}
	if targetOrbitable:obt:apoapsis > ship:obt:apoapsis and phaseAngle < transferAngle
		set phaseAngle to phaseAngle + 360.

	local transfer_eta is mod(abs(phaseAngle - transferAngle), 360) / relativeAngularSpeed.

	return time:seconds + transfer_eta.
}
function TWR {
	return ship:maxThrust * (body:radius + altitude)^2 / (ship:mass * body:mu).
}
function isCurrentStageEngineActive {
	parameter en, at_stage.
	return at_stage = stage:number and en:ignition and not en:flameout.
}
function isEngineInStage {
	parameter en, at_stage.
	return at_stage < stage:number and en:stage = at_stage.
}
function engineStats {
	parameter at_stage is stage:number.
	local p is 0.
	local f is 0.
	local n is 0.
	for en in ship:engines {
		if isEngineInStage(en, at_stage) or isCurrentStageEngineActive(en, at_stage) {
			set f to f + en:possiblethrustat(ship:q).
			set p to p + en:ispat(ship:q).
			set n to n + 1.
		}
	}
	if n > 0 set p to p / n.
	return List(f, p).
}
function stageMass {
	parameter at_stage is stage:number.
	local total_mass is 0.
	for p in ship:parts if p:stage <= at_stage set total_mass to total_mass + p:mass.
	return total_mass.
}

function safestage {
	stage.
	wait until stage:ready.
}
function autostage {
	local flameout is 1.
	until not flameout {
		set flameout to 0.
		for en in ship:engines {
			if (en:flameout) {
				safestage().
				set flameout to 1.
				break.
			}
		}
	}
}
function stageUntil {
	parameter num.
	lock throttle to 0.
	until stage:number = 0 or stage:number <= num { safestage(). }
	wait 0.1.
}
function awaitSteering {
	wait 0.
	wait until vang(ship:facing:vector, steeringManager:target:vector) < 0.25.
}

function burnDuration {
	parameter dV, at_stage is stage:number.

	local m is stageMass(at_stage).
	local e is constant:e.
	local ens is engineStats(at_stage).
	local f is ens[0].
	local p is ens[1].
	local g is constant:g0.
	if f = 0 or p = 0 return 0.

	return g * m * p * (1 - e^(-abs(dV) / (g*p))) / f.
}
function executeNextNode {
	parameter args is lex().
	local MINUMUM_THRUST is 0.001.

	local conf is lex(
		"lead_time", 60,
		"precision", 1e-2,
		"auto_warp", 0
	).
	for k in args:keys set conf[k] to args[k].

	if not hasnode return.
	local mnv is nextnode.

	local halfBurnDuration is burnDuration(mnv:deltav:mag/2).
	local leadDuration is halfBurnDuration + conf:lead_time.
	//if conf:auto_warp safeWarpTo(time:seconds + mnv:eta - leadDuration).
	wait until mnv:eta <= leadDuration.

	lock steering to mnv:burnvector.
	awaitSteering().

	local dV0 is mnv:deltav.
	local lock max_acceleration to ship:availablethrust / ship:mass.
	local lock mnv_throttle to max(MINUMUM_THRUST, min(mnv:deltav:mag / max_acceleration, 1)).

	wait until mnv:eta <= halfBurnDuration.
	lock throttle to mnv_throttle.
	wait until vdot(dV0, mnv:deltav) < 0 or (mnv:deltav:mag < conf:precision and vdot(dV0, mnv:deltav) < 0.5).
	lock throttle to 0.
	unlock steering.
	wait 0.1.
}

function executeAscent {
	parameter altTarget, ascProfile is list(), incTarget is 0, twrMax is 1.8, pitchDeviationMax is 5, apTaper is 3000.

	local launchDirection is 90 - incTarget.
	local pitchTarget is 90.

	local lock pitchCurrent to 90 - vang(UP:vector, srfPrograde:vector).

	local lock pitchClamp to max(
		pitchCurrent - pitchDeviationMax,
		min(pitchCurrent + pitchDeviationMax, pitchTarget)
	).
	lock steering to heading(launchDirection, pitchClamp).

	local lock throttleTWRLimit to min(1, twrMax / max(1e-6, TWR())).
.
	local lock throttleApLimit to min(1, ((altTarget - apoapsis) / apTaper)^2).
	lock throttle to max(0.1, throttleTWRLimit * throttleApLimit).

	local ascentStep is 0.
	local ascentStepAltitude is ascProfile[0].
	wait 5.
	stage.

	clearScreen.
	print ("Launch to " + round(altTarget/1e3,0) + "km " + incTarget + " inclination"):padright(terminal:width) AT (0,0).
	until apoapsis > altTarget {
		print ("Alt:       " + round(altitude, 0)):padright(terminal:width) AT (0,1).
		print ("Ap:        " + round(apoapsis, 0)):padright(terminal:width) AT (0,2).
		print ("Pitch:     " + round(pitchCurrent, 1) + " / " + round(pitchTarget, 1) + " (" + round(pitchClamp, 1) + ")"):padright(terminal:width) AT (0, 3).
		print ("TWR:       " + round(TWR(), 2)):padright(terminal:width) AT (0,4).
		print ("Throttle : " + round(throttle, 2)):padright(terminal:width) AT (0,5).

		if (max(apoapsis-10e3, altitude) > ascentStepAltitude) and ((ascentStep + 2) < ascProfile:length) {
			set pitchTarget to ascProfile[ascentStep + 1].
			set ascentStep to ascentStep + 2.
			set ascentStepAltitude to ascProfile[ascentStep].
		}
		autostage().
		wait 0.1.
	}

	clearScreen.
	print "Launch to " + round(altTarget/1e3,0) + "km " + incTarget + " inclination".
	print "Coasting to space".
	lock throttle to 0.
	wait 0.1.
	wait until altitude > 70e3.

	if apoapsis < altTarget {
		lock steering to prograde.
		awaitSteering().
		lock throttle to 0.1.
		until apoapsis >= altTarget {
			autostage().
			wait 0.
		}
		lock throttle to 0.
		wait 0.1.
	} else if apoapsis > altTarget {
		lock steering to retrograde.
		awaitSteering().
		lock throttle to 0.1.
		until apoapsis <= altTarget {
			autostage().
			wait 0.
		}
		lock throttle to 0.
		wait 0.1.
	}
}

set APSIS_PERIAPSIS to 0.
set APSIS_APOAPSIS to 1.
function changeApsis {
	parameter whichApsis, altTarget, mnv_args is lex().
	local qApsis is choose periapsis if whichApsis = APSIS_APOAPSIS else apoapsis.
	local burnTime is time:seconds + (choose eta:periapsis if whichApsis = APSIS_APOAPSIS else eta:apoapsis).
	local v0 is VisViva(qApsis).
	local v1 is VisViva(qApsis, qApsis, altTarget).
	local dV is v1 - v0.
	local mnv is node(burnTime, 0, 0, dV).
	add mnv.
	executeNextNode(mnv_args).
	remove mnv.
}

set TWR_MAX to 1.8.
set PITCH_DEVIATION_MAX to 5.
set APOAPSIS_TAPER to 5000.
set targetInclination to 83.2.
set targetInclinationMax to 83.5.
set targetAltitude to 230000.
set maxEccentricity to 0.0021.
set ascentProfile to list(
	1e3, 85,
	2e3, 80,
	3e3, 75,
	4e3, 70,
	5e3, 65,
	6e3, 60,
	8e3, 55,
	10e3, 45,
	20e3, 40,
	30e3, 30,
	40e3, 20,
	50e3, 10,
	60e3, 0
).

if status = "PRELAUNCH" {
	executeAscent(targetAltitude, ascentProfile, targetInclination, TWR_MAX, PITCH_DEVIATION_MAX, APOAPSIS_TAPER).
	panels on.
	lights on.
	stageUntil(0).
}

if status = "SUB_ORBITAL" {
	print "Orbital insertion burn".
	changeApsis(APSIS_PERIAPSIS, apoapsis).
}

lock vslNormal to vcrs(body:position, ship:velocity:orbit).
if core:tag <> ship:name {
	print "Tuning orbit".
	if orbit:inclination < targetInclination {
		print "increasing inclination".
		lock steering to lookDirUp(-vslNormal, body:position).
		awaitSteering().
		wait until latitude > 5.
		wait until latitude < 5.
		lock throttle to 1.
		wait until orbit:inclination >= targetInclination.
		lock throttle to 0.
		wait 0.
	}

	if orbit:inclination > targetInclinationMax {
		print "decreasing inclination".
		lock steering to lookDirUp(vslNormal, body:position).
		awaitSteering().
		wait until latitude > 5.
		wait until latitude < 5.
		lock throttle to 1.
		wait until orbit:inclination <= targetInclinationMax.
		lock throttle to 0.
		wait 0.
	}

	if orbit:eccentricity > maxEccentricity {
		print "reducing eccentricity".
		lock steering to prograde.
		awaitSteering().

		until orbit:eccentricity < maxEccentricity {
			wait until eta:apoapsis < 10.
			lock throttle to 1.
			wait until eta:apoapsis > 10 or orbit:eccentricity < maxEccentricity.
			lock throttle to 0.
			wait 0.
		}
	}

	set core:tag to ship:name.
}

on abort {
	print "Preparing to de-orbit".
	lock throttle to 0.
	lock steering to retrograde.
	awaitSteering().
	lock throttle to 1.
}

print "Aligning panels & deploying radar".
toggle ag1.
lock throttle to 0.
lock steering to sun:position.
awaitSteering().
print "Program complete".
wait until 0.