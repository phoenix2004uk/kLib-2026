wait until ship:unpacked.
core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
set ship:control:pilotmainthrottle to 0.
sas off.
set config:ipu to 200.
clearScreen.
{
	local importStack is stack().
	local imported is lex().
	global import is {
		parameter libFile.
		if imported:haskey(libFile) return imported[libFile].
		copyPath("0:/klib/" + libFile + ".ks", "1:/klib/" + libFile + ".ks").
		runPath("/klib/" + libFile).
		local object is importStack:pop.
		set imported[libFile] to object.
		return object.
	}.
	global export is {
		parameter object.
		importStack:push(object).
	}.

	local ApiResult is {
		parameter success, value is success, message is "".
		return lex(
			"ok", success,
			"val", value,
			"msg", message
		).
	}.
	global ApiOK is {
		parameter value, message is "".
		return ApiResult(true, value, message).
	}.
	global ApiFail is {
		parameter message, value is false.
		return ApiResult(false, value, message).
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
		copyPath("0:" + missionFilepath + ".ks", "1:/main.ks").
	}
}
runOncePath("/main").