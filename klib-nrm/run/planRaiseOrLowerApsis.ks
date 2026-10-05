{
	local raiseOrLowerApsis is import("mnv/raiseOrLowerApsis-v1").
	local onFail is import("run/onFail").
	function planRaiseOrLowerApsis {
		parameter plannerDelegate, targetAltitude, runner.
		until not hasNode { remove nextNode. wait 0. }
		dmsg("Planning apsis change", true, true).
		local plannerResult is plannerDelegate(targetAltitude).
		onFail:shutdown(plannerResult, "Change apsis").
		add plannerResult:val.
		runner:next().
	}
	export(lex(
		"Ap", planRaiseOrLowerApsis@:bind(raiseOrLowerApsis:Ap),
		"Pe", planRaiseOrLowerApsis@:bind(raiseOrLowerApsis:Pe)
	)).
}