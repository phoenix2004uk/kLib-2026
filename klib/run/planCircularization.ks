{
	local mnvCircularize is import("mnv/circularizeAtApsis-v1").
	local onFail is import("run/onFail").
	function planCircularization {
		parameter plannerDelegate, runner.
		until not hasNode { remove nextNode. wait 0. }
		dmsg("Planning " + body:name + " circularization", true, true).
		local circularizeResult is plannerDelegate().
		onFail:shutdown(circularizeResult, "Circularization").
		add circularizeResult:val.
		runner:next().
	}
	export(lex(
		"AtAp", planCircularization@:bind(mnvCircularize:Ap),
		"AtPe", planCircularization@:bind(mnvCircularize:Pe)
	)).
}