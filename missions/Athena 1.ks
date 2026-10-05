// kldrv2 mission runner
// Athena 1: First Kerbal orbit

// Reusable Mission Runner Steps
local prelaunch is import("run/prelaunch").
local kerbinLaunch is import("run/runKerbinLaunch").
local execNode is import("run/execNode").
local planCircularization is import("run/planCircularization").
local planRaiseOrLowerApsis is import("run/planRaiseOrLowerApsis").
local planInclinationChange is import("run/planInclinationChange").
local kerbinReEntry is import("run/runKerbinReEntry").

// regular klib imports
local awaitSteering is import("sys/steering-v1"):awaitSteering.

// Mission Parameters
local launchApoapsis is 100e3.
local launchInclination is 90.
local targetInclination is 90.
local higherAltitude is 300e3.
local returnAltitude is 35e3.
local kerbinOrbitalStage is 2.
local kerbinDescentStage is 1.
local kerbinLandingStage is 0.
local NODE_LEAD_TIME is 60.
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
	list("warpto-kerbin-circularization", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-kerbin-circularization", execNode:exec:bind(NODE_LEAD_TIME, "circularization")),
	list("plan-inclination-change", planInclinationChange:highest:bind(targetInclination, INCLINATION_ACCURACY)),
	list("warpto-inclination-change", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-inclination-change", execNode:exec:bind(NODE_LEAD_TIME, "plane change")),
	list("kerbin-orbit", {
		parameter runner.
		kuniverse:timewarp:cancelWarp().
		wait until kuniverse:timewarp:isSettled.
		dmsg(body:name + " orbit achieved - Deploying solar panels", true, true).
		panels on.
		lights on.
		lock steering to -sun:position.
		awaitSteering().
		print "Press Y to proceed to higher altitude".
		terminal:input:clear().
		runner:next().
	}),
	list("waiting-for-next-stage", {
		parameter runner.
		if terminal:input:hasChar {
			if terminal:input:getChar() = "Y" {
				dmsg("Proceeding to higher altitude", true, true).
				runner:next().
			}
			terminal:input:clear().
		}
	}),
	list("plan-raise-apoapsis", planRaiseOrLowerApsis:Ap:bind(higherAltitude)),
	list("warpto-raise-apoapsis", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-raise-apoapsis", execNode:exec:bind(NODE_LEAD_TIME, "raise apoapsis")),
	list("plan-kerbin-hi-circularization", planCircularization:AtAp),
	list("warpto-kerbin-hi-circularization", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-kerbin-hi-circularization", execNode:exec:bind(NODE_LEAD_TIME, "circularization")),
	list("kerbin-high-orbit", {
		parameter runner.
		dmsg(body:name + " high orbit achieved", true, true).
		lock steering to -sun:position.
		awaitSteering().
		print "Press Y to return to " + runner:fetch("Home").
		terminal:input:clear().
		runner:next().
	}),
	list("waiting-for-deorbit", {
		parameter runner.
		if terminal:input:hasChar {
			if terminal:input:getChar() = "Y" {
				dmsg("Proceeding to de-orbit and return", true, true).
				runner:next().
			}
			terminal:input:clear().
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