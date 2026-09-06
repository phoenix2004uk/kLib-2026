{
	local OrbitalMechanics is import("mech/orbitalMechanics-v1").
	local OrbitalParameters is import("mech/orbitalParameters-v1").
	local seekNode is import("mnv/seekNode-v1").
	function getReturnNode{
		parameter targetPeriapsis,burnUT is 0.
		local parentBody is body:body.
		local moonOrbitAltitude is body:orbit:semimajoraxis-parentBody:radius.
		local parkingSemiMajorAxis is obt:semimajoraxis.
		local parkingAltitude is parkingSemiMajorAxis-body:radius.
		local escapeSemiMajorAxis is -body:mu/(OrbitalMechanics:v(moonOrbitAltitude,body:orbit:semimajoraxis,parentBody)-OrbitalMechanics:v(moonOrbitAltitude,OrbitalParameters:a(moonOrbitAltitude,targetPeriapsis,parentBody),parentBody))^2.
		local escapeTrueAnomaly is OrbitalParameters:Vlim(1-parkingSemiMajorAxis/escapeSemiMajorAxis).
		local orbitNormal is OrbitalMechanics:h(ship):normalized.
		local escapeDirection is vxcl(orbitNormal,choose -body:velocity:orbit if burnUT=0 else -velocityAt(body,burnUT):orbit):normalized.
		local burnRadial is escapeDirection*cos(escapeTrueAnomaly)-vcrs(orbitNormal,escapeDirection)*sin(escapeTrueAnomaly).
		local currentRadial is up:vector.
		set burnUT to time:seconds+OrbitalMechanics:dtV(mod(arctan2(vdot(vcrs(currentRadial,burnRadial),orbitNormal),vdot(currentRadial,burnRadial))+360,360)).
		return node(burnUT,0,0,OrbitalMechanics:v(parkingAltitude,escapeSemiMajorAxis,body)-OrbitalMechanics:v(parkingAltitude,parkingSemiMajorAxis,body)).
	}
	export({
		parameter targetPeriapsis.
		local mnv is getReturnNode(targetPeriapsis,getReturnNode(targetPeriapsis):time).
		add mnv.
		local largestPeriapsisError is body:orbit:apoapsis+body:body:radius+body:soiradius.
		local targetPeriapsisRadius is targetPeriapsis+body:body:radius.
		seekNode(mnv,list("prograde"),{
			parameter candidate.
			if not candidate:orbit:hasNextPatch return candidate:orbit:apoapsis+body:radius-largestPeriapsisError-body:soiradius.
			return targetPeriapsisRadius-candidate:orbit:nextPatch:periapsis-body:body:radius.
		}).
		if not mnv:orbit:hasNextPatch return ApiFail("Failed to find an escape trajectory").
		local parentPatch is mnv:orbit:nextPatch.
		if parentPatch:hasNextPatch and parentPatch:eta:transition<parentPatch:eta:periapsis return ApiFail("We will encounter another body before periapsis: "+parentPatch:nextPatch:body,true).
		return ApiOK().
	}).
}