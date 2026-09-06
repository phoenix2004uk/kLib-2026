{
	local OrbitalMechanics is import("mech/orbitalMechanics-v1").
	local OrbitalParameters is import("mech/orbitalParameters-v1").
	export({
		parameter targetOrbitable.
		local targetOrbit is targetOrbitable:orbit.
		local targetAltitudeEstimate is targetOrbit:semimajoraxis-body:radius.
		local shipAltitudeEstimate is obt:semimajoraxis-body:radius.
		local targetAngularSpeed is 360/targetOrbit:period.
		local phaseAngle is mod(mod(targetOrbit:lan+targetOrbit:argumentofperiapsis+targetOrbit:trueanomaly,360)+360-mod(obt:lan+obt:argumentofperiapsis+obt:trueanomaly,360),360).
		local transferAngle is mod(180-targetAngularSpeed*OrbitalMechanics:P((targetAltitudeEstimate+shipAltitudeEstimate)/2)/2,360).
		if targetAltitudeEstimate<shipAltitudeEstimate{
			set phaseAngle to phaseAngle-360.
			if phaseAngle>transferAngle set phaseAngle to phaseAngle-360.
		}
		if targetAltitudeEstimate>shipAltitudeEstimate and phaseAngle<transferAngle set phaseAngle to phaseAngle+360.
		local mnvTime is time:seconds+mod(abs(phaseAngle-transferAngle),360)/abs(360/obt:period-targetAngularSpeed).
		local departureAltitude is body:altitudeOf(positionAt(ship,mnvTime)).
		return ApiOK(node(mnvTime,0,0,OrbitalMechanics:v(departureAltitude,OrbitalParameters:a(departureAltitude,targetOrbitable:orbit:semimajoraxis-body:radius))-OrbitalMechanics:v(departureAltitude))).
	}).
}