{
	// local orbitalMechanics is import("mech/orbitalMechanics-v1").
	local velocityChangeToNode is import("mnv/velocityChangeToNode-v1").

	function circularizeAtUT {
		parameter burnUT.

		if burnUT >= time:seconds + eta:transition {
			return ApiFail("Targeted burn time is outside the current orbit patch").
		}

		if burnUT < time:seconds {
			return ApiFail("Targeted burn time is in the past").
		}

		local positionAtNode is positionAt(ship, burnUT) - body:position.
		local velocityAtNode is velocityAt(ship, burnUT):orbit.

		local vecRadial is positionAtNode:normalized.
		local vecPrograde is vxcl(vecRadial, velocityAtNode):normalized.
		
		// local burnRadius is positionAtNode:mag.
		// local burnAltitude is burnRadius - body:radius.
		// local circularSpeed is orbitalMechanics:v(burnAltitude, burnRadius).
		local circularSpeed is sqrt(body:mu / positionAtNode:mag).
		local circularVelocityAtNode is vecPrograde * circularSpeed.

		local mnv is velocityChangeToNode(
			burnUT,
			positionAtNode,
			velocityAtNode,
			circularVelocityAtNode
		).

		return ApiOK(mnv).
	}

	export(circularizeAtUT@).
}