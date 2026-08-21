// #include "math-v1.ks"

// works for elliptical orbits (e<1 -> a>0) and hyperbolic trajectories (e>1 -> a<0)
local function SemiMajorAxis {
	parameter h1, h2, b is body.

	if h1 < 0 or h2 < 0 { print "Error: SemiMajorAxis is only valid for elliptical orbits". }

	return (h1 + h2) / 2 + b:radius.
}

// Returns the maximum absolute true anomaly.
// Elliptical: returns 180 degrees.
// Hyperbolic: returns the asymptotic true anomaly.
//             Physical trajectory is -Vlimit < V < +Vlimit.
// Note: kOS represents elliptical true anomaly as 0..360,
//       but open-orbit true anomaly as -180..180.
local function TrueAnomalyLimit {
	parameter e is orbit:eccentricity.

	if (e < 1) return 180.
	return arccos(max(-1, -1/e)).
}

// works for elliptical orbits and hyperbolic trajectories
local function TrueAnomalyOfAN {
	parameter w is orbit:argumentOfPeriapsis, e is orbit:eccentricity.

	if e < 1 return mod(360 - w, 360).
	return -w.
	// if i < 0 return mod(180 - w, 360).
	// return mod(360 - w,360).
}

// works for elliptical orbits and hyperbolic trajectories
local function TrueAnomalyOfDN {
	parameter w is orbit:argumentOfPeriapsis, e is orbit:eccentricity.

	if e < 1 return mod(540 - w, 360).
	return 180 - w.
	// if i < 0 return mod(360 - w, 360).
	// return mod(540 - w,360).
}

// for elliptical orbits only, e<1
local function EccentricAnomaly {
	parameter V0, e is orbit:eccentricity.

	if e >= 1 { print "Error: EccentricAnomaly is only valid for elliptical orbits". }

	local eccentricAnomalyDegrees is arccos( (e + cos(V0)) / (1 + e * cos(V0))).
	if (V0 > 180) {
		set eccentricAnomalyDegrees to 360 - eccentricAnomalyDegrees.
	}
	return eccentricAnomalyDegrees.
}

// for hyperbolic trajectories only, e>1
// Note: caller must ensure the Hyperbolic Anomaly (F) is within the domain limit from TrueAnomalyLimit(e)
local function HyperbolicAnomaly {
	parameter V0, e is orbit:eccentricity.

	if e <= 1 { print "Error: HyperbolicAnomaly is only valid for hyperbolic orbits". }

	local F is acosh((e + cos(V0)) / (1 + e * cos(V0))) * constant:radToDeg.

	if V0 < 0 {
		return -F.
	}

	return F.
}

// for elliptical orbits only, e<1
local function MeanAnomaly {
	parameter eccentricAnomalyDegrees, e is orbit:eccentricity.

	if e >= 1 { print "Error: MeanAnomaly is only valid for elliptical orbits". }

	return eccentricAnomalyDegrees - e * sin(eccentricAnomalyDegrees) * constant:radToDeg.
}

// for hyperbolic trajectories only, e>1
// Note: caller must ensure the Hyperbolic Anomaly (F) is within the domain limit from TrueAnomalyLimit(e)
local function HyperbolicMeanAnomaly {
	parameter F, e is orbit:eccentricity.

	if e <= 1 { print "Error: HyperbolicMeanAnomaly is only valid for hyperbolic orbits". }

	local Fr is F * constant:degToRad.
	return (e * sinh(Fr) - Fr) * constant:radToDeg.
}

// works for elliptical orbits and hyperbolic trajectories
local function TrueAnomalyRadius {
	parameter V0, a is orbit:semimajoraxis, e is orbit:eccentricity.

	return (a * (1 - e^2)) / (1 + e * cos(V0)).
}

global OrbitalParameters is lex(
	"a", SemiMajorAxis@,
	"Vlim", TrueAnomalyLimit@,
	"Van", TrueAnomalyOfAN@,
	"Vdn", TrueAnomalyOfDN@,
	"Vr", TrueAnomalyRadius@,
	"Vh", { parameter V0, a is orbit:semimajoraxis, e is orbit:eccentricity, b is body. return TrueAnomalyRadius(V0, a, e) - b:radius. },
	"E", EccentricAnomaly@,
	"F", HyperbolicAnomaly@,
	"M", MeanAnomaly@,
	"Mh", HyperbolicMeanAnomaly@
).