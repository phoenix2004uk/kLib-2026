{
	local raiseOrLowerApsis is import("mnv/raiseOrLowerApsis-v1").
	local format is import("util/format-v1").
	export({
		parameter moonDeorbitPeriapsis, runner.
		until not hasNode { remove nextNode. wait 0. }
		dmsg("Planning de-orbit burn", true, true).
		dmsg("  Pe <= " + format:distance(moonDeorbitPeriapsis), true).

		// TODO: suffix terminology is misleading, as the suffix is the opposing apsis, maybe should be :AtPe and :AtAp
		local deorbitResult is raiseOrLowerApsis:Ap(moonDeorbitPeriapsis).

		// Note: `raiseOrLowerApsis` does not have an `ApiFail` return, so just add its `val`
		add deorbitResult:val.

		runner:next().
	}).
}