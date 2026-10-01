{
	local changeApsisAtUT is import("mnv/changeApsisAtUT-v1").
	local onFail is import("run/onFail").
	export({
		parameter returnPeriapsis, runner.
		until not hasNode { remove nextNode. wait 0. }
		dmsg("Trimming " + body:name + " re-entry trajectory", true, true).
		local trimResult is changeApsisAtUT:Pe(returnPeriapsis, time:seconds + 60).
		onFail:shutdown(trimResult, "Re-entry trim").
		add trimResult:val.
		runner:next().
	}).
}