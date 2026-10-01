{
	local changeApsisAtUT is import("mnv/changeApsisAtUT-v1").
	local onFail is import("run/onFail").
	local NODE_UT_MARGIN is 60.
	export({
		parameter returnPeriapsis, runner.
		until not hasNode { remove nextNode. wait 0. }
		dmsg("Trimming " + body:name + " re-entry trajectory", true, true).

		local trimResult is changeApsisAtUT:Pe(returnPeriapsis, time:seconds + NODE_UT_MARGIN).
		onFail:shutdown(trimResult, "Re-entry trim").

		add trimResult:val.
		runner:next().
	}).
}