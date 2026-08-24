// #include "../kldr-stub.ks"
{
	local OrbitalMechanics is import("OrbitalMechanics-v1").
	local OrbitalParameters is import("OrbitalParameters-v1").

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
		// we need to add twice the angle difference of the next node to the other node
		// now we know which node is the next node
		if angNodes > 90 {
			set thetaDN to thetaDN + 2*thetaAN.
			set result["next"] to "AN".
			set result["other"] to "DN".
		}
		else {
			set thetaAN to thetaAN + 2*thetaDN.
			set result["next"] to "DN".
			set result["other"] to "AN".
		}

		set result["AN"] to ship:orbit:trueanomaly + thetaAN.
		set result["DN"] to ship:orbit:trueanomaly + thetaDN.
		if orbit:eccentricity < 1 {
			set result["AN"] to mod(360 + result["AN"], 360).
			set result["DN"] to mod(360 + result["DN"], 360).
		}

		return result.
	}

	// if ship is on a hyberbolic trajectory, can return false if ship has passed both nodes
	// otherwise adds the calculated maneuver node and returns true
	function matchInclination {
		parameter targetOrbitable is target.

		local theta is getRelativeInclination(targetOrbitable).
		local nodes is getRelativeNodes(targetOrbitable).
		local whichNode is nodes["other"].
		local nodeTrueAnomaly is nodes[whichNode].
		local etaNextNode is 0.
		if orbit:eccentricity < 1 {
			set etaNextNode to OrbitalMechanics:etaV(nodeTrueAnomaly).
		}
		else {
			set whichNode to nodes["next"].
			set nodeTrueAnomaly to nodes[whichNode].
			// if we're hyperbolic, test node anomaly is within limit otherwise switch node
			if (nodeTrueAnomaly < -abs(OrbitalParameters:Vlim()) or nodeTrueAnomaly > abs(OrbitalParameters:Vlim())) {
				set whichNode to nodes["other"].
				set nodeTrueAnomaly to nodes[whichNode].
			}
			// if other node is also outside limit, we have passed both nodes already
			if (nodeTrueAnomaly < -abs(OrbitalParameters:Vlim()) or nodeTrueAnomaly > abs(OrbitalParameters:Vlim())) {
				return false.
			}
			set etaNextNode to OrbitalMechanics:etaVh(nodeTrueAnomaly).
		}
		local timeNextNode is time:seconds + etaNextNode.
		if whichNode = "DN" set theta to -theta.

		// 1. Fetch exact raw future positions/velocities at the same moment in time
		local futureShipRaw is positionAt(ship, timeNextNode).
		local shipVelocityAtNode is velocityAt(ship, timeNextNode):orbit.

		// 2. Build the correct future-relative coordinate system
		local vecPrograde is shipVelocityAtNode:normalized.
		local vecRadialOut is (futureShipRaw - body:position):normalized.
		local vecNormal is -vcrs(vecRadialOut, vecPrograde):normalized.
		local vecTransverse is vcrs(vecNormal, vecPrograde):normalized.

		// 3. Perform the rotation on the future velocity
		local rotatedVelocityVector is angleAxis(theta, vecRadialOut) * shipVelocityAtNode.
		local dV is rotatedVelocityVector - shipVelocityAtNode.

		{
			// vecDraw debugging
			clearVecDraws().
			vecDraw(V(0,0,0), {return futureShipRaw.}, BLUE, "ship future", 1, true, 0.1).
			vecDraw(V(0,0,0), {return body:position.}, BLUE, "body now", 1, true, 0.1).
			vecDraw(V(0,0,0), {return futureShipRaw - body:position.}, BLUE, "body future", 1, true, 0.1).
			vecDraw({return futureShipRaw.}, {return vecPrograde * shipVelocityAtNode:mag.}, YELLOW, "prograde", 100, true, 0.0005).
			vecDraw({return futureShipRaw.}, {return vecNormal * shipVelocityAtNode:mag.}, MAGENTA, "normal", 100, true, 0.0005).
			vecDraw({return futureShipRaw.}, {return vecRadialOut * shipVelocityAtNode:mag.}, CYAN, "radial", 100, true, 0.0005).
			vecDraw({return futureShipRaw.}, {return vecTransverse * shipVelocityAtNode:mag.}, BLUE, "transverse", 100, true, 0.0005).
			vecDraw({return futureShipRaw.}, {return rotatedVelocityVector.}, GREEN, "theta", 100, true, 0.0005).
		}

		// 4. Project the deltaV vector onto each of the maneuver node's radial/normal/prograde vectors
		local dvRadial is vdot(dV, vecTransverse).
		local dvNormal is vdot(dV, vecNormal).
		local dvPrograde is vdot(dV, vecPrograde).

		local mnv is node(timeNextNode, dvRadial, dvNormal, dvPrograde).
		add mnv.
		return true.
	}
	export(matchInclination@).
}