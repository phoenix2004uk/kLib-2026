wait until ship:unpacked.
core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
set ship:control:pilotmainthrottle to 0.
sas off.
clearScreen.
{
	function copyBest {
		parameter src, dst is src.

		local ksPath is choose src + "-min" if exists("0:" + src + "-min.ks") else src.
		compile "0:" + ksPath.
		local ks is open("0:" + ksPath + ".ks").
		local ksm is open("0:" + ksPath + ".ksm").
		if ksm:size < ks:size {
			copyPath("0:" + ksPath + ".ksm", "1:" + dst + ".ksm").
		}
		else {
			copyPath("0:" + ksPath + ".ks", "1:" + dst + ".ks").
		}
		deletePath("0:" + ksPath + ".ksm").
	}
	local importStack is stack().
	local imported is lex().
	global import is {
		parameter libFile.
		if imported:haskey(libFile) return imported[libFile].
		copyBest("/klib/" + libFile).
		runPath("/klib/" + libFile).
		local object is importStack:pop.
		set imported[libFile] to object.
		return object.
	}.
	global export is {
		parameter object.
		importStack:push(object).
	}.

	local missionFilepath is "/missions/" + (choose ship:name if not core:tag else core:tag).
	if status = "PRELAUNCH" {
		if not homeConnection:isconnected {
			print "Error! No KSC Connection".
			shutdown.
		}
		if not exists("0:" + missionFilepath) {
			print "Error! No mission script: " + missionFilepath.
			shutdown.
		}
	}
	if homeConnection:isconnected and exists("0:" + missionFilepath) {
		copyBest(missionFilepath, "/main").
	}
}
runOncePath("/main").