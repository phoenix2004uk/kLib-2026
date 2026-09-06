{
	local printLn is import("util/printLn-v1"):printLn.
	local autostage is import("sys/staging-v1"):autostage.
	local twr is import("tlm/twr-v1").
	local createSmoothThrottle is import("sys/smoothThrottle-v1").
	function ascentEtaTarget{
		return max(15,min(75,15+altitude/1e3)).
	}
	function ascentSteeringDirection{
		parameter launchDirection.
		local guidancePrograde is choose srfPrograde if altitude<35e3 else prograde.
		local progradePitch is 90-vang(up:vector,guidancePrograde:vector).
		local pitchDeflection is min(10,max(0,(verticalSpeed-350)*0.1)).
		return heading(launchDirection,progradePitch-pitchDeflection).
	}
	function minimumAscentThrottle{
		if altitude>=35e3 and groundSpeed>=2*verticalSpeed return 0.
		local availableVerticalTwr is twr:vAvailable().
		if availableVerticalTwr<=0 return 1.
		return min(1,1.05/availableVerticalTwr).
	}
	function nextAscentLogAltitude{
		return(floor(altitude/100)+1)*100.
	}
	function reportAscent{
		parameter phase,apTarget,wantedThrottle,currentQ,maxQ,showDisplay,writeLog.
		local etaTarget is ascentEtaTarget().
		local availableTwr is twr:available().
		local currentTwrValue is twr:current().
		local steeringVector is steeringManager:target:vector.
		local facingZenith is vang(up:vector,facing:foreVector).
		local verticalTwr is currentTwrValue*cos(facingZenith).
		local targetPitch is 90-vang(up:vector,steeringVector).
		local facingPitch is 90-facingZenith.
		if showDisplay{
			printLn("Ascent",0).
			printLn("       Altitude: "+round(altitude/1e3,1)+"km",1).
			printLn("       Apoapsis: "+round(apoapsis/1e3,1)+"km / "+round(apTarget/1e3,1)+"km",2).
			printLn("   Apoapsis ETA: "+round(eta:apoapsis,1)+"s / "+round(etaTarget,1)+"s",3).
			printLn("      Speed V/H: "+round(verticalSpeed,0)+" / "+round(groundSpeed,0)+"m/s",4).
			printLn("      Periapsis: "+round(periapsis/1e3,1)+"km",5).
			printLn("  Pitch tgt/act: "+round(targetPitch,1)+" / "+round(facingPitch,1)+"deg",6).
			printLn("Target Throttle: "+round(wantedThrottle*100,0)+"% / Stage: "+stage:number,7).
			printLn("Actual Throttle: "+round(throttle*100,0)+"%",8).
			printLn("   TWR avl/vert: "+round(availableTwr,2)+" / "+round(verticalTwr,2),9).
			printLn("          Q/max: "+round(currentQ,2)+" / "+round(maxQ,2)+"kPa",10).
		}
		if writeLog dmsg("Ascent: "+phase+"; ut="+round(time:seconds,1)+"; altitude="+round(altitude,0)+"m; apoapsis="+round(apoapsis,0)+"/"+round(apTarget,0)+"m; eta="+round(eta:apoapsis,1)+"/"+round(etaTarget,1)+"s; vertical="+round(verticalSpeed,1)+"m/s; ground="+round(groundSpeed,1)+"m/s; periapsis="+round(periapsis,0)+"m; pitch="+round(targetPitch,1)+"/"+round(facingPitch,1)+"deg; error="+round(vang(steeringVector,facing:foreVector),1)+"deg; wantedThrottle="+round(wantedThrottle*100,1)+"%; throttle="+round(throttle*100,1)+"%; twr="+round(availableTwr,2)+"; currentTwr="+round(currentTwrValue,2)+"; verticalTwr="+round(verticalTwr,2)+"; q="+round(currentQ,2)+"/"+round(maxQ,2)+"kPa; stage="+stage:number).
	}
	function updateAscentTelemetry{
		parameter logState,apTarget,wantedThrottle,showDisplay is false.
		local currentQ is ship:q*constant:ATMtokPa.
		local altitudeLogDue is altitude>=logState:nextAltitude.
		set logState["maxQ"]to max(logState:maxQ,currentQ).
		if showDisplay or altitudeLogDue reportAscent("ascent",apTarget,wantedThrottle,currentQ,logState:maxQ,showDisplay,altitudeLogDue).
		if altitudeLogDue set logState["nextAltitude"]to nextAscentLogAltitude().
	}
	function logAscentEvent{
		parameter logState,phase,apTarget,wantedThrottle.
		reportAscent(phase,apTarget,wantedThrottle,ship:q*constant:ATMtokPa,logState:maxQ,false,true).
	}
	function insertionComplete{
		parameter apTarget,apMaxError,etaMin,peTarget.
		return periapsis>peTarget or eta:apoapsis<etaMin or eta:periapsis<eta:apoapsis or apoapsis>apTarget+apMaxError.
	}
	function performOrbitalInsertion{
		parameter apTarget,apMaxError,etaTarget,etaMin,peTarget.
		clearScreen.
		printLn("Orbital Insertion").
		local pidThrottle is pidLoop(0.1,1e-3,1e-3,0.01,1,1).
		local pidPitch is pidLoop(1e-2,1e-3,1e-3,-20,20,100).
		local pitchOffset is 0.
		local insertionThrottle is 0.1.
		local lock vPrograde to velocity:orbit:normalized.
		local lock vRadial to body:position:normalized.
		local lock radialPerp to vxcl(vPrograde,vRadial):normalized.
		local lock vSteer to vPrograde*cos(pitchOffset)-radialPerp*sin(pitchOffset).
		lock steering to vSteer.
		printLn("Orbital Insertion - awaiting atmospheric border: "+body:atm:height).
		wait until altitude>body:atm:height+50.
		kuniverse:timewarp:cancelwarp().
		wait until kuniverse:timewarp:issettled().
		printLn("Orbital Insertion - awaiting eta:apoapsis < "+etaTarget).
		wait until eta:apoapsis<=etaTarget or eta:periapsis<eta:apoapsis.
		kuniverse:timewarp:cancelwarp().
		wait until kuniverse:timewarp:issettled().
		printLn("Orbital Insertion - raising Pe").
		local smoothThrottle is createSmoothThrottle().
		smoothThrottle:setTarget(insertionThrottle).
		lock throttle to smoothThrottle:current().
		set pidThrottle:setpoint to etaTarget.
		set pidPitch:setpoint to apTarget.
		until insertionComplete(apTarget,apMaxError,etaMin,peTarget){
			printLn("Apoapsis:       "+round(apoapsis/1e3,1)+"km / "+round(apTarget/1e3,1)+"km",1).
			printLn("Apoapsis Error: "+round((apoapsis-apTarget)/1e3,1)+"km / "+round(apMaxError/1e3,1)+"km",2).
			printLn("Apoapsis ETA:   "+round(eta:apoapsis,1)+"s / "+round(etaTarget,1)+"s",3).
			printLn("Periapsis:      "+round(periapsis/1e3,1)+"km / "+round(peTarget/1e3,1)+"km",4).
			printLn("Pitch Angle:    "+round(pitchOffset,2)+"°",5).
			set insertionThrottle to pidThrottle:update(time:seconds,eta:apoapsis).
			smoothThrottle:setTarget(insertionThrottle).
			set pitchOffset to pidPitch:update(time:seconds,apoapsis).
			autostage().
			wait 0.
		}
		unlock vPrograde.
		unlock vRadial.
		unlock radialPerp.
		unlock vSteer.
	}
	function ascentHandoff{
		clearScreen.
		printLn("Coasting towards apoapsis").
		lock throttle to 0.
		lock steering to prograde.
		wait 0.1.
	}
	export(lex(
		"executeAscent",{
			parameter apTarget,incTarget is 0.
			local launchDirection is 90-incTarget.
			local logState is lex("maxQ",0,"nextAltitude",nextAscentLogAltitude()).
			lock steering to heading(launchDirection,90).
			lock throttle to 1.
			clearScreen.
			wait 1.
			stage.
			printLn("Ignition").
			wait until stage:ready.
			printLn("Liftoff!").
			until verticalSpeed>=50{
				updateAscentTelemetry(logState,apTarget,1).
				autostage().
				wait 0.
			}
			printLn("Pitching to "+80+"°").
			lock steering to heading(launchDirection,80).
			printLn("Performing gravity turn").
			until vang(up:vector,srfPrograde:vector)>90-80{
				updateAscentTelemetry(logState,apTarget,1).
				autostage().
				wait 0.
			}
			local smoothThrottle is createSmoothThrottle().
			printLn("Following surface prograde").
			lock steering to ascentSteeringDirection(launchDirection).
			local pidThrottle is pidLoop(5e-2,5e-4,1e-2,0.1,1,1).
			local wantedThrottle is 1.
			local throttleControlEnabled is false.
			lock throttle to smoothThrottle:current().
			logAscentEvent(logState,"following prograde",apTarget,wantedThrottle).
			until apoapsis>=apTarget{
				if not throttleControlEnabled and verticalSpeed>=250 set throttleControlEnabled to true.
				updateAscentTelemetry(logState,apTarget,wantedThrottle,true).
				set pidThrottle:setpoint to ascentEtaTarget().
				set wantedThrottle to choose max(minimumAscentThrottle(),pidThrottle:update(time:seconds,eta:apoapsis))if throttleControlEnabled else 1.
				smoothThrottle:setTarget(wantedThrottle).
				if autostage() logAscentEvent(logState,"staged",apTarget,wantedThrottle).
				wait 0.
			}
			logAscentEvent(logState,"apoapsis target",apTarget,wantedThrottle).
			clearScreen.
			printLn("Maintaining apoapsis").
			lock steering to ascentSteeringDirection(launchDirection).
			local pidApHold is pidLoop(1e-4,1e-5,0,0,1,100).
			set pidApHold:setpoint to apTarget.
			smoothThrottle:reset(0).
			set wantedThrottle to 0.
			lock throttle to smoothThrottle:current().
			until altitude>=body:atm:height{
				updateAscentTelemetry(logState,apTarget,wantedThrottle).
				set wantedThrottle to pidApHold:update(time:seconds,apoapsis).
				smoothThrottle:setTarget(wantedThrottle).
				autostage().
				wait 0.
			}
			lock throttle to 0.
		},
		"orbitalInsertion",{
			parameter apTarget,apMaxError is 1e4,etaTarget is 60,etaMin is 30,peTarget is 35e3.
			if insertionComplete(apTarget,apMaxError,etaMin,peTarget){
				ascentHandoff().
				return.
			}
			performOrbitalInsertion(apTarget,apMaxError,etaTarget,etaMin,peTarget).
			ascentHandoff().
		}
	)).
}