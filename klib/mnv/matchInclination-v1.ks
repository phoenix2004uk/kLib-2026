{
	local OrbitalMechanics is import("orbitalMechanics-v1").
	local OrbitalParameters is import("orbitalParameters-v1").
	local velocityChangeToNode is import("mnv/velocityChangeToNode-v1").

	function getRelativeInclination {
		parameter targetOrbitable is target, atTime is time:seconds.

		local rShip is positionAt(ship, atTime) - positionAt(body, atTime).
		local vShip is velocityAt(ship, atTime):orbit.
		local rTarget is targetOrbitable:position - body:position.
		local vTarget is targetOrbitable:velocity:orbit.

		// angular momentum, h = r * v
		local hShip is vcrs(rShip, vShip).
		local hTarget is vcrs(rTarget, vTarget).

		return vang(hShip, hTarget).
	}

	// returns the trueanomaly of the AN and DN nodes
	// for elliptical orbits, these are wrapped to 0..360
	// returns a lex containing:
	// - AN, DN: the trueanomly of each node
	// - first, last: will contain "AN" and "DN" based on altitude eta
	// - high, low: will contain "AN" and "DN" based on trueanomly altitude
	function getRelativeNodes {
		parameter targetOrbitable is target.

		local rShip is ship:position - body:position.
		local vShip is ship:velocity:orbit.
		local rTarget is targetOrbitable:position - body:position.
		local vTarget is targetOrbitable:velocity:orbit.

		// angular momentum, h = r * v
		local hShip is vcrs(rShip, vShip).
		local hTarget is vcrs(rTarget, vTarget).

		// line of nodes
		local vNodes is vcrs(hShip, hTarget):normalized.

		// vector normal of line of nodes and position vector
		local vNodesNormal is vcrs(hShip, vNodes):normalized.

		// angle between nodes normal and position tells us which half of the orbit we are in
		local angNodes is vang(rShip, vNodesNormal).

		// angle between current position and line of nodes is the AN
		local thetaAN is vang(vNodes, rShip).
		local thetaDN is vang(-vNodes, rShip).

		local result is lex().
		// since angle to AN/DN is relative, depending on which half of the orbit we are in
		// we need to add twice the angle difference of the first node to the last node
		// now we know which node is the first node
		if angNodes > 90 {
			set thetaDN to thetaDN + 2*thetaAN.
			set result["first"] to "AN".
			set result["last"] to "DN".
		}
		else {
			set thetaAN to thetaAN + 2*thetaDN.
			set result["first"] to "DN".
			set result["last"] to "AN".
		}

		set result["AN"] to ship:orbit:trueanomaly + thetaAN.
		set result["DN"] to ship:orbit:trueanomaly + thetaDN.
		if orbit:eccentricity < 1 {
			set result["AN"] to mod(360 + result["AN"], 360).
			set result["DN"] to mod(360 + result["DN"], 360).
		}
		
		// altitude of each node
		// we use abs() just so the logical selection of low/high makes sense to the user,
		// so that a node beyond the limit on a hyperbolic trajectory (negative Vr) will still be presented as the "high" orbit orbit
		local rAN is abs(OrbitalParameters:Vr(result["AN"])).
		local rDN is abs(OrbitalParameters:Vr(result["DN"])).
		if rAN < rDN {
			set result["low"] to "AN".
			set result["high"] to "DN".
		}
		else {
			set result["low"] to "DN".
			set result["high"] to "AN".
		}

		return result.
	}

	// whichNode can be one of: AN, DN, first, last, low, high
	// returns an ApiOK with the created node on success, it does not add the node to the flight plan
	// returns an ApiFail if:
	//  - whichNode is not valid
	//  - ship is on a hyberbolic trajectory and trueanomaly of selected node is beyond limit
	function matchInclination {
		parameter targetOrbitable is target, whichNode is "first", thetaLim is 1e-2.

		local theta is getRelativeInclination(targetOrbitable).
		if theta < thetaLim {
			local mnv is node(time:seconds, 0, 0, 0).
			return ApiOK(mnv, "Relative inclination is within limit ("+round(thetaLim,4)+"): " + round(theta,4)).
		}
		local nodes is getRelativeNodes(targetOrbitable).
		local selectedNode is "".
		if whichNode = "AN" or whichNode = "DN" {
			set selectedNode to whichNode.
		}
		else if nodes:haskey(whichNode) {
			set selectedNode to nodes[whichNode].
		}
		else {
			return ApiFail("Not a valid node selection: " + whichNode).
		}
		local nodeTrueAnomaly is nodes[selectedNode].
		local etaNextNode is 0.
		if orbit:eccentricity < 1 {
			set etaNextNode to OrbitalMechanics:etaV(nodeTrueAnomaly).
		}
		else {
			// if we're hyperbolic, ensure node anomaly is within limit otherwise return false
			if (nodeTrueAnomaly < -abs(OrbitalParameters:Vlim()) or nodeTrueAnomaly > abs(OrbitalParameters:Vlim())) {
				return ApiFail("The trueanomaly is beyond the hyperbolic limit for the selected node: " + selectedNode).
			}
			set etaNextNode to OrbitalMechanics:etaVh(nodeTrueAnomaly).
		}
		local timeNextNode is time:seconds + etaNextNode.
		if selectedNode = "DN" set theta to -theta.

		local futureShipRaw is positionAt(ship, timeNextNode).
		local shipVelocityAtNode is velocityAt(ship, timeNextNode):orbit.

		local vecRadial is (futureShipRaw - body:position):normalized. // true body-radial direction
		local rotatedVelocityVector is angleAxis(theta, vecRadial) * shipVelocityAtNode.

		local mnv is velocityChangeToNode(
			timeNextNode,
			futureShipRaw - body:position,
			shipVelocityAtNode,
			rotatedVelocityVector
		).
		// local mnv is node(timeNextNode, dvRadial, dvNormal, dvPrograde).
		return ApiOK(mnv, "Maneuver planned").
	}
	export(matchInclination@).
}