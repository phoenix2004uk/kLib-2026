{
	local velocityChangeToNode is import("mnv/velocityChangeToNode-v1").
	export({
		parameter burnUT.
		if burnUT >= time:seconds + eta:transition return ApiFail("Targeted burn time is outside the current orbit patch").
		if burnUT < time:seconds return ApiFail("Targeted burn time is in the past").
		local positionAtNode is positionAt(ship, burnUT) - body:position.
		local velocityAtNode is velocityAt(ship, burnUT):orbit.
		return ApiOK(velocityChangeToNode(
			burnUT,
			positionAtNode,
			velocityAtNode,
			vxcl(positionAtNode:normalized, velocityAtNode):normalized * sqrt(body:mu / positionAtNode:mag)
		)).
	}).
}