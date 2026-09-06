{
	local autostage is import("sys/staging-v1"):autostage.
	local awaitSteering is import("sys/steering-v1"):awaitSteering.
	export({
		parameter ascentHeading,targetApoapsis.
		local madeSurfaceContact is false.
		local insufficientDeltaV is false.
		local vesselBounds is ship:bounds.
		local targetPitch is 0.
		local etaPid is pidLoop(3,0,0.1,0,90,1).
		sas off.
		lock steering to up:vector.
		lock throttle to 1.
		until(vesselBounds:bottomAltRadar>=10 and eta:apoapsis>=15)or insufficientDeltaV{
			if stage:number=0 and availableThrust=0 set insufficientDeltaV to true.
			autostage().
			wait 0.
		}
		if not insufficientDeltaV{
			gear off.
			local lock etaControl to choose eta:apoapsis if eta:apoapsis<eta:periapsis else eta:apoapsis-obt:period.
			lock steering to heading(ascentHeading,targetPitch).
			set etaPid:setpoint to 30.
			until(apoapsis>=targetApoapsis and etaControl>=10)or madeSurfaceContact or insufficientDeltaV{
				if status="LANDED"or status="SPLASHED"set madeSurfaceContact to true.
				if stage:number=0 and availableThrust=0 set insufficientDeltaV to true.
				set targetPitch to etaPid:update(time:seconds,etaControl).
				autostage().
				wait 0.
			}
			unlock etaControl.
		}
		lock throttle to 0.
		if madeSurfaceContact{
			unlock steering.
			wait until not steeringManager:enabled and groundSpeed<1 and abs(verticalSpeed)<1.
			wait 1.
			sas on.
			dmsg("Crashed back into the surface",true).
			return"CRASHED".
		}
		else if insufficientDeltaV{
			unlock steering.
			dmsg("We ran out of fuel",true).
			return"NO_FUEL".
		}
		else{
			lock steering to prograde.
			awaitSteering().
			dmsg("Ready to circularize at Apoapsis",true).
			return status.
		}
	}).
}