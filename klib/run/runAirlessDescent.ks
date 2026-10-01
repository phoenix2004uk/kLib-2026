{
	local airlessDescent is import("prg/airlessDescent-v2").
	local stageUntil is import("sys/staging-v1"):stageUntil.
	export({
		parameter moonDescentStage, runner.
		dmsg(body:name + " descent guidance active", true, true).
		stageUntil(moonDescentStage).
		airlessDescent().
		clearScreen.
		dmsg(body:name + " landing complete", true, true).
		runner:next().
	}).
}