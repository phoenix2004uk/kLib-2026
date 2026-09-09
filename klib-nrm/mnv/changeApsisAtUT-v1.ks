{
	local velocityChangeToNode is import("mnv/velocityChangeToNode-v1").
	function changeApsisAtUT{
		parameter targetApsis,burnUT,changePeriapsis.
		if burnUT<=time:seconds return ApiFail("Maneuver UT must be in the future").
		local burnOrbit is orbitAt(ship,burnUT).
		if burnOrbit:body<>body return ApiFail("Apsis maneuver must remain in the current SOI").
		if changePeriapsis and burnOrbit:eccentricity>=1 return ApiFail("Cannot preserve apoapsis on an open trajectory").
		local targetPeriapsis is burnOrbit:periapsis.
		local targetApoapsis is targetApsis.
		if changePeriapsis{
			set targetPeriapsis to targetApsis.
			set targetApoapsis to burnOrbit:apoapsis.
		}
		if targetPeriapsis+body:radius<=0 return ApiFail("Target periapsis radius must be positive").
		if targetApoapsis<targetPeriapsis return ApiFail("Target apoapsis cannot be below target periapsis").
		local vecPositionAtBurn is positionAt(ship,burnUT)-body:position.
		local vecVelocityAtBurn is velocityAt(ship,burnUT):orbit.
		local radiusAtBurn is vecPositionAtBurn:mag.
		local periapsisRadius is targetPeriapsis+body:radius.
		local apoapsisRadius is targetApoapsis+body:radius.
		if radiusAtBurn<periapsisRadius or radiusAtBurn>apoapsisRadius return ApiFail("Burn position is outside the target orbit apsides").
		local vecRadial is vecPositionAtBurn:normalized.
		local vecTransverse is vxcl(vecRadial,vecVelocityAtBurn).
		if vecTransverse:mag<1e-9 return ApiFail("Orbital plane is undefined at the burn position").
		set vecTransverse to vecTransverse:normalized.
		local targetTransverseSpeed is sqrt(2*body:mu*periapsisRadius*apoapsisRadius/(periapsisRadius+apoapsisRadius))/radiusAtBurn.
		local targetRadialSpeedSquared is 2*body:mu*(1/radiusAtBurn-1/(periapsisRadius+apoapsisRadius))-targetTransverseSpeed^2.
		if targetRadialSpeedSquared<0{
			if targetRadialSpeedSquared>-1e-3 set targetRadialSpeedSquared to 0.
			else return ApiFail("Target orbit is unreachable from the burn position").
		}
		local radialSign is 1.
		if vdot(vecVelocityAtBurn,vecRadial)<0 set radialSign to-1.
		return ApiOK(velocityChangeToNode(burnUT,vecPositionAtBurn,vecVelocityAtBurn,vecRadial*radialSign*sqrt(targetRadialSpeedSquared)+vecTransverse*targetTransverseSpeed)).
	}
	export(lex(
		"Pe",{
			parameter targetPeriapsis,burnUT.
			return changeApsisAtUT(targetPeriapsis,burnUT,true).
		},
		"Ap",{
			parameter targetApoapsis,burnUT.
			return changeApsisAtUT(targetApoapsis,burnUT,false).
		}
	)).
}