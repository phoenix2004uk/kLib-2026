// kldrv2 mission runner
// Athena 4: Minmus Landing and Return

// Reusable Mission Runner Steps
local prelaunch is import("run/prelaunch").
local kerbinLaunch is import("run/runKerbinLaunch").
local execNode is import("run/execNode").
local planCircularization is import("run/planCircularization").
local planMatchInclination is import("run/planMatchInclination").
local planHohmannTransfer is import("run/planHohmannTransfer").
local soiTransition is import("run/soiTransition").
local planFlybyTrim is import("run/planFlybyTrim").
local planDeorbit is import("run/planDeorbit").
local airlessDescent is import("run/runAirlessDescent").
local crewEva is import("run/crewEva").
local airlessAscent is import("run/runAirlessAscent").
local planReturnToParent is import("run/planReturnToParent").
local planReEntryTrim is import("run/planReEntryTrim").
local kerbinReEntry is import("run/runKerbinReEntry").

// regular klib imports
local awaitSteering is import("sys/steering-v1"):awaitSteering.
local stageUntil is import("sys/staging-v1"):stageUntil.
local rt is import("sys/remoteTech-v1").
local format is import("util/format-v1").

// Mission Parameters
local launchApoapsis is 100e3.
local launchInclination is 0.
local targetBody is Minmus.
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
local NODE_LEAD_TIME is 60.
local HIGH_POWER_PCT is 0.6.
local LOW_POWER_PCT is 0.3.
local INCLINATION_ACCURACY is 0.01.
local INIT_TPU is false.

// Mission Runner
// TODO: Any `shutdown` in any defined or imported steps, should ideally have a better failure mode, currently these are just left for manual intervention
import("missionRunner-v1")
:create(list(
	list("prelaunch", prelaunch:bind(INIT_TPU)),
	list("run-launch", kerbinLaunch:ascent:bind(launchApoapsis, launchInclination)),
	list("run-orbital-insertion", kerbinLaunch:insertion:bind(launchApoapsis, kerbinOrbitalStage)),
	list("plan-kerbin-circularization", planCircularization:AtAp),
	// list("warpto-kerbin-circularization", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-kerbin-circularization", execNode:exec:bind(NODE_LEAD_TIME, "circularization")),
	list("kerbin-orbit", {
		parameter runner.
		dmsg(body:name + " orbit achieved - Deploying solar panels", true, true).
		panels on.
		lights on.
		runner:enable("high-power").
		set target to targetBody.
		runner:next().
	}),
	list("plan-match-inclination", planMatchInclination:bind(targetBody, "first", INCLINATION_ACCURACY)),
	// list("warpto-match-inclination", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-match-inclination", execNode:exec:bind(NODE_LEAD_TIME, "inclination match with " + targetBody:name)),
	list("plan-moon-transfer", planHohmannTransfer:bind(targetBody)),
	// list("warpto-moon-transfer", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-moon-transfer", execNode:exec:bind(NODE_LEAD_TIME, "transfer to " + targetBody:name)),
	list("post-moon-transfer", {
		parameter runner.
		if not (obt:hasNextPatch and obt:nextPatch:body = targetBody) {
			notify("Transfer failed - shutting down").
			dmsg("Transfer did not reach " + targetBody:name, true).
			shutdown.
		}
		dmsg(targetBody:name + " encounter confirmed - Coasting to " + targetBody:name + " SOI", true, true).
		runner:next().
	}),
	// list("warpto-moon-soi", soiTransition:warpTo),
	list("await-moon-soi", soiTransition:await:bind(targetBody)),
	list("plan-flyby-trim", planFlybyTrim:bind(-10e3, NODE_LEAD_TIME, false)),
	// list("warpto-flyby-trim", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-flyby-trim", execNode:exec:bind(NODE_LEAD_TIME, "flyby trim")),
	list("post-flyby-trim", {
		parameter runner.
		local targetedFlybyPeriapsis is runner:fetch("targetedFlybyPeriapsis").
		dmsg(body:name + " flyby periapsis targeted: " + format:distance(periapsis), true, true).
		dmsg("  Target Periapsis = " + format:distance(targetedFlybyPeriapsis), true).
		dmsg("   Periapsis error = " + format:distance(obt:periapsis - targetedFlybyPeriapsis), true).
		runner:next().
	}),
	list("discard-transfer-stage", {
		parameter runner.
		lock steering to -body:position.
		awaitSteering().
		stageUntil(moonDescentStage).
		runner:next().
	}),
	list("plan-capture-trim", planFlybyTrim:bind(moonFlybyPeriapsis, NODE_LEAD_TIME, true)),
	// list("warpto-capture-trim", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-capture-trim", execNode:exec:bind(NODE_LEAD_TIME, "flyby trim")),
	list("post-capture-trim", {
		parameter runner.
		local targetedFlybyPeriapsis is runner:fetch("targetedFlybyPeriapsis").
		dmsg(body:name + " flyby periapsis targeted: " + format:distance(periapsis), true, true).
		dmsg("  Target Periapsis = " + format:distance(targetedFlybyPeriapsis), true).
		dmsg("   Periapsis error = " + format:distance(obt:periapsis - targetedFlybyPeriapsis), true).
		runner:next().
	}),
	list("plan-moon-deorbit", planDeorbit:bind(moonDeorbitPeriapsis)),
	// list("warpto-moon-deorbit", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-moon-deorbit", execNode:exec:bind(NODE_LEAD_TIME, "de-orbit burn")),
	list("run-moon-descent", airlessDescent:bind(moonDescentStage)),
	list("begin-moon-eva", crewEva:begin),
	list("await-moon-egress", crewEva:egress),
	list("await-moon-ingress", crewEva:ingress),
	list("run-moon-ascent", airlessAscent:bind(moonAscentHeading, moonAscentApoapsis)),
	list("plan-moon-circularization", planCircularization:AtAp),
	// list("warpto-moon-circularization", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-moon-circularization", execNode:exec:bind(NODE_LEAD_TIME, "circularization")),
	list("plan-kerbin-return", planReturnToParent:bind(returnPeriapsis)),
	// list("warpto-kerbin-return", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-kerbin-return", execNode:exec:bind(NODE_LEAD_TIME, "ejection burn")),
	list("post-kerbin-return", {
		parameter runner.
		local home is runner:fetch("Home").
		if not (obt:hasNextPatch and obt:nextPatch:body:name = home) {
			notify("Return failed - shutting down").
			dmsg("Return burn did not reach " + home, true).
			shutdown.
		}
		dmsg(home + " return confirmed - Coasting to " + home + " SOI", true, true).
		runner:next().
	}),
	// list("warpto-kerbin-soi", soiTransition:warpTo),
	list("await-kerbin-soi", soiTransition:await:bind(Kerbin)),
	list("plan-reentry-trim", planReEntryTrim:bind(returnPeriapsis)),
	list("exec-reentry-trim", execNode:exec:bind(NODE_LEAD_TIME, "re-entry trim")),
	list("post-reentry-trim", {
		parameter runner.
		dmsg(body:name + " re-entry periapsis targeted: " + format:distance(periapsis), true, true).
		dmsg("  Target Periapsis = " + format:distance(returnPeriapsis), true).
		dmsg("   Periapsis error = " + format:distance(obt:periapsis - returnPeriapsis), true).
		runner:next().
	}),
	// list("warpto-reentry", {
	// 	parameter runner.
	// 	// 5 minutes before periapsis
	// 	local reentryMarginUT is time:seconds + eta:periapsis - 300.
	// 	if warp = 0 and time:seconds < reentryMarginUT - 30 {
	// 		warpTo(reentryMarginUT).
	// 	}
	// 	runner:next().
	// }),
	list("coast-to-reentry", {
		parameter runner.
		if altitude < body:atm:height + 100e3 {
			kuniverse:timewarp:cancelWarp().
			wait until kuniverse:timewarp:isSettled.
			dmsg("Preparing for re-entry", true, true).
			runner:disable("high-power").
			runner:disable("low-power").
			runner:invoke("comms-off").
			panels off.
			runner:next().
		}
	}),
	list("run-kerbin-descent", kerbinReEntry:bind(kerbinDescentStage, kerbinLandingStage)),
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
			if res:name = "ELECTRICCHARGE" and res:amount / res:capacity < LOW_POWER_PCT {
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
			if res:name = "ELECTRICCHARGE" and res:amount / res:capacity > HIGH_POWER_PCT {
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
	})
))
:start().