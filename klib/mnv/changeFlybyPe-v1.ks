{
	local velocityChangeToNode is import("mnv/velocityChangeToNode-v1").

	// Attempt to create a trim maneuver in `leadTime` seconds to correct the current SOI fly-by periapsis.
	// post-burn `periapsis` should be within `errorMargin` meters of `targetPeriapsis`.
	function changeFlybyPeriapsis {
		parameter targetPeriapsis, leadTime is 60, errorMargin is 100.

		local burnTime is time:seconds + leadTime.

		if (abs(obt:periapsis - targetPeriapsis) <= errorMargin) {
			return ApiOK(node(burnTime,0,0,0), "Fly-by periapsis is within limit ("+round(errorMargin,0)+"): "+round(obt:periapsis,1)).
		}

		if obt:eccentricity <= 1 {
			return ApiFail("Error: changeFlybyPeriapsis requires a hyperbolic trajectory.").
		}
		
		if eta:periapsis <= leadTime {
			return ApiFail("Fly-by trim maneuver must be performed before periapsis; lead time = " + leadTime).
		}

		local vecPositionAtBurn is positionAt(ship, burnTime) - body:position.
		local vecVelocityAtBurn is velocityAt(ship, burnTime):orbit.
		local radiusAtBurn is vecPositionAtBurn:mag.
		local speedAtBurn is vecVelocityAtBurn:mag.
		local targetRadius is targetPeriapsis + body:radius.

		if targetRadius > radiusAtBurn {
			return ApiFail("Target periapsis is above the burn position").
		}

		local specificEnergy is speedAtBurn^2 / 2 - body:mu / radiusAtBurn.
		local targetAngularMomentumSquared is
			2 * specificEnergy * targetRadius^2 +
			2 * body:mu * targetRadius.

		// this should not be a valid state if e > 1, but we can leave as a sanity check
		if targetAngularMomentumSquared < 0 {
			return ApiFail("Target periapsis is unreachable at current orbital energy").
		}

		local vecRadial is vecPositionAtBurn:normalized.
		local vecTransverse is vxcl(vecRadial, vecVelocityAtBurn):normalized.
		local targetTransverseSpeed is sqrt(targetAngularMomentumSquared) / radiusAtBurn.
		local targetRadialSpeedSquared is speedAtBurn^2 - targetTransverseSpeed^2.

		// this should not be a valid state if e > 1, but we can leave as a sanity check
		if targetRadialSpeedSquared < 0 {
			// to account for floating-point noise, if we're slightly negative then assume 0 instead of failing
			if targetRadialSpeedSquared > -0.001 set targetRadialSpeedSquared to 0.
			else return ApiFail("Target periapsis is unreachable from the burn position at current orbital energy").
		}

		local targetRadialSpeed is -sqrt(targetRadialSpeedSquared).
		local vecTargetVelocity is
			vecRadial * targetRadialSpeed +
			vecTransverse * targetTransverseSpeed.

		return ApiOK(velocityChangeToNode(
			burnTime,
			vecPositionAtBurn,
			vecVelocityAtBurn,
			vecTargetVelocity
		)).
	}

	export(changeFlybyPeriapsis@).
}