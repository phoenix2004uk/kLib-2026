{
	local atmosphericDescent is import("prg/atmosphericDescent-v1").
	export({
		parameter kerbinDescentStage, kerbinLandingStage, runner.
		dmsg(body:name + " descent guidance active", true, true).
		atmosphericDescent(kerbinLandingStage, kerbinDescentStage).
		runner:next().
	}).
}