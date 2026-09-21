{
	export({
		parameter nodeUT, vecPositionAtNode, vecVelocityAtNode, vecDepartureVelocityAtNode.
		local vecPrograde is vecVelocityAtNode:normalized.
		local vecNormal is -vcrs(vecPositionAtNode:normalized, vecPrograde):normalized.
		local deltaV is vecDepartureVelocityAtNode - vecVelocityAtNode.
		return node(
			nodeUT,
			deltaV * vcrs(vecNormal, vecPrograde):normalized,
			deltaV * vecNormal,
			deltaV * vecPrograde
		).
	}).
}