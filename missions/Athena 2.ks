// kldrv2 mission runner
// Athena 1: First Kerbal orbit

// Reusable Mission Runner Steps
local prelaunch is import("run/prelaunch").
local kerbinLaunch is import("run/runKerbinLaunch").
local execNode is import("run/execNode").
local planCircularization is import("run/planCircularization").
local planRaiseOrLowerApsis is import("run/planRaiseOrLowerApsis").
local planMatchInclination is import("run/planMatchInclination").
local planHohmannTransfer is import("run/planHohmannTransfer").
local kerbinReEntry is import("run/runKerbinReEntry").

// regular klib imports
local approach is import("prg/approach-v1").
local dock is import("prg/dock-v1").
local format is import("util/format-v1").

// Mission Parameters
local targetVessel is Vessel("Athena 2-DT").
local launchApoapsis is 80e3.
local launchInclination is 0.
local returnAltitude is 35e3.
local kerbinOrbitalStage is 2.
local kerbinDescentStage is 1.
local kerbinLandingStage is 0.
local NODE_LEAD_TIME is 60.
local INCLINATION_ACCURACY is 0.01.
local INIT_TPU is false.
local APPROACH_STEPS is list(
	list(1000, 20),
	list(100, 10),
	list(20, 2)
).

// Mission Runner
// TODO: Any `shutdown` in any defined or imported steps, should ideally have a better failure mode, currently these are just left for manual intervention
import("missionRunner-v1")
:create(list(
	list("prelaunch", prelaunch:bind(INIT_TPU)),
	list("run-launch", kerbinLaunch:ascent:bind(launchApoapsis, launchInclination)),
	list("run-orbital-insertion", kerbinLaunch:insertion:bind(launchApoapsis, kerbinOrbitalStage)),
	list("plan-kerbin-circularization", planCircularization:AtAp),
	list("warpto-kerbin-circularization", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-kerbin-circularization", execNode:exec:bind(NODE_LEAD_TIME, "circularization")),
	list("kerbin-orbit", {
		parameter runner.
		kuniverse:timewarp:cancelWarp().
		wait until kuniverse:timewarp:isSettled.
		dmsg(body:name + " orbit achieved - Deploying solar panels", true, true).
		panels on.
		lights on.
		runner:next().
	}),
	list("plan-match-inclination", planMatchInclination:bind(targetVessel, "first", INCLINATION_ACCURACY)),
	list("warpto-match-inclination", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-match-inclination", execNode:exec:bind(NODE_LEAD_TIME, "inclination match with " + targetVessel:name)),
	list("plan-target-transfer", planHohmannTransfer:bind(targetVessel)),
	list("warpto-target-transfer", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-target-transfer", execNode:exec:bind(NODE_LEAD_TIME, "transfer to " + targetVessel:name)),
	list("plan-target-intercept", planCircularization:AtAp),
	list("warpto-target-intercept", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-target-intercept", execNode:exec:bind(NODE_LEAD_TIME, "intercept")),

	list("approach-target", {
		parameter runner.

		dmsg("Approaching " + targetVessel:name, true, true).
		set target to targetVessel.

		for approachStep in APPROACH_STEPS {
			dmsg("Approach target: " + format:distance(approachStep[0]) + " @ " + format:speed(approachStep[1]), true).
			dmsg("  starting distance: " + format:distance(targetVessel:distance), true).
			approach(targetVessel, approachStep[0], approachStep[1]).
			dmsg("  ending distance: " + format:distance(targetVessel:distance), true).
			dmsg("  distance error: " + format:distance(targetVessel:distance - approachStep[0]), true).
			print "".
		}

		dmsg("Final separation: " + format:distance(targetVessel:distance), true, true).
		runner:next().
	}),

	list("dock-wtih-target", {
		parameter runner.

		local shipPort is ship:dockingPorts[0].
		local targetPort is targetVessel:dockingPorts[0].
		set target to targetPort.

		dmsg("Initiating docking procedure", true, true).
		local dockResult is dock(shipPort, targetPort).

		if dockResult:ok {
			dmsg("Docking complete", true, true).
			runner:next().
		}
		else {
			dmsg("Docking failed - Retry in 30 seconds", true, true).
			wait 30.
		}
	}),

	list("plan-lower-periapsis", planRaiseOrLowerApsis:Pe:bind(returnAltitude)),
	list("warpto-lower-periapsis", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-lower-periapsis", execNode:exec:bind(NODE_LEAD_TIME, "lower periapsis")),
	list("coast-to-reentry", {
		parameter runner.
		if altitude <= body:atm:height {
			kuniverse:timewarp:cancelWarp().
			wait until kuniverse:timewarp:isSettled.
			dmsg("Preparing for re-entry", true, true).
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
:start().