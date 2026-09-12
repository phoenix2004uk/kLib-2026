{
	local isSteeringSettled is{
		if not steeringManager:enabled return true.
		if abs(steeringManager:angleError)>=.25 return false.
		return steeringManager:pitchPid:changeRate^2+steeringManager:yawPid:changeRate^2<constant:degToRad^2/16.
	}.
	local isRollSettled is{
		if not steeringManager:enabled return true.
		if abs(steeringManager:angleError)>=steeringManager:rollControlAngleRange or abs(steeringManager:rollError)>=1 return false.
		return abs(steeringManager:rollPid:changeRate)<constant:degToRad.
	}.
	local isSettled is{
		parameter includeRoll is false.
		return isSteeringSettled()and(not includeRoll or isRollSettled()).
	}.
	local awaitSteering is{
		parameter includeRoll is false.
		wait 0.
		wait until isSettled(includeRoll).
	}.
	export(lex(
		"awaitSteering",awaitSteering,
		"awaitRoll",{awaitSteering(true).},
		"isSteeringSettled",isSteeringSettled,
		"isRollSettled",isRollSettled,
		"isSettled",isSettled
	)).
}