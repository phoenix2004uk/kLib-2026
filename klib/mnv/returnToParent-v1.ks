{
	local OrbitalMechanics is import("mech/orbitalMechanics-v1").
	local OrbitalParameters is import("mech/orbitalParameters-v1").
	local seekNode is import("mnv/seekNode-v1").

	// TODO: currently only `bodyOrbitalVelocity` is adjusted by a specified `burnUT`, we would also need to adjust: `moonOrbitAltitude`, `moonSpeed` and `returnSemiMajorAxis` (derived from `moonOrbitAltitude`)
	function getReturnNode {
		parameter targetPeriapsis, burnUT is 0.

		local parentBody is body:body.

		// Construct the parent-body return ellipse
		local moonOrbitAltitude is body:orbit:semimajoraxis - parentBody:radius.
		local returnSemiMajorAxis is OrbitalParameters:a(moonOrbitAltitude, targetPeriapsis, parentBody).

		// Parent-relative speed of moon, vs speed required at apoapsis of the return ellipse
		local moonSpeed is OrbitalMechanics:v(moonOrbitAltitude, body:orbit:semimajoraxis, parentBody).
		local returnSpeed is OrbitalMechanics:v(moonOrbitAltitude, returnSemiMajorAxis, parentBody).
		local excessSpeed is moonSpeed - returnSpeed.

		// Construct moon-relative escape hyperbola whose v-infinity provides the required parent-relative velocity reduction
		local parkingSemiMajorAxis is obt:semimajoraxis.
		local parkingAltitude is parkingSemiMajorAxis - body:radius.
		local escapeSemiMajorAxis is -body:mu / excessSpeed^2.
		local escapeSpeed is OrbitalMechanics:v(parkingAltitude, escapeSemiMajorAxis, body).
		local parkingSpeed is OrbitalMechanics:v(parkingAltitude, parkingSemiMajorAxis, body).
		local progradeDeltaV is escapeSpeed - parkingSpeed.

		// Hyperbolic asymptote angle from escape periapsis
		local escapeEccentricity is 1 - parkingSemiMajorAxis / escapeSemiMajorAxis.
		local escapeTrueAnomaly is OrbitalParameters:Vlim(escapeEccentricity).

		// Desired outgoing Vlim is opposite of moon's motion around it's parent, so project it into the vessel's orbital plane
		local orbitNormal is OrbitalMechanics:h(ship):normalized.
		local bodyOrbitalVelocity is
			choose body:velocity:orbit
			if burnUT = 0
			else velocityAt(body, burnUT):orbit.
		local escapeDirection is vxcl(orbitNormal, -bodyOrbitalVelocity):normalized.

		// Move backwards by the hyperbolic asymptote angle to find the required radius vector at escape periapsis
		local burnRadial is
			escapeDirection * cos(escapeTrueAnomaly)
			- vcrs(orbitNormal, escapeDirection) * sin(escapeTrueAnomaly).

		// Forwrd angular distance around the parking orbit from the present position to the burn radius
		local currentRadial is up:vector.
		local burnAngle is mod(
			arctan2(
				vdot(
					vcrs(currentRadial, burnRadial),
					orbitNormal
				),
				vdot(currentRadial, burnRadial)
			) + 360,
			360
		).
		set burnUT to time:seconds + OrbitalMechanics:dtV(burnAngle).

		return node(burnUT, 0, 0, progradeDeltaV).
	}

	function returnFromMoon {
		parameter targetPeriapsis.

		local mnv is getReturnNode(targetPeriapsis).
		// refine the node by creating it again based on the original calculated burnUT, since velocity vectors will have moved
		set mnv to getReturnNode(targetPeriapsis, mnv:time).

		add mnv.

		local largestPeriapsisError is body:orbit:apoapsis + body:body:radius + body:soiradius.
		local targetPeriapsisRadius is targetPeriapsis + body:body:radius.
		seekNode(mnv, list("prograde"), {
			parameter candidate.

			if not candidate:orbit:hasNextPatch {
				return -largestPeriapsisError - (body:soiradius - (candidate:orbit:apoapsis + body:radius)).
			}
			return targetPeriapsisRadius - (candidate:orbit:nextPatch:periapsis + body:body:radius).
		}).

		// Check if we still leave SOI
		if not mnv:orbit:hasNextPatch {
			return ApiFail("Failed to find an escape trajectory", false).
		}

		// Check if we encounter another body before parent periapsis
		local parentPatch is mnv:orbit:nextPatch.
		if parentPatch:hasNextPatch and parentPatch:eta:transition < parentPatch:eta:periapsis {
			return ApiFail("We will encounter another body before periapsis: " + parentPatch:nextPatch:body, true).
		}
		return ApiOK().
	}

	export(returnFromMoon@).
}