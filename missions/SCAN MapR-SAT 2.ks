// kldrv2 mission runner
// SCAN MapR-SAT 2: SCANsat HiRes Resource scan of Mun
// AG1: Deploy scanners

// Reusable Mission Runner Steps
local prelaunch is import("run/prelaunch").
local kerbinLaunch is import("run/runKerbinLaunch").
local execNode is import("run/execNode").
local planCircularization is import("run/planCircularization").
local planMatchInclination is import("run/planMatchInclination").
local planHohmannTransfer is import("run/planHohmannTransfer").
local soiTransition is import("run/soiTransition").
local planFlybyTrim is import("run/planFlybyTrim").
local planRaiseOrLowerApsis is import("run/planRaiseOrLowerApsis").
local planInclinationChange is import("run/planInclinationChange").

// regular klib imports
local awaitSteering is import("sys/steering-v1"):awaitSteering.
local stageUntil is import("sys/staging-v1"):stageUntil.
local format is import("util/format-v1").
local rt is import("sys/remoteTech-v1").

// Mission Parameters
local launchApoapsis is 100e3.
local launchInclination is 0.
local targetBody is Mun.
local moonFlybyPeriapsis is 0. // we'll use terrain safety so this is minimum safe altitude
local moonCaptureAltitude is targetBody:soiRadius - targetBody:radius - 100e3.
local targetAltitude is 499e3.
local targetInclination is 90.
local transferStage is 0.
local moonStage is 0.
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
	list("run-orbital-insertion", kerbinLaunch:insertion:bind(launchApoapsis, transferStage)),
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
		for dish in rt:getAll() dish:enable().
		runner:next().
	}),
	list("plan-match-inclination", planMatchInclination:bind(targetBody, "first", INCLINATION_ACCURACY)),
	list("warpto-match-inclination", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-match-inclination", execNode:exec:bind(NODE_LEAD_TIME, "inclination match with " + targetBody:name)),
	list("plan-moon-transfer", planHohmannTransfer:bind(targetBody)),
	list("warpto-moon-transfer", execNode:warpTo:bind(NODE_LEAD_TIME)),
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
	list("warpto-moon-soi", soiTransition:warpTo),
	list("await-moon-soi", soiTransition:await:bind(targetBody)),
	list("plan-flyby-trim", planFlybyTrim:bind(-10e3, NODE_LEAD_TIME, false)),
	list("warpto-flyby-trim", execNode:warpTo:bind(NODE_LEAD_TIME)),
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
		stageUntil(moonStage).
		runner:next().
	}),
	list("plan-capture-trim", planFlybyTrim:bind(moonFlybyPeriapsis, NODE_LEAD_TIME, true)),
	list("warpto-capture-trim", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-capture-trim", execNode:exec:bind(NODE_LEAD_TIME, "flyby trim")),
	list("post-capture-trim", {
		parameter runner.
		local targetedFlybyPeriapsis is runner:fetch("targetedFlybyPeriapsis").
		dmsg(body:name + " flyby periapsis targeted: " + format:distance(periapsis), true, true).
		dmsg("  Target Periapsis = " + format:distance(targetedFlybyPeriapsis), true).
		dmsg("   Periapsis error = " + format:distance(obt:periapsis - targetedFlybyPeriapsis), true).
		runner:next().
	}),
	list("plan-moon-capture", planRaiseOrLowerApsis:Ap:bind(moonCaptureAltitude)),
	list("warpto-moon-capture", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-moon-capture", execNode:exec:bind(NODE_LEAD_TIME, "orbit capture")),
	list("plan-inclination-change", planInclinationChange:highest:bind(targetInclination, INCLINATION_ACCURACY)),
	list("warpto-inclination-change", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-inclination-change", execNode:exec:bind(NODE_LEAD_TIME, "plane change")),
	list("plan-raise-apoapsis", planRaiseOrLowerApsis:Ap:bind(targetAltitude)),
	list("warpto-raise-apoapsis", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-raise-apoapsis", execNode:exec:bind(NODE_LEAD_TIME, "raise apoapsis")),
	list("plan-moon-circularization", planCircularization:AtAp),
	list("warpto-moon-circularization", execNode:warpTo:bind(NODE_LEAD_TIME)),
	list("exec-moon-circularization", execNode:exec:bind(NODE_LEAD_TIME, "circularization")),
	list("start-scan", {
		parameter runner.
		toggle ag1.
		lock steering to -sun:position.
		awaitSteering().
		wait 10.
	})
))
:start().