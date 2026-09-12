{
	local awaitSteering is import("sys/steering-v1"):awaitSteering.
	local getApproachVector is{
		parameter targetVessel,approachSpeed.
		return targetVessel:velocity:orbit-velocity:orbit+targetVessel:position:normalized*approachSpeed.
	}.
	local setRelativeVelocity is{
		parameter targetVessel,approachSpeed.
		local lock approachVector to getApproachVector(targetVessel,approachSpeed).
		lock steering to approachVector.
		awaitSteering().
		lock throttle to choose 0 if ship:availableThrust=0 else min(1,min(1,approachVector:mag/2)*mass/ship:availableThrust).
		wait until approachVector:mag<.1.
		lock throttle to 0.
		unlock steering.
	}.
	export({
		parameter targetVessel,targetSeparation,approachSpeed.
		until targetVessel:distance<=targetSeparation{
			setRelativeVelocity(targetVessel,approachSpeed).
			lock steering to getApproachVector(targetVessel,0).
			wait until targetVessel:distance<=targetSeparation or vdot(targetVessel:position,targetVessel:velocity:orbit-velocity:orbit)>=0.
			setRelativeVelocity(targetVessel,0).
			lock steering to getApproachVector(targetVessel,approachSpeed).
			wait 0.
		}
	}).
}