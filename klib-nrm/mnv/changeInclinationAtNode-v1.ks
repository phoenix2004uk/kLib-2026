{
	local orbitalParameters is import("mech/orbitalParameters-v1").
	local orbitalMechanics is import("mech/orbitalMechanics-v1").
	local velocityChangeToNode is import("mnv/velocityChangeToNode-v1").
	local changeInclination is {
		parameter whichNode, targetInclination, thetaLim is 0.25.
		local theta is targetInclination - obt:inclination.
		if abs(theta) <= thetaLim return ApiOK(node(time:seconds, 0, 0, 0), "Inclination is within " + thetaLim + "° limit of " + targetInclination + "°: " + obt:inclination + "°").
		if obt:eccentricity = 1 return ApiFail("Parabolic trajectories are not supported").
		local selectedNode is whichNode.
		local nodes is lex().
		local elliptical is obt:eccentricity < 1.
		local Van is orbitalParameters:Van().
		local Vdn is orbitalParameters:Vdn().
		local Vlim is orbitalParameters:Vlim().
		local hasAN is elliptical or abs(Van) < Vlim.
		local hasDN is elliptical or abs(Vdn) < Vlim.
		local etaAN is 0.
		local etaDN is 0.
		local now is time:seconds.
		if hasAN {
			if elliptical set etaAN to orbitalMechanics:etaAN().
			else set etaAN to orbitalMechanics:etaANh().
			if etaAN < 0 or etaAN > eta:transition set hasAN to false.
			else set nodes["AN"] to now + etaAN.
		}
		if hasDN {
			if elliptical set etaDN to orbitalMechanics:etaDN().
			else set etaDN to orbitalMechanics:etaDNh().
			if etaDN < 0 or etaDN > eta:transition set hasDN to false.
			else set nodes["DN"] to now + etaDN.
		}
		if hasAN and not hasDN {
			set nodes["next"] to "AN".
			set nodes["last"] to "AN".
			set nodes["high"] to "AN".
			set nodes["low"] to "AN".
		}
		if hasDN and not hasAN {
			set nodes["next"] to "DN".
			set nodes["last"] to "DN".
			set nodes["high"] to "DN".
			set nodes["low"] to "DN".
		}
		if hasAN and hasDN {
			if etaAN <= etaDN {
				set nodes["next"] to "AN".
				set nodes["last"] to "DN".
			}
			else {
				set nodes["next"] to "DN".
				set nodes["last"] to "AN".
			}
			if orbitalParameters:Vr(Van) <= orbitalParameters:Vr(Vdn) {
				set nodes["low"] to "AN".
				set nodes["high"] to "DN".
			}
			else {
				set nodes["low"] to "DN".
				set nodes["high"] to "AN".
			}
		}
		if not (hasAN or hasDN) return ApiFail("There is no AN or DN on the current trajectory").
		if whichNode <> "AN" and whichNode <> "DN" {
			if nodes:hasKey(whichNode) set selectedNode to nodes[whichNode].
			else return ApiFail("Not a valid node selection: " + whichNode).
		}
		if not nodes:hasKey(selectedNode) return ApiFail(selectedNode + " is undefined on the current trajectory").
		if selectedNode = "DN" set theta to -theta.
		local utNode is nodes[selectedNode].
		local futureShipRaw is positionAt(ship, utNode).
		local shipVelocityAtNode is velocityAt(ship, utNode):orbit.
		return ApiOK(velocityChangeToNode(
			utNode,
			futureShipRaw - body:position,
			shipVelocityAtNode,
			angleAxis(-theta, (futureShipRaw - body:position):normalized) * shipVelocityAtNode
		)).
	}.
	export(lex(
		"AN", changeInclination:bind("AN"),
		"DN", changeInclination:bind("DN"),
		"next", changeInclination:bind("next"),
		"last", changeInclination:bind("last"),
		"highest", changeInclination:bind("high"),
		"lowest", changeInclination:bind("low")
	)).
}