{
	local velocityChangeToNode is import("mnv/velocityChangeToNode-v1").

	// Create a maneuver at an arbitrary future UT that changes one apsis
	// while preserving the altitude of the opposite apsis and the orbital plane.
	//
	// The burn position must lie within the radial range of the target orbit.
	// Changing Pe requires an existing apoapsis; changing Ap can also capture
	// an open trajectory while preserving its periapsis.
	function changeApsisAtUT {
		parameter targetApsis, burnUT, changePeriapsis.

		if burnUT <= time:seconds {
			return ApiFail("Maneuver UT must be in the future").
		}

		local burnOrbit is orbitAt(ship, burnUT).
		if burnOrbit:body <> body {
			return ApiFail("Apsis maneuver must remain in the current SOI").
		}

		// Pe cannot be changed while preserving Ap if the current trajectory
		// has no apoapsis.
		if changePeriapsis and burnOrbit:eccentricity >= 1 {
			return ApiFail("Cannot preserve apoapsis on an open trajectory").
		}

		local targetPeriapsis is
			choose targetApsis
			if changePeriapsis
			else burnOrbit:periapsis.
		local targetApoapsis is
			choose burnOrbit:apoapsis
			if changePeriapsis
			else targetApsis.

		if targetPeriapsis + body:radius <= 0 {
			return ApiFail("Target periapsis radius must be positive").
		}
		if targetApoapsis < targetPeriapsis {
			return ApiFail("Target apoapsis cannot be below target periapsis").
		}

		local vecPositionAtBurn is positionAt(ship, burnUT) - body:position.
		local vecVelocityAtBurn is velocityAt(ship, burnUT):orbit.
		local radiusAtBurn is vecPositionAtBurn:mag.

		local periapsisRadius is targetPeriapsis + body:radius.
		local apoapsisRadius is targetApoapsis + body:radius.

		if radiusAtBurn < periapsisRadius
		or radiusAtBurn > apoapsisRadius {
			return ApiFail("Burn position is outside the target orbit apsides").
		}

		// Target ellipse:
		// a = (rp + ra) / 2
		// h^2 = mu * p = 2*mu*rp*ra/(rp+ra)
		//
		// At the burn radius:
		// v^2  = mu*(2/r - 1/a)
		// vt   = h/r
		// vr^2 = v^2 - vt^2
		local targetSemiMajorAxis is (periapsisRadius + apoapsisRadius) / 2.
		local targetSpeedSquared is
			body:mu * (
				2 / radiusAtBurn -
				1 / targetSemiMajorAxis
			).
		local targetAngularMomentumSquared is
			2 * body:mu *
			periapsisRadius *
			apoapsisRadius /
			(periapsisRadius + apoapsisRadius).

		local vecRadial is vecPositionAtBurn:normalized.
		local vecTransverse is vxcl(
			vecRadial,
			vecVelocityAtBurn
		).

		if vecTransverse:mag < 1e-9 {
			return ApiFail("Orbital plane is undefined at the burn position").
		}

		set vecTransverse to vecTransverse:normalized.

		local targetTransverseSpeed is
			sqrt(targetAngularMomentumSquared) /
			radiusAtBurn.
		local targetRadialSpeedSquared is
			targetSpeedSquared -
			targetTransverseSpeed^2.

		// Floating-point protection at/very near an apsis.
		if targetRadialSpeedSquared < 0 {
			if targetRadialSpeedSquared > -0.001 {
				set targetRadialSpeedSquared to 0.
			}
			else {
				return ApiFail("Target orbit is unreachable from the burn position").
			}
		}

		// There are two mirror-image target ellipses through the burn point.
		// Retain the current radial direction to select the lower-dV solution.
		local radialSign is
			choose -1
			if vdot(vecVelocityAtBurn, vecRadial) < 0
			else 1.
		local targetRadialSpeed is
			radialSign * sqrt(targetRadialSpeedSquared).

		local vecTargetVelocity is
			vecRadial * targetRadialSpeed +
			vecTransverse * targetTransverseSpeed.

		return ApiOK(velocityChangeToNode(
			burnUT,
			vecPositionAtBurn,
			vecVelocityAtBurn,
			vecTargetVelocity
		)).
	}

	export(lex(
		"Pe", {
			parameter targetPeriapsis, burnUT.
			return changeApsisAtUT(targetPeriapsis, burnUT, true).
		},
		"Ap", {
			parameter targetApoapsis, burnUT.
			return changeApsisAtUT(targetApoapsis, burnUT, false).
		}
	)).
}