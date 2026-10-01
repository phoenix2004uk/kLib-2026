{
	local raiseOrLowerApsis is import("mnv/raiseOrLowerApsis-v1").
	local format is import("util/format-v1").
	export({
		parameter moonDeorbitPeriapsis, runner.
		until not hasNode { remove nextNode. wait 0. }
		dmsg("Planning de-orbit burn", true, true).
		dmsg("  Pe <= " + format:distance(moonDeorbitPeriapsis), true).
		add raiseOrLowerApsis:Ap(moonDeorbitPeriapsis):val.
		runner:next().
	}).
}