{
	local velocityChangeToNode is import("mnv/velocityChangeToNode-v1").
	export({
		parameter targetPeriapsis,leadTime is 60,errorMargin is 100.
		local burnTime is time:seconds+leadTime.
		if (abs(obt:periapsis-targetPeriapsis)<=errorMargin)return ApiOK(node(burnTime,0,0,0),"Fly-by periapsis is within limit ("+round(errorMargin,0)+"): "+round(obt:periapsis,1)).
		if obt:eccentricity<=1 return ApiFail("Error: changeFlybyPeriapsis requires a hyperbolic trajectory.").
		if eta:periapsis<=leadTime return ApiFail("Fly-by trim maneuver must be performed before periapsis; lead time = "+leadTime).
		local vecPositionAtBurn is positionAt(ship,burnTime)-body:position.
		local vecVelocityAtBurn is velocityAt(ship,burnTime):orbit.
		local radiusAtBurn is vecPositionAtBurn:mag.
		local speedAtBurn is vecVelocityAtBurn:mag.
		local targetRadius is targetPeriapsis+body:radius.
		if targetRadius>radiusAtBurn return ApiFail("Target periapsis is above the burn position").
		local targetAngularMomentumSquared is targetRadius*(speedAtBurn^2*targetRadius+2*body:mu*(1-targetRadius/radiusAtBurn)).
		if targetAngularMomentumSquared<0 return ApiFail("Target periapsis is unreachable at current orbital energy").
		local vecRadial is vecPositionAtBurn:normalized.
		local targetTransverseSpeed is sqrt(targetAngularMomentumSquared)/radiusAtBurn.
		local targetRadialSpeedSquared is speedAtBurn^2-targetTransverseSpeed^2.
		if targetRadialSpeedSquared<0{
			if targetRadialSpeedSquared>-0.001 set targetRadialSpeedSquared to 0.
			else return ApiFail("Target periapsis is unreachable from the burn position at current orbital energy").
		}
		return ApiOK(velocityChangeToNode(burnTime,vecPositionAtBurn,vecVelocityAtBurn,vecRadial*-sqrt(targetRadialSpeedSquared)+vxcl(vecRadial,vecVelocityAtBurn):normalized*targetTransverseSpeed)).
	}).
}