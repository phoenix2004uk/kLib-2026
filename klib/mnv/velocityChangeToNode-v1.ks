{
	// Convert a velocity change at a known state into a kOS maneuver node.
	function velocityChangeToNode {
		parameter nodeUT, vecPositionAtNode, vecVelocityAtNode, vecDepartureVelocityAtNode.

		local vecPrograde is vecVelocityAtNode:normalized.
		local vecRadial is vecPositionAtNode:normalized.
		local vecNormal is -vcrs(vecRadial, vecPrograde):normalized.
		local vecTransverse is vcrs(vecNormal, vecPrograde):normalized.
		local deltaV is vecDepartureVelocityAtNode - vecVelocityAtNode.

		return node(
			nodeUT,
			vdot(deltaV, vecTransverse),
			vdot(deltaV, vecNormal),
			vdot(deltaV, vecPrograde)
		).
	}

	export(velocityChangeToNode@).
}