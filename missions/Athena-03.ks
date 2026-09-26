// regular klib imports
local kerbinLaunch is import("prg/atmosphericAscent-v2").
local mnvCircularize is import("mnv/circularizeAtApsis-v1").
local matchInclination is import("mnv/matchInclination-v1").
local hohmannTransfer is import("mnv/hohmannTransfer-v1").
local altitudeSafety is import("tlm/altitudeSafety-v1").
local changeFlybyPe is import("mnv/changeFlybyPe-v1").
local raiseOrLowerApsis is import("mnv/raiseOrLowerApsis-v1").
local changeApsisAtUT is import("mnv/changeApsisAtUT-v1").
local returnToParent is import("mnv/returnToParent-v1").
local moonDescent is import("prg/airlessDescent-v2").
local moonAscent is import("prg/airlessAscent-v1").
local kerbinDescent is import("prg/atmosphericDescent-v1").
local prgExecuteNode is import("prg/executeNode-v1").
local executeNode is prgExecuteNode:executeNode.
local burnDuration is prgExecuteNode:burnDuration.
local stageUntil is import("sys/staging-v1"):stageUntil.
local rt is import("sys/remoteTech-v1").

// Mission Parameters
local launchApoapsis is 100e3.
local launchInclination is 0.
local targetBody is Mun.
local moonFlybyPeriapsis is 0. // we'll use terrain safety so this is minimum safe altitude
local moonDeorbitPeriapsis is -10e3.
local moonAscentApoapsis is 15e3.
local moonAscentInclination is 0.
local moonAscentHeading is 90 - moonAscentInclination. // this should probably be inclination
local returnPeriapsis is 35e3.
local kerbinOrbitalStage is 4.
local moonDescentStage is 2.
local kerbinDescentStage is 1.
local kerbinLandingStage is 0.
local terrainSafetyMargin is 100. // safe target above max terrain height

// Mission Runner
// TODO: Any `shutdown` should ideally have a better failure mode, currently this is just left for manual intervention
import("missionRunner-v1")
:create(list(
	list("prelaunch", {
		parameter runner.
		runner:share("Home", body:name).

		// Initialize Telemetry Processor (TPU)
		local hasTPU is false.
		for kOSProcessor in ship:modulesNamed("kOSProcessor") {
			local kOSProcessorVolume is kOSProcessor:volume.
			if (kOSProcessor:bootFileName = "" or kOSProcessor:bootFileName = "None") and kOSProcessorVolume:files:length = 0 {
				set kOSProcessor:tag to "TPU".
				set kOSProcessorVolume:name to "tpu" + kOSProcessor:part:uid.
				set hasTPU to true.

				copyPath(
					"1:/" + core:bootFileName,
					kOSProcessorVolume:name + ":/" + core:bootFileName
				).
				set kOSProcessor:bootFileName to core:bootFileName.

				runner:share("TPUid", kOSProcessor:part:uid).
				runner:share("TPUvolume", kOSProcessorVolume:name).

				kOSProcessor:deactivate().
				kOSProcessor:activate().
				break.
				// To get the TPU processor later:
				//	if runner:fetch("hasTPU") {
				//		local TPU is processor(volume(runner:fetch("TPUvolume"))).
				//		local tpuConnection is TPU:connection.
				//	}
			}
		}
		runner:share("hasTPU", hasTPU).

		notify("Launch in 3 seconds").
		lights on.
		wait 3.
		runner:next().
	}),
	list("run-launch", {
		parameter runner.
		dmsg("Beginning " + body:name + " ascent", true, true).
		// TODO: atmosphericAscent needs updating to support runner:tick
		kerbinLaunch:executeAscent(launchApoapsis, launchInclination).
		runner:next().
	}),
	list("run-orbital-insertion", {
		parameter runner.
		dmsg("Performing " + body:name + " orbital insertion", true, true).
		kerbinLaunch:orbitalInsertion(launchApoapsis).
		stageUntil(kerbinOrbitalStage).
		runner:next().
	}),
	list("plan-kerbin-circularization", {
		parameter runner.
		until not hasNode { remove nextNode. wait 0. }
		dmsg("Planning " + body:name + " circularization", true, true).
		local circularizeResult is mnvCircularize:Ap().
		if not circularizeResult:ok {
			notify("Circularization failed - shutting down").
			dmsg("Circularization planning failed: " + circularizeResult:msg, true).
			shutdown.
		}
		add circularizeResult:val.
		runner:next().
	}),
	list("warpto-kerbin-circularization", {
		parameter runner.
		// TODO: `executeNode` needs a better api suffix than just `burnDuration`
		local preburnUT is time:seconds + nextNode:eta - 60 - burnDuration(nextNode:deltav:mag / 2).
		if warp = 0 and time:seconds < preburnUT - 30 {
			warpTo(preburnUT).
		}
		runner:next().
	}),
	list("exec-kerbin-circularization", {
		parameter runner.
		if nextNode:eta < 60 + burnDuration(nextNode:deltav:mag / 2) {
			dmsg("Executing " + body:name + " circularization", true, true).
			runner:invoke("exec-node").
			runner:next().
		}
	}),
	list("kerbin-orbit", {
		parameter runner.
		dmsg(body:name + " orbit achieved - Deploying solar panels", true, true).
		panels on.
		lights on.
		runner:enable("high-power").
		set target to targetBody.
		runner:next().
	}),
	list("plan-match-inclination", {
		parameter runner.
		until not hasNode { remove nextNode. wait 0. }
		dmsg("Planning to match inclination with " + targetBody:name, true, true).
		local matchInclinationResult is matchInclination(targetBody).
		if not matchInclinationResult:ok {
			notify("Inclination change failed - shutting down").
			dmsg("Inclination planning failed: " + matchInclinationResult:msg, true).
			shutdown.
		}
		add matchInclinationResult:val.
		runner:next().
	}),
	list("warpto-match-inclination", {
		parameter runner.
		local preburnUT is time:seconds + nextNode:eta - 60 - burnDuration(nextNode:deltav:mag / 2).
		if warp = 0 and time:seconds < preburnUT - 30 {
			warpTo(preburnUT).
		}
		runner:next().
	}),
	list("exec-match-inclination", {
		parameter runner.
		if nextNode:eta < 60 + burnDuration(nextNode:deltav:mag / 2) {
			dmsg("Matching inclination with " + targetBody:name, true, true).
			runner:invoke("exec-node").
			runner:next().
		}
	}),
	list("plan-moon-transfer", {
		parameter runner.
		until not hasNode { remove nextNode. wait 0. }
		dmsg("Planning transfer to " + targetBody:name, true, true).
		local hohmannResult is hohmannTransfer(targetBody).
		if not hohmannResult:ok {
			notify("Transfer failed - shutting down").
			dmsg("Transfer planning failed: " + hohmannResult:msg, true).
			shutdown.
		}
		add hohmannResult:val.
		runner:next().
	}),
	list("warpto-moon-transfer", {
		parameter runner.
		local preburnUT is time:seconds + nextNode:eta - 60 - burnDuration(nextNode:deltav:mag / 2).
		if warp = 0 and time:seconds < preburnUT - 30 {
			warpTo(preburnUT).
		}
		runner:next().
	}),
	list("exec-moon-transfer", {
		parameter runner.
		if nextNode:eta < 60 + burnDuration(nextNode:deltav:mag / 2) {
			dmsg("Executing transfer to " + targetBody:name, true, true).
			runner:invoke("exec-node").
			runner:next().
		}
	}),
	list("post-moon-transfer", {
		parameter runner.
		if not (obt:hasnextpatch and obt:nextpatch:body = targetBody) {
			notify("Transfer failed - shutting down").
			dmsg("Transfer did not reach " + targetBody:name, true).
			shutdown.
		}
		dmsg(targetBody:name + " encounter confirmed - Coasting to " + targetBody:name + " SOI", true, true).
		runner:next().
	}),
	list("warpto-moon-soi", {
		parameter runner.
		local transitionUT is time:seconds + eta:transition.
		if warp = 0 and time:seconds < transitionUT - 30 {
			warpTo(transitionUT).
		}
		runner:next().
	}),
	list("await-moon-soi", {
		parameter runner.
		if body = targetBody {
			local crossingUT is time:seconds.
			kuniverse:timewarp:cancelwarp().
			// TODO: we need a better method to ensure SOI boundary changes without a blocking wait
			wait until kuniverse:timewarp:isSettled and time:seconds > crossingUT + 10.
			dmsg("Entered " + body:name + " SOI", true, true).
			runner:next().
		}
	}),
	list("plan-flyby-trim", {
		parameter runner.
		until not hasNode { remove nextNode. wait 0. }
		dmsg("Trimming " + body:name + " approach", true, true).

		local altitudeSafetyResult is altitudeSafety:altitude(body).
		if not altitudeSafetyResult:ok {
			notify("Approach trim failed - shutting down").
			dmsg("Terrain height check failed: " + altitudeSafetyResult:msg, true).
			shutdown.
		}
		local targetedFlybyPeriapsis is max(
			moonFlybyPeriapsis,
			altitudeSafetyResult:val + terrainSafetyMargin
		).
		runner:share("targetedFlybyPeriapsis", targetedFlybyPeriapsis).
		dmsg("     Minimum Pe = " + moonFlybyPeriapsis + "m", true).
		dmsg("    Terrain max = " + altitudeSafetyResult:val + "m", true).
		dmsg("  Safety margin = " + terrainSafetyMargin + "m", true).
		dmsg("    Targeted Pe = " + targetedFlybyPeriapsis + "m", true).

		local flybyResult is changeFlybyPe(targetedFlybyPeriapsis).
		if not flybyResult:ok {
			notify("Approach trim failed - shutting down").
			dmsg("Approach trim planning failed: " + flybyResult:msg, true).
			shutdown.
		}

		add flybyResult:val.
		runner:next().
	}),
	list("warpto-flyby-trim", {
		parameter runner.
		local preburnUT is time:seconds + nextNode:eta - 60 - burnDuration(nextNode:deltav:mag / 2).
		if warp = 0 and time:seconds < preburnUT - 30 {
			warpTo(preburnUT).
		}
		runner:next().
	}),
	list("exec-flyby-trim", {
		parameter runner.
		if nextNode:eta < 60 + burnDuration(nextNode:deltav:mag / 2) {
			dmsg("Executing " + body:name + " flyby trim", true, true).
			runner:invoke("exec-node").

			local targetedFlybyPeriapsis is runner:fetch("targetedFlybyPeriapsis").
			dmsg(body:name + " flyby periapsis targeted: " + round(periapsis, 0) + "m", true, true).
			dmsg("  Target Periapsis = " + round(targetedFlybyPeriapsis, 1) + "m", true).
			dmsg("   Periapsis error = " + round(obt:periapsis - targetedFlybyPeriapsis, 1) + "m", true).
			runner:next().
		}
	}),
	list("plan-moon-deorbit", {
		parameter runner.
		until not hasNode { remove nextNode. wait 0. }
		dmsg("Planning de-orbit burn", true, true).
		dmsg("  Pe <= " + moonDeorbitPeriapsis + "m", true).
		// TODO: suffix terminology is misleading, as the suffix is the opposing apsis, maybe should be :AtPe and :AtAp
		local deorbitResult is raiseOrLowerApsis:Ap(moonDeorbitPeriapsis).
		// `raiseOrLowerApsis` has no failure mode, so just add the result value
		add deorbitResult:val.
		runner:next().
	}),
	list("warpto-moon-deorbit", {
		parameter runner.
		local preburnUT is time:seconds + nextNode:eta - 60 - burnDuration(nextNode:deltav:mag / 2).
		if warp = 0 and time:seconds < preburnUT - 30 {
			warpTo(preburnUT).
		}
		runner:next().
	}),
	list("exec-moon-deorbit", {
		parameter runner.
		if nextNode:eta < 60 + burnDuration(nextNode:deltav:mag / 2) {
			dmsg("De-orbiting over " + body:name, true, true).
			runner:invoke("exec-node").
			runner:next().
		}
	}),
	list("run-moon-descent", {
		parameter runner.
		dmsg(body:name + " descent guidance active", true, true).
		stageUntil(moonDescentStage).
		moonDescent().
		clearScreen.
		dmsg(body:name + " landing complete", true, true).
		dmsg("Awaiting crew egress", true).
		runner:share("crewComplement", ship:crew():length).
		runner:next().
	}),
	list("await-moon-egress", {
		parameter runner.
		if ship:crew():length < runner:fetch("crewComplement") {
			dmsg("Crew egress detected", true).
			dmsg("Awaiting crew return", true).
			runner:next().
		}
	}),
	list("await-moon-ingress", {
		parameter runner.
		if ship:crew():length = runner:fetch("crewComplement") {
			dmsg("Crew ingress complete", true).
			runner:next().
		}
	}),
	list("run-moon-ascent", {
		parameter runner.
		dmsg(body:name + " ascent guidance active", true, true).
		local ascentState is moonAscent(moonAscentHeading, moonAscentApoapsis).
		if ascentState <> "ORBITING" and ascentState <> "SUB_ORBITAL" {
			notify(body:name + " ascent failed - shutting down").
			dmsg(body:name + " ascent failed: " + ascentState, true).
			shutdown. // TODO: We should probably add abort sequences :)
		}
		runner:next().
	}),
	list("plan-moon-circularization", {
		parameter runner.
		until not hasNode { remove nextNode. wait 0. }
		dmsg("Planning " + body:name + " circularization", true, true).
		local circularizeResult is mnvCircularize:Ap().
		if not circularizeResult:ok {
			notify("Circularization failed - shutting down").
			dmsg("Circularization planning failed: " + circularizeResult:msg, true).
			shutdown. // TODO: We should probably add abort sequences :)
		}
		add circularizeResult:val.
		runner:next().
	}),
	list("warpto-moon-circularization", {
		parameter runner.
		// TODO: `executeNode` needs a better api suffix than just `burnDuration`
		local preburnUT is time:seconds + nextNode:eta - 60 - burnDuration(nextNode:deltav:mag / 2).
		if warp = 0 and time:seconds < preburnUT - 30 {
			warpTo(preburnUT).
		}
		runner:next().
	}),
	list("exec-moon-circularization", {
		parameter runner.
		if nextNode:eta < 60 + burnDuration(nextNode:deltav:mag / 2) {
			dmsg("Executing " + body:name + " circularization", true, true).
			runner:invoke("exec-node").
			runner:next().
		}
	}),
	list("plan-kerbin-return", {
		parameter runner.
		until not hasNode { remove nextNode. wait 0. }
		local home is runner:fetch("Home").
		notify("Planning return to " + home).
		dmsg("Planning return to " + home + " at " + returnPeriapsis + "m", true).
		local returnFromMoonResult is returnToParent(returnPeriapsis).
		if not returnFromMoonResult:val {
			notify("Return attempt failed").
			dmsg("Failed to escape " + body:name + " SOI", true).
			shutdown.
		}
		else {
			if not returnFromMoonResult:ok {
				notify("Return trajectory has additional encounter").
				dmsg("Return trajectory encounters another body before periapsis", true).
				dmsg("Proceeding with return trajectory", true).
			}
			// returnToParent already adds the node to the flight-path, unlike other maneuver scripts
			runner:next().
		}
	}),
	list("warpto-kerbin-return", {
		parameter runner.
		local preburnUT is time:seconds + nextNode:eta - 60 - burnDuration(nextNode:deltav:mag / 2).
		if warp = 0 and time:seconds < preburnUT - 30 {
			warpTo(preburnUT).
		}
		runner:next().
	}),
	list("exec-kerbin-return", {
		parameter runner.
		if nextNode:eta < 60 + burnDuration(nextNode:deltav:mag / 2) {
			dmsg("Executing " + body:name + " ejection burn", true, true).
			runner:invoke("exec-node").
			runner:next().
		}
	}),
	list("post-kerbin-return", {
		parameter runner.
		local home is runner:fetch("Home").

		if not (obt:hasnextpatch and obt:nextpatch:body:name = home) {
			notify("Return failed - shutting down").
			dmsg("Return burn did not reach " + home, true).
			shutdown. // TODO: failure mode? fuel = try again, empty = send help
		}
		dmsg(home + " return confirmed - Coasting to " + home + " SOI", true, true).
		runner:next().
	}),
	list("warpto-kerbin-soi", {
		parameter runner.
		local transitionUT is time:seconds + eta:transition.
		if warp = 0 and time:seconds < transitionUT - 30 {
			warpTo(transitionUT).
		}
		runner:next().
	}),
	list("await-kerbin-soi", {
		parameter runner.
		if body:name = runner:fetch("Home") {
			local crossingUT is time:seconds.
			kuniverse:timewarp:cancelwarp().
			// TODO: we need a better method to ensure SOI boundary changes without a blocking wait
			wait until kuniverse:timewarp:isSettled and time:seconds > crossingUT + 10.
			dmsg("Entered " + body:name + " SOI", true, true).
			runner:next().
		}
	}),
	list("plan-reentry-trim", {
		parameter runner.
		until not hasNode { remove nextNode. wait 0. }
		notify("Trimming re-entry trajectory").
		dmsg("Planning re-entry trajectory to " + returnPeriapsis + "m", true).
		local trimResult is changeApsisAtUT:Pe(returnPeriapsis, time:seconds + 60).
		if not trimResult:ok {
			notify("Re-entry trim failed - shutting down").
			dmsg("Re-entry trim planning failed: " + trimResult:msg, true).
			shutdown.
		}
		add trimResult:val.
		runner:next().
	}),
	list("exec-reentry-trim", {
		parameter runner.
		if nextNode:eta < 60 + burnDuration(nextNode:deltav:mag / 2) {
			dmsg("Executing " + body:name + " re-entry trim", true, true).
			runner:invoke("exec-node").

			dmsg(body:name + " re-entry periapsis targeted: " + round(periapsis, 0) + "m", true, true).
			dmsg("  Target Periapsis = " + round(returnPeriapsis, 1) + "m", true).
			dmsg("   Periapsis error = " + round(obt:periapsis - returnPeriapsis, 1) + "m", true).
			runner:next().
		}
	}),
	list("warpto-reentry", {
		parameter runner.
		// 5 minutes before periapsis
		local reentryMarginUT is time:seconds + eta:periapsis - 300.
		if warp = 0 and time:seconds < reentryMarginUT - 30 {
			warpTo(reentryMarginUT).
		}
		runner:next().
	}),
	list("coast-to-reentry", {
		parameter runner.
		// TODO: `atmosphericDescent` has a WARP_BOUNDARY of 100km above atmosphere, we should either remove authority until we hit atmopshere, or add some more parameters
		if altitude < body:atm:height + 100e3 {
			kuniverse:timewarp:cancelwarp().
			wait until kuniverse:timewarp:issettled.
			dmsg("Preparing for re-entry", true, true).
			runner:disable("high-power").
			runner:disable("low-power").
			runner:invoke("comms-off").
			panels off.
			runner:next().
		}
	}),
	list("run-kerbin-descent", {
		parameter runner.
		dmsg(body:name + " descent guidance active", true, true).
		kerbinDescent(kerbinLandingStage, kerbinDescentStage).
		runner:next().
	}),
	list("returned-safely", {
		parameter runner.
		dmsg("Mission complete", true, true).
		runner:next().
	})
))
:events(list(
	list("low-power", {
		parameter events.
		for res in ship:resources {
			if res:name = "ELECTRICCHARGE" and res:amount / res:capacity < 0.3 {
				notify("Warning! Low power").
				dmsg("[event] Entering low-power mode", true).
				events:enable("high-power").
				events:disable("low-power").
				events:invoke("comms-off").
				break.
			}
		}
	}, false),
	list("high-power", {
		parameter events.
		for res in ship:resources {
			if res:name = "ELECTRICCHARGE" and res:amount / res:capacity > 0.6 {
				notify("Power restored").
				dmsg("[event] Leaving low-power mode", true).
				events:enable("low-power").
				events:disable("high-power").
				events:invoke("comms-on").
				break.
			}
		}
	}, false)
))
:commands(list(
	list("comms-on", {
		parameter commands.

		dmsg("Deploying communication dish", true, true).
		for dish in rt:getAllDish() {
			dish:enable().
			dish:setTarget(commands:fetch("Home")).
		}
	}),
	list("comms-off", {
		parameter commands.

		dmsg("Communication disabled", true, true).
		for dish in rt:getAllDish() {
			dish:disable().
		}
	}),
	list("exec-node", {
		parameter commands.
		kuniverse:timewarp:cancelwarp().
		wait until kuniverse:timewarp:isSettled.
		rcs on.
		executeNode(60).
		rcs off.
	})
))
:start().