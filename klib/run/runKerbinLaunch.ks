{
	local atmosphericAscent is import("prg/atmosphericAscent-v2").
	local stageUntil is import("sys/staging-v1"):stageUntil.
	export(lex(
		"ascent", {
			parameter launchApoapsis, launchInclination, runner.
			dmsg("Beginning " + body:name + " ascent", true, true).
			// TODO: atmosphericAscent needs updating to support runner:tick
			atmosphericAscent:executeAscent(launchApoapsis, launchInclination).
			runner:next().
		},
		"insertion", {
			parameter launchApoapsis, kerbinOrbitalStage, runner.
			dmsg("Performing " + body:name + " orbital insertion", true, true).
			atmosphericAscent:orbitalInsertion(launchApoapsis).
			stageUntil(kerbinOrbitalStage).
			runner:next().
		}
	)).
}