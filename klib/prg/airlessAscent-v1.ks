{
	local autostage is import("sys/staging-v1"):autostage.
	local awaitSteering is import("sys/steering-v1"):awaitSteering.

	local ETA_KP is 3.
	local ETA_KI is 0.
	local ETA_KD is 0.1.
	local ETA_MIN_PITCH is 0.
	local ETA_MAX_PITCH is 90.
	local ETA_EPSILON is 1.
	local MINIMUM_VERTICAL_CLIMB is 10.
	local VERTICAL_CLIMB_ETA_TARGET is 15.
	local LAUNCH_AP_ETA_TARGET is 30.
	local MINIMUM_AP_LEAD_TIME is 10.

	function surfaceContact {
		return status = "LANDED" or status = "SPLASHED".
	}

	function airlessAscent {
		parameter ascentHeading, targetApoapsis.

		local madeSurfaceContact is false.
		local insufficientDeltaV is false.
		local vesselBounds is ship:bounds.

		// Vertical Launch
		sas off.
		lock steering to up:vector.
		lock throttle to 1.
		until (
			vesselBounds:bottomAltRadar >= MINIMUM_VERTICAL_CLIMB
			and eta:apoapsis >= VERTICAL_CLIMB_ETA_TARGET
		) or insufficientDeltaV {
			if stage:number = 0 and availableThrust = 0 set insufficientDeltaV to true.

			autostage().

			wait 0.
		}

		if not insufficientDeltaV {
			gear off.

			// we use etaControl instead of eta:apoapsis directly, so that if we pass apoapsis we get a negative error, instead of a huge positive error
			local lock etaControl to
				choose eta:apoapsis
				if eta:apoapsis < eta:periapsis
				else eta:apoapsis - obt:period.

			// Horizontal Burn to raise Apoapsis
			local targetPitch is 0.
			lock steering to heading(ascentHeading, targetPitch).
			local etaPid is pidLoop(ETA_KP, ETA_KI, ETA_KD, ETA_MIN_PITCH, ETA_MAX_PITCH, ETA_EPSILON).
			set etaPid:setpoint to LAUNCH_AP_ETA_TARGET.

			// We could have used max(altitudeSafety,targetApoapsis), but that is down to the caller,
			// as the targetApoapsis may intentionally be below safe terrain altitude if it's know the trajectory has a lower limit
			until (apoapsis >= targetApoapsis and etaControl >= MINIMUM_AP_LEAD_TIME) or madeSurfaceContact or insufficientDeltaV {
				if surfaceContact() set madeSurfaceContact to true.
				if stage:number = 0 and availableThrust = 0 set insufficientDeltaV to true.
				set targetPitch to etaPid:update(time:seconds, etaControl).

				autostage(). // we don't need to adjust vesselBounds after the vertical take-off phase

				wait 0.
			}
			unlock etaControl.
		}
		lock throttle to 0.

		if madeSurfaceContact {
			unlock steering.
			wait until not steeringManager:enabled and groundSpeed < 1 and abs(verticalSpeed) < 1.
			wait 1.
			sas on.
			dmsg("Crashed back into the surface", true).
			return "CRASHED".
		}
		else if insufficientDeltaV {
			unlock steering.
			dmsg("We ran out of fuel", true).
			return "NO_FUEL".
		}
		else {
			lock steering to prograde.
			awaitSteering().
			dmsg("Ready to circularize at Apoapsis", true).
			return status. // this will be ORBITING or SUB_ORBITAL
		}
	}

	export(airlessAscent@).
}