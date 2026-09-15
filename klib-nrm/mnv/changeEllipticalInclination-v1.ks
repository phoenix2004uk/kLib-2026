{
	local orbitalParameters is import("mech/orbitalParameters-v1").
	local orbitalMechanics is import("mech/orbitalMechanics-v1").
	local velocityChangeToNode is import("mnv/velocityChangeToNode-v1").
	local changeInclination is{
		parameter targetInclination,utNode,errorMargin,isDN is false.
		if obt:inclination>=targetInclination-errorMargin and obt:inclination<=targetInclination+errorMargin return ApiOK(node(time:seconds,0,0,0),"Inclination is within "+errorMargin+"° limit of "+targetInclination+"°: "+obt:inclination+"°").
		if obt:eccentricity>=1 return ApiFail("Change inclination is not supported on an open orbit: e="+round(obt:eccentricity,4)).
		local theta is targetInclination-obt:inclination.
		if isDN set theta to-theta.
		local futureShipRaw is positionAt(ship,utNode).
		local shipVelocityAtNode is velocityAt(ship,utNode):orbit.
		return ApiOK(velocityChangeToNode(
			utNode,
			futureShipRaw-body:position,
			shipVelocityAtNode,
			angleAxis(-theta,(futureShipRaw-body:position):normalized)*shipVelocityAtNode
		)).
	}.
	export(lex(
		"AN",{
			parameter targetInclination,errorMargin is .25.
			return changeInclination(targetInclination,time:seconds+orbitalMechanics:etaAN(),errorMargin).
		},
		"DN",{
			parameter targetInclination,errorMargin is .25.
			return changeInclination(targetInclination,time:seconds+orbitalMechanics:etaDN(),errorMargin,true).
		},
		"next",{
			parameter targetInclination,errorMargin is .25.
			local utAN is time:seconds+orbitalMechanics:etaAN().
			local utDN is time:seconds+orbitalMechanics:etaDN().
			if utDN<utAN return changeInclination(targetInclination,utDN,errorMargin,true).
			return changeInclination(targetInclination,utAN,errorMargin,false).
		},
		"highest",{
			parameter targetInclination,errorMargin is .25.
			local Van is orbitalParameters:Van().
			local Vdn is orbitalParameters:Vdn().
			if orbitalParameters:Vr(Vdn)>orbitalParameters:Vr(Van)return changeInclination(targetInclination,time:seconds+orbitalMechanics:etaV(Vdn),errorMargin,true).
			return changeInclination(targetInclination,time:seconds+orbitalMechanics:etaV(Van),errorMargin).
		}
	)).
}