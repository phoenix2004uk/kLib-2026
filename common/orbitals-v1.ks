global function VisViva {
	parameter
		altQuery is altitude,
		r1 is periapsis,
		r2 is apoapsis,
		whichBody is body.

	local rQuery is altQuery + whichBody:radius.
	local smaQuery is (r1 + r2) / 2 + whichBody:radius.

	return sqrt( whichBody:mu * ( 2/rQuery - 1/smaQuery ) ).
}

global function getOrbitPeriod {
	parameter Ap, Pe.
	local sma is (Ap + Pe) / 2 + body:radius.
	return 2 * constant:pi * sqrt(sma^3 / body:mu).
}

global function getEccentricAnomaly {
	parameter trueAnomalyDegrees.

	local eccentricAnomalyDegrees is arccos( (ship:orbit:eccentricity + cos(trueAnomalyDegrees)) / (1 + ship:orbit:eccentricity * cos(trueAnomalyDegrees))).
	if (trueAnomalyDegrees > 180) {
		set eccentricAnomalyDegrees to 360 - eccentricAnomalyDegrees.
	}
	return eccentricAnomalyDegrees.
}

global function getMeanAnomaly {
	parameter eccentricAnomalyDegrees.

	return eccentricAnomalyDegrees - ship:orbit:eccentricity * sin(eccentricAnomalyDegrees) * constant:radToDeg.
}

global function getAnomalyRadius {
	parameter anomalyDegrees.

	return (ship:orbit:semimajoraxis * (1 - ship:orbit:eccentricity^2)) / (1 + ship:orbit:eccentricity * cos(anomalyDegrees)).
}

global function getAnomalyAltitude {
	parameter anomalyDegrees.
	return getAnomalyRadius(anomalyDegrees) - body:radius.
}

global function getAnomalyEta {
	parameter anomalyDegrees.

	local n is 360 / ship:orbit:period.

	local V0 is ship:orbit:trueanomaly.
	local E0 is getEccentricAnomaly(V0).
	local M0 is getMeanAnomaly(E0).

	local V1 is anomalyDegrees.
	local E1 is getEccentricAnomaly(V1).
	local M1 is getMeanAnomaly(E1).

	local t is (M1 - M0) / n.
	if t < 0 set t to t + ship:orbit:period.
	return t.
}

// returns the relative inclination to the targetOrbitable
// specify atTime as a future time to take into account planned maneuver nodes
global function getRelativeInclination {
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

// finds the relative AN/DN between 2 orbitables
// returns a Lexicon with keys "AN","DN","next","other"
//  - AN/DN: the true anomaly of the AN/DN nodes
//  - next: either "AN" or "DN" depending which is the next node
//  - other: the opposite of next
global function getRelativeNodes {
	parameter targetOrbitable is target.

	local rShip is ship:position - body:position.
	local vShip is ship:velocity:orbit.
	local rTarget is targetOrbitable:position - body:position.
	local vTarget is targetOrbitable:velocity:orbit.

	// angular momentum, h = r * v
	local hShip is vcrs(rShip, vShip).
	local hTarget is vcrs(rTarget, vTarget).

	// line of nodes
	local vNodes is vcrs(hShip, hTarget).

	// vector normal of line of nodes and position vector
	local vNodesNormal is vcrs(hShip, vNodes).

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
	set result["AN"] to mod(360 + ship:orbit:trueanomaly + thetaAN, 360).
	set result["DN"] to mod(360 + ship:orbit:trueanomaly + thetaDN, 360).

	return result.
}

global function getTransferTime {
	parameter targetOrbitable, targetSeparation is 0.

	local tagetAngularSpeed is 360 / targetOrbitable:obt:period.
	local shipAngularSpeed is 360 / ship:obt:period.
	local periodOfTransfer is getOrbitPeriod(targetOrbitable:obt:apoapsis, ship:obt:apoapsis) / 2.
	local targetAngularMovement is tagetAngularSpeed * periodOfTransfer.
	local relativeAngularSpeed is abs(shipAngularSpeed - tagetAngularSpeed).

	local targetAngularPosition is targetOrbitable:obt:lan + targetOrbitable:obt:argumentofperiapsis + targetOrbitable:obt:trueanomaly.
	local shipAngularPosition is ship:obt:lan + ship:obt:argumentofperiapsis + ship:obt:trueanomaly.
	local phaseAngle is mod(targetAngularPosition + 360 - shipAngularPosition, 360).
	local transferAngle is mod(180 - targetAngularMovement - targetSeparation, 360).

	if targetOrbitable:obt:apoapsis < ship:obt:apoapsis {
		set phaseAngle to phaseAngle - 360.
		if phaseAngle > transferAngle set phaseAngle to phaseAngle - 360.
	}
	if targetOrbitable:obt:apoapsis > ship:obt:apoapsis and phaseAngle < transferAngle
		set phaseAngle to phaseAngle + 360.

	local transfer_eta is mod(abs(phaseAngle - transferAngle), 360) / relativeAngularSpeed.

	return time:seconds + transfer_eta.
}