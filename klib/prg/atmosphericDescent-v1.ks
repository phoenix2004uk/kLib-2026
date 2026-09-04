{
	local awaitSteering is import("sys/steering-v1"):awaitSteering.
	local stageUntil is import("sys/staging-v1"):stageUntil.

	function atmosphericDescent {
		parameter landingStage is 0, descentStage is 1, parachuteAltitude is 10e3, landingAltitude is 1e3.

		dmsg("Waiting for atmospheric re-entry", true).
		wait until altitude < body:atm:height.
		lock steering to lookDirUp(srfRetrograde:vector, sun:position).
		awaitSteering().
		if stage:number > descentStage {
			dmsg("Discarding descent stage", true).
			stageUntil(descentStage).
		}

		wait until alt:radar < parachuteAltitude.
		dmsg("Staging parachutes", true).
		stageUntil(landingStage).

		wait until alt:radar < landingAltitude.
		gear on.

		wait until status = "LANDED" or status = "SPLASHED".
		dmsg("Touch down: " + status, true).
		if status = "LANDED" {
			lock steering to lookDirUp(up:vector, sun:position).
			wait 10.
		}
		unlock steering.
		wait until not steeringManager:enabled.
		sas on.
	}

	export(atmosphericDescent@).
}