{
	local awaitSteering is import("sys/steering-v1"):awaitSteering.
	local stageUntil is import("sys/staging-v1"):stageUntil.

	local WARP_BOUNDARY is 100e3.
	local PARACHUTE_ALTITUDE is 10e3.
	local GEAR_ALTITUDE is 1e3.

	function atmosphericDescent {
		parameter landingStage is 0, descentStage is 1.

		wait until altitude < body:atm:height + WARP_BOUNDARY.
		kuniverse:timewarp:cancelwarp().
		wait until kuniverse:timewarp:issettled.

		dmsg("Waiting for atmospheric re-entry", true).
		wait until altitude < body:atm:height.

		if stage:number > descentStage {
			dmsg("Discarding descent stage", true).
			stageUntil(descentStage).
			wait 1.
		}

		lock steering to lookDirUp(srfRetrograde:vector, sun:position).
		awaitSteering().

		wait until alt:radar < PARACHUTE_ALTITUDE.
		dmsg("Staging parachutes", true).
		stageUntil(landingStage).

		wait until alt:radar < GEAR_ALTITUDE.
		gear on.

		wait until status = "LANDED" or status = "SPLASHED".
		dmsg("Touch down: " + status, true).
		if status = "LANDED" {
			// Hold upright while the landing gear settles.
			lock steering to lookDirUp(up:vector, sun:position).
			wait 10.
		}
		unlock throttle.
		unlock steering.
		wait until not steeringManager:enabled.
		sas on.
	}

	export(atmosphericDescent@).
}