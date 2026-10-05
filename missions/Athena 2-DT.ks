// kldrv2 mission runner
// Athena 2-DT: Dock target probe for Athena 2

// Reusable Mission Runner Steps
local prelaunch is import("run/prelaunch").
local kerbinLaunch is import("run/runKerbinLaunch").
local execNode is import("run/execNode").
local planCircularization is import("run/planCircularization").
local planInclinationChange is import("run/planInclinationChange").

// regular klib imports
local awaitSteering is import("sys/steering-v1"):awaitSteering.

// Mission Parameters
local launchApoapsis is 120e3.
local launchInclination is 0.
local targetInclination is launchInclination.
local kerbinOrbitalStage is 0.
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
		lock steering to prograde.
		awaitSteering().
		runner:next().
	}),
	list("prepare-for-docking", {
		parameter runner.
		unlock steering.
		sas on.

		set ship:dockingPorts[0]:tag to "dockee".
		runner:next().
	}),
	list("await-docking", {
		parameter runner.

		local dockingPort is ship:partsTagged("dockee")[0].
		set sas to dockingPort:state = "Ready".

		if dockingPort:hasPartner {
			runner:next().
		}
	})
))
:start().