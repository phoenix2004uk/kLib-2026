// kldrv2 mission runner
// SCAN MapR-SAT 1: SCANsat HiRes Resource scan of Kerbin
// AG1: Deploy scanners

// Reusable Mission Runner Steps
local prelaunch is import("run/prelaunch").
local kerbinLaunch is import("run/runKerbinLaunch").
local execNode is import("run/execNode").
local planCircularization is import("run/planCircularization").
local planRaiseOrLowerApsis is import("run/planRaiseOrLowerApsis").
local planInclinationChange is import("run/planInclinationChange").

// regular klib imports
local awaitSteering is import("sys/steering-v1"):awaitSteering.
local format is import("util/format-v1").
local rt is import("sys/remoteTech-v1").

// Mission Parameters
local launchApoapsis is 100e3.
local launchInclination is 90.
local targetAltitude is 499e3.
local targetInclination is 90.
local kerbinOrbitalStage is 0.
local NODE_LEAD_TIME is 60.
local INCLINATION_ACCURACY is 0.01.
local INIT_TPU is false.

function deorbit {
	notify("Preparing to decommission via lithobraking").
	dmsg("Preparing to de-orbit", true).

	sas off.
	lock steering to retrograde.
	awaitSteering().
	lock throttle to 1.
	wait until periapsis < -10e3.
	lock throttle to 0.

	notify("De-orbit burn complete - brace for impact").
	dmsg("De-orbit burn complete: Pe = " + format:distance(periapsis), true).
	wait until 0.
}
on abort deorbit().

// Mission Runner
// TODO: Any `shutdown` in any defined or imported steps, should ideally have a better failure mode, currently these are just left for manual intervention
import("missionRunner-v1")
:create(list(
	list("prelaunch", prelaunch:bind(INIT_TPU)),
	list("run-launch", kerbinLaunch:ascent:bind(launchApoapsis, launchInclination)),
	list("run-orbital-insertion", kerbinLaunch:insertion:bind(launchApoapsis, kerbinOrbitalStage)),
	list("kerbin-orbit", {
		parameter runner.
		kuniverse:timewarp:cancelWarp().
		wait until kuniverse:timewarp:isSettled.
		dmsg(body:name + " orbit achieved - Deploying solar panels", true, true).
		panels on.
		lights on.
		for dish in rt:getAll() dish:enable().
		runner:next().
	}),
	list("plan-raise-apoapsis", planRaiseOrLowerApsis:Pe:bind(targetAltitude)),
	list("warpto-raise-apoapsis", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-raise-apoapsis", execNode:exec:bind(NODE_LEAD_TIME, "raise apoapsis")),
	list("plan-inclination-change", planInclinationChange:highest:bind(targetInclination, INCLINATION_ACCURACY)),
	list("warpto-inclination-change", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-inclination-change", execNode:exec:bind(NODE_LEAD_TIME, "plane change")),
	list("plan-kerbin-circularization", planCircularization:AtAp),
	list("warpto-kerbin-circularization", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-kerbin-circularization", execNode:exec:bind(NODE_LEAD_TIME, "circularization")),
	list("start-scan", {
		parameter runner.
		toggle ag1.
		lock steering to -sun:position.
		awaitSteering().
		wait 10.
	})
))
:start().