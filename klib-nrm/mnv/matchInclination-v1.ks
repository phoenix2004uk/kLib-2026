{
	local OrbitalMechanics is import("orbitalMechanics-v1").
	local OrbitalParameters is import("orbitalParameters-v1").
	local velocityChangeToNode is import("mnv/velocityChangeToNode-v1").
	export({
		parameter targetOrbitable is target,whichNode is"first",thetaLim is 1e-2.
		local theta is vang(OrbitalMechanics:h(ship),OrbitalMechanics:h(targetOrbitable)).
		if theta<thetaLim return ApiOK(node(time:seconds,0,0,0),"Relative inclination is within limit ("+round(thetaLim,4)+"): "+round(theta,4)).
		local selectedNode is"".
		local rShip is ship:position-body:position.
		local hShip is OrbitalMechanics:h(ship).
		local vNodes is vcrs(hShip,OrbitalMechanics:h(targetOrbitable)):normalized.
		local thetaAN is vang(vNodes,rShip).
		local thetaDN is vang(-vNodes,rShip).
		local nodes is lex().
		if vang(rShip,vcrs(hShip, vNodes):normalized)>90{
			set thetaDN to thetaDN+2*thetaAN.
			set nodes["first"]to"AN".
			set nodes["last"]to"DN".
		}
		else{
			set thetaAN to thetaAN+2*thetaDN.
			set nodes["first"]to"DN".
			set nodes["last"]to"AN".
		}
		set nodes["AN"]to ship:orbit:trueanomaly+thetaAN.
		set nodes["DN"]to ship:orbit:trueanomaly+thetaDN.
		if orbit:eccentricity<1{
			set nodes["AN"]to mod(360+nodes["AN"],360).
			set nodes["DN"]to mod(360+nodes["DN"],360).
		}
		if abs(OrbitalParameters:Vr(nodes["AN"]))<abs(OrbitalParameters:Vr(nodes["DN"])){
			set nodes["low"]to"AN".
			set nodes["high"]to"DN".
		}
		else{
			set nodes["low"]to"DN".
			set nodes["high"]to"AN".
		}
		if whichNode="AN"or whichNode="DN"set selectedNode to whichNode.
		else if nodes:haskey(whichNode)set selectedNode to nodes[whichNode].
		else return ApiFail("Not a valid node selection: "+whichNode).
		local nodeTrueAnomaly is nodes[selectedNode].
		local etaNextNode is 0.
		if orbit:eccentricity<1 set etaNextNode to OrbitalMechanics:etaV(nodeTrueAnomaly).
		else{
			if (nodeTrueAnomaly<-abs(OrbitalParameters:Vlim())or nodeTrueAnomaly>abs(OrbitalParameters:Vlim()))return ApiFail("The trueanomaly is beyond the hyperbolic limit for the selected node: "+selectedNode).
			set etaNextNode to OrbitalMechanics:etaVh(nodeTrueAnomaly).
		}
		local timeNextNode is time:seconds+etaNextNode.
		local futureShipRaw is positionAt(ship,timeNextNode).
		local shipVelocityAtNode is velocityAt(ship,timeNextNode):orbit.
		if selectedNode="DN"set theta to -theta.
		return ApiOK(velocityChangeToNode(timeNextNode,futureShipRaw-body:position,shipVelocityAtNode,angleAxis(theta,(futureShipRaw-body:position):normalized)*shipVelocityAtNode),"Maneuver planned").
	}).
}